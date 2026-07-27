#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
modules_root="$(dirname "$root")"
menu_root="$modules_root/menu"
menu="$menu_root/bin/smia-menu"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config/smia/services.d" "$tmp/config/smia/session.d" \
    "$tmp/config/gnist/themes" "$tmp/data/smia/menu.d" "$tmp/system-data"
log="$tmp/commands.log"

for plugin in "$menu_root"/menu.d/*.sh; do
    ln -s "$plugin" "$tmp/data/smia/menu.d/${plugin##*/}"
done

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
        [[ "${SMIA_MENU_TEST_FLOW:-services}" == picker-failure ]] && exit 42
        case "${SMIA_MENU_TEST_FLOW:-services}" in
            services) target="Services" ;;
            themes) target="Themes" ;;
            themes-failure) target="Themes" ;;
            custom) target="Config Alpha" ;;
            wallpaper) target="Wallpaper" ;;
            defaults-wrapper|defaults-plain) target="Defaults" ;;
            toggles) target="Toggles" ;;
        esac
        ;;
    1)
        case "${SMIA_MENU_TEST_FLOW:-services}" in
            services) target="Restart Walker" ;;
            themes) target="paper  moon" ;;
            themes-failure) exit 130 ;;
            wallpaper) target="black moon" ;;
            defaults-wrapper|defaults-plain) target="Terminal" ;;
            toggles) target="Do Not Disturb" ;;
        esac
        ;;
    2)
        case "${SMIA_MENU_TEST_FLOW:-services}" in
            defaults-wrapper) target="Foot Flatpak" ;;
            defaults-plain) target="Kitty Plain" ;;
            *) exit 130 ;;
        esac
        ;;
    *) exit 130 ;;
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

for command in pkill pgrep setsid notify-send gio systemctl makoctl; do
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
for toggle_stub in smia-idle smia-dnd smia-night-light; do
    cat >"$tmp/bin/$toggle_stub" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${0##*/}" >>"$SMIA_MENU_TEST_LOG"
printf ' <%s>' "$@" >>"$SMIA_MENU_TEST_LOG"
printf '\n' >>"$SMIA_MENU_TEST_LOG"
if [[ "${1:-}" == status ]]; then
    echo off
    exit 1
fi
EOF
done
cat >"$tmp/bin/gnist" <<'EOF'
#!/usr/bin/env bash
printf 'gnist <%s>\n' "$*" >>"$SMIA_MENU_TEST_LOG"
case "$1" in
    list)
        [[ -z "${SMIA_MENU_TEST_GNIST_STATUS:-}" ]] || exit "$SMIA_MENU_TEST_GNIST_STATUS"
        printf 'aeryn  dusk (current)\npaper  moon\nalmost (current) \nvoid\n'
        ;;
esac
EOF
chmod +x "$tmp/bin"/*

printf 'test-menu\n' >"$tmp/config/smia/menu-theme"
printf '%s\n' toggles network profiles themes wallpaper defaults services power \
    >"$tmp/config/smia/menu-items"
printf 'aeryn  dusk\n' >"$tmp/config/gnist/themes/current.theme"
mkdir -p "$tmp/config/gnist/themes/current/backgrounds"
touch "$tmp/config/gnist/themes/current/backgrounds/0-black-moon.jpg" \
    "$tmp/config/gnist/themes/current/backgrounds/2-blue-moon.jpg"
mkdir -p "$tmp/home/.local/share/applications"
cat >"$tmp/home/.local/share/applications/foot-flatpak.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Foot Flatpak
Categories=System;TerminalEmulator;
Exec=flatpak run --command=foot org.codeberg.dnkl.foot
EOF
cat >"$tmp/home/.local/share/applications/kitty-plain.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Kitty Plain
Categories=System;TerminalEmulator;
Exec=kitty %F
EOF
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
export XDG_DATA_HOME="$tmp/data"
export XDG_DATA_DIRS="$tmp/system-data"
export SMIA_MENU_TEST_LOG="$log"
export SMIA_MENU_TEST_STATE="$tmp/walker-state"

discovery="$tmp/discovery"
mkdir -p "$discovery/config/smia/menu.d" "$discovery/data/smia/menu.d" \
    "$discovery/home/.local/share/smia/menu.d" "$discovery/system/smia/menu.d"
printf '# No managed plugins enabled for the first discovery pass.\n' \
    >"$discovery/config/smia/menu-items"
cat >"$discovery/config/smia/menu.d/alpha.sh" <<'EOF'
#!/usr/bin/env bash
# smia-menu-label: Config Alpha
# smia-menu-order: 30
printf 'custom-plugin\n' >>"$SMIA_MENU_TEST_LOG"
: >"$SMIA_MENU_TEST_SENTINEL"
EOF
cat >"$discovery/data/smia/menu.d/alpha.sh" <<'EOF'
#!/usr/bin/env bash
# smia-menu-label: Data Alpha
exit 99
EOF
cat >"$discovery/data/smia/menu.d/beta.sh" <<'EOF'
#!/usr/bin/env bash
# smia-menu-label: Data Beta
# smia-menu-order: 5
exit 0
EOF
cat >"$discovery/system/smia/menu.d/gamma.sh" <<'EOF'
#!/usr/bin/env bash
# smia-menu-label: System Gamma
# smia-menu-order: 20
exit 0
EOF
cat >"$discovery/home/.local/share/smia/menu.d/delta.sh" <<'EOF'
#!/usr/bin/env bash
# smia-menu-label: Managed Delta
# smia-menu-order: 25
exit 0
EOF
cat >"$discovery/config/smia/menu.d/duplicate.sh" <<'EOF'
#!/usr/bin/env bash
# smia-menu-label: Config Alpha
exit 0
EOF
cat >"$discovery/config/smia/menu.d/invalid.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$discovery/config/smia/menu.d/not-executable.sh" <<'EOF'
#!/usr/bin/env bash
# smia-menu-label: Not Executable
exit 0
EOF
ln -s "$menu_root/menu.d/network.sh" "$discovery/data/smia/menu.d/network.sh"
chmod +x "$discovery/config/smia/menu.d/alpha.sh" \
    "$discovery/config/smia/menu.d/duplicate.sh" \
    "$discovery/config/smia/menu.d/invalid.sh" \
    "$discovery/data/smia/menu.d/alpha.sh" \
    "$discovery/data/smia/menu.d/beta.sh" \
    "$discovery/home/.local/share/smia/menu.d/delta.sh" \
    "$discovery/system/smia/menu.d/gamma.sh"

export SMIA_MENU_TEST_SENTINEL="$tmp/plugin-executed"
plugins="$(HOME="$discovery/home" XDG_CONFIG_HOME="$discovery/config" XDG_DATA_HOME="$discovery/data" \
    XDG_DATA_DIRS="$discovery/system" "$menu" list --verbose \
    2>"$tmp/discovery-errors")"
plugin_ids="$(awk -F '\t' 'NR > 1 { print $2 }' <<<"$plugins")"
[[ "$plugin_ids" == $'beta\ngamma\ndelta\nalpha' ]] \
    || fail "plugins were not ordered by metadata and ID"
grep -q $'alpha\tConfig Alpha\t' <<<"$plugins" \
    || fail "config plugin did not override the data plugin"
if grep -q 'Data Alpha\|Not Executable' <<<"$plugins"; then
    fail "shadowed or non-executable plugin was listed"
fi
grep -q 'duplicate label' "$tmp/discovery-errors" \
    || fail "duplicate plugin label was not diagnosed"
grep -q 'invalid metadata' "$tmp/discovery-errors" \
    || fail "invalid plugin metadata was not diagnosed"
[[ ! -e "$SMIA_MENU_TEST_SENTINEL" ]] || fail "listing executed a plugin"

printf 'network\n' >"$discovery/config/smia/menu-items"
enabled_plugins="$(HOME="$discovery/home" XDG_CONFIG_HOME="$discovery/config" \
    XDG_DATA_HOME="$discovery/data" XDG_DATA_DIRS="$discovery/system" \
    "$menu" list --verbose 2>>"$tmp/discovery-errors")"
grep -q $'network\t.*Network\t' <<<"$enabled_plugins" \
    || fail "managed plugin was not enabled by the menu-items manifest"

rm "$discovery/config/smia/menu-items"
no_manifest_plugins="$(HOME="$discovery/home" XDG_CONFIG_HOME="$discovery/config" \
    XDG_DATA_HOME="$discovery/data" XDG_DATA_DIRS="$discovery/system" \
    "$menu" list --verbose 2>>"$tmp/discovery-errors")"
grep -q $'network\t.*Network\t' <<<"$no_manifest_plugins" \
    || fail "managed plugin was hidden without a menu-items manifest"

tiebreak="$tmp/tiebreak"
mkdir -p "$tiebreak/config/smia/menu.d" "$tiebreak/data" "$tiebreak/home" \
    "$tiebreak/system"
cat >"$tiebreak/config/smia/menu.d/zeta.sh" <<'EOF'
#!/usr/bin/env bash
# smia-menu-label: Tie Zeta
# smia-menu-order: 15
exit 0
EOF
cat >"$tiebreak/config/smia/menu.d/eta.sh" <<'EOF'
#!/usr/bin/env bash
# smia-menu-label: Tie Eta
# smia-menu-order: 15
exit 0
EOF
chmod +x "$tiebreak/config/smia/menu.d/zeta.sh" \
    "$tiebreak/config/smia/menu.d/eta.sh"
tie_ids="$(HOME="$tiebreak/home" XDG_CONFIG_HOME="$tiebreak/config" \
    XDG_DATA_HOME="$tiebreak/data" XDG_DATA_DIRS="$tiebreak/system" \
    "$menu" list --verbose 2>/dev/null | awk -F '\t' 'NR > 1 { print $2 }')"
[[ "$tie_ids" == $'eta\nzeta' ]] || fail "equal-order plugins were not ID-sorted"

printf '0\n' >"$SMIA_MENU_TEST_STATE"
SMIA_MENU_TEST_FLOW=custom HOME="$discovery/home" XDG_CONFIG_HOME="$discovery/config" \
    XDG_DATA_HOME="$discovery/data" XDG_DATA_DIRS="$discovery/system" \
    "$menu" 2>>"$tmp/discovery-errors"
[[ -e "$SMIA_MENU_TEST_SENTINEL" ]] || fail "selected plugin was not executed"

printf '0\n' >"$SMIA_MENU_TEST_STATE"
picker_status=0
SMIA_MENU_TEST_FLOW=picker-failure HOME="$discovery/home" \
    XDG_CONFIG_HOME="$discovery/config" XDG_DATA_HOME="$discovery/data" \
    XDG_DATA_DIRS="$discovery/system" "$menu" 2>>"$tmp/discovery-errors" \
    || picker_status=$?
[[ "$picker_status" -eq 42 ]] || fail "picker failure was treated as cancellation"
grep -q 'notify-send <smia-menu> <Picker failed with status 42>' "$log" \
    || fail "picker failure was not reported"

printf '0\n' >"$SMIA_MENU_TEST_STATE"
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

: >"$log"
printf '0\n' >"$SMIA_MENU_TEST_STATE"
SMIA_MENU_TEST_FLOW=themes-failure SMIA_MENU_TEST_GNIST_STATUS=42 "$menu"
grep -q 'notify-send <smia-menu> <Plugin themes failed with status 42>' "$log" \
    || fail "Gnist listing failure was treated as cancellation"

: >"$log"
printf '0\n' >"$SMIA_MENU_TEST_STATE"
SMIA_MENU_TEST_FLOW=wallpaper "$menu"
grep -q '^option <black moon>$' "$log" \
    || fail "numeric prefix was not stripped from the wallpaper label"
grep -q '^option <blue moon>$' "$log" \
    || fail "wallpaper labels with a shared suffix collided"
grep -q '^gnist <wallpaper .*/0-black-moon.jpg>$' "$log" \
    || fail "selected wallpaper path was not applied"

: >"$log"
printf '0\n' >"$SMIA_MENU_TEST_STATE"
SMIA_MENU_TEST_FLOW=defaults-wrapper "$menu"
[[ "$(cat "$tmp/config/xdg-terminals.list")" == "foot-flatpak.desktop" ]] \
    || fail "wrapper terminal was not recorded in xdg-terminals.list"
if [[ -r "$tmp/config/environment.d/gnist-defaults.conf" ]] \
    && grep -q '^TERMINAL=' "$tmp/config/environment.d/gnist-defaults.conf"; then
    fail "multi-word wrapper Exec leaked a TERMINAL value"
fi

: >"$log"
printf '0\n' >"$SMIA_MENU_TEST_STATE"
SMIA_MENU_TEST_FLOW=defaults-plain "$menu"
[[ "$(cat "$tmp/config/xdg-terminals.list")" == "kitty-plain.desktop" ]] \
    || fail "plain terminal was not recorded in xdg-terminals.list"
grep -q '^TERMINAL=kitty$' "$tmp/config/environment.d/gnist-defaults.conf" \
    || fail "single-word terminal Exec did not set TERMINAL"
grep -q '^systemctl <--user> <set-environment> <TERMINAL=kitty>$' "$log" \
    || fail "TERMINAL was not exported to the user session"

: >"$log"
printf '0\n' >"$SMIA_MENU_TEST_STATE"
SMIA_MENU_TEST_FLOW=toggles "$menu"
grep -q 'option <󰒲  Idle Inhibitor  \[off\]>' "$log" \
    || fail "toggles plugin did not list the idle entry"
grep -q '^smia-dnd <toggle>$' "$log" \
    || fail "toggles plugin did not toggle the selected command"
grep -q 'notify-send <Do Not Disturb> <Off>' "$log" \
    || fail "toggles plugin did not report the new state"

cat >"$tmp/bin/menu-stub" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    pick) exit "${SMIA_MENU_BACK_STATUS:-10}" ;;
    notify) printf 'notify <%s>\n' "$*" >>"$SMIA_MENU_TEST_LOG" ;;
esac
EOF
chmod +x "$tmp/bin/menu-stub"
for plugin in toggles network power; do
    smoke_status=0
    SMIA_MENU_COMMAND="$tmp/bin/menu-stub" SMIA_MENU_BACK_STATUS=10 \
        bash "$menu_root/menu.d/$plugin.sh" || smoke_status=$?
    [[ "$smoke_status" -eq 10 ]] \
        || fail "$plugin plugin did not propagate the back status ($smoke_status)"
done

printf 'smia menu tests passed\n'
