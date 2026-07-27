#!/usr/bin/env bash
# smia-menu-label: 󰔡  Toggles
# smia-menu-order: 10
# smia-menu-managed: true

set -euo pipefail

MENU_COMMAND="${SMIA_MENU_COMMAND:-smia-menu}"
BACK_STATUS="${SMIA_MENU_BACK_STATUS:-10}"

menu_pick() {
    "$MENU_COMMAND" pick "$1"
}

menu_notify() {
    "$MENU_COMMAND" notify "$@"
}

# command|icon|label. An entry is hidden when its command is not installed,
# e.g. when the providing module is disabled in the active profile.
TOGGLES=(
    "smia-idle|󰒲|Idle Inhibitor"
    "smia-dnd|󰂛|Do Not Disturb"
    "smia-night-light|󰖔|Night Light"
)

while true; do
    labels=()
    declare -A label_to_cmd=()
    declare -A label_to_name=()
    for entry in "${TOGGLES[@]}"; do
        IFS='|' read -r cmd icon label <<<"$entry"
        command -v "$cmd" >/dev/null 2>&1 || continue
        state="$("$cmd" status 2>/dev/null || true)"
        display="$icon  $label  [${state:-unknown}]"
        labels+=("$display")
        label_to_cmd["$display"]="$cmd"
        label_to_name["$display"]="$label"
    done

    if [[ ${#labels[@]} -eq 0 ]]; then
        menu_notify "Toggles" "No toggle commands installed"
        exit "$BACK_STATUS"
    fi

    choice="$(printf '%s\n' "${labels[@]}" | menu_pick "Toggles")" \
        || exit $?
    cmd="${label_to_cmd[$choice]:-}"
    [[ -n "$cmd" ]] || continue
    "$cmd" toggle || true
    state="$("$cmd" status 2>/dev/null || true)"
    case "$state" in
        on) menu_notify "${label_to_name[$choice]}" "On" ;;
        off) menu_notify "${label_to_name[$choice]}" "Off" ;;
        *) menu_notify "${label_to_name[$choice]}" "Unavailable" ;;
    esac
done
