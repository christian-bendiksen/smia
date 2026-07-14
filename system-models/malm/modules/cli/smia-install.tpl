#!/usr/bin/env bash

set -euo pipefail

repository_url={{repository-url:shell-word}}
branch={{branch:shell-word}}
model_state={{model-state:shell-word}}
desktop_state={{desktop-state:shell-word}}

usage() {
    cat <<'EOF'
Usage: smia install MODEL_PROFILE [--astral] [--plan]

MODEL_PROFILE:
  mango-desktop       mango-gaming
  niri-desktop        niri-gaming
  hyprland-desktop    hyprland-gaming

Options:
  --astral  Apply the matching Astral desktop profile
  --plan    Preview the model, Moss transition, and desktop without applying
EOF
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'smia-install: %s not found in PATH\n' "$1" >&2
        exit 1
    }
}

model_profile="${1:-}"
case "$model_profile" in
    -h|--help)
        (($# == 1)) || { usage >&2; exit 2; }
        usage
        exit 0
        ;;
    mango-desktop|mango-gaming) desktop_profile="mango" ;;
    niri-desktop|niri-gaming) desktop_profile="niri" ;;
    hyprland-desktop|hyprland-gaming) desktop_profile="hyprland" ;;
    "") usage >&2; exit 2 ;;
    *) printf 'smia-install: unknown model profile: %s\n' "$model_profile" >&2; exit 2 ;;
esac
shift

astral=0
plan_only=0
while (($#)); do
    case "$1" in
        --astral) astral=1 ;;
        --plan) plan_only=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'smia-install: unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

if ((astral)); then
    desktop_profile+="-astral"
fi

require_command malm
require_command moss
require_command sudo

preview="$(mktemp -d)"
cleanup() {
    rm -rf "$preview"
}
trap cleanup EXIT

printf '\nSystem model: %s\nDesktop profile: %s\n\n' "$model_profile" "$desktop_profile"

malm \
    --state "$model_state" \
    --profile "$model_profile" \
    render --output "$preview"

model="$preview/HOME/.local/share/smia-system-models/system-model.kdl"
[[ -r "$model" ]] || {
    printf 'smia-install: rendered model not found: %s\n' "$model" >&2
    exit 1
}
moss sync --import "$model" --dry-run

malm \
    --config malm.kdl \
    --state "$desktop_state" \
    --profile "$desktop_profile" \
    plan "$repository_url" \
    --branch "$branch" \
    --allow-local-includes

((plan_only)) && exit 0

malm \
    --state "$model_state" \
    --profile "$model_profile" \
    apply

smia-system-model apply

malm \
    --config malm.kdl \
    --state "$desktop_state" \
    --profile "$desktop_profile" \
    apply "$repository_url" \
    --branch "$branch" \
    --trust-remote \
    --track \
    --allow-local-includes

if ! malm --state "$desktop_state" doctor; then
    printf 'smia-install: desktop applied, but required commands are missing\n' >&2
    exit 1
fi

cat <<'EOF'

Smia is installed. Finish runtime setup with:
  gnist init
  smia session
EOF
