#!/usr/bin/env bash

set -euo pipefail

test_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/lib.bash
source "$test_dir/lib.bash"

installer="$SMIA_REPO_ROOT/malm/modules/cli/smia-install"
work="$(mktemp -d "$SMIA_TEST_TMPDIR/.smia-install-test.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

mkdir -p "$work/bin" "$work/home/Dev/smia" "$work/operator-source"
log="$work/commands.log"
: >"$log"

cat >"$work/bin/malm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'malm'
    printf ' [%s]' "$@"
    printf '\n'
} >>"$SMIA_TEST_LOG"
[[ "$#" -eq 8 && "$1" == plan && "$2" == create \
    && "$3" == --profile && "$5" == --source && "$7" == --namespace ]] || exit 90
EOF
chmod +x "$work/bin/malm"
for command in moss smia smia-session smia-system-model sudo gnist; do
    make_forbidden_stub "$work/bin/$command"
done

run_installer() {
    : >"$log"
    capture env \
        HOME="$work/home" \
        PATH="$work/bin:/usr/bin:/bin" \
        SMIA_TEST_LOG="$log" \
        "$installer" "$@"
}

run_installer_with_source() {
    local source="$1"
    shift
    : >"$log"
    capture env \
        HOME="$work/home" \
        PATH="$work/bin:/usr/bin:/bin" \
        SMIA_TEST_LOG="$log" \
        SMIA_SOURCE_ROOT="$source" \
        "$installer" "$@"
}

source_root="$work/home/Dev/smia"
while IFS=: read -r model_profile combined_profile; do
    run_installer "$model_profile"
    assert_status 0 "smia-install $model_profile"
    assert_contains "$output" "Requested model: $model_profile" \
        "installer model summary"
    assert_contains "$output" "Combined profile: $combined_profile" \
        "installer combined profile summary"
    assert_contains "$output" "Source: $source_root" \
        "installer source summary"
    assert_contains "$output" 'Namespace: default' "installer namespace summary"
    assert_contains "$output" 'No plan was applied.' "installer review notice"
    expected_log="malm [plan] [create] [--profile] [$combined_profile] [--source] [$source_root] [--namespace] [default]"
    assert_eq "$(<"$log")" "$expected_log" \
        "installer prepare commands for $model_profile"
    assert_prepare_only_commands "$log" "smia-install $model_profile"
done <<'EOF'
mango-desktop:mango
mango-gaming:mango-gaming
niri-desktop:niri
niri-gaming:niri-gaming
hyprland-desktop:hyprland
hyprland-gaming:hyprland-gaming
EOF

run_installer niri-gaming --astral
assert_status 0 "smia-install Astral plan"
assert_contains "$(<"$log")" \
    'malm [plan] [create] [--profile] [niri-gaming-astral]' \
    "Astral combined prepare"
assert_not_contains "$(<"$log")" '[--profile] [niri-gaming] ' \
    "Astral combined prepare"
assert_prepare_only_commands "$log" "smia-install Astral"

run_installer niri-gaming --studio
assert_status 0 "smia-install Studio plan"
assert_contains "$(<"$log")" \
    'malm [plan] [create] [--profile] [niri-gaming-studio]' \
    "Studio combined prepare"
assert_not_contains "$(<"$log")" '[--profile] [niri-gaming] ' \
    "Studio combined prepare"
assert_prepare_only_commands "$log" "smia-install Studio"

run_installer niri-gaming --astral --studio
assert_status 2 "conflicting installer appearances"
assert_contains "$output" 'choose only one appearance: --astral or --studio' \
    "conflicting installer appearances report"
[[ ! -s "$log" ]] || fail "conflicting installer appearances executed a command"

run_installer niri-gaming --allow-component
assert_status 2 "removed installer component option"
assert_contains "$output" 'unknown option: --allow-component' \
    "removed installer component option report"
[[ ! -s "$log" ]] || fail "removed installer component option executed a command"

run_installer_with_source relative/source niri-gaming
assert_status 2 "relative installer source"
assert_contains "$output" 'source root must be absolute: relative/source' \
    "relative installer source report"
[[ ! -s "$log" ]] || fail "relative installer source executed a command"

run_installer_with_source "$work/operator-source" mango-desktop
assert_status 0 "absolute installer source"
expected_log="malm [plan] [create] [--profile] [mango] [--source] [$work/operator-source] [--namespace] [default]"
assert_eq "$(<"$log")" "$expected_log" "absolute installer source"
assert_prepare_only_commands "$log" "smia-install absolute source"

run_installer niri-gaming --plan
assert_status 2 "removed installer --plan option"
assert_contains "$output" 'unknown option: --plan' "removed installer option report"
[[ ! -s "$log" ]] || fail "smia-install --plan executed a command"

run_installer unknown
assert_status 2 "unknown installer profile"
assert_contains "$output" 'unknown model profile: unknown' \
    "unknown installer profile report"
[[ ! -s "$log" ]] || fail "unknown installer profile executed a command"

run_installer --help
assert_status 0 "smia-install help"
assert_not_contains "$output" '--allow-component' \
    "removed installer component option in help"
assert_contains "$output" 'SMIA_SOURCE_ROOT' "installer source help"
assert_contains "$output" '$HOME/Dev/smia.' \
    "installer default source help"
assert_contains "$output" 'This command publishes one review plan' \
    "installer plan-only help"
assert_not_contains "$output" '[--plan]' "installer removed option in help"
assert_contains "$output" 'never applies Malm state or' \
    "installer no-apply help"
assert_contains "$output" 'imports a model through Moss.' \
    "installer no-Moss help"
[[ ! -s "$log" ]] || fail "smia-install help executed a command"

printf 'Smia installer tests passed\n'
