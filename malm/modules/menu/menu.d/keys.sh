#!/usr/bin/env bash
# smia-menu-label: 󰌌  Keybinds
# smia-menu-order: 15
# smia-menu-managed: true

set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
MENU_COMMAND="${SMIA_MENU_COMMAND:-smia-menu}"
BACK_STATUS="${SMIA_MENU_BACK_STATUS:-10}"

menu_notify() {
    "$MENU_COMMAND" notify "$@"
}

# The key list needs more width than the narrow menu theme offers, so this
# plugin runs walker --dmenu directly and inherits walker's configured
# launcher theme. Cancel semantics mirror `smia-menu pick`.
pick_rows() {
    local out rc
    if out="$(walker --dmenu --placeholder "$1")"; then
        :
    else
        rc=$?
        ((rc == 1 || rc == 130)) && return "$BACK_STATUS"
        return "$rc"
    fi
    [[ -n "$out" ]] || return "$BACK_STATUS"
    printf '%s\n' "$out"
}

running_compositor_provider() {
    local desktop
    for desktop in "${XDG_CURRENT_DESKTOP:-}" "${XDG_SESSION_DESKTOP:-}"; do
        case "${desktop,,}" in
            *mango*)     printf 'mango\n'; return 0 ;;
            *niri*)      printf 'niri\n'; return 0 ;;
            *hyprland*)  printf 'hypr\n'; return 0 ;;
        esac
    done

    if pgrep -x mango >/dev/null 2>&1; then printf 'mango\n'
    elif pgrep -x niri >/dev/null 2>&1; then printf 'niri\n'
    elif pgrep -x Hyprland >/dev/null 2>&1; then printf 'hypr\n'
    else return 1
    fi
}

# Each parser emits KEYS<TAB>ACTION rows from the rendered configuration.

parse_mango() {
    awk -F',' '
        /^bind=/ {
            sub(/^bind=/, "")
            n = split($0, f, ",")
            keys = (f[1] == "NONE" ? f[2] : f[1] "+" f[2])
            action = f[3]
            for (i = 4; i <= n; i++) action = action "," f[i]
            sub(/^spawn_shell,/, "", action)
            sub(/^spawn,/, "", action)
            print keys "\t" action
        }
    ' "$1"
}

parse_niri() {
    awk '
        /^binds \{/ { in_binds = 1; next }
        in_binds && /^\}/ { in_binds = 0 }
        !in_binds { next }
        /^    [A-Za-z0-9+_]+.*\{[[:space:]]*$/ {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            split(line, parts, " ")
            chord = parts[1]
            title = ""
            if (match(line, /hotkey-overlay-title="[^"]*"/)) {
                title = substr(line, RSTART + 22, RLENGTH - 23)
            } else if (line ~ /hotkey-overlay-title=null/) {
                title = ""
            }
            pending = chord
            pending_title = title
            next
        }
        pending != "" {
            body = $0
            sub(/^[[:space:]]+/, "", body)
            sub(/;[[:space:]]*$/, "", body)
            gsub(/"/, "", body)
            sub(/^spawn-sh /, "", body)
            sub(/^spawn /, "", body)
            action = (pending_title != "" ? pending_title : body)
            print pending "\t" action
            pending = ""
        }
    ' "$1"
}

# Malm renders hypr/binds.list as one `chord|label` row per bind,
# workspace binds included.
parse_hypr() {
    awk -F'|' 'NF >= 2 { print $1 "\t" $2 }' "$1"
}

provider="$(running_compositor_provider)" || {
    menu_notify "Keybinds" "No supported compositor detected"
    exit "$BACK_STATUS"
}

case "$provider" in
    mango) config="$XDG_CONFIG_HOME/mango/conf.d/binds.conf" ;;
    niri)  config="$XDG_CONFIG_HOME/niri/binds.kdl" ;;
    hypr)  config="$XDG_CONFIG_HOME/hypr/binds.list" ;;
esac

if [[ ! -r "$config" ]]; then
    menu_notify "Keybinds" "No rendered bindings at $config"
    exit "$BACK_STATUS"
fi

rows="$("parse_$provider" "$config")"
if [[ -z "$rows" ]]; then
    menu_notify "Keybinds" "No bindings found in $config"
    exit "$BACK_STATUS"
fi

while true; do
    while IFS=$'\t' read -r keys action; do
        printf '%-28s %s\n' "$keys" "$action"
    done <<<"$rows" | pick_rows "Keybinds ($provider)" >/dev/null \
        || exit $?
done
