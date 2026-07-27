#!/usr/bin/env bash
# smia-menu-label: 󰤨  Network
# smia-menu-order: 20
# smia-menu-managed: true

set -euo pipefail

MENU_COMMAND="${SMIA_MENU_COMMAND:-smia-menu}"
BACK_STATUS="${SMIA_MENU_BACK_STATUS:-10}"

choice="$(printf '%s\n' \
    "󰤨  WiFi / Network" \
    "󰂯  Bluetooth" \
    | "$MENU_COMMAND" pick "Network")" || exit $?

case "$choice" in
    *WiFi*)      exec xdg-terminal-exec impala ;;
    *Bluetooth*) exec xdg-terminal-exec bluetui ;;
    *)           exit "$BACK_STATUS" ;;
esac
