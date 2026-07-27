#!/usr/bin/env bash
# smia-menu-label: 󰸉  Wallpaper
# smia-menu-order: 50
# smia-menu-managed: true

set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
MENU_COMMAND="${SMIA_MENU_COMMAND:-smia-menu}"
BACK_STATUS="${SMIA_MENU_BACK_STATUS:-10}"

fmt_wallpaper_name() {
    local base="${1%.*}"
    base="${base#[0-9]*-}"
    base="${base//-/ }"
    printf '%s' "$base"
}

backgrounds_dir="$XDG_CONFIG_HOME/gnist/themes/current/backgrounds"
declare -A label_to_path
labels=()

while IFS= read -r path; do
    label="$(fmt_wallpaper_name "$(basename "$path")")"
    label_to_path["$label"]="$path"
    labels+=("$label")
done < <(find -L "$backgrounds_dir" -maxdepth 1 -type f \
    \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.webp" \) \
    | sort)

if [[ ${#labels[@]} -eq 0 ]]; then
    "$MENU_COMMAND" notify "Wallpaper" "No wallpapers found for current theme"
    exit "$BACK_STATUS"
fi

choice="$(printf '%s\n' "${labels[@]}" | "$MENU_COMMAND" pick "Wallpaper")" \
    || exit $?
path="${label_to_path[$choice]:-}"
[[ -n "$path" ]] || exit "$BACK_STATUS"

if ! gnist wallpaper "$path" >/dev/null 2>&1; then
    "$MENU_COMMAND" notify "Wallpaper" "Failed to apply $choice"
    exit "$BACK_STATUS"
fi
"$MENU_COMMAND" notify "Wallpaper" "$choice"
