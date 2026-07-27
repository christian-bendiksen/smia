#!/usr/bin/env bash

set -euo pipefail

test_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/lib.bash
source "$test_dir/lib.bash"

refresh="$SMIA_REPO_ROOT/malm/modules/base/bin/smia-refresh"
theme_links="$SMIA_REPO_ROOT/malm/modules/base/bin/smia-theme-links"
work="$(mktemp -d "$SMIA_TEST_TMPDIR/.smia-runtime-test.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

refresh_root="$work/refresh"
mkdir -p "$refresh_root/bin"
refresh_log="$refresh_root/commands.log"
: >"$refresh_log"

cat >"$refresh_root/bin/smia-session" <<'EOF'
#!/usr/bin/env bash
{
    printf 'smia-session'
    printf ' [%s]' "$@"
    printf '\n'
} >>"$SMIA_TEST_LOG"
EOF
chmod +x "$refresh_root/bin/smia-session"
for command in malm moss smia-system-model; do
    make_forbidden_stub "$refresh_root/bin/$command"
done

capture env \
    PATH="$refresh_root/bin:/usr/bin:/bin" \
    SMIA_TEST_LOG="$refresh_log" \
    "$refresh"
assert_status 0 "smia-refresh"
assert_eq "$(<"$refresh_log")" 'smia-session [--reapply-theme]' \
    "smia-refresh command"
assert_not_contains "$(<"$refresh_log")" 'malm' \
    "smia-refresh must not apply Malm state"

: >"$refresh_log"
capture env \
    PATH="$refresh_root/bin:/usr/bin:/bin" \
    SMIA_TEST_LOG="$refresh_log" \
    "$refresh" --help
assert_status 0 "smia-refresh help"
assert_eq "$output" 'usage: smia-refresh' "smia-refresh help output"
[[ ! -s "$refresh_log" ]] || fail "smia-refresh help started a session"

capture env \
    PATH="$refresh_root/bin:/usr/bin:/bin" \
    SMIA_TEST_LOG="$refresh_log" \
    "$refresh" --apply
assert_status 2 "smia-refresh removed option"
[[ ! -s "$refresh_log" ]] || fail "smia-refresh invalid option executed a command"

links_root="$work/theme-links"
links_config="$links_root/config"
mkdir -p "$links_config/smia"
printf 'niri-astral\n' >"$links_config/smia/profile"

capture env \
    HOME="$links_root/home" \
    PATH="/usr/bin:/bin" \
    XDG_CONFIG_HOME="$links_config" \
    "$theme_links"
assert_status 0 "smia-theme-links for Niri"

assert_link() {
    local link="$1" target="$2"
    [[ -L "$link" ]] || fail "theme link was not created: $link"
    assert_eq "$(readlink -- "$link")" "$target" "theme link target for $link"
}

theme_root="$links_config/gnist/themes/current"
assert_link "$links_config/btop/themes/current.theme" "$theme_root/btop.theme"
assert_link "$links_config/helix/themes/gnist.toml" "$theme_root/helix.toml"
assert_link "$links_config/gtk-3.0/gtk.css" "$theme_root/gtk.css"
assert_link "$links_config/gtk-4.0/gtk.css" "$theme_root/gtk.css"
assert_link "$links_config/niri/niri-colors.kdl" "$theme_root/niri-colors.kdl"

capture env \
    HOME="$links_root/home" \
    PATH="/usr/bin:/bin" \
    XDG_CONFIG_HOME="$links_config" \
    "$theme_links"
assert_status 0 "idempotent smia-theme-links"
assert_link "$links_config/niri/niri-colors.kdl" "$theme_root/niri-colors.kdl"

printf 'mango\n' >"$links_config/smia/profile"
capture env \
    HOME="$links_root/home" \
    PATH="/usr/bin:/bin" \
    XDG_CONFIG_HOME="$links_config" \
    "$theme_links"
assert_status 0 "smia-theme-links outside Niri"
[[ ! -e "$links_config/niri/niri-colors.kdl" ]] \
    || fail "managed Niri theme link survived a non-Niri profile"

foreign_target="$links_root/foreign-niri-colors.kdl"
ln -sfn -- "$foreign_target" "$links_config/niri/niri-colors.kdl"
capture env \
    HOME="$links_root/home" \
    PATH="/usr/bin:/bin" \
    XDG_CONFIG_HOME="$links_config" \
    "$theme_links"
assert_status 0 "foreign Niri link preservation"
assert_link "$links_config/niri/niri-colors.kdl" "$foreign_target"

guard_root="$work/theme-links-guard"
guard_config="$guard_root/config"
mkdir -p "$guard_config/smia" "$guard_config/btop/themes"
printf 'mango\n' >"$guard_config/smia/profile"
printf 'user-owned\n' >"$guard_config/btop/themes/current.theme"
capture env \
    HOME="$guard_root/home" \
    PATH="/usr/bin:/bin" \
    XDG_CONFIG_HOME="$guard_config" \
    "$theme_links"
assert_status 1 "non-symlink theme protection"
assert_contains "$output" 'refusing to replace non-symlink' \
    "non-symlink theme protection report"
assert_eq "$(<"$guard_config/btop/themes/current.theme")" user-owned \
    "non-symlink theme content"

printf 'Smia runtime tests passed\n'
