#!/usr/bin/env bash

set -euo pipefail

test_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/lib.bash
source "$test_dir/lib.bash"

vendor_assets="$SMIA_REPO_ROOT/tools/vendor-assets/vendor-assets"
malm_root="${MALM_ROOT:-$SMIA_REPO_ROOT/../malm}"
work="$(mktemp -d "$SMIA_TEST_TMPDIR/.smia-tools-test.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

fake_cargo="$work/cargo"
cargo_log="$work/cargo.log"
cat >"$fake_cargo" <<'EOF'
#!/usr/bin/env bash
{
    printf 'offline=%s\n' "${CARGO_NET_OFFLINE:-unset}"
    printf 'cargo'
    printf ' [%s]' "$@"
    printf '\n'
} >>"$SMIA_TEST_LOG"
EOF
chmod +x "$fake_cargo"

: >"$cargo_log"
capture env -u CARGO_NET_OFFLINE \
    CARGO="$fake_cargo" \
    CARGO_TARGET_DIR="$work/target" \
    SMIA_TEST_LOG="$cargo_log" \
    "$vendor_assets" verify
assert_status 0 "vendor-assets verify wrapper"
assert_contains "$(<"$cargo_log")" 'offline=true' \
    "vendor-assets verify offline mode"
assert_contains "$(<"$cargo_log")" \
    "cargo [+1.95.0] [run] [--quiet] [--offline] [--locked] [--manifest-path] [$SMIA_REPO_ROOT/tools/vendor-assets/Cargo.toml] [--] [verify]" \
    "vendor-assets verify cargo arguments"

: >"$cargo_log"
capture env -u CARGO_NET_OFFLINE \
    CARGO="$fake_cargo" \
    CARGO_TARGET_DIR="$work/target" \
    SMIA_TEST_LOG="$cargo_log" \
    "$vendor_assets" generate
assert_status 0 "vendor-assets generate wrapper"
assert_contains "$(<"$cargo_log")" 'offline=true' \
    "vendor-assets generate offline mode"
assert_contains "$(<"$cargo_log")" '[--offline]' \
    "vendor-assets generate cargo arguments"

: >"$cargo_log"
capture env -u CARGO_NET_OFFLINE \
    CARGO="$fake_cargo" \
    CARGO_TARGET_DIR="$work/target" \
    SMIA_TEST_LOG="$cargo_log" \
    "$vendor_assets" fetch
assert_status 0 "vendor-assets fetch wrapper fixture"
assert_contains "$(<"$cargo_log")" 'offline=unset' \
    "vendor-assets fetch environment"
assert_not_contains "$(<"$cargo_log")" '[--offline]' \
    "vendor-assets fetch arguments"

: >"$cargo_log"
capture env \
    CARGO="$fake_cargo" \
    CARGO_TARGET_DIR="$work/target" \
    SMIA_TEST_LOG="$cargo_log" \
    "$vendor_assets" unknown
assert_status 2 "vendor-assets usage"
assert_contains "$output" '{fetch|generate|verify}' "vendor-assets usage output"
[[ ! -s "$cargo_log" ]] || fail "vendor-assets invalid mode invoked Cargo"

printf 'Smia tool tests passed\n'
