#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
session="$root/bin/smia-session"
refresh="$root/bin/smia-refresh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config/smia/session.d"
log="$tmp/commands.log"

fail() {
    printf 'smia-session test: %s\n' "$*" >&2
    exit 1
}

cat >"$tmp/bin/gnist" <<'EOF'
#!/usr/bin/env bash
printf 'gnist %s\n' "$*" >>"$SMIA_SESSION_TEST_LOG"
case "$1" in
    current)
        [[ "${SMIA_SESSION_TEST_HAS_CURRENT:-1}" == 1 ]]
        ;;
    set)
        [[ "${SMIA_SESSION_TEST_GNIST_SET_FAIL:-0}" != 1 ]]
        ;;
    reload)
        [[ "${SMIA_SESSION_TEST_GNIST_RELOAD_FAIL:-0}" != 1 ]]
        ;;
    reapply)
        [[ "${SMIA_SESSION_TEST_GNIST_REAPPLY_FAIL:-0}" != 1 ]]
        ;;
esac
EOF

cat >"$tmp/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
printf 'pgrep %s\n' "$*" >>"$SMIA_SESSION_TEST_LOG"
[[ "${*: -1}" != mako ]]
EOF

cat >"$tmp/bin/pkill" <<'EOF'
#!/usr/bin/env bash
printf 'pkill %s\n' "$*" >>"$SMIA_SESSION_TEST_LOG"
EOF

cat >"$tmp/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$SMIA_SESSION_TEST_LOG"
EOF

cat >"$tmp/bin/dbus-update-activation-environment" <<'EOF'
#!/usr/bin/env bash
printf 'dbus-update-activation-environment %s\n' "$*" >>"$SMIA_SESSION_TEST_LOG"
EOF

cat >"$tmp/bin/malm" <<'EOF'
#!/usr/bin/env bash
printf 'malm %s\n' "$*" >>"$SMIA_SESSION_TEST_LOG"
EOF

cat >"$tmp/bin/setsid" <<'EOF'
#!/usr/bin/env bash
printf 'setsid %s\n' "$*" >>"$SMIA_SESSION_TEST_LOG"
EOF

cat >"$tmp/bin/mako" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$tmp/bin"/*
export PATH="$tmp/bin:$root/bin:/usr/bin:/bin"
export XDG_CONFIG_HOME="$tmp/config"
export SMIA_SESSION_TEST_LOG="$log"

printf 'aeryn\n' >"$tmp/config/smia/default-theme"
cat >"$tmp/config/smia/session.services" <<'EOF'
stop stopped-daemon
prepare elephant
run waybar
restart mako
EOF
cat >"$tmp/config/smia/session.d/custom" <<'EOF'
prepare fragment-helper
restart mako  mako --wrong-command
EOF

line_index() {
    local needle="$1" index=0 line
    while IFS= read -r line; do
        [[ "$line" == "$needle" ]] && { printf '%s\n' "$index"; return 0; }
        ((index += 1))
    done <"$log"
    return 1
}

assert_absent() {
    ! line_index "$1" >/dev/null || fail "$2"
}

assert_status() {
    local expected="$1"
    shift
    local actual=0
    "$@" >/dev/null 2>&1 || actual=$?
    [[ "$actual" -eq "$expected" ]] \
        || fail "expected status $expected, got $actual: $*"
}

# Normal startup reloads an existing theme between prepare and run/restart.
: >"$log"
"$session"
stop_index="$(line_index 'pkill -x stopped-daemon')" || fail "stop directive was not processed"
prepare_index="$(line_index 'pgrep -x elephant')" || fail "prepare directive was not processed"
line_index 'pgrep -x fragment-helper' >/dev/null || fail "session.d fragment was not processed"
current_index="$(line_index 'gnist current')" || fail "normal mode did not inspect theme state"
theme_index="$(line_index 'gnist reload')" || fail "normal mode did not reload the current theme"
run_index="$(line_index 'pgrep -x waybar')" || fail "run directive was not processed"
restart_index="$(line_index 'pkill -x mako')" || fail "restart directive was not processed"
((stop_index < prepare_index && prepare_index < current_index \
    && current_index < theme_index && theme_index < run_index \
    && run_index < restart_index)) \
    || fail "service/theme operations did not preserve stop/prepare/theme/run/restart order"
assert_absent 'gnist set aeryn' "normal mode replaced an existing theme"
[[ "$(grep -c '^pkill -x mako$' "$log")" -eq 1 ]] \
    || fail "duplicate service entries were not deduplicated"
assert_absent 'setsid sh -c mako --wrong-command' \
    "fragment duplicate overrode the main service entry"

# A first session initializes the configured default theme.
: >"$log"
SMIA_SESSION_TEST_HAS_CURRENT=0 "$session"
line_index 'gnist current' >/dev/null || fail "first session did not inspect theme state"
line_index 'gnist set aeryn' >/dev/null || fail "first session did not set the default theme"
assert_absent 'gnist reload' "first session reloaded a nonexistent current theme"

# Explicit apply always selects the configured default without inspecting state.
: >"$log"
"$session" --apply-theme
line_index 'gnist set aeryn' >/dev/null || fail "--apply-theme did not set the default theme"
assert_absent 'gnist current' "--apply-theme unnecessarily inspected current state"
assert_absent 'gnist reload' "--apply-theme redundantly reloaded after set"

# Explicit reapply republishes an existing current theme, but initializes when absent.
: >"$log"
"$session" --reapply-theme
line_index 'gnist current' >/dev/null || fail "--reapply-theme did not inspect current state"
line_index 'gnist reapply' >/dev/null || fail "--reapply-theme did not call gnist reapply"
assert_absent 'gnist set aeryn' "--reapply-theme replaced an existing current theme"

: >"$log"
SMIA_SESSION_TEST_HAS_CURRENT=0 "$session" --reapply-theme
line_index 'gnist set aeryn' >/dev/null \
    || fail "--reapply-theme did not initialize the default when no current theme exists"
assert_absent 'gnist reapply' "--reapply-theme reapplied without current state"

# Every requested Gnist operation is fatal on failure.
: >"$log"
assert_status 1 env SMIA_SESSION_TEST_GNIST_RELOAD_FAIL=1 "$session"
line_index 'gnist reload' >/dev/null || fail "reload failure fixture did not run"

: >"$log"
assert_status 1 env SMIA_SESSION_TEST_GNIST_SET_FAIL=1 "$session" --apply-theme
line_index 'gnist set aeryn' >/dev/null || fail "set failure fixture did not run"
assert_absent 'pgrep -x waybar' "services started after a failed theme activation"

: >"$log"
assert_status 1 env SMIA_SESSION_TEST_GNIST_REAPPLY_FAIL=1 "$session" --reapply-theme
line_index 'gnist reapply' >/dev/null || fail "reapply failure fixture did not run"
assert_absent 'pgrep -x waybar' "services started after a failed theme reapply"

# Refresh applies Malm, then requests a re-render.
: >"$log"
"$refresh"
mapfile -t commands <"$log"
[[ "${commands[0]:-}" == 'malm --state default apply' ]] \
    || fail "refresh did not apply the desktop state first"
line_index 'gnist reapply' >/dev/null || fail "refresh did not use --reapply-theme"

printf 'smia session tests passed\n'
