#!/usr/bin/env bash
# smia-menu-label: 󰐥  Power
# smia-menu-order: 80
# smia-menu-managed: true

set -euo pipefail

MENU_COMMAND="${SMIA_MENU_COMMAND:-smia-menu}"

compositor_quit() {
    case "${XDG_CURRENT_DESKTOP:-}" in
        *niri*) niri msg action quit ;;
        *)
            if pgrep -x niri >/dev/null 2>&1; then
                niri msg action quit
            elif pgrep -x mango >/dev/null 2>&1; then
                pkill -TERM -x mango
            elif pgrep -x Hyprland >/dev/null 2>&1; then
                hyprctl dispatch exit
            else
                "$MENU_COMMAND" notify "smia-menu" "Unknown compositor; cannot log out"
            fi
            ;;
    esac
}

while true; do
    choice="$(printf '%s\n' \
        "󰌾  Lock" \
        "󰒲  Suspend" \
        "󰑓  Reboot" \
        "󰚦  Shutdown" \
        "󰗼  Logout" \
        | "$MENU_COMMAND" pick "Power")" || exit $?
    case "$choice" in
        *Lock*)     hyprlock ;;
        *Suspend*)  systemctl suspend ;;
        *Reboot*)   systemctl reboot ;;
        *Shutdown*) systemctl poweroff ;;
        *Logout*)   compositor_quit ;;
    esac
done
