#!/usr/bin/env bash

set -euo pipefail

test_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo="$(CDPATH= cd -- "$test_dir/.." && pwd -P)"
malm="${MALM:-$repo/../malm/target/debug/malm}"

if [[ ! -x "$malm" ]]; then
    printf 'Malm executable not found: %s\n' "$malm" >&2
    exit 1
fi
export MALM="$malm"

printf '==> malm source check\n'
"$MALM" source check --source "$repo"

for test_script in \
    malm/modules/base/tests/smia-cli.bash \
    malm/modules/base/tests/smia-menu.bash \
    malm/modules/base/tests/smia-session.bash \
    malm/modules/base/tests/smia-actions.bash \
    malm/modules/base/tests/smia-keys.bash \
    malm/modules/base/tests/smia-maintenance.bash \
    tests/authoring-component.bash \
    tests/smia-profiles.bash \
    tests/smia-install.bash \
    tests/smia-runtime.bash \
    tests/smia-tools.bash; do
    printf '==> %s\n' "$test_script"
    bash "$repo/$test_script"
done

printf '==> golden-render.bash\n'
bash "$test_dir/golden-render.bash"
