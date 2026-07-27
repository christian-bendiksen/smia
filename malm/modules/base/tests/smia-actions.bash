#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
modules_root="$(dirname "$root")"
idle="$modules_root/menu/bin/smia-idle"
dnd="$modules_root/menu/bin/smia-dnd"
terminals_kdl="$modules_root/terminals/terminals.kdl"
screenshot_kdl="$modules_root/screenshot/screenshot.kdl"
screenshot_tpl="$modules_root/screenshot/gnist-screenshot.tpl"
record_kdl="$modules_root/record/record.kdl"
record_tpl="$modules_root/record/smia-record.tpl"
night_tpl="$modules_root/night-light/smia-night-light.tpl"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/runtime" "$tmp/home"
chmod 700 "$tmp/runtime" "$tmp/home"
log="$tmp/commands.log"

fail() {
    printf 'smia-actions test: %s\n' "$*" >&2
    exit 1
}

for command in pkill notify-send; do
    cat >"$tmp/bin/$command" <<'EOF'
#!/usr/bin/env bash
entry="${0##*/}"
for arg in "$@"; do
    entry+=" <$arg>"
done
printf '%s\n' "$entry" >>"$ACTIONS_TEST_LOG"
EOF
done
chmod +x "$tmp/bin"/*

export PATH="$tmp/bin:/usr/bin:/bin"
export ACTIONS_TEST_LOG="$log"

# --- smia-idle (real sleep child, stubbed pgrep) ---
sleep 60 &
sleep_pid=$!
cat >"$tmp/bin/pgrep" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == "-x hypridle" ]]; then
    printf '%s\n' "$sleep_pid"
    exit 0
fi
exit 1
EOF
chmod +x "$tmp/bin/pgrep"
"$idle" status >/dev/null && fail "running daemon reported as inhibited"
output="$("$idle" status --waybar)"
[[ "$output" == '{"text":""}' ]] || fail "idle waybar off JSON wrong: $output"
: >"$log"
"$idle" toggle
sleep 0.1
state="$(ps -o state= -p "$sleep_pid" | tr -d ' ')"
[[ "$state" == T* ]] || fail "idle toggle did not stop the daemon"
grep -q '^pkill <-RTMIN+9> <waybar>$' "$log" || fail "idle toggle did not signal waybar"
"$idle" status >/dev/null || fail "stopped daemon not reported as inhibited"
output="$("$idle" status --waybar)"
[[ "$output" == '{"text":"󰒲","tooltip":"Idle Inhibitor: on","class":"active"}' ]] \
    || fail "idle waybar on JSON wrong: $output"
"$idle" toggle
sleep 0.1
state="$(ps -o state= -p "$sleep_pid" | tr -d ' ')"
[[ "$state" != T* ]] || fail "idle toggle did not resume the daemon"
kill "$sleep_pid" 2>/dev/null || true
idle_rc=0
"$idle" bogus 2>/dev/null || idle_rc=$?
[[ "$idle_rc" -eq 2 ]] || fail "idle bogus mode did not fail with usage"

# --- smia-dnd (stubbed makoctl) ---
cat >"$tmp/bin/makoctl" <<'EOF'
#!/usr/bin/env bash
state_file="$ACTIONS_TEST_DND_STATE"
case "$*" in
    mode) [[ -r "$state_file" ]] && cat "$state_file" ;;
    "mode -a do-not-disturb") printf 'do-not-disturb\n' >"$state_file" ;;
    "mode -r do-not-disturb") : >"$state_file" ;;
esac
EOF
chmod +x "$tmp/bin/makoctl"
export ACTIONS_TEST_DND_STATE="$tmp/dnd-state"
"$dnd" status >/dev/null && fail "dnd reported on before enabling"
: >"$log"
"$dnd" toggle
grep -q '^pkill <-RTMIN+10> <waybar>$' "$log" || fail "dnd toggle did not signal waybar"
"$dnd" status >/dev/null || fail "dnd not reported on after enabling"
output="$("$dnd" status --waybar)"
[[ "$output" == '{"text":"󰂛","tooltip":"Do Not Disturb: on","class":"active"}' ]] \
    || fail "dnd waybar on JSON wrong: $output"
"$dnd" toggle
"$dnd" status >/dev/null && fail "dnd reported on after disabling"
output="$("$dnd" status --waybar)"
[[ "$output" == '{"text":""}' ]] || fail "dnd waybar off JSON wrong: $output"

# Bare invocation defaults to toggle so terminal use refreshes the bar.
: >"$log"
"$dnd"
"$dnd" status >/dev/null || fail "bare dnd invocation did not toggle"
grep -q '^pkill <-RTMIN+10> <waybar>$' "$log" \
    || fail "bare dnd invocation did not signal waybar"
"$dnd" toggle

# --- generation-home portability ---
grep -Fq 'input "theme-kitty" type="string" default="~/.config/gnist/themes/current/kitty.conf"' "$terminals_kdl" \
    || fail "Kitty theme path is not preserved for runtime expansion"
grep -Fq 'input "theme-alacritty" type="string" default="~/.config/gnist/themes/current/alacritty.toml"' "$terminals_kdl" \
    || fail "Alacritty theme path is not preserved for runtime expansion"
grep -Fq 'input "theme-ghostty" type="string" default="~/.config/gnist/themes/current/ghostty.conf"' "$terminals_kdl" \
    || fail "Ghostty theme path is not preserved for runtime expansion"
grep -Fq 'input "directory" type="string" default="~/Pictures/Screenshots"' "$screenshot_kdl" \
    || fail "screenshot directory is generation-home dependent"
grep -Fq 'input "directory" type="string" default="~/Videos/Recordings"' "$record_kdl" \
    || fail "recording directory is generation-home dependent"
for record_requirement in mkfifo pkill python3; do
    grep -Fq "command \"$record_requirement\"" "$record_kdl" \
        || fail "record module does not require $record_requirement"
done

generation_home="/home/smia-generation-user"
terminal_outputs=$'include ~/.config/gnist/themes/current/kitty.conf\n'
terminal_outputs+=$'import = ["~/.config/gnist/themes/current/alacritty.toml"]\n'
terminal_outputs+='config-file = ~/.config/gnist/themes/current/ghostty.conf'
[[ "$terminal_outputs" != *"$generation_home"* && "$terminal_outputs" != *'/home/christian'* ]] \
    || fail "terminal output contains a generation-home literal"

sed -e "s|{{directory:shell-word}}|'~/Pictures/Screenshots'|" \
    "$screenshot_tpl" >"$tmp/bin/gnist-screenshot"
chmod +x "$tmp/bin/gnist-screenshot"
[[ "$(<"$tmp/bin/gnist-screenshot")" != *"$generation_home"* \
    && "$(<"$tmp/bin/gnist-screenshot")" != *'/home/christian'* ]] \
    || fail "rendered screenshot script contains a generation-home literal"
cat >"$tmp/bin/grim" <<'EOF'
#!/usr/bin/env bash
entry="grim"
last=""
for arg in "$@"; do
    entry+=" <$arg>"
    last="$arg"
done
printf '%s\n' "$entry" >>"$ACTIONS_TEST_LOG"
: >"$last"
EOF
chmod +x "$tmp/bin/grim"
: >"$log"
HOME="$tmp/home" gnist-screenshot screen
grep -q "^grim <$tmp/home/Pictures/Screenshots/Screenshot-" "$log" \
    || fail "screenshot output did not use runtime HOME"

# --- rendered smia-record (placeholders substituted by hand) ---
sed -e "s|{{directory:shell-word}}|'~/Videos/Recordings'|" \
    -e "s|{{fps}}|30|" \
    -e "s|{{audio-source:shell-word}}|default_output|" \
    -e "s|{{screen-target:shell-word}}|portal|" \
    "$record_tpl" >"$tmp/bin/smia-record"
chmod +x "$tmp/bin/smia-record"
[[ "$(<"$tmp/bin/smia-record")" != *"$generation_home"* \
    && "$(<"$tmp/bin/smia-record")" != *'/home/christian'* ]] \
    || fail "rendered recorder script contains a generation-home literal"
export ACTIONS_TEST_RECORDER_MODE="$tmp/recorder-mode"
export ACTIONS_TEST_RECORDER_PIDS="$tmp/recorder-pids"
export ACTIONS_TEST_RECORDER_EXIT="$tmp/recorder-exit"
printf 'normal\n' >"$ACTIONS_TEST_RECORDER_MODE"
cat >"$tmp/bin/gpu-screen-recorder" <<'EOF'
#!/usr/bin/env bash
entry="gpu-screen-recorder"
for arg in "$@"; do
    entry+=" <$arg>"
done
printf '%s\n' "$entry" >>"$ACTIONS_TEST_LOG"
printf '%s %s\n' "$$" "$PPID" >>"$ACTIONS_TEST_RECORDER_PIDS"
if [[ "$(<"$ACTIONS_TEST_RECORDER_MODE")" == early ]]; then
    echo "gsr info: gsr_kms_client_init: gsr-kms-server is missing sys_admin cap" >&2
    exit 127
fi
trap 'printf "recorder-term <%s>\n" "$$" >>"$ACTIONS_TEST_LOG"; exit 0' TERM
while true; do
    [[ ! -e "$ACTIONS_TEST_RECORDER_EXIT" ]] || exit 42
    sleep 0.05
done
EOF
cat >"$tmp/bin/slurp" <<'EOF'
#!/usr/bin/env bash
printf '100x200+10+20\n'
EOF
chmod +x "$tmp/bin/gpu-screen-recorder" "$tmp/bin/slurp"
export XDG_RUNTIME_DIR="$tmp/runtime"
export HOME="$tmp/home"
record_runtime="$tmp/runtime/smia-record"
state_file="$record_runtime/active"

wait_for_path_absent() {
    local path="$1"
    local attempt
    for ((attempt = 0; attempt < 100; attempt++)); do
        [[ -e "$path" || -L "$path" ]] || return 0
        sleep 0.05
    done
    return 1
}

wait_for_process_exit() {
    local pid="$1"
    local attempt
    for ((attempt = 0; attempt < 100; attempt++)); do
        kill -0 "$pid" 2>/dev/null || return 0
        sleep 0.05
    done
    return 1
}

: >"$log"
record_rc=0
smia-record status >"$tmp/out" || record_rc=$?
[[ "$record_rc" -eq 1 && "$(<"$tmp/out")" == idle ]] || fail "record idle status wrong"
output="$(smia-record status --waybar)"
[[ "$output" == '{"text":""}' ]] || fail "record waybar idle JSON wrong: $output"
smia-record start >"$tmp/start-one.out" 2>&1 &
start_one=$!
smia-record start >"$tmp/start-two.out" 2>&1 &
start_two=$!
wait "$start_one" || fail "first concurrent recorder start failed"
wait "$start_two" || fail "second concurrent recorder start failed"
[[ "$(grep -c '^gpu-screen-recorder ' "$log")" -eq 1 ]] \
    || fail "concurrent starts launched more than one recorder"
[[ -r "$state_file" ]] || fail "record start wrote no state file"
[[ "$(stat -c %a "$state_file")" == 600 ]] || fail "record state file is not private"
mapfile -t recorder_state <"$state_file"
[[ "${#recorder_state[@]}" -eq 3 && "${recorder_state[0]}" == smia-record-v2 \
    && "${recorder_state[1]}" == session.* \
    && "${recorder_state[2]}" =~ ^[0-9a-f]{64}$ ]] \
    || fail "record state does not use the PID-free v2 schema"
session_dir="$record_runtime/${recorder_state[1]}"
[[ -d "$record_runtime" && "$(stat -c %a "$record_runtime")" == 700 ]] \
    || fail "record runtime directory is not private"
[[ -d "$session_dir" && "$(stat -c %a "$session_dir")" == 700 ]] \
    || fail "record session directory is not private"
[[ -p "$session_dir/control" && "$(stat -c %a "$session_dir/control")" == 600 ]] \
    || fail "record control FIFO is not private"
for private_file in "$session_dir/lease" "$session_dir/output"; do
    [[ -f "$private_file" && "$(stat -c %a "$private_file")" == 600 ]] \
        || fail "record session file is not private: $private_file"
done
read -r recorder_pid supervisor_pid <"$ACTIONS_TEST_RECORDER_PIDS"
[[ "${recorder_state[*]}" != *" $recorder_pid "* \
    && "${recorder_state[*]}" != *" $supervisor_pid "* ]] \
    || fail "frontend state stores a numeric process ID"
state_temps=("$record_runtime"/.active.*)
[[ ! -e "${state_temps[0]}" ]] || fail "record start left a state temporary file"
grep -q '^gpu-screen-recorder .*<-w> <portal>' "$log" || fail "portal target missing"
grep -q '<-restore-portal-session> <yes>' "$log" \
    || fail "portal session restore flag missing"
grep -q "<-o> <$tmp/home/Videos/Recordings/Recording-" "$log" \
    || fail "recording output did not use runtime HOME"
grep -q '^pkill <-RTMIN+8> <waybar>$' "$log" || fail "record start did not signal waybar"
smia-record status >/dev/null || fail "record status not recording after start"
output="$(smia-record status --waybar)"
[[ "$output" == '{"text":"󰑊","tooltip":"Screen Recording: on","class":"active"}' ]] \
    || fail "record waybar on JSON wrong: $output"

# Stops serialize behind the same lock; only the supervisor sends one TERM to
# its still-unreaped recorder child.
: >"$log"
stop_pids=()
for stop_number in 1 2 3 4; do
    smia-record stop >"$tmp/stop-$stop_number.out" 2>&1 &
    stop_pids+=("$!")
done
for stop_pid in "${stop_pids[@]}"; do
    wait "$stop_pid" || fail "concurrent recorder stop failed"
done
[[ ! -e "$state_file" ]] || fail "record stop left recorder state"
wait_for_path_absent "$session_dir" || fail "record stop left its private session"
[[ "$(grep -c '^recorder-term ' "$log" || true)" -eq 1 ]] \
    || fail "concurrent stops signaled the recorder more than once"
grep -q '^pkill <-RTMIN+8> <waybar>$' "$log" || fail "record stop did not signal waybar"
smia-record status >/dev/null && fail "record status recording after stop"
: >"$log"
: >"$ACTIONS_TEST_RECORDER_PIDS"
smia-record toggle region
grep -q '<-region> <100x200+10+20>' "$log" || fail "region geometry missing"
smia-record toggle
[[ ! -e "$state_file" ]] || fail "record toggle did not stop"

# Malformed state is removed without interpreting any field as a process ID.
printf 'malformed\n' >"$state_file"
: >"$log"
record_rc=0
smia-record status >"$tmp/out" || record_rc=$?
[[ "$record_rc" -eq 1 && ! -e "$state_file" ]] \
    || fail "malformed recorder state was not cleaned up"

# A valid-looking but unowned FIFO has no reader. The nonblocking client must
# reject it promptly and remove only the private stale session.
stale_session="$record_runtime/session.STALEFIFO1"
mkdir "$stale_session"
chmod 700 "$stale_session"
mkfifo -m 600 "$stale_session/control"
: >"$stale_session/lease"
printf '%s\n' "$tmp/stale-recording.mp4" >"$stale_session/output"
chmod 600 "$stale_session/lease" "$stale_session/output"
stale_token="$(printf '0%.0s' {1..64})"
printf 'smia-record-v2\n%s\n%s\n' \
    "${stale_session##*/}" "$stale_token" >"$state_file"
chmod 600 "$state_file"
record_rc=0
timeout 3 smia-record status >"$tmp/out" || record_rc=$?
[[ "$record_rc" -eq 1 && "$(<"$tmp/out")" == idle \
    && ! -e "$state_file" && ! -e "$stale_session" ]] \
    || fail "stale recorder FIFO was not cleaned up promptly"

# Even a full stale FIFO cannot block a frontend write. Its unrelated holder is
# not signaled or otherwise used as recorder identity.
full_session="$record_runtime/session.FULLFIFO1"
mkdir "$full_session"
chmod 700 "$full_session"
mkfifo -m 600 "$full_session/control"
: >"$full_session/lease"
printf '%s\n' "$tmp/full-fifo-recording.mp4" >"$full_session/output"
chmod 600 "$full_session/lease" "$full_session/output"
python3 - "$full_session/control" <<'PY' &
import os
import sys
import time

fd = os.open(sys.argv[1], os.O_RDWR | os.O_NONBLOCK)
while True:
    try:
        os.write(fd, b"x" * 4096)
    except BlockingIOError:
        break
time.sleep(10)
PY
fifo_holder=$!
sleep 0.1
printf 'smia-record-v2\n%s\n%s\n' \
    "${full_session##*/}" "$stale_token" >"$state_file"
chmod 600 "$state_file"
record_rc=0
timeout 3 smia-record status >"$tmp/out" || record_rc=$?
[[ "$record_rc" -eq 1 && ! -e "$state_file" && ! -e "$full_session" ]] \
    || fail "full stale recorder FIFO blocked or survived cleanup"
kill -0 "$fifo_holder" 2>/dev/null || fail "stale FIFO cleanup affected its unrelated holder"
kill "$fifo_holder"
wait "$fifo_holder" 2>/dev/null || true

# Simulate PID reuse with a legacy state record naming a currently live,
# unrelated process. V2 rejects the record and never sends it a signal.
sleep 60 &
unrelated_pid=$!
printf 'smia-record-v1\n%s\nreused-start\nreused-exe\nreused-recorder\n%s\n' \
    "$unrelated_pid" "$tmp/unrelated.mp4" >"$state_file"
chmod 600 "$state_file"
smia-record stop
kill -0 "$unrelated_pid" 2>/dev/null || fail "PID reuse state signaled an unrelated process"
[[ ! -e "$state_file" ]] || fail "PID reuse state was not discarded"
kill "$unrelated_pid"
wait "$unrelated_pid" 2>/dev/null || true

# Killing the supervisor releases its lease and the kernel parent-death signal
# kills the recorder. The next frontend call cleans the stale private state.
: >"$log"
: >"$ACTIONS_TEST_RECORDER_PIDS"
smia-record start
read -r recorder_pid supervisor_pid <"$ACTIONS_TEST_RECORDER_PIDS"
mapfile -t recorder_state <"$state_file"
dead_session="$record_runtime/${recorder_state[1]}"
kill -KILL "$supervisor_pid"
wait_for_process_exit "$recorder_pid" || fail "supervisor death left the recorder running"
record_rc=0
timeout 3 smia-record status >"$tmp/out" || record_rc=$?
[[ "$record_rc" -eq 1 && "$(<"$tmp/out")" == idle \
    && ! -e "$state_file" && ! -e "$dead_session" ]] \
    || fail "supervisor death left stale recorder state"

# A recorder that exits after startup is observed without reaping, then its
# state and Waybar indicator are cleaned before the supervisor finally reaps it.
: >"$log"
: >"$ACTIONS_TEST_RECORDER_PIDS"
smia-record start
mapfile -t recorder_state <"$state_file"
exit_session="$record_runtime/${recorder_state[1]}"
touch "$ACTIONS_TEST_RECORDER_EXIT"
wait_for_path_absent "$state_file" || fail "unexpected recorder exit left active state"
wait_for_path_absent "$exit_session" || fail "unexpected recorder exit left its session"
rm -f "$ACTIONS_TEST_RECORDER_EXIT"
grep -q '^pkill <-RTMIN+8> <waybar>$' "$log" \
    || fail "unexpected recorder exit did not refresh waybar"
grep -q '^notify-send <Screen Recording> <Recorder failed; see ' "$log" \
    || fail "unexpected recorder exit did not report failure"

record_rc=0
smia-record bogus 2>/dev/null || record_rc=$?
[[ "$record_rc" -eq 2 ]] || fail "record bogus mode did not fail with usage"

# An invalid XDG runtime directory is rejected before any shared state is used.
mkdir "$tmp/insecure-runtime"
chmod 755 "$tmp/insecure-runtime"
record_rc=0
output="$(XDG_RUNTIME_DIR="$tmp/insecure-runtime" smia-record status 2>&1)" || record_rc=$?
[[ "$record_rc" -eq 1 && "$output" == *'mode 0700'* ]] \
    || fail "insecure XDG_RUNTIME_DIR was not rejected"
[[ ! -e "$tmp/insecure-runtime/smia-record" ]] \
    || fail "insecure XDG_RUNTIME_DIR received recorder state"

# Without XDG_RUNTIME_DIR, state lives in a private per-user HOME directory,
# never in shared /tmp.
mkdir "$tmp/fallback-home"
chmod 700 "$tmp/fallback-home"
record_rc=0
output="$(env -u XDG_RUNTIME_DIR HOME="$tmp/fallback-home" smia-record status 2>&1)" \
    || record_rc=$?
[[ "$record_rc" -eq 1 && "$output" == idle ]] || fail "private runtime fallback failed: $output"
fallback_runtime="$tmp/fallback-home/.local/state/smia/record"
[[ -d "$fallback_runtime" && "$(stat -c %a "$fallback_runtime")" == 700 ]] \
    || fail "fallback runtime directory is not private"
[[ "$(<"$record_tpl")" != *'${XDG_RUNTIME_DIR:-/tmp}'* ]] \
    || fail "recorder retains the shared /tmp fallback"

# A recorder that dies with the KMS capability error produces a setcap hint.
printf 'early\n' >"$ACTIONS_TEST_RECORDER_MODE"
: >"$log"
: >"$ACTIONS_TEST_RECORDER_PIDS"
record_rc=0
smia-record start >/dev/null 2>&1 || record_rc=$?
[[ "$record_rc" -eq 1 ]] || fail "dead recorder start did not fail"
[[ ! -e "$state_file" ]] || fail "dead recorder left state"
early_sessions=("$record_runtime"/session.*)
[[ ! -e "${early_sessions[0]}" ]] || fail "dead recorder left a private session"
grep -q '^notify-send <Screen Recording> <KMS capture needs a one-time setup' "$log" \
    || fail "KMS capability failure did not produce the setcap hint"

# --- rendered smia-night-light ---
sed -e "s|{{latitude}}|59.9|" \
    -e "s|{{longitude}}|10.8|" \
    -e "s|{{night-temp}}|4000|" \
    -e "s|{{day-temp}}|6500|" \
    "$night_tpl" >"$tmp/bin/smia-night-light"
chmod +x "$tmp/bin/smia-night-light"

# The flag file stands in for a running wlsunset: the stub creates it, the
# pgrep stub reports from it, and the pkill stub removes it.
export ACTIONS_TEST_NIGHT_FLAG="$tmp/night-flag"
cat >"$tmp/bin/wlsunset" <<'EOF'
#!/usr/bin/env bash
entry="wlsunset"
for arg in "$@"; do
    entry+=" <$arg>"
done
printf '%s\n' "$entry" >>"$ACTIONS_TEST_LOG"
touch "$ACTIONS_TEST_NIGHT_FLAG"
EOF
cat >"$tmp/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "-x wlsunset" && -e "$ACTIONS_TEST_NIGHT_FLAG" ]]
EOF
cat >"$tmp/bin/pkill" <<'EOF'
#!/usr/bin/env bash
entry="pkill"
for arg in "$@"; do
    entry+=" <$arg>"
done
printf '%s\n' "$entry" >>"$ACTIONS_TEST_LOG"
[[ "$*" == "-x wlsunset" ]] && rm -f "$ACTIONS_TEST_NIGHT_FLAG"
exit 0
EOF
chmod +x "$tmp/bin/wlsunset" "$tmp/bin/pgrep" "$tmp/bin/pkill"

: >"$log"
smia-night-light start
grep -q '^wlsunset <-l> <59.9> <-L> <10.8> <-t> <4000> <-T> <6500>$' "$log" \
    || fail "night-light start args wrong"
[[ -e "$ACTIONS_TEST_NIGHT_FLAG" ]] || fail "night-light start did not launch wlsunset"
: >"$log"
smia-night-light start
grep -q wlsunset "$log" && fail "night-light start relaunched a running daemon"
night_rc=0
smia-night-light status >"$tmp/out" || night_rc=$?
[[ "$night_rc" -eq 0 && "$(<"$tmp/out")" == on ]] || fail "night-light on status wrong"
: >"$log"
smia-night-light toggle
grep -q '^pkill <-x> <wlsunset>$' "$log" || fail "night-light toggle did not stop"
[[ ! -e "$ACTIONS_TEST_NIGHT_FLAG" ]] || fail "night-light toggle left the daemon running"
night_rc=0
smia-night-light status >"$tmp/out" || night_rc=$?
[[ "$night_rc" -eq 1 && "$(<"$tmp/out")" == off ]] || fail "night-light off status wrong"
: >"$log"
smia-night-light toggle || fail "night-light toggle start reported failure"
grep -q '^wlsunset <-l>' "$log" || fail "night-light toggle did not start the daemon"
[[ -e "$ACTIONS_TEST_NIGHT_FLAG" ]] || fail "night-light toggle start left the daemon off"

printf 'smia actions tests passed\n'
