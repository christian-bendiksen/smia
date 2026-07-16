#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
menu="$root/bin/smia-menu"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config/smia/services.d" "$tmp/config/smia/session.d" \
    "$tmp/config/gnist/themes"
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
    0)
        case "${SMIA_MENU_TEST_FLOW:-services}" in
            services) target="Services" ;;
            themes) target="Themes" ;;
        esac
        ;;
    1)
        case "${SMIA_MENU_TEST_FLOW:-services}" in
            services) target="Restart Walker" ;;
            themes) target="paper  moon" ;;
        esac
        ;;
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
entry="${0##*/}"
for arg in "$@"; do
    entry+=" <$arg>"
done
printf '%s\n' "$entry" >>"$SMIA_MENU_TEST_LOG"
[[ "${0##*/}" != pgrep ]]
EOF
done
cat >"$tmp/bin/gnist" <<'EOF'
#!/usr/bin/env bash
printf 'gnist <%s>\n' "$*" >>"$SMIA_MENU_TEST_LOG"
case "$1" in
    list) printf 'aeryn  dusk (current)\npaper  moon\nalmost (current) \nvoid\n' ;;
esac
EOF
chmod +x "$tmp/bin"/*

printf 'test-menu\n' >"$tmp/config/smia/menu-theme"
printf 'aeryn  dusk\n' >"$tmp/config/gnist/themes/current.theme"
cat >"$tmp/config/smia/services.d/desktop" <<'EOF'
restart waybar
restart mako
restart swayosd-server  swayosd-server -s ~/.config/swayosd/style.css
restart walker  walker --gapplication-service
EOF
cat >"$tmp/config/smia/session.services" <<'EOF'
# Session entries remain discoverable, but the catalog takes precedence.
restart walker  walker --wrong-command
restart custom-service  custom-service --flag
EOF
cat >"$tmp/config/smia/session.d/custom" <<'EOF'
restart fragment-service  fragment-service --flag
EOF

export PATH="$tmp/bin:/usr/bin:/bin"
export HOME="$tmp/home"
export XDG_CONFIG_HOME="$tmp/config"
export SMIA_MENU_TEST_LOG="$log"
export SMIA_MENU_TEST_STATE="$tmp/walker-state"

"$menu"

grep -q '^walker .*<--theme> <test-menu>$' "$log" \
    || fail "menu theme was not read from Smia configuration"
for label in "Restart Waybar" "Restart Notifications" "Restart OSD" \
    "Restart Walker" "Restart custom-service" "Restart fragment-service"; do
    grep -q "option <.*$label>" "$log" || fail "missing service option: $label"
done
[[ "$(grep -c 'option <.*Restart Walker>' "$log")" -eq 1 ]] \
    || fail "duplicate service entries were not collapsed"
grep -q '^pkill <-x> <walker>$' "$log" || fail "Walker was not stopped"
for _ in $(seq 1 200); do
    grep -q '^setsid ' "$log" && break
    sleep 0.01
done
grep -q '^setsid <sh> <-c> <walker --gapplication-service>$' "$log" \
    || fail "catalog restart command was not used"
if grep -q -- '--wrong-command' "$log"; then
    fail "session duplicate overrode the catalog restart command"
fi
: >"$log"
printf '0\n' >"$SMIA_MENU_TEST_STATE"
SMIA_MENU_TEST_FLOW=themes "$menu"
grep -q '^gnist <list>$' "$log" || fail "theme menu did not use gnist list"
grep -q '^walker .*<--placeholder> <Theme: aeryn  dusk>' "$log" \
    || fail "current theme whitespace was not preserved"
grep -q '^option <aeryn  dusk>$' "$log" || fail "current marker was not removed from gnist list"
grep -q '^option <paper  moon>$' "$log" || fail "spaced Gnist theme was not offered"
grep -Fq 'option <almost (current) >' "$log" \
    || fail "non-exact current suffix was stripped"
if grep -q '^option <aeryn  dusk (current)>$' "$log"; then
    fail "theme menu exposed Gnist's current marker as part of the theme name"
fi
grep -q '^setsid <gnist> <set> <paper  moon>$' "$log" \
    || fail "selected spaced Gnist theme was not preserved"

printf 'smia menu tests passed\n'
