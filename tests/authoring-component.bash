#!/usr/bin/env bash

set -euo pipefail

test_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/lib.bash
source "$test_dir/lib.bash"

renderer="$SMIA_REPO_ROOT/vendor/render-lua-data.wasm"
manifest="$SMIA_REPO_ROOT/malm-pack.kdl"
lock="$SMIA_REPO_ROOT/malm.lock"
config="$SMIA_REPO_ROOT/malm.kdl"
hypr="$SMIA_REPO_ROOT/malm/modules/hypr/hypr.kdl"
renderer_digest="5c95310034f813d8e9e6e85041ec80f3cdb7342707ccf8a80510476dc0d1f9e4"
execution_profile="sha256-04e65236a70c15dd5106430b6848ae5e0ddeb7f9ac5b907b5c6a916a146f7c58"

[[ -f "$renderer" ]] || fail "Lua data renderer component is missing"
actual_digest="$(sha256sum -- "$renderer")"
assert_eq "${actual_digest%% *}" "$renderer_digest" "Lua data renderer component digest"

renderer_declaration="component \"render-lua-data\" path=\"vendor/render-lua-data.wasm\" digest=\"sha256-$renderer_digest\" interface=\"format-component/v1\""
grep -Fq -- "$renderer_declaration" "$manifest" \
    || fail "pack manifest does not pin the exact Lua data renderer component"
if grep -Fq -- 'execution-profile=' "$manifest"; then
    fail "pack manifest authors a component execution profile"
fi
if grep -RFq -- 'execution-profile=' "$config" "$SMIA_REPO_ROOT/malm"; then
    fail "authoring configuration authors a component execution profile"
fi
grep -Fq -- 'include "vendor/render-lua-data.wasm"' "$manifest" \
    || fail "pack capture omits the Lua data renderer component"
grep -Fq -- '"name": "render-lua-data"' "$lock" \
    || fail "source lock omits the Lua data renderer component"
grep -Fq -- "\"digest\": \"sha256-$renderer_digest\"" "$lock" \
    || fail "source lock carries the wrong Lua data renderer digest"
component_count="$(grep -Fc -- '"interface": "format-component/v1"' "$lock")"
assert_eq "$component_count" 1 "locked component count"
profile_count="$(grep -Fc -- "\"execution_profile\": \"$execution_profile\"" "$lock")"
assert_eq "$profile_count" 1 "host-generated component execution-profile count"

renderer_count="$(grep -RhsF 'component-renderer="render-lua-data"' "$SMIA_REPO_ROOT/malm" | wc -l)"
assert_eq "$renderer_count" 1 "Lua data renderer attachment count"
grep -Fq -- 'render "hypr/config.lua" format="lua" component-renderer="render-lua-data"' "$hypr" \
    || fail "Hyprland data output does not declare the Lua renderer"

printf 'Smia authoring component contracts passed\n'
