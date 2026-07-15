#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
menu="$root/bin/smia-menu"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config/gnist/services.d"
log="$tmp/commands.log"

fail() {
    printf 'smia-menu test: %s\n' "$*" >&2
    exit 1
}

cat >"$tmp/bin/walker" <<'EOF'
#!/usr/bin/env bash
state=0
[[ -r "$SMIA_MENU_TEST_STATE" ]] && read -r state <"$SMIA_MENU_TEST_STATE"
case "$state" in
    0) target="Services" ;;
    1) target="Restart Walker" ;;
    *) exit 1 ;;
esac
mapfile -t choices
printf 'walker' >>"$SMIA_MENU_TEST_LOG"
printf ' <%s>' "$@" >>"$SMIA_MENU_TEST_LOG"
printf '\n' >>"$SMIA_MENU_TEST_LOG"
printf 'option <%s>\n' "${choices[@]}" >>"$SMIA_MENU_TEST_LOG"
printf '%s\n' "$((state + 1))" >"$SMIA_MENU_TEST_STATE"

for choice in "${choices[@]}"; do
    if [[ "$choice" == *"$target"* ]]; then
        printf '%s\n' "$choice"
        exit 0
    fi
done
exit 1
EOF

for command in pkill pgrep setsid notify-send; do
    cat >"$tmp/bin/$command" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${0##*/}" >>"$SMIA_MENU_TEST_LOG"
printf ' <%s>' "$@" >>"$SMIA_MENU_TEST_LOG"
printf '\n' >>"$SMIA_MENU_TEST_LOG"
[[ "${0##*/}" != pgrep ]]
EOF
done
chmod +x "$tmp/bin"/*

cat >"$tmp/config/gnist/services.d/desktop" <<'EOF'
restart waybar
restart mako
restart swayosd-server  swayosd-server -s ~/.config/swayosd/style.css
restart walker  walker --gapplication-service
EOF
cat >"$tmp/config/gnist/session.services" <<'EOF'
# Legacy session entries remain discoverable, but the catalog takes precedence.
restart walker  walker --wrong-command
restart custom-service  custom-service --flag
EOF

export PATH="$tmp/bin:/usr/bin:/bin"
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
export SMIA_MENU_TEST_LOG="$log"
export SMIA_MENU_TEST_STATE="$tmp/walker-state"

"$menu"

for label in "Restart Waybar" "Restart Notifications" "Restart OSD" \
    "Restart Walker" "Restart custom-service"; do
    grep -q "option <.*$label>" "$log" || fail "missing service option: $label"
done
[[ "$(grep -c 'option <.*Restart Walker>' "$log")" -eq 1 ]] \
    || fail "duplicate service entries were not collapsed"
grep -q '^pkill <-x> <walker>$' "$log" || fail "Walker was not stopped"
grep -q '^setsid <sh> <-c> <walker --gapplication-service>$' "$log" \
    || fail "catalog restart command was not used"
if grep -q -- '--wrong-command' "$log"; then
    fail "legacy duplicate overrode the catalog restart command"
fi

printf 'smia menu tests passed\n'
