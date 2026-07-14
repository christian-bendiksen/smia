#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
session="$root/bin/smia-session"
refresh="$root/bin/smia-refresh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config/gnist"
log="$tmp/commands.log"

fail() {
    printf 'smia-session test: %s\n' "$*" >&2
    exit 1
}

cat >"$tmp/bin/gnist" <<'EOF'
#!/usr/bin/env bash
printf 'gnist %s\n' "$*" >>"$SMIA_SESSION_TEST_LOG"
EOF

cat >"$tmp/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
printf 'pgrep %s\n' "$*" >>"$SMIA_SESSION_TEST_LOG"
[[ "${SMIA_SESSION_TEST_PROCESSES_MISSING:-0}" == 1 ]] && exit 1
exit 0
EOF

cat >"$tmp/bin/pkill" <<'EOF'
#!/usr/bin/env bash
printf 'pkill %s\n' "$*" >>"$SMIA_SESSION_TEST_LOG"
exit 0
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

cat >"$tmp/bin/waybar" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$tmp/bin"/*
export PATH="$tmp/bin:$root/bin:/usr/bin:/bin"
export XDG_CONFIG_HOME="$tmp/config"
export SMIA_SESSION_TEST_LOG="$log"

cat >"$tmp/config/gnist/session.services" <<'EOF'
theme aeryn
run waybar waybar
EOF

line_index() {
    local needle="$1" index=0 line
    while IFS= read -r line; do
        [[ "$line" == "$needle" ]] && { printf '%s\n' "$index"; return 0; }
        ((index += 1))
    done <"$log"
    return 1
}

: >"$log"
"$session"
current_index="$(line_index 'gnist current')" || fail "normal session did not inspect the active theme"
service_index="$(line_index 'pgrep -x waybar')" || fail "normal session did not process services"
reload_index="$(line_index 'gnist reload')" || fail "normal session did not reload Gnist"
((current_index < reload_index && reload_index < service_index)) \
    || fail "Gnist reload did not run before service startup"

cat >"$tmp/config/gnist/session.services" <<'EOF'
theme aeryn
restart waybar
EOF
: >"$log"
SMIA_SESSION_TEST_PROCESSES_MISSING=1 "$session"
reload_index="$(line_index 'gnist reload')" || fail "restart session did not reload Gnist"
restart_index="$(line_index 'pkill -x waybar')" || fail "restart session did not reconcile Waybar"
((reload_index < restart_index)) \
    || fail "Waybar was restarted before receiving Gnist's reload signal"

cat >"$tmp/config/gnist/session.services" <<'EOF'
theme aeryn
run waybar waybar
EOF

: >"$log"
"$refresh"
mapfile -t commands <"$log"
[[ "${commands[0]:-}" == 'malm --state default apply' ]] \
    || fail "refresh did not apply the desktop state first"
line_index 'gnist reload' >/dev/null || fail "refresh did not reload Gnist"

: >"$log"
"$session" --apply-theme
line_index 'gnist set aeryn' >/dev/null || fail "--apply-theme did not select the configured theme"
if line_index 'gnist reload' >/dev/null; then
    fail "--apply-theme redundantly reloaded after gnist set"
fi

cat >"$tmp/config/gnist/session.services" <<'EOF'
theme keep
EOF
: >"$log"
"$session"
line_index 'gnist reload' >/dev/null || fail "theme keep did not reload Gnist"

printf 'smia session tests passed\n'
