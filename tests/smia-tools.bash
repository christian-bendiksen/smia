#!/usr/bin/env bash

set -euo pipefail

test_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/lib.bash
source "$test_dir/lib.bash"

format_component="$SMIA_REPO_ROOT/tools/smia-format-component"
render_lua_data_component="$SMIA_REPO_ROOT/tools/render-lua-data-component"
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

capture "$format_component" unknown
assert_status 2 "smia-format-component usage"
assert_contains "$output" 'verify|update' "smia-format-component usage output"

capture "$render_lua_data_component" unknown
assert_status 2 "render-lua-data-component usage"
assert_contains "$output" 'tools/render-lua-data-component verify|update' \
    "render-lua-data-component usage output"

: >"$cargo_log"
capture env \
    MALM_ROOT="$work" \
    PATH="$work:$PATH" \
    SMIA_TEST_LOG="$cargo_log" \
    "$format_component" verify
assert_status 1 "smia-format-component mismatched MALM_ROOT"
assert_contains "$output" 'MALM_ROOT does not match Cargo path dependency' \
    "smia-format-component checkout mismatch output"
[[ ! -s "$cargo_log" ]] \
    || fail "smia-format-component invoked Cargo before rejecting MALM_ROOT"

format_fixture="$work/format fixture"
format_bin="$format_fixture/bin"
format_cargo_home="$format_fixture/original cargo home"
format_rustup_home="$format_fixture/original rustup home"
format_sysroot="$format_rustup_home/toolchains/1.95.0-test"
format_native_target="$format_fixture/native target"
format_tmp="$format_fixture/temporary root"
format_log="$format_fixture/cargo.log"
mkdir -p \
    "$format_bin" \
    "$format_cargo_home/registry/cache" \
    "$format_cargo_home/registry/index" \
    "$format_sysroot" \
    "$format_native_target" \
    "$format_tmp" \
    "$format_fixture/host home"

cat >"$format_bin/rustup" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" -eq 5 \
    && "$1" == run \
    && "$2" == 1.95.0 \
    && "$3" == rustc \
    && "$4" == --print \
    && "$5" == sysroot ]] || exit 90
printf '%s\n' "$SMIA_FAKE_SYSROOT"
EOF
chmod +x "$format_bin/rustup"

cat >"$format_bin/cargo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

target=${CARGO_TARGET_DIR:-}
native=false
previous=
for argument in "$@"; do
    if [[ "$previous" == --target-dir ]]; then
        target=$argument
    fi
    [[ "$argument" == component-builder ]] && native=true
    previous=$argument
done
[[ -n "$target" ]] || exit 91

if [[ "$native" == true ]]; then
    mkdir -p "$target/debug"
    cat >"$target/debug/component-builder" <<'BUILDER'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    pack)
        if [[ -n "${SMIA_FAKE_BAD_COMPONENT:-}" ]]; then
            cp -- "$2" "$3"
        else
            cp -- "$SMIA_FAKE_CHECKED_COMPONENT" "$3"
        fi
        ;;
    verify)
        ;;
    manifest-named)
        cp -- "$SMIA_FAKE_CHECKED_MANIFEST" "$6"
        ;;
    *)
        exit 92
        ;;
esac
BUILDER
    cat >"$target/debug/malm-host-check" <<'HOST_CHECK'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    profile-digest)
        printf '%s\n' 'sha256-04e65236a70c15dd5106430b6848ae5e0ddeb7f9ac5b907b5c6a916a146f7c58'
        ;;
    verify-render-lua-data)
        printf '%s\n' 'fixture host admitted and invoked component'
        ;;
    *)
        exit 93
        ;;
esac
HOST_CHECK
    chmod +x "$target/debug/component-builder" "$target/debug/malm-host-check"
    exit 0
fi

{
    printf '%s\n' release-build
    printf 'home=%s\n' "$HOME"
    printf 'cargo-home=%s\n' "$CARGO_HOME"
    printf 'target=%s\n' "$CARGO_TARGET_DIR"
    printf 'tmp=%s\n' "$TMPDIR"
    printf 'rustflags=%s\n' "${RUSTFLAGS-unset}"
    printf 'build-rustflags=%s\n' "${CARGO_BUILD_RUSTFLAGS-unset}"
    printf 'target-rustflags=%s\n' \
        "${CARGO_TARGET_WASM32_UNKNOWN_UNKNOWN_RUSTFLAGS-unset}"
    IFS=$'\x1f' read -r -a flags <<<"${CARGO_ENCODED_RUSTFLAGS:?}"
    for flag in "${flags[@]}"; do
        printf 'flag=[%s]\n' "$flag"
    done
} >>"$SMIA_TEST_LOG"

mkdir -p "$target/wasm32-unknown-unknown/release"
if [[ -n "${SMIA_FAKE_BAD_COMPONENT:-}" ]]; then
    printf '%s\n' '/home/release/.cargo/registry/src/host-only/source.rs' \
        >"$target/wasm32-unknown-unknown/release/render_lua_data.wasm"
else
    printf '%s\n' 'fixture core module' \
        >"$target/wasm32-unknown-unknown/release/render_lua_data.wasm"
fi
EOF
chmod +x "$format_bin/cargo"

run_format_fixture() {
    local bad_component=${1:-}
    env \
        MALM_ROOT="$malm_root" \
        PATH="$format_bin:/usr/bin:/bin" \
        HOME="$format_fixture/host home" \
        CARGO_HOME="$format_cargo_home" \
        RUSTUP_HOME="$format_rustup_home" \
        CARGO_TARGET_DIR="$format_native_target" \
        TMPDIR="$format_tmp" \
        RUSTFLAGS='--remap-path-prefix=/poison=poison' \
        CARGO_BUILD_RUSTFLAGS='--cfg poison' \
        CARGO_TARGET_WASM32_UNKNOWN_UNKNOWN_RUSTFLAGS='--cfg target_poison' \
        SMIA_FAKE_SYSROOT="$format_sysroot" \
        SMIA_FAKE_CHECKED_COMPONENT="$SMIA_REPO_ROOT/vendor/render-lua-data.wasm" \
        SMIA_FAKE_CHECKED_MANIFEST="$SMIA_REPO_ROOT/vendor/render-lua-data.manifest.json" \
        SMIA_FAKE_BAD_COMPONENT="$bad_component" \
        SMIA_TEST_LOG="$format_log" \
        "$format_component" verify
}

: >"$format_log"
capture run_format_fixture
assert_status 0 "smia-format-component isolated reproducibility fixture"
assert_contains "$output" \
    'component rebuilds from distinct checkout/Cargo roots are byte-identical' \
    "smia-format-component cross-context result"
assert_contains "$output" 'fixture host admitted and invoked component' \
    "smia-format-component host fixture"
format_log_content="$(<"$format_log")"
assert_contains "$format_log_content" '/first-context/checkouts/smia/components' \
    "smia-format-component first copied checkout"
assert_contains "$format_log_content" '/second-context/checkouts/smia/components' \
    "smia-format-component second copied checkout"
assert_contains "$format_log_content" '/first-context/cargo-home' \
    "smia-format-component first isolated Cargo home"
assert_contains "$format_log_content" '/second-context/cargo-home' \
    "smia-format-component second isolated Cargo home"
assert_contains "$format_log_content" \
    'first-context/checkouts/smia/components=smia]' \
    "smia-format-component encoded first source remap"
assert_contains "$format_log_content" \
    'second-context/checkouts/smia/components=smia]' \
    "smia-format-component encoded second source remap"
assert_contains "$format_log_content" 'original cargo home/registry/src=cargo-registry-origin]' \
    "smia-format-component encoded path with spaces"
for remap in \
    '=host-home]' \
    '=smia-origin]' \
    '=malm-origin]' \
    '=cargo-origin]' \
    '=cargo-registry-origin]' \
    '=rustup-origin]' \
    '=rust-toolchain]' \
    '=build-context]' \
    '=smia]' \
    '=build-home]' \
    '=cargo-home]' \
    '=cargo-registry]' \
    '=build-target]' \
    '=build-tmp]'; do
    assert_contains "$format_log_content" "$remap" \
        "smia-format-component compiler input remap $remap"
done
assert_contains "$format_log_content" 'rustflags=unset' \
    "smia-format-component inherited RUSTFLAGS removal"
assert_contains "$format_log_content" 'build-rustflags=unset' \
    "smia-format-component inherited Cargo build rustflags removal"
assert_contains "$format_log_content" 'target-rustflags=unset' \
    "smia-format-component inherited target rustflags removal"

: >"$format_log"
capture run_format_fixture contaminated
assert_status 1 "smia-format-component host-path rejection fixture"
assert_contains "$output" \
    'component contains a recognized absolute host/build path prefix: /home/' \
    "smia-format-component host-path rejection output"

printf 'Smia tool tests passed\n'
