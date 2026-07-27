#!/usr/bin/env bash

set -euo pipefail

export LC_ALL=C
umask 077

SMIA_REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SMIA_TEST_TMPDIR="${SMIA_TEST_TMPDIR:-$SMIA_REPO_ROOT}"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    local actual="$1" expected="$2" context="${3:-values differ}"
    [[ "$actual" == "$expected" ]] \
        || fail "$context: expected '$expected', got '$actual'"
}

assert_contains() {
    local actual="$1" expected="$2" context="${3:-output mismatch}"
    [[ "$actual" == *"$expected"* ]] \
        || fail "$context: missing '$expected'"
}

assert_not_contains() {
    local actual="$1" forbidden="$2" context="${3:-output mismatch}"
    [[ "$actual" != *"$forbidden"* ]] \
        || fail "$context: unexpectedly contained '$forbidden'"
}

capture() {
    status=0
    output="$("$@" 2>&1)" || status=$?
}

assert_status() {
    local expected="$1" context="${2:-command status}"
    [[ "$status" -eq "$expected" ]] \
        || fail "$context: expected status $expected, got $status; output: $output"
}

make_forbidden_stub() {
    local path="$1"
    cat >"$path" <<'EOF'
#!/usr/bin/env bash
{
    printf '%s' "${0##*/}"
    printf ' [%s]' "$@"
    printf '\n'
} >>"$SMIA_TEST_LOG"
exit 97
EOF
    chmod +x "$path"
}

assert_prepare_only_commands() {
    local log="$1" context="$2"
    if grep -Eq '\[(--state|apply|commit|render|doctor)\]|^(moss|smia-system-model)( |$)' "$log"; then
        fail "$context invoked a command outside the prepare-only boundary: $(<"$log")"
    fi
}
