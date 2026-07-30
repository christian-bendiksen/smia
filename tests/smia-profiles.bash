#!/usr/bin/env bash

set -euo pipefail

test_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/lib.bash
source "$test_dir/lib.bash"

profiles="$SMIA_REPO_ROOT/malm/modules/base/bin/smia-profiles"
work="$(mktemp -d "$SMIA_TEST_TMPDIR/.smia-profiles-test.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

mkdir -p "$work/bin" "$work/config/smia"
log="$work/commands.log"
walker_input="$work/walker-input"
: >"$log"

cat >"$work/bin/malm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'malm'
    printf ' [%s]' "$@"
    printf '\n'
} >>"$SMIA_TEST_LOG"
if [[ "$#" -eq 7 && "$1" == plan && "$2" == switch-profile \
    && "$4" == --namespace && "$6" == --format && "$7" == json ]]; then
    [[ "${SMIA_TEST_SWITCH_FAIL:-0}" == 0 ]] || exit 7
    if [[ -v SMIA_TEST_PLAN_JSON ]]; then
        printf '%s\n' "$SMIA_TEST_PLAN_JSON"
    else
        printf '%s\n' '{"schema_version":1,"command":"plan.switch-profile","outcome":"planned","data":{"plan_id":"pp-1111111111111111111111111111111111111111111111111111111111111111"}}'
    fi
elif [[ "$#" -eq 4 && "$1" == plan && "$2" == apply && "$4" == --yes ]]; then
    if [[ "${SMIA_TEST_APPROVAL_REQUIRED:-0}" != 0 ]]; then
        printf 'error[approval-required]: durable plan was not applied\n' >&2
        exit 2
    fi
    [[ "${SMIA_TEST_APPLY_FAIL:-0}" == 0 ]] || exit 8
else
    exit 90
fi
EOF
cat >"$work/bin/walker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'walker'
    printf ' [%s]' "$@"
    printf '\n'
} >>"$SMIA_TEST_LOG"
while IFS= read -r row; do
    printf '%s\n' "$row" >>"$SMIA_TEST_WALKER_INPUT"
done
[[ "${SMIA_TEST_WALKER_STATUS:-0}" == 0 ]] || exit "$SMIA_TEST_WALKER_STATUS"
printf '%s\n' "${SMIA_TEST_WALKER_CHOICE:-}"
EOF
cat >"$work/bin/pgrep" <<'EOF'
#!/usr/bin/env sh
exit 1
EOF
cat >"$work/bin/smia-session" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'smia-session'
    printf ' [%s]' "$@"
    printf '\n'
} >>"$SMIA_TEST_LOG"
[[ "$#" -eq 1 && "$1" == --apply-theme ]] || exit 90
[[ "${SMIA_TEST_SESSION_FAIL:-0}" == 0 ]] || exit 9
EOF
chmod +x "$work/bin/malm" "$work/bin/walker" "$work/bin/pgrep" \
    "$work/bin/smia-session"
for command in moss smia-system-model; do
    make_forbidden_stub "$work/bin/$command"
done

cat >"$work/config/smia/profiles" <<'EOF'
# This deployed manifest is the only profile catalog.
niri
niri-astral
niri-studio
mango
mango-astral
mango-studio
hyprland
hyprland-astral
hyprland-studio
EOF
printf 'mango\n' >"$work/config/smia/profile"
printf 'test-menu\n' >"$work/config/smia/menu-theme"

common_env=(
    HOME="$work/home"
    PATH="$work/bin:/usr/bin:/bin"
    XDG_CONFIG_HOME="$work/config"
    SMIA_TEST_LOG="$log"
    SMIA_TEST_WALKER_INPUT="$walker_input"
    SMIA_DESKTOP_NAMESPACE=desktop-test
)

capture env "${common_env[@]}" "$profiles" list
assert_status 0 "smia-profiles list"
expected_profiles=$'niri\nniri-astral\nniri-studio\nmango\nmango-astral\nmango-studio\nhyprland\nhyprland-astral\nhyprland-studio'
assert_eq "$output" "$expected_profiles" "manifest-driven profile list"
[[ ! -s "$log" ]] || fail "profile listing consulted an executable catalog: $(<"$log")"

capture env "${common_env[@]}" "$profiles" current
assert_status 0 "smia-profiles current"
assert_eq "$output" mango "active profile"
[[ ! -s "$log" ]] || fail "current profile consulted Malm"

: >"$log"
capture env "${common_env[@]}" "$profiles" switch niri-astral
assert_status 2 "cross-compositor profile switch"
assert_contains "$output" 'compositor changes require `smia install MODEL_PROFILE`' \
    "cross-compositor guidance"
[[ ! -s "$log" ]] || fail "cross-compositor profile switch reached Malm"

printf 'niri-gaming\n' >"$work/config/smia/profile"
: >"$log"
capture env "${common_env[@]}" "$profiles" switch niri-astral
assert_status 0 "smia-profiles switch"
assert_contains "$output" \
    'Profile niri-astral deployed as niri-gaming-astral; default theme applied and session refreshed.' \
    "profile deployment notice"
expected_switch='malm [plan] [switch-profile] [niri-gaming-astral] [--namespace] [desktop-test] [--format] [json]
malm [plan] [apply] [pp-1111111111111111111111111111111111111111111111111111111111111111] [--yes]
smia-session [--apply-theme]'
assert_eq "$(<"$log")" "$expected_switch" "automatic profile deployment"

: >"$log"
pretty_plan_json='{
  "diagnostics": [],
  "data": {
    "plan_id" : "pp-1111111111111111111111111111111111111111111111111111111111111111"
  },
  "outcome" : "planned",
  "command" : "plan.switch-profile",
  "schema_version" : 1
}'
mkdir "$work/no-temp-files"
chmod 500 "$work/no-temp-files"
capture env "${common_env[@]}" TMPDIR="$work/no-temp-files" \
    SMIA_TEST_PLAN_JSON="$pretty_plan_json" \
    "$profiles" switch niri
assert_status 0 "pretty profile plan envelope"
assert_contains "$(<"$log")" 'malm [plan] [apply]' \
    "pretty profile plan was not applied without temporary files"

invalid_plan_envelopes=(
    '{'
    '{"schema_version":true,"command":"plan.switch-profile","outcome":"planned","data":{"plan_id":"pp-1111111111111111111111111111111111111111111111111111111111111111"}}'
    '{"schema_version":2,"command":"plan.switch-profile","outcome":"planned","data":{"plan_id":"pp-1111111111111111111111111111111111111111111111111111111111111111"}}'
    '{"schema_version":1,"command":"plan.apply","outcome":"planned","data":{"plan_id":"pp-1111111111111111111111111111111111111111111111111111111111111111"}}'
    '{"schema_version":1,"command":"plan.switch-profile","outcome":"applied","data":{"plan_id":"pp-1111111111111111111111111111111111111111111111111111111111111111"}}'
    '{"schema_version":1,"command":"plan.switch-profile","outcome":"planned","data":"pp-1111111111111111111111111111111111111111111111111111111111111111"}'
    '{"schema_version":1,"command":"plan.switch-profile","outcome":"planned","data":{"plan_id":"prefix-pp-1111111111111111111111111111111111111111111111111111111111111111"}}'
    '{"schema_version":1,"command":"plan.switch-profile","outcome":"planned","data":{"plan_id":"pp-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}}'
    '{"schema_version":1,"schema_version":1,"command":"plan.switch-profile","outcome":"planned","data":{"plan_id":"pp-1111111111111111111111111111111111111111111111111111111111111111"}}'
)
for envelope in "${invalid_plan_envelopes[@]}"; do
    : >"$log"
    capture env "${common_env[@]}" SMIA_TEST_PLAN_JSON="$envelope" \
        "$profiles" switch niri
    assert_status 1 "invalid profile plan envelope"
    assert_contains "$output" 'profile switch returned no valid plan ID' \
        "invalid profile plan envelope report"
    assert_not_contains "$(<"$log")" '[apply]' \
        "invalid profile plan envelope reached application"
    assert_not_contains "$(<"$log")" 'smia-session' \
        "invalid profile plan envelope refreshed the session"
done

: >"$log"
printf 'niri-gaming\n' >"$work/config/smia/profile"
capture env "${common_env[@]}" SMIA_TEST_SWITCH_FAIL=1 \
    "$profiles" switch niri
assert_status 7 "profile plan failure"
assert_contains "$output" 'profile switch failed (exit 7)' \
    "profile plan failure report"
assert_not_contains "$(<"$log")" '[apply]' \
    "failed profile plan reached application"
assert_not_contains "$(<"$log")" 'smia-session' \
    "failed profile plan refreshed the session"

: >"$log"
capture env "${common_env[@]}" SMIA_TEST_APPLY_FAIL=1 \
    "$profiles" switch niri
assert_status 8 "profile deployment failure"
assert_contains "$output" 'profile deployment failed (exit 8)' \
    "profile deployment failure report"
assert_not_contains "$(<"$log")" 'smia-session' \
    "failed profile deployment refreshed the session"

: >"$log"
capture env "${common_env[@]}" SMIA_TEST_APPROVAL_REQUIRED=1 \
    "$profiles" switch niri
assert_status 2 "approval-required profile deployment"
assert_contains "$output" 'error[approval-required]' \
    "approval-required profile deployment report"
assert_contains "$output" 'profile deployment failed (exit 2)' \
    "approval-required profile deployment status"
assert_not_contains "$(<"$log")" 'smia-session' \
    "approval-required profile deployment refreshed the session"

: >"$log"
capture env "${common_env[@]}" SMIA_TEST_SESSION_FAIL=1 \
    "$profiles" switch niri
assert_status 9 "profile session refresh failure"
assert_contains "$output" 'profile deployed, but session refresh failed (exit 9)' \
    "profile session refresh failure report"
assert_contains "$(<"$log")" 'malm [plan] [apply]' \
    "session refresh failed before profile deployment"

: >"$log"
capture env "${common_env[@]}" "$profiles" switch mango-paper
assert_status 2 "profile absent from deployed manifest"
assert_contains "$output" 'unknown profile: mango-paper' "unknown profile report"
[[ ! -s "$log" ]] || fail "unknown profile reached Malm"

: >"$log"
: >"$walker_input"
capture env \
    "${common_env[@]}" \
    XDG_CURRENT_DESKTOP=niri \
    SMIA_TEST_WALKER_CHOICE='Niri (Astral)' \
    "$profiles" select
assert_status 0 "manifest-driven profile selection"
assert_eq "$(<"$walker_input")" $'Niri\nNiri (Astral)\nNiri (Studio)' \
    "compositor-filtered manifest choices"
expected_select="walker [--dmenu] [--placeholder] [Profiles] [--theme] [test-menu]
$expected_switch"
assert_eq "$(<"$log")" "$expected_select" \
    "selected automatic profile deployment"

: >"$log"
: >"$walker_input"
capture env \
    "${common_env[@]}" \
    XDG_CURRENT_DESKTOP=niri \
    SMIA_MENU_BACK_STATUS=42 \
    SMIA_TEST_WALKER_STATUS=130 \
    "$profiles" select
assert_status 42 "Walker profile selection cancellation"
assert_not_contains "$(<"$log")" 'malm [plan]' \
    "cancelled Walker profile selection reached Malm"

: >"$log"
: >"$walker_input"
capture env \
    "${common_env[@]}" \
    XDG_CURRENT_DESKTOP=niri \
    SMIA_TEST_WALKER_CHOICE='Unknown profile' \
    "$profiles" select
assert_status 1 "unknown Walker profile choice"
assert_not_contains "$(<"$log")" 'malm [plan]' \
    "unknown Walker profile choice reached Malm"

: >"$log"
capture env "${common_env[@]}" "$profiles" switch niri --apply
assert_status 2 "profile removed apply option"
[[ ! -s "$log" ]] || fail "profile switch with extra apply option executed a command"

missing_manifest="$work/missing-profiles"
capture env \
    "${common_env[@]}" \
    SMIA_PROFILE_MANIFEST="$missing_manifest" \
    "$profiles" list
assert_status 1 "missing deployed profile manifest"
assert_contains "$output" "profile manifest not found: $missing_manifest" \
    "missing profile manifest report"

printf 'Smia profile tests passed\n'
