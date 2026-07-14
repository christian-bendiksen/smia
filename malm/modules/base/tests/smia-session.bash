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
((current_index < service_index && service_index < reload_index)) \
    || fail "Gnist reload did not run after service startup"

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
