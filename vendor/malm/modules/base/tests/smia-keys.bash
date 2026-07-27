#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
modules_root="$(dirname "$root")"
keys="$modules_root/menu/menu.d/keys.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config/mango/conf.d" "$tmp/config/niri" "$tmp/config/hypr"
log="$tmp/commands.log"

fail() {
    printf 'smia-keys test: %s\n' "$*" >&2
    exit 1
}

cat >"$tmp/bin/menu-stub" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    notify)
        shift
        printf 'notify <%s>\n' "$*" >>"$KEYS_TEST_LOG"
        ;;
esac
EOF
cat >"$tmp/bin/walker" <<'EOF'
#!/usr/bin/env bash
printf 'walker' >>"$KEYS_TEST_LOG"
for arg in "$@"; do
    printf ' <%s>' "$arg" >>"$KEYS_TEST_LOG"
done
printf '\n' >>"$KEYS_TEST_LOG"
while IFS= read -r line; do
    printf 'row <%s>\n' "$line" >>"$KEYS_TEST_LOG"
done
exit 130
EOF
chmod +x "$tmp/bin/menu-stub" "$tmp/bin/walker"

# Fixtures mirror real `malm source render` output for each compositor.
cat >"$tmp/config/mango/conf.d/binds.conf" <<'EOF'
# Generated keyed Mango bindings.
bind=SUPER,Return,spawn,xdg-terminal-exec
bind=NONE,Print,spawn_shell,gnist-screenshot region
bind=SUPER+SHIFT,H,exchange_client,left
EOF

cat >"$tmp/config/niri/binds.kdl" <<'EOF'
binds {
    Mod+Return hotkey-overlay-title="Open a Terminal" {
        spawn-sh "xdg-terminal-exec"
    }
    Super+Alt+S allow-when-locked=true hotkey-overlay-title=null {
        spawn-sh "pkill orca || exec orca"
    }
    Mod+O repeat=false {
        toggle-overview
    }
    XF86AudioRaiseVolume allow-when-locked=true {
        spawn "swayosd-client" "--output-volume" "raise"
    }
}
EOF

cat >"$tmp/config/hypr/binds.list" <<'EOF'
SUPER + Return|Open terminal
SUPER + Q|Close window
SUPER + F|Toggle maximize
XF86AudioRaiseVolume|Raise volume
SUPER + 1|Workspace 1
SUPER + SHIFT + 3|Move window to workspace 3
malformed row without separator
EOF

run_keys() {
    local desktop="$1" rc=0
    : >"$log"
    XDG_CONFIG_HOME="$tmp/config" XDG_CURRENT_DESKTOP="$desktop" \
        SMIA_MENU_COMMAND="$tmp/bin/menu-stub" SMIA_MENU_BACK_STATUS=10 \
        KEYS_TEST_LOG="$log" PATH="$tmp/bin:/usr/bin:/bin" \
        bash "$keys" || rc=$?
    [[ "$rc" -eq 10 ]] || fail "$desktop: expected back status 10, got $rc"
}

run_keys mango
grep -q '^walker <--dmenu> <--placeholder> <Keybinds (mango)>$' "$log" \
    || fail "mango picker placeholder missing"
grep -q -- '<--theme>' "$log" && fail "keys plugin forced a walker theme"
grep -q '^row <SUPER+Return .*xdg-terminal-exec>$' "$log" \
    || fail "mango terminal bind missing"
grep -q '^row <Print .*gnist-screenshot region>$' "$log" \
    || fail "mango NONE mods were not stripped"
grep -q '^row <SUPER+SHIFT+H .*exchange_client,left>$' "$log" \
    || fail "mango compositor action missing"

run_keys niri
grep -q '^row <Mod+Return .*Open a Terminal>$' "$log" \
    || fail "niri overlay title missing"
grep -q '^row <Super+Alt+S .*pkill orca || exec orca>$' "$log" \
    || fail "niri null-title bind did not fall back to its body"
grep -q '^row <Mod+O .*toggle-overview>$' "$log" \
    || fail "niri untitled bind missing"
grep -q '^row <XF86AudioRaiseVolume .*swayosd-client --output-volume raise>$' "$log" \
    || fail "niri multi-argument spawn was not flattened"

run_keys Hyprland
grep -q '^row <SUPER + Return .*Open terminal>$' "$log" \
    || fail "hypr terminal bind missing"
grep -q '^row <SUPER + Q .*Close window>$' "$log" \
    || fail "hypr close bind missing"
grep -q '^row <XF86AudioRaiseVolume .*Raise volume>$' "$log" \
    || fail "hypr unmodded bind missing"
grep -q '^row <SUPER + 1 .*Workspace 1>$' "$log" \
    || fail "hypr workspace row missing"
grep -q '^row <SUPER + SHIFT + 3 .*Move window to workspace 3>$' "$log" \
    || fail "hypr shifted workspace row missing"
grep -q 'row <malformed' "$log" && fail "hypr kept a row without a separator"

rm "$tmp/config/mango/conf.d/binds.conf"
: >"$log"
rc=0
XDG_CONFIG_HOME="$tmp/config" XDG_CURRENT_DESKTOP=mango \
    SMIA_MENU_COMMAND="$tmp/bin/menu-stub" SMIA_MENU_BACK_STATUS=10 \
    KEYS_TEST_LOG="$log" PATH="$tmp/bin:/usr/bin:/bin" \
    bash "$keys" || rc=$?
[[ "$rc" -eq 10 ]] || fail "missing config: expected back status, got $rc"
grep -q '^notify <Keybinds No rendered bindings at' "$log" \
    || fail "missing config was not notified"

printf 'smia keys tests passed\n'
