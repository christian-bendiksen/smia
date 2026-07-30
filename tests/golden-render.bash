#!/usr/bin/env bash
# Verifies every profile against tests/golden-manifest.json, or explicitly
# updates that manifest with --update. Every profile is rendered twice and
# compared exactly.
set -euo pipefail

repo="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
malm="${MALM:-$repo/../malm/target/debug/malm}"
manifest="$repo/tests/golden-manifest.json"
mode=verify
case "${1:-}" in
    "") ;;
    --update) mode=update ;;
    *) printf 'usage: %s [--update]\n' "${0##*/}" >&2; exit 2 ;;
esac
[[ "$#" -le 1 ]] || {
    printf 'usage: %s [--update]\n' "${0##*/}" >&2
    exit 2
}

if [[ ! -x "$malm" ]]; then
    printf 'Malm executable not found: %s\n' "$malm" >&2
    exit 1
fi

scratch="$(mktemp -d "${SMIA_TEST_TMPDIR:-$repo}/.smia-golden.XXXXXX")"
candidate_manifest=""
cleanup() {
    rm -rf -- "$scratch"
    if [[ -n "$candidate_manifest" ]]; then
        rm -f -- "$candidate_manifest"
    fi
}
trap cleanup EXIT

if [[ "$mode" == verify ]]; then
python3 - "$manifest" <<'PYTHON'
import json
import re
import sys
from pathlib import PurePosixPath

manifest_path = sys.argv[1]
with open(manifest_path, encoding="utf-8") as handle:
    manifest = json.load(handle)

profiles = manifest.get("profiles")
if not isinstance(profiles, dict) or not profiles:
    raise SystemExit("golden manifest must contain profiles")

artifact_names = re.compile(r"(^|[._-])(cache|pid|timestamp)([._-]|$)")
digest = re.compile(r"[0-9a-f]{64}")


def validate_path(profile, destination):
    path = PurePosixPath(destination)
    if (
        not destination
        or path.is_absolute()
        or str(path) != destination
        or ".." in path.parts
    ):
        raise SystemExit(f"{profile}: invalid artifact path {destination!r}")
    for component in path.parts:
        if artifact_names.search(component.lower()):
            raise SystemExit(
                f"{profile}: cache/PID/timestamp artifact in manifest: {destination}"
            )


for profile, definition in profiles.items():
    if definition.get("kind") not in {"desktop", "system"}:
        raise SystemExit(f"{profile}: invalid profile kind")
    files = definition.get("files")
    if not isinstance(files, dict):
        raise SystemExit(f"{profile}: files must be an object")
    for destination, entry in files.items():
        validate_path(profile, destination)
        if set(entry) != {"executable", "sha256"}:
            raise SystemExit(f"{profile}: invalid entry for {destination}")
        if not isinstance(entry["executable"], bool):
            raise SystemExit(f"{profile}: invalid executable bit for {destination}")
        if not digest.fullmatch(entry["sha256"]):
            raise SystemExit(f"{profile}: invalid digest for {destination}")
    symlinks = definition.get("symlinks", {})
    if not isinstance(symlinks, dict):
        raise SystemExit(f"{profile}: symlinks must be an object")
    for destination, target in symlinks.items():
        validate_path(profile, destination)
        if not isinstance(target, str) or not target:
            raise SystemExit(f"{profile}: invalid symlink target for {destination}")
    trees = definition.get("trees", {})
    if not isinstance(trees, dict):
        raise SystemExit(f"{profile}: trees must be an object")
    for destination, entry in trees.items():
        validate_path(profile, destination)
        if set(entry) != {"archive_decoder", "archive_sha256", "sha256"}:
            raise SystemExit(f"{profile}: invalid tree entry for {destination}")
        if not isinstance(entry["archive_decoder"], str) or not entry["archive_decoder"]:
            raise SystemExit(f"{profile}: invalid archive decoder for {destination}")
        if not digest.fullmatch(entry["archive_sha256"]):
            raise SystemExit(f"{profile}: invalid archive digest for {destination}")
        if not digest.fullmatch(entry["sha256"]):
            raise SystemExit(f"{profile}: invalid tree digest for {destination}")
PYTHON
fi

profile_report="$scratch/source-check.json"
profile_rows="$scratch/profiles.tsv"
profile_fragments="$scratch/profiles"
mkdir "$profile_fragments"
"$malm" source --format json check --source "$repo" >"$profile_report"
python3 - "$mode" "$manifest" "$profile_report" >"$profile_rows" <<'PYTHON'
import json
import sys

mode, manifest_path, report_path = sys.argv[1:]
with open(report_path, encoding="utf-8") as handle:
    report = json.load(handle)
if (
    report.get("command") != "source.check"
    or report.get("outcome") != "valid"
    or not isinstance(report.get("data"), dict)
):
    raise SystemExit("Malm did not return a valid source check")
profiles = report["data"].get("profiles")
if (
    not isinstance(profiles, list)
    or not profiles
    or any(not isinstance(profile, str) or not profile for profile in profiles)
    or len(profiles) != len(set(profiles))
):
    raise SystemExit("Malm source check returned invalid profiles")

kinds = {
    profile: "system" if profile == "install" else "desktop"
    for profile in profiles
}
if mode == "verify":
    with open(manifest_path, encoding="utf-8") as handle:
        expected = json.load(handle)["profiles"]
    if set(expected) != set(kinds):
        missing = sorted(set(kinds) - set(expected))
        unexpected = sorted(set(expected) - set(kinds))
        raise SystemExit(
            "golden manifest profile set differs from source check; "
            f"missing={missing}, unexpected={unexpected}"
        )
    for profile, kind in kinds.items():
        if expected[profile]["kind"] != kind:
            raise SystemExit(
                f"{profile}: expected canonical kind {kind!r}, "
                f"found {expected[profile]['kind']!r}"
            )

for profile in profiles:
    if any(character in profile for character in "\t\r\n"):
        raise SystemExit(f"invalid profile name {profile!r}")
    print(f"{profile}\t{kinds[profile]}")
PYTHON

record_source_render() {
    local profile="$1" kind="$2" root="$3" fragment="$4"
    python3 - "$mode" "$manifest" "$profile" "$kind" "$root" "$fragment" <<'PYTHON'
import hashlib
import json
import os
import stat
import sys

mode, manifest_path, profile, kind, root, fragment_path = sys.argv[1:]
expected = None
if mode == "verify":
    with open(manifest_path, encoding="utf-8") as handle:
        expected = json.load(handle)["profiles"][profile]["files"]

actual = {}
for parent, directories, names in os.walk(root, followlinks=False):
    directories[:] = [
        name for name in directories
        if not os.path.islink(os.path.join(parent, name))
    ]
    for name in names:
        path = os.path.join(parent, name)
        metadata = os.lstat(path)
        if not stat.S_ISREG(metadata.st_mode):
            continue
        with open(path, "rb") as handle:
            sha256 = hashlib.file_digest(handle, "sha256").hexdigest()
        destination = os.path.relpath(path, root)
        actual[destination] = {
            "executable": bool(metadata.st_mode & 0o111),
            "sha256": sha256,
        }

if expected is not None:
    failed = False
    for destination in sorted(expected.keys() - actual.keys()):
        print(f"FAIL {profile}: missing {destination}", file=sys.stderr)
        failed = True
    for destination in sorted(actual.keys() - expected.keys()):
        print(f"FAIL {profile}: unexpected {destination}", file=sys.stderr)
        failed = True
    for destination in sorted(expected.keys() & actual.keys()):
        if actual[destination] != expected[destination]:
            print(
                f"FAIL {profile}: metadata mismatch for {destination}: "
                f"expected {expected[destination]}, got {actual[destination]}",
                file=sys.stderr,
            )
            failed = True
    if failed:
        raise SystemExit(1)

with open(fragment_path, "w", encoding="utf-8") as handle:
    json.dump({"files": actual, "kind": kind}, handle, sort_keys=True)
    handle.write("\n")
PYTHON
}

failures=0
while IFS=$'\t' read -r profile kind; do
    case "$kind" in
        desktop | system) source="$repo" ;;
        *) printf 'unknown profile kind %s\n' "$kind" >&2; exit 2 ;;
    esac
    fragment="$profile_fragments/$profile.json"
    first_render="$scratch/$profile-1"

    if render_output="$("$malm" source render \
        --source "$source" --profile "$profile" \
        --output "$first_render" 2>&1)"; then
        second_render="$scratch/$profile-2"
        "$malm" source render \
            --source "$source" --profile "$profile" \
            --output "$second_render" >/dev/null
        if ! diff --no-dereference -r "$first_render" "$second_render" >/dev/null; then
            printf 'FAIL %s: render is not deterministic\n' "$profile" >&2
            failures=$((failures + 1))
            continue
        fi
        if ! record_source_render "$profile" "$kind" "$first_render" "$fragment"; then
            failures=$((failures + 1))
            continue
        fi
        printf 'ok %s\n' "$profile"
        continue
    fi

    printf 'FAIL %s: source render failed: %s\n' "$profile" "$render_output" >&2
    failures=$((failures + 1))
done <"$profile_rows"

if ((failures > 0)); then
    printf '%s golden divergence(s)\n' "$failures" >&2
    exit 1
fi

observed_manifest="$scratch/golden-manifest.json"
python3 - "$profile_rows" "$profile_fragments" "$observed_manifest" <<'PYTHON'
import json
import re
import sys
from pathlib import Path, PurePosixPath

rows_path, fragments_path, output_path = sys.argv[1:]
profiles = {}
with open(rows_path, encoding="utf-8") as handle:
    for line in handle:
        profile, _kind = line.rstrip("\n").split("\t")
        fragment_path = Path(fragments_path, f"{profile}.json")
        with fragment_path.open(encoding="utf-8") as fragment:
            profiles[profile] = json.load(fragment)

artifact_names = re.compile(r"(^|[._-])(cache|pid|timestamp)([._-]|$)")
digest = re.compile(r"[0-9a-f]{64}")


def validate_path(profile, destination):
    path = PurePosixPath(destination)
    if (
        not destination
        or path.is_absolute()
        or str(path) != destination
        or ".." in path.parts
    ):
        raise SystemExit(f"{profile}: invalid generated artifact path {destination!r}")
    for component in path.parts:
        if artifact_names.search(component.lower()):
            raise SystemExit(
                f"{profile}: generated cache/PID/timestamp artifact: {destination}"
            )


for profile, definition in profiles.items():
    if definition.get("kind") not in {"desktop", "system"}:
        raise SystemExit(f"{profile}: invalid generated profile kind")
    files = definition.get("files")
    if not isinstance(files, dict):
        raise SystemExit(f"{profile}: generated files must be an object")
    for destination, entry in files.items():
        validate_path(profile, destination)
        if (
            set(entry) != {"executable", "sha256"}
            or not isinstance(entry["executable"], bool)
            or not digest.fullmatch(entry["sha256"])
        ):
            raise SystemExit(f"{profile}: invalid generated file {destination}")
    for destination, target in definition.get("symlinks", {}).items():
        validate_path(profile, destination)
        if not isinstance(target, str) or not target:
            raise SystemExit(f"{profile}: invalid generated symlink {destination}")
    for destination, entry in definition.get("trees", {}).items():
        validate_path(profile, destination)
        if (
            set(entry) != {"archive_decoder", "archive_sha256", "sha256"}
            or not isinstance(entry["archive_decoder"], str)
            or not entry["archive_decoder"]
            or not digest.fullmatch(entry["archive_sha256"])
            or not digest.fullmatch(entry["sha256"])
        ):
            raise SystemExit(f"{profile}: invalid generated tree {destination}")

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump({"profiles": profiles}, handle, indent=2, sort_keys=True)
    handle.write("\n")
PYTHON

if [[ "$mode" == update ]]; then
    candidate_manifest="$(mktemp "$repo/tests/.golden-manifest.XXXXXX")"
    cp -- "$observed_manifest" "$candidate_manifest"
    chmod 644 "$candidate_manifest"
    mv -f -- "$candidate_manifest" "$manifest"
    candidate_manifest=""
    printf 'updated tests/golden-manifest.json from isolated renders and plans\n'
    exit 0
fi

python3 - "$manifest" "$observed_manifest" <<'PYTHON'
import json
import sys

expected_path, observed_path = sys.argv[1:]
with open(expected_path, encoding="utf-8") as handle:
    expected = json.load(handle)
with open(observed_path, encoding="utf-8") as handle:
    observed = json.load(handle)
if expected != observed:
    raise SystemExit(
        "golden manifest structure differs from the isolated rendered manifest"
    )
PYTHON
printf 'all profiles match the exact golden artifact manifest\n'
