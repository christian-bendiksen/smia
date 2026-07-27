#!/usr/bin/env bash

set -euo pipefail

test_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/lib.bash
source "$test_dir/lib.bash"

update="$SMIA_REPO_ROOT/malm/modules/base/bin/smia-update"
status_command="$SMIA_REPO_ROOT/malm/modules/base/bin/smia-status"
appearance_module="$SMIA_REPO_ROOT/malm/modules/appearance/appearance.kdl"
work="$(mktemp -d "$SMIA_TEST_TMPDIR/.smia-maintenance-test.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

appearance_source="$(<"$appearance_module")"
assert_contains "$appearance_source" '@line "prepare gnist-appearance-apply.sh"' \
    "appearance start-once directive"
assert_not_contains "$appearance_source" '@line "run gnist-appearance-apply.sh"' \
    "appearance persistent directive"

update_root="$work/update"
mkdir -p "$update_root/bin" "$update_root/runtime"
update_log="$update_root/commands.log"
scratch_log="$update_root/scratch.log"
: >"$update_log"
: >"$scratch_log"

cat >"$update_root/bin/malm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

{
    printf 'malm'
    printf ' [%s]' "$@"
    printf '\n'
} >>"$SMIA_TEST_LOG"

[[ "$#" -eq 8 && "$1" == plan && "$2" == refresh \
    && "$3" == --namespace && "$5" == --git-executable \
    && "$7" == --root-scratch ]] || exit 90
namespace="$4"
scratch="$8"
case "$scratch" in
    "$XDG_RUNTIME_DIR"/smia-update.*/"$namespace") ;;
    *) exit 91 ;;
esac
[[ -d "$scratch" ]] || exit 92
printf '%s\n' "$scratch" >>"$SMIA_TEST_SCRATCH_LOG"
[[ "${SMIA_TEST_FAIL_NAMESPACE:-}" != "$namespace" ]] || exit 23
EOF
cat >"$update_root/trusted-git" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "$update_root/bin/malm" "$update_root/trusted-git"
for command in moss smia-system-model smia-session; do
    make_forbidden_stub "$update_root/bin/$command"
done

capture env \
    PATH="$update_root/bin:/usr/bin:/bin" \
    XDG_RUNTIME_DIR="$update_root/runtime" \
    SMIA_TEST_LOG="$update_log" \
    SMIA_TEST_SCRATCH_LOG="$scratch_log" \
    SMIA_GIT_EXECUTABLE="$update_root/trusted-git" \
    SMIA_DESKTOP_NAMESPACE=desktop-test \
    "$update"
assert_status 0 "smia-update"
assert_contains "$output" 'No plan was applied.' "smia-update review notice"
mapfile -t update_commands <"$update_log"
assert_eq "${#update_commands[@]}" 1 "smia-update command count"
assert_contains "${update_commands[0]}" \
    'malm [plan] [refresh] [--namespace] [desktop-test]' \
    "desktop namespace update"
for line in "${update_commands[@]}"; do
    assert_contains "$line" "[--git-executable] [$update_root/trusted-git]" \
        "trusted Git forwarding"
done
assert_prepare_only_commands "$update_log" "smia-update"
while IFS= read -r scratch; do
    [[ ! -e "$scratch" ]] || fail "smia-update left scratch behind: $scratch"
done <"$scratch_log"

: >"$update_log"
: >"$scratch_log"
capture env \
    PATH="$update_root/bin:/usr/bin:/bin" \
    XDG_RUNTIME_DIR="$update_root/runtime" \
    SMIA_TEST_LOG="$update_log" \
    SMIA_TEST_SCRATCH_LOG="$scratch_log" \
    SMIA_TEST_FAIL_NAMESPACE=desktop-test \
    SMIA_GIT_EXECUTABLE="$update_root/trusted-git" \
    SMIA_DESKTOP_NAMESPACE=desktop-test \
    "$update"
assert_status 23 "smia-update first-namespace failure"
mapfile -t update_commands <"$update_log"
assert_eq "${#update_commands[@]}" 1 "smia-update failure command count"
while IFS= read -r scratch; do
    [[ ! -e "$scratch" ]] || fail "failed smia-update left scratch behind: $scratch"
done <"$scratch_log"

: >"$update_log"
capture env \
    PATH="$update_root/bin:/usr/bin:/bin" \
    SMIA_TEST_LOG="$update_log" \
    "$update" --apply
assert_status 2 "smia-update removed --apply option"
[[ ! -s "$update_log" ]] || fail "smia-update --apply executed a command"

status_root="$work/status"
status_home="$status_root/home"
status_config="$status_root/config"
status_tmp="$status_root/tmp"
mkdir -p \
    "$status_root/bin" \
    "$status_config/smia/session.d" \
    "$status_config/gnist/themes/current" \
    "$status_tmp"
export TMPDIR="$status_tmp"
status_log="$status_root/commands.log"
status_pgrep_log="$status_root/pgrep.log"
: >"$status_log"
: >"$status_pgrep_log"

assert_status_tmp_clean() {
    local path
    for path in "$status_tmp"/smia-status.*; do
        [[ ! -e "$path" ]] || fail "smia-status left temporary file behind: $path"
    done
}

cat >"$status_root/bin/malm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'malm'
    printf ' [%s]' "$@"
    printf '\n'
} >>"$SMIA_TEST_LOG"
[[ "$#" -eq 6 && "$1" == namespace && "$2" == status \
    && "$3" == --namespace && "$5" == --format && "$6" == json ]] || exit 90
namespace="$4"
[[ "${SMIA_TEST_FAIL_NAMESPACE:-}" != "$namespace" ]] || exit 23
if [[ "${SMIA_TEST_STREAM_NAMESPACE:-}" == "$namespace" ]]; then
    case "${SMIA_TEST_STREAM_KIND:-}" in
        nul)
            printf '{"outcome":"enabled_exact"}\0'
            ;;
        invalid-utf8)
            printf '{"outcome":"enabled_exact","detail":"\377"}\n'
            ;;
        trailing-garbage)
            printf '{"outcome":"enabled_exact"}\ntrailing\n'
            ;;
        duplicate-status)
            printf '{"outcome":"enabled_exact","outcome":"enabled_exact"}\n'
            ;;
        nested-status)
            printf '{"detail":{"outcome":"enabled_exact"}}\n'
            ;;
        *) exit 94 ;;
    esac
    exit 0
fi
if [[ "${SMIA_TEST_MALFORMED_NAMESPACE:-}" == "$namespace" ]]; then
    printf '{"outcome":"enabled_exact"\n'
    exit 0
fi
status=enabled_exact
if [[ "${SMIA_TEST_STATUS_NAMESPACE:-}" == "$namespace" ]]; then
    status="$SMIA_TEST_STATUS"
fi
json_status="$status"
if [[ "${SMIA_TEST_ESCAPED_STATUS_NAMESPACE:-}" == "$namespace" ]]; then
    json_status='enabled\u005fexact'
fi
printf '{"schema_version":1,"command":"namespace.status","outcome":"%s","data":{"namespace":"%s","status":"%s"},"diagnostics":[]}\n' \
    "$json_status" "$namespace" "$json_status"
case "$status" in
    enabled_exact|not_found|disabled) exit 0 ;;
    enabled_modified|enabled_missing|enabled_unexpected) exit 1 ;;
    stale|incompatible_or_corrupt|recovery_required) exit 2 ;;
    *) exit 93 ;;
esac
EOF
cat >"$status_root/bin/gnist" <<'EOF'
#!/usr/bin/env bash
[[ "$#" -eq 1 && "$1" == current ]] || exit 90
printf 'aeryn\n'
EOF
cat >"$status_root/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ "$#" -eq 2 && "$1" == -x ]] || exit 90
if [[ -n "${SMIA_TEST_PGREP_LOG:-}" ]]; then
    printf 'pgrep [%s]\n' "$2" >>"$SMIA_TEST_PGREP_LOG"
fi
case "$2" in
    desktop-daemon|notification-daemon) exit 0 ;;
    stopped-daemon) exit 1 ;;
    *) exit 1 ;;
esac
EOF
for command in desktop-tool system-tool; do
    cat >"$status_root/bin/$command" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
done
absolute_tool="$status_root/absolute-tool"
cat >"$absolute_tool" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "$status_root/bin"/* "$absolute_tool"

printf 'mango\n' >"$status_config/smia/profile"
cat >"$status_config/smia/session.services" <<'EOF'
run desktop-daemon
restart notification-daemon
stop stopped-daemon
prepare start-once-helper
EOF
cat >"$status_config/smia/session.d/appearance" <<'EOF'
# Generated by the `appearance` module; edits will be replaced.
prepare gnist-appearance-apply.sh
EOF
cat >"$status_config/smia/requirements.commands" <<EOF
# Unified deployment requirements.
desktop-tool
system-tool
$absolute_tool
EOF

capture env \
    HOME="$status_home" \
    PATH="$status_root/bin:/usr/bin:/bin" \
    XDG_CONFIG_HOME="$status_config" \
    XDG_CURRENT_DESKTOP=mango \
    SMIA_TEST_LOG="$status_log" \
    SMIA_TEST_PGREP_LOG="$status_pgrep_log" \
    SMIA_DESKTOP_NAMESPACE=desktop-test \
    "$status_command"
assert_status 0 "healthy smia-status"
assert_status_tmp_clean
assert_contains "$output" 'ok:   namespace desktop-test matches' \
    "desktop namespace status"
assert_contains "$output" 'ok:   required command desktop-tool' \
    "desktop requirement manifest"
assert_contains "$output" 'ok:   required command system-tool' \
    "system requirement manifest"
assert_contains "$output" "ok:   required executable $absolute_tool" \
    "absolute requirement"
assert_contains "$output" 'info: start-once-helper is start-once (not checked)' \
    "prepare-only service status"
assert_contains "$output" \
    'info: gnist-appearance-apply.sh is start-once (not checked)' \
    "appearance start-once status"
assert_not_contains "$(<"$status_pgrep_log")" 'gnist-appearance-apply.sh' \
    "appearance status process check"
expected_status_log='malm [namespace] [status] [--namespace] [desktop-test] [--format] [json]'
assert_eq "$(<"$status_log")" "$expected_status_log" \
    "smia-status namespace commands"
assert_prepare_only_commands "$status_log" "smia-status"

: >"$status_log"
capture env \
    HOME="$status_home" \
    PATH="$status_root/bin:/usr/bin:/bin" \
    XDG_CONFIG_HOME="$status_config" \
    XDG_CURRENT_DESKTOP=mango \
    SMIA_TEST_LOG="$status_log" \
    SMIA_TEST_ESCAPED_STATUS_NAMESPACE=desktop-test \
    SMIA_DESKTOP_NAMESPACE=desktop-test \
    "$status_command"
assert_status 0 "JSON-escaped enabled_exact status"

for unhealthy_status in \
    not_found \
    disabled \
    enabled_modified \
    enabled_missing \
    enabled_unexpected \
    stale \
    incompatible_or_corrupt \
    recovery_required; do
    capture env \
        HOME="$status_home" \
        PATH="$status_root/bin:/usr/bin:/bin" \
        XDG_CONFIG_HOME="$status_config" \
        XDG_CURRENT_DESKTOP=mango \
        SMIA_TEST_LOG="$status_log" \
        SMIA_TEST_STATUS_NAMESPACE=desktop-test \
        SMIA_TEST_STATUS="$unhealthy_status" \
        SMIA_DESKTOP_NAMESPACE=desktop-test \
        "$status_command"
    assert_status 1 "$unhealthy_status namespace status"
    assert_contains "$output" 'FAIL: namespace desktop-test is not enabled and exact' \
        "$unhealthy_status namespace report"
done

capture env \
    HOME="$status_home" \
    PATH="$status_root/bin:/usr/bin:/bin" \
    XDG_CONFIG_HOME="$status_config" \
    XDG_CURRENT_DESKTOP=mango \
    SMIA_TEST_LOG="$status_log" \
    SMIA_TEST_MALFORMED_NAMESPACE=desktop-test \
    SMIA_DESKTOP_NAMESPACE=desktop-test \
    "$status_command"
assert_status 1 "malformed namespace JSON"
assert_contains "$output" 'FAIL: namespace desktop-test is not enabled and exact' \
    "malformed namespace JSON report"

for rejected_stream in \
    nul \
    invalid-utf8 \
    trailing-garbage \
    duplicate-status \
    nested-status; do
    capture env \
        HOME="$status_home" \
        PATH="$status_root/bin:/usr/bin:/bin" \
        XDG_CONFIG_HOME="$status_config" \
        XDG_CURRENT_DESKTOP=mango \
        SMIA_TEST_LOG="$status_log" \
        SMIA_TEST_STREAM_NAMESPACE=desktop-test \
        SMIA_TEST_STREAM_KIND="$rejected_stream" \
        SMIA_DESKTOP_NAMESPACE=desktop-test \
        "$status_command"
    assert_status 1 "$rejected_stream namespace JSON"
    assert_contains "$output" 'FAIL: namespace desktop-test is not enabled and exact' \
        "$rejected_stream namespace JSON report"
    assert_status_tmp_clean
done

capture env \
    HOME="$status_home" \
    PATH="$status_root/bin:/usr/bin:/bin" \
    XDG_CONFIG_HOME="$status_config" \
    XDG_CURRENT_DESKTOP=mango \
    SMIA_TEST_LOG="$status_log" \
    SMIA_TEST_FAIL_NAMESPACE=desktop-test \
    SMIA_DESKTOP_NAMESPACE=desktop-test \
    "$status_command"
assert_status 1 "namespace status command failure"
assert_contains "$output" 'FAIL: namespace desktop-test is not enabled and exact' \
    "namespace status command failure report"

printf 'missing-system-tool\n' \
    >>"$status_config/smia/requirements.commands"
capture env \
    HOME="$status_home" \
    PATH="$status_root/bin:/usr/bin:/bin" \
    XDG_CONFIG_HOME="$status_config" \
    XDG_CURRENT_DESKTOP=mango \
    SMIA_TEST_LOG="$status_log" \
    SMIA_DESKTOP_NAMESPACE=desktop-test \
    "$status_command"
assert_status 1 "missing deployed requirement"
assert_contains "$output" 'FAIL: required command is missing: missing-system-tool' \
    "missing deployed requirement report"

rm -- "$status_config/smia/requirements.commands"
capture env \
    HOME="$status_home" \
    PATH="$status_root/bin:/usr/bin:/bin" \
    XDG_CONFIG_HOME="$status_config" \
    XDG_CURRENT_DESKTOP=mango \
    SMIA_TEST_LOG="$status_log" \
    SMIA_DESKTOP_NAMESPACE=desktop-test \
    "$status_command"
assert_status 1 "absent deployed requirement manifests"
assert_contains "$output" 'FAIL: no deployed requirement manifest was found' \
    "absent deployed requirement manifest report"

printf 'Smia maintenance tests passed\n'
