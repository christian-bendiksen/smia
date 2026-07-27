#!/usr/bin/env bash
# smia-menu-label: 󰣖  Services
# smia-menu-order: 70
# smia-menu-managed: true

set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
MENU_COMMAND="${SMIA_MENU_COMMAND:-smia-menu}"
BACK_STATUS="${SMIA_MENU_BACK_STATUS:-10}"

service_dir="$XDG_CONFIG_HOME/smia/services.d"
manifest="$XDG_CONFIG_HOME/smia/session.services"
fragment_dir="$XDG_CONFIG_HOME/smia/session.d"
entries=()
declare -A proc_to_cmd
declare -A seen_procs

while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    read -r directive rest <<<"$line"
    case "$directive" in
        restart)
            read -r proc cmd <<<"$rest"
            [[ -z "$cmd" ]] && cmd="$proc"
            case "$proc" in
                waybar)         label="󰝘  Restart Waybar" ;;
                mako)           label="󰂞  Restart Notifications" ;;
                swayosd-server) label="󰸉  Restart OSD" ;;
                walker)         label="󰍉  Restart Walker" ;;
                elephant)       label="󰈞  Restart Elephant" ;;
                wlsunset)       label="󰖔  Restart Night Light" ;;
                *)              label="󰝘  Restart ${proc}" ;;
            esac
            [[ -n "${seen_procs[$proc]+set}" ]] && continue
            seen_procs["$proc"]=1
            entries+=("$label")
            proc_to_cmd["$label"]="$proc $cmd"
            ;;
    esac
done < <(
    for file in "$service_dir"/* "$manifest" "$fragment_dir"/*; do
        [[ -r "$file" ]] && cat "$file"
    done
)

if [[ ${#entries[@]} -eq 0 ]]; then
    "$MENU_COMMAND" notify "Services" "No restartable services configured"
    exit "$BACK_STATUS"
fi

while true; do
    choice="$(printf '%s\n' "${entries[@]}" | "$MENU_COMMAND" pick "Services")" \
        || exit $?
    match="${proc_to_cmd[$choice]:-}"
    [[ -n "$match" ]] || continue
    proc="${match%% *}"
    cmd="${match#* }"

    pkill -x "$proc" 2>/dev/null || true
    for _ in $(seq 1 50); do
        pgrep -x "$proc" >/dev/null 2>&1 || break
        sleep 0.1
    done
    setsid sh -c "$cmd" >"${XDG_RUNTIME_DIR:-/tmp}/smia-${proc}.log" 2>&1 </dev/null &
    disown 2>/dev/null || true
    "$MENU_COMMAND" notify "Services" "$proc restarted"
done
