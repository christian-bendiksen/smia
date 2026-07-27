#!/usr/bin/env bash

set -euo pipefail

base_root="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
repo_root="$(CDPATH= cd -- "$base_root/../../.." && pwd -P)"

exec bash "$repo_root/tests/smia-maintenance.bash"
