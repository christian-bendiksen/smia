#!/usr/bin/env bash
# smia-menu-label: 󰔨  Themes
# smia-menu-order: 40
# smia-menu-managed: true

set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
MENU_COMMAND="${SMIA_MENU_COMMAND:-smia-menu}"
BACK_STATUS="${SMIA_MENU_BACK_STATUS:-10}"

current_theme() {
    local file="$XDG_CONFIG_HOME/gnist/themes/current.theme" theme
    if [[ -r "$file" ]]; then
        IFS= read -r theme < "$file" || true
        printf '%s' "$theme"
    else
        printf 'unknown'
    fi
}

list_themes() {
    local output theme
    output="$(gnist list)" || return $?
    while IFS= read -r theme; do
        theme="${theme% (current)}"
        [[ -n "$theme" ]] && printf '%s\n' "$theme"
    done <<<"$output"
}

current="$(current_theme)"
themes="$(list_themes)" || exit $?
if [[ -z "$themes" ]]; then
    "$MENU_COMMAND" notify "Theme" "No themes found"
    exit "$BACK_STATUS"
fi
choice="$(printf '%s\n' "$themes" | "$MENU_COMMAND" pick "Theme: ${current}")" \
    || exit $?
if [[ "$choice" == "$current" ]]; then
    "$MENU_COMMAND" notify "Theme" "Already using $choice"
    exit 0
fi
setsid gnist set "$choice" >"${XDG_RUNTIME_DIR:-/tmp}/smia-gnist-set.log" 2>&1
"$MENU_COMMAND" notify "Theme" "Switched to $choice"
