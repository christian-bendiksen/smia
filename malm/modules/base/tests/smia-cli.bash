#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
smia="$root/../../../system-models/malm/modules/cli/smia"
profiles="$root/bin/smia-profiles"
completion="$root/../shell/smia-completion.bash"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config/gnist"

fail() {
    printf 'smia-cli test: %s\n' "$*" >&2
    exit 1
}

assert_status() {
    local expected="$1"
    shift
    local actual=0
    "$@" >/dev/null 2>&1 || actual=$?
    [[ "$actual" -eq "$expected" ]] \
        || fail "expected status $expected, got $actual: $*"
}

cat > "$tmp/bin/smia-echo-args" <<'EOF'
#!/usr/bin/env bash
printf '<%s>\n' "$@"
EOF
cat > "$tmp/bin/smia-status" <<'EOF'
#!/usr/bin/env bash
exit 42
EOF
cat > "$tmp/bin/smia-side-effect" <<'EOF'
#!/usr/bin/env bash
touch "$SMIA_TEST_SENTINEL"
EOF
chmod +x "$tmp/bin"/smia-*
ln -s "$smia" "$tmp/bin/smia-loop"

smia_dir="$(dirname "$smia")"
export PATH="$tmp/bin:$smia_dir:$root/bin:/usr/bin:/bin"
export SMIA_TEST_SENTINEL="$tmp/executed"

output="$($smia echo-args "two words" "" --flag)"
[[ "$output" == $'<two words>\n<>\n<--flag>' ]] || fail "arguments changed during dispatch"
assert_status 42 "$smia" status
assert_status 127 "$smia" missing
assert_status 126 "$smia" loop
assert_status 2 "$smia" '../bad'

commands="$($smia list --names)"
[[ "$commands" == *echo-args* && "$commands" == *side-effect* ]] \
    || fail "installed commands were not discovered"
$smia help side-effect >/dev/null
[[ ! -e "$SMIA_TEST_SENTINEL" ]] || fail "help or list executed a plugin"

"$root/bin/smia-menu" --help >/dev/null
"$root/bin/smia-refresh" --help >/dev/null
"$root/bin/smia-profile" --help >/dev/null
"$root/bin/smia-session" --help >/dev/null
assert_status 2 "$root/bin/smia-menu" extra
assert_status 2 "$root/bin/smia-refresh" extra
assert_status 2 "$root/bin/smia-profile" one two
assert_status 2 "$root/bin/smia-session" --help extra
assert_status 2 "$profiles" unknown

cat > "$tmp/bin/malm" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *" profiles --selectable "*)
        printf '\n  PROFILES\n     mango\n     niri-astral\n'
        ;;
    *" apply -y "*)
        printf 'malm:%s\n' "$*"
        ;;
    *)
        printf 'unexpected malm arguments: %s\n' "$*" >&2
        exit 2
        ;;
esac
EOF
cat > "$tmp/bin/walker" <<'EOF'
#!/usr/bin/env bash
while IFS= read -r _; do :; done
printf 'Niri (Astral)\n'
EOF
cat > "$tmp/bin/smia-session" <<'EOF'
#!/usr/bin/env bash
printf 'session:%s\n' "$*"
EOF
chmod +x "$tmp/bin/malm" "$tmp/bin/walker" "$tmp/bin/smia-session"
printf 'mango\n' > "$tmp/config/gnist/profile"

output="$(SMIA_DESKTOP_STATE=desktop "$profiles" list)"
[[ "$output" == $'mango\nniri-astral' ]] || fail "profile listing was not parsed"
output="$(XDG_CONFIG_HOME="$tmp/config" "$profiles" current)"
[[ "$output" == mango ]] || fail "current profile was not read"
output="$(SMIA_DESKTOP_STATE=desktop XDG_CONFIG_HOME="$tmp/config" "$profiles" select)"
[[ "$output" == $'malm:--state desktop --profile niri-astral apply -y\nsession:--apply-theme' ]] \
    || fail "profile selection did not switch the selected profile"

# shellcheck source=/dev/null
source "$completion"
COMP_WORDS=(smia si)
COMP_CWORD=1
_smia_complete
[[ " ${COMPREPLY[*]} " == *" side-effect "* ]] || fail "completion missed a dynamic plugin"

COMP_WORDS=(smia profiles switch n)
COMP_CWORD=3
_smia_complete
[[ " ${COMPREPLY[*]} " == *" niri-astral "* ]] || fail "completion missed a profile"

COMP_WORDS=(smia system-model p)
COMP_CWORD=2
_smia_complete
[[ " ${COMPREPLY[*]} " == *" plan "* && " ${COMPREPLY[*]} " == *" path "* ]] \
    || fail "completion missed system-model commands"

COMP_WORDS=(smia install n)
COMP_CWORD=2
_smia_complete
[[ "${COMPREPLY[*]}" == 'niri-desktop niri-gaming' ]] \
    || fail "completion missed install model profiles"

COMP_WORDS=(smia install niri-gaming --a)
COMP_CWORD=3
_smia_complete
[[ "${COMPREPLY[*]}" == '--astral' ]] \
    || fail "completion missed install options"

printf 'smia CLI tests passed\n'
