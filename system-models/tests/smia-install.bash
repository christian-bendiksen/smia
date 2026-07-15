#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
real_malm="$(command -v malm)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'"
}

assert_contains() {
    [[ "$1" == *"$2"* ]] || fail "expected output to contain: $2"
}

assert_not_contains() {
    [[ "$1" != *"$2"* ]] || fail "expected output not to contain: $2"
}

"$real_malm" \
    --repo "$root/system-models" \
    --state smia-system-models \
    --profile install \
    render --output "$work/rendered" >/dev/null

installer="$work/rendered/HOME/.local/bin/smia-install"
[[ -x "$installer" ]] || fail "install profile did not render an executable smia-install"
bootstrap_bins=("$work/rendered/HOME/.local/bin"/*)
assert_eq "${#bootstrap_bins[@]}" 2
[[ -x "$work/rendered/HOME/.local/bin/smia" ]] \
    || fail "install profile did not render an executable smia"

model_profiles=(
    mango-desktop mango-gaming
    niri-desktop niri-gaming
    hyprland-desktop hyprland-gaming
)
for model_profile in "${model_profiles[@]}"; do
    model_output="$work/rendered-$model_profile"
    HOME="$work/home" "$real_malm" \
        --repo "$root/system-models" \
        --state smia-system-models \
        --profile "$model_profile" \
        render --output "$model_output" >/dev/null
    rendered_model="$(<"$model_output/HOME/.local/share/smia-system-models/system-model.kdl")"
    assert_contains "$rendered_model" $'version "stream/unstable"\n        priority 10'
    assert_contains "$rendered_model" $'version "stream/volatile"\n        priority 0'
    assert_contains "$rendered_model" 'gnist'
done

mock_bin="$work/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/malm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'malm'
    printf ' [%s]' "$@"
    printf '\n'
} >>"$SMIA_TEST_LOG"

if [[ " ${*} " == *" doctor "* && "${SMIA_TEST_DOCTOR_FAIL:-0}" == 1 ]]; then
    exit 1
fi

output=
is_render=0
while (($#)); do
    case "$1" in
        render) is_render=1 ;;
        --output)
            shift
            output="${1:-}"
            ;;
    esac
    shift
done

if ((is_render)); then
    [[ -n "$output" ]] || exit 2
    mkdir -p "$output/HOME/.local/share/smia-system-models"
    printf 'packages { test-package }\n' \
        >"$output/HOME/.local/share/smia-system-models/system-model.kdl"
fi
EOF

cat >"$mock_bin/moss" <<'EOF'
#!/usr/bin/env bash
{
    printf 'moss'
    printf ' [%s]' "$@"
    printf '\n'
} >>"$SMIA_TEST_LOG"
EOF

cat >"$mock_bin/smia-system-model" <<'EOF'
#!/usr/bin/env bash
{
    printf 'smia-system-model'
    printf ' [%s]' "$@"
    printf '\n'
} >>"$SMIA_TEST_LOG"
EOF

cat >"$mock_bin/sudo" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$mock_bin/malm" "$mock_bin/moss" "$mock_bin/smia-system-model" "$mock_bin/sudo"

run_installer() {
    : >"$work/commands.log"
    set +e
    output="$(
        SMIA_TEST_LOG="$work/commands.log" \
            SMIA_TEST_DOCTOR_FAIL="${doctor_fail:-0}" \
            PATH="$mock_bin:/usr/bin:/bin" \
            "$installer" "$@" 2>&1
    )"
    status=$?
    set -e
    commands="$(<"$work/commands.log")"
}

run_installer --help
assert_eq "$status" 0
assert_contains "$output" 'Usage: smia install MODEL_PROFILE'

run_installer unknown
assert_eq "$status" 2
assert_contains "$output" 'unknown model profile: unknown'
assert_eq "$commands" ''

declare -A desktop_profiles=(
    [mango-desktop]=mango
    [mango-gaming]=mango
    [niri-desktop]=niri
    [niri-gaming]=niri
    [hyprland-desktop]=hyprland
    [hyprland-gaming]=hyprland
)

for model_profile in "${!desktop_profiles[@]}"; do
    desktop_profile="${desktop_profiles[$model_profile]}"
    run_installer "$model_profile" --plan
    assert_eq "$status" 0
    assert_contains "$commands" \
        "malm [--state] [smia-system-models] [--profile] [$model_profile] [render] [--output]"
    assert_contains "$commands" 'moss [sync] [--import]'
    assert_contains "$commands" '[--dry-run]'
    assert_contains "$commands" \
        "malm [--config] [malm.kdl] [--state] [default] [--profile] [$desktop_profile] [plan] [https://github.com/christian-bendiksen/smia.git] [--branch] [main] [--allow-local-includes]"
    assert_not_contains "$commands" ' [apply]'
    assert_not_contains "$commands" 'smia-system-model [apply]'
done

run_installer niri-gaming --astral --plan
assert_eq "$status" 0
assert_contains "$commands" '[--profile] [niri-astral] [plan]'

run_installer niri-gaming --astral
assert_eq "$status" 0
assert_contains "$output" 'Smia is installed.'
mapfile -t command_lines <"$work/commands.log"
assert_eq "${#command_lines[@]}" 7
assert_contains "${command_lines[0]}" \
    'malm [--state] [smia-system-models] [--profile] [niri-gaming] [render] [--output]'
assert_contains "${command_lines[1]}" 'moss [sync] [--import]'
assert_contains "${command_lines[1]}" '[--dry-run]'
assert_contains "${command_lines[2]}" '[--profile] [niri-astral] [plan]'
assert_eq "${command_lines[3]}" \
    'malm [--state] [smia-system-models] [--profile] [niri-gaming] [apply]'
assert_eq "${command_lines[4]}" 'smia-system-model [apply]'
assert_eq "${command_lines[5]}" \
    'malm [--config] [malm.kdl] [--state] [default] [--profile] [niri-astral] [apply] [https://github.com/christian-bendiksen/smia.git] [--branch] [main] [--trust-remote] [--track] [--allow-local-includes]'
assert_eq "${command_lines[6]}" 'malm [--state] [default] [doctor]'

doctor_fail=1
run_installer mango-desktop
assert_eq "$status" 1
assert_contains "$output" 'desktop applied, but required commands are missing'

printf 'smia installer tests passed\n'
