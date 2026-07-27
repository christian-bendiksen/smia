#!/usr/bin/env bash
# Verifies every profile against tests/golden-manifest.json, or explicitly
# updates that manifest with --update. Source-renderable profiles are rendered
# twice and compared exactly. Component-backed profiles refuse source rendering,
# then execute their pinned components in isolated, lock-backed deployment plans.
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

component_source="$scratch/component-source"
component_home="$scratch/component-home"
component_state="$scratch/component-state"
component_cache="$scratch/component-cache"
component_config="$scratch/component-config"
component_data="$scratch/component-data"
component_runtime="$scratch/component-runtime"
mkdir -p \
    "$component_source" \
    "$component_home" \
    "$component_state" \
    "$component_cache" \
    "$component_config" \
    "$component_data" \
    "$component_runtime"
chmod 700 \
    "$component_home" \
    "$component_state" \
    "$component_cache" \
    "$component_config" \
    "$component_data" \
    "$component_runtime"
cp -a -- \
    "$repo/malm-pack.kdl" \
    "$repo/malm.kdl" \
    "$repo/malm.lock" \
    "$repo/malm" \
    "$repo/gnist" \
    "$repo/vendor" \
    "$component_source/"

component_env=(
    "HOME=$component_home"
    "XDG_STATE_HOME=$component_state"
    "XDG_CACHE_HOME=$component_cache"
    "XDG_CONFIG_HOME=$component_config"
    "XDG_DATA_HOME=$component_data"
    "XDG_RUNTIME_DIR=$component_runtime"
)
env -u MALM_FAILPOINT "${component_env[@]}" "$malm" store init >/dev/null
# Refresh only the copied lock so dirty authoring work can be tested without
# modifying the repository lock or acquiring anything outside this fixture.
env -u MALM_FAILPOINT "${component_env[@]}" \
    "$malm" source lock update --source "$component_source" >/dev/null

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

record_component_plan() {
    local profile="$1" kind="$2" plan="$3" records="$4" fragment="$5"
    python3 - \
        "$mode" "$manifest" "$profile" "$kind" "$plan" "$records" \
        "$fragment" "$component_state" <<'PYTHON'
import hashlib
import json
import os
import sys
from collections import Counter
from pathlib import PurePosixPath

(
    mode,
    manifest_path,
    profile,
    kind,
    plan_path,
    records_path,
    fragment_path,
    state_home,
) = sys.argv[1:]
profile_manifest = None
if mode == "verify":
    with open(manifest_path, encoding="utf-8") as handle:
        profile_manifest = json.load(handle)["profiles"][profile]
with open(plan_path, encoding="utf-8") as handle:
    envelope = json.load(handle)
if envelope.get("outcome") != "planned" or not isinstance(envelope.get("data"), dict):
    raise SystemExit(f"FAIL {profile}: Malm did not return a planned deployment")
plan = envelope["data"]

expected_components = {
    (
        "sha256-5c95310034f813d8e9e6e85041ec80f3cdb7342707ccf8a80510476dc0d1f9e4",
        "vendor/render-lua-data.wasm",
    ),
}
execution_profile = "sha256-04e65236a70c15dd5106430b6848ae5e0ddeb7f9ac5b907b5c6a916a146f7c58"
actual_components = set()
for transform in plan["transforms"]:
    implementation = transform["implementation"]
    if (
        implementation.get("kind") != "component"
        or implementation.get("interface_version") != "format-component/v1"
        or implementation.get("execution_profile_digest") != execution_profile
    ):
        raise SystemExit(f"FAIL {profile}: unpinned component transform provenance")
    actual_components.add(
        (implementation["component_digest"], implementation["component_path"])
    )
if actual_components != expected_components or len(plan["transforms"]) != 1:
    raise SystemExit(f"FAIL {profile}: unexpected component transform set")

def strip_digest(value, label):
    if not isinstance(value, str) or not value.startswith("sha256-") or len(value) != 71:
        raise SystemExit(f"FAIL {profile}: invalid {label} {value!r}")
    result = value.removeprefix("sha256-")
    if any(character not in "0123456789abcdef" for character in result):
        raise SystemExit(f"FAIL {profile}: invalid {label} {value!r}")
    return result


def symlink_target(value, label):
    sha256 = strip_digest(value, label)
    object_path = os.path.join(state_home, "malm", "objects", "symlinks", value)
    with open(object_path, "rb") as handle:
        canonical = handle.read()
    if hashlib.sha256(canonical).hexdigest() != sha256:
        raise SystemExit(f"FAIL {profile}: corrupt {label}")
    domain = b"malm-symlink-object\0"
    cursor = len(domain)
    if not canonical.startswith(domain) or canonical[cursor:cursor + 2] != b"\0\1":
        raise SystemExit(f"FAIL {profile}: noncanonical {label}")
    cursor += 2
    byte_len = int.from_bytes(canonical[cursor:cursor + 8], "big")
    cursor += 8
    encoded = canonical[cursor:]
    if len(encoded) != byte_len:
        raise SystemExit(f"FAIL {profile}: invalid length in {label}")
    try:
        target = encoded.decode("utf-8")
    except UnicodeDecodeError as error:
        raise SystemExit(f"FAIL {profile}: non-UTF-8 {label}") from error
    if not target:
        raise SystemExit(f"FAIL {profile}: empty target in {label}")
    return target


artifacts = {}
artifact_hashes = Counter()
records = []
for artifact in plan["artifacts"]:
    if set(artifact) != {"byte_len", "digest", "id", "media_type"}:
        raise SystemExit(f"FAIL {profile}: malformed plan artifact {artifact!r}")
    artifact_id = artifact["id"]
    if artifact_id in artifacts:
        raise SystemExit(f"FAIL {profile}: duplicate plan artifact {artifact_id}")
    if (
        not isinstance(artifact["byte_len"], int)
        or isinstance(artifact["byte_len"], bool)
        or artifact["byte_len"] < 0
        or not isinstance(artifact["media_type"], str)
        or not artifact["media_type"]
    ):
        raise SystemExit(f"FAIL {profile}: invalid descriptor for artifact {artifact_id}")
    sha256 = strip_digest(artifact["digest"], f"artifact digest for {artifact_id}")
    artifacts[artifact_id] = artifact
    artifact_hashes[sha256] += 1
    records.append((artifact_id, sha256))

actual_files = {}
actual_symlinks = {}
actual_trees = {}
actual_directories = {}
destinations = set()
for operation in plan["operations"]:
    operation_kind = operation.get("operation")
    destination = operation.get("relative_path")
    if operation.get("authority") != "home" or not isinstance(destination, str):
        raise SystemExit(f"FAIL {profile}: invalid operation target {operation!r}")
    if destination in destinations:
        raise SystemExit(f"FAIL {profile}: duplicate operation path {destination}")
    destinations.add(destination)
    if operation_kind == "place_file":
        if set(operation) != {
            "artifact_id", "authority", "mode", "operation", "relative_path",
            "replace_existing",
        }:
            raise SystemExit(f"FAIL {profile}: malformed file operation for {destination}")
        if operation["replace_existing"] is not False or operation["mode"] not in {0o644, 0o755}:
            raise SystemExit(f"FAIL {profile}: invalid file operation for {destination}")
        artifact_id = operation["artifact_id"]
        if artifact_id not in artifacts:
            raise SystemExit(
                f"FAIL {profile}: missing artifact {artifact_id} for {destination}"
            )
        actual_files[destination] = {
            "executable": operation["mode"] == 0o755,
            "sha256": strip_digest(
                artifacts[artifact_id]["digest"],
                f"artifact digest for {destination}",
            ),
        }
    elif operation_kind == "place_symlink":
        if set(operation) != {
            "authority", "object", "operation", "relative_path", "replace_existing",
        } or not isinstance(operation["replace_existing"], bool):
            raise SystemExit(f"FAIL {profile}: malformed symlink operation for {destination}")
        actual_symlinks[destination] = symlink_target(
            operation["object"], f"symlink object for {destination}"
        )
    elif operation_kind == "place_tree":
        if set(operation) != {
            "archive_provenance", "authority", "operation", "relative_path",
            "replace_existing", "tree",
        } or operation["replace_existing"] is not False:
            raise SystemExit(f"FAIL {profile}: malformed tree operation for {destination}")
        provenance = operation["archive_provenance"]
        if not isinstance(provenance, dict) or set(provenance) != {"decoder", "payload"}:
            raise SystemExit(f"FAIL {profile}: invalid tree provenance for {destination}")
        actual_trees[destination] = {
            "archive_decoder": provenance["decoder"],
            "archive_sha256": strip_digest(
                provenance["payload"], f"archive digest for {destination}"
            ),
            "sha256": strip_digest(operation["tree"], f"tree digest for {destination}"),
        }
    elif operation_kind == "ensure_directory":
        if set(operation) != {
            "authority", "mode", "operation", "relative_path", "replace_existing",
        }:
            raise SystemExit(f"FAIL {profile}: malformed directory operation for {destination}")
        actual_directories[destination] = {
            "mode": operation["mode"],
            "replace_existing": operation["replace_existing"],
        }
        continue
    else:
        raise SystemExit(f"FAIL {profile}: unexpected operation {operation_kind!r}")

if plan.get("operation_count") != len(plan["operations"]):
    raise SystemExit(f"FAIL {profile}: incorrect operation count")

expected_files = (
    profile_manifest["files"] if profile_manifest is not None else actual_files
)
expected_symlinks = (
    profile_manifest.get("symlinks", {})
    if profile_manifest is not None
    else actual_symlinks
)
expected_trees = (
    profile_manifest.get("trees", {})
    if profile_manifest is not None
    else actual_trees
)
expected_artifact_hashes = Counter(
    entry["sha256"] for entry in expected_files.values()
)
if artifact_hashes != expected_artifact_hashes:
    missing = sorted((expected_artifact_hashes - artifact_hashes).elements())
    unexpected = sorted((artifact_hashes - expected_artifact_hashes).elements())
    raise SystemExit(
        f"FAIL {profile}: plan artifacts differ; "
        f"missing hashes={missing}, unexpected hashes={unexpected}"
    )


def compare_entries(label, expected, actual):
    failed = False
    for destination in sorted(expected.keys() - actual.keys()):
        print(f"FAIL {profile}: missing {label} {destination}", file=sys.stderr)
        failed = True
    for destination in sorted(actual.keys() - expected.keys()):
        print(f"FAIL {profile}: unexpected {label} {destination}", file=sys.stderr)
        failed = True
    for destination in sorted(expected.keys() & actual.keys()):
        if actual[destination] != expected[destination]:
            print(
                f"FAIL {profile}: {label} mismatch for {destination}: "
                f"expected {expected[destination]!r}, got {actual[destination]!r}",
                file=sys.stderr,
            )
            failed = True
    return failed


failed = compare_entries("file", expected_files, actual_files)
failed |= compare_entries("symlink", expected_symlinks, actual_symlinks)
failed |= compare_entries("tree", expected_trees, actual_trees)

expected_directories = set()
for destination in (*expected_files, *expected_symlinks, *expected_trees):
    parent = PurePosixPath(destination).parent
    while str(parent) != ".":
        expected_directories.add(str(parent))
        parent = parent.parent
expected_directory_entries = {
    destination: {"mode": 0o755, "replace_existing": False}
    for destination in expected_directories
}
failed |= compare_entries("directory", expected_directory_entries, actual_directories)
if failed:
    raise SystemExit(1)

definition = {
    "files": actual_files,
    "kind": kind,
    "symlinks": actual_symlinks,
    "trees": actual_trees,
}
with open(fragment_path, "w", encoding="utf-8") as handle:
    json.dump(definition, handle, sort_keys=True)
    handle.write("\n")
with open(records_path, "w", encoding="utf-8") as handle:
    for artifact_id, sha256 in sorted(records):
        handle.write(f"{plan['plan_id']}\t{artifact_id}\t{sha256}\n")
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

    if [[ "$render_output" != *"source render cannot execute component transforms"* ]]; then
        printf 'FAIL %s: unexpected source-render failure: %s\n' \
            "$profile" "$render_output" >&2
        failures=$((failures + 1))
        continue
    fi

    target="$scratch/$profile-target"
    plan="$scratch/$profile-plan.json"
    records="$scratch/$profile-artifacts.tsv"
    mkdir -m 700 "$target"
    before="$failures"
    if ! env -u MALM_FAILPOINT "${component_env[@]}" \
        "$malm" plan --format json create \
            --source "$component_source" \
            --profile "$profile" \
            --namespace "golden-$profile" \
            --target "home=$target" >"$plan"; then
        printf 'FAIL %s: lock-backed component plan failed\n' "$profile" >&2
        failures=$((failures + 1))
        continue
    fi
    if ! record_component_plan \
        "$profile" "$kind" "$plan" "$records" "$fragment"; then
        failures=$((failures + 1))
        continue
    fi
    export_root="$scratch/$profile-export"
    mkdir -m 700 "$export_root"
    while IFS=$'\t' read -r plan_id artifact_id expected_sha; do
        exported="$export_root/${artifact_id//\//_}"
        if ! env -u MALM_FAILPOINT "${component_env[@]}" \
            "$malm" plan artifact export \
                "$plan_id" "$artifact_id" --output "$exported" >/dev/null; then
            printf 'FAIL %s: could not export artifact %s\n' \
                "$profile" "$artifact_id" >&2
            failures=$((failures + 1))
            continue
        fi
        actual_sha="$(sha256sum -- "$exported")"
        if [[ "${actual_sha%% *}" != "$expected_sha" ]]; then
            printf 'FAIL %s: exported digest mismatch for artifact %s\n' \
                "$profile" "$artifact_id" >&2
            failures=$((failures + 1))
        fi
    done <"$records"
    if [[ "$before" -eq "$failures" ]]; then
        printf 'ok %s (isolated lock-backed component plan)\n' "$profile"
    fi
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
