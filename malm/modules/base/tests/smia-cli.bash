#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
smia="$root/../../../system-models/malm/modules/cli/smia"
profiles="$root/bin/smia-profiles"
completion="$root/../shell/smia-completion.bash"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/config/smia"

fail() {
    printf 'smia-cli test: %s\n' "$*" >&2
    exit 1
}

shopt -s globstar nullglob
for stylesheet in "$root"/../../profiles/**/*.css; do
    [[ "$(<"$stylesheet")" != *'!important'* ]] \
        || fail "$stylesheet uses unsupported GTK CSS !important"
done

repo_root="$(cd "$root/../../.." && pwd)"
module_root="$root/.."
facade="$module_root/gnist/gnist.kdl"
niri_binding="$module_root/niri/gnist/niri.kdl"

[[ -r "$facade" ]] || fail "first-class Gnist facade is missing"
[[ ! -e "$module_root/gnist-core/gnist-core.kdl" ]] || fail "gnist-core still exists"
[[ ! -e "$module_root/gnist-runtime/gnist-runtime.kdl" ]] || fail "gnist-runtime still exists"
[[ ! -d "$repo_root/gnist/themes/templates" ]] || fail "central Gnist template directory still exists"
if grep -RqsE '^[[:space:]]*(dir|file|render) "gnist/themes/(data|templates|generated/live|live)"([[:space:]]|$)|to="gnist/themes/(data|templates|generated/live|live)"([[:space:]]|$)' \
    "$module_root"; then
    fail "a module owns a complete Gnist data, template, or live root"
fi
[[ "$(<"$facade")" != *'gnist/themes/data/forge'* ]] \
    || fail "Gnist facade owns Theme Forge data"

theme_dirs=("$repo_root"/gnist/themes/data/*)
((${#theme_dirs[@]} > 0)) || fail "no built-in themes found"
for theme_dir in "${theme_dirs[@]}"; do
    [[ -d "$theme_dir" ]] || fail "non-directory found in the theme data root: $theme_dir"
    theme="${theme_dir##*/}"
    owner="dir \"gnist/themes/data/$theme\" to=\"gnist/themes/data/$theme\""
    [[ "$(grep -Fc "$owner" "$facade")" -eq 1 ]] \
        || fail "built-in theme $theme is not individually owned"
done
[[ "$(grep -c 'to="gnist/themes/data/' "$facade")" -eq "${#theme_dirs[@]}" ]] \
    || fail "Gnist facade owns unexpected theme data directories"

mapfile -t module_kdls < <(printf '%s\n' "$module_root"/**/*.kdl)
mapfile -t template_files < <(printf '%s\n' "$module_root"/**/gnist/*.tpl | sort)
((${#template_files[@]} > 0)) || fail "no module-owned Gnist templates found"
for template_file in "${template_files[@]}"; do
    output="${template_file##*/}"
    owner="file \"./gnist/$output\" to=\"gnist/themes/templates/$output\""
    count="$(grep -hFc "$owner" "${module_kdls[@]}" \
        | awk '{ total += $1 } END { print total + 0 }')"
    [[ "$count" -eq 1 ]] || fail "template output $output has $count owners"
done
mapfile -t template_outputs < <(
    grep -hEo 'to="gnist/themes/templates/[^"[:space:]]+"' "${module_kdls[@]}" \
        | while IFS= read -r output; do
            output="${output#to=\"}"
            printf '%s\n' "${output%\"}"
        done
)
[[ "${#template_outputs[@]}" -eq "${#template_files[@]}" ]] \
    || fail "template files and individually owned outputs differ"
for output in "${template_outputs[@]}"; do
    leaf="${output#gnist/themes/templates/}"
    [[ -n "$leaf" && "$leaf" != */* ]] || fail "template output is not individually owned: $output"
done
duplicates="$(printf '%s\n' "${template_outputs[@]}" | sort | uniq -d)"
[[ -z "$duplicates" ]] || fail "duplicate template outputs: $duplicates"

binding_files=()
for binding_file in "$module_root"/**/gnist/*.kdl; do
    [[ "$binding_file" == "$facade" ]] || binding_files+=("$binding_file")
done
((${#binding_files[@]} > 0)) || fail "no module-owned Gnist binding drop-ins found"
for binding_file in "${binding_files[@]}"; do
    output="${binding_file##*/}"
    owner="render \"gnist/bindings.d/$output\" format=\"text\" validate=\"kdl-v2\""
    count="$(grep -hFc "$owner" "${module_kdls[@]}" \
        | awk '{ total += $1 } END { print total + 0 }')"
    [[ "$count" -eq 1 ]] \
        || fail "validated binding drop-in $output has $count owners"
done
mapfile -t binding_outputs < <(
    grep -hEo 'gnist/bindings\.d/[^"[:space:]]+\.kdl' "${module_kdls[@]}"
)
[[ "${#binding_outputs[@]}" -eq "${#binding_files[@]}" ]] \
    || fail "binding files and individually owned drop-ins differ"
for output in "${binding_outputs[@]}"; do
    leaf="${output#gnist/bindings.d/}"
    [[ -n "$leaf" && "$leaf" != */* ]] || fail "binding drop-in is not individually owned: $output"
done
duplicates="$(printf '%s\n' "${binding_outputs[@]}" | sort | uniq -d)"
[[ -z "$duplicates" ]] || fail "duplicate binding drop-ins: $duplicates"

if grep -Eq '^[[:space:]]*action[[:space:]]' "$niri_binding"; then
    fail "Niri binding uses Gnist's unsupported action strategy"
fi
grep -Fq 'argv "niri" "msg" "action" "load-config-file"' "$niri_binding" \
    || fail "Niri binding does not use the supported load-config-file command"

if grep -RqsE '"gnist/(session|services)\.d/|"gnist/(profile|default-theme|menu-theme|session\.services)"' \
    "$module_root"; then
    fail "Smia-owned state is still emitted below gnist"
fi
if grep -Eq '^[[:space:]]*@line([[:space:]]+\(f\))?"theme[[:space:]]' "$facade"; then
    fail "Smia service manifest still contains a theme directive"
fi

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
"$root/bin/smia-session" --help >/dev/null
assert_status 2 "$root/bin/smia-menu" extra
assert_status 2 "$root/bin/smia-refresh" extra
assert_status 2 "$root/bin/smia-session" --help extra
assert_status 2 "$profiles" unknown

cat > "$tmp/bin/malm" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *" profiles --selectable "*)
        printf '\n  PROFILES\n     hyprland\n     hyprland-astral\n     mango\n     mango-astral\n     mango-paper\n     mango-void\n     niri\n     niri-astral\n'
        ;;
    *" --profile hyprland --json vars "*|*" --profile hyprland-astral --json vars "*)
        printf '{"instances":[{"module": "hypr"}]}\n'
        ;;
    *" --profile mango --json vars "*|*" --profile mango-astral --json vars "*|\
    *" --profile mango-paper --json vars "*|\
    *" --profile mango-void --json vars "*)
        printf '{"instances":[{"module": "mango"}]}\n'
        ;;
    *" --profile niri --json vars "*|*" --profile niri-astral --json vars "*)
        printf '{"instances":[{"module": "niri"}]}\n'
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
mapfile -t choices
printf '%s\n' "${choices[@]}" > "$SMIA_TEST_WALKER_INPUT"
printf '%s\n' "$SMIA_TEST_WALKER_CHOICE"
EOF
cat > "$tmp/bin/smia-session" <<'EOF'
#!/usr/bin/env bash
printf 'session:%s\n' "$*"
EOF
cat > "$tmp/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$tmp/bin/malm" "$tmp/bin/walker" "$tmp/bin/smia-session" "$tmp/bin/pgrep"
printf 'mango\n' > "$tmp/config/smia/profile"
export SMIA_TEST_WALKER_INPUT="$tmp/walker-input"

output="$(SMIA_DESKTOP_STATE=desktop "$profiles" list)"
[[ "$output" == $'hyprland\nhyprland-astral\nmango\nmango-astral\nmango-paper\nmango-void\nniri\nniri-astral' ]] \
    || fail "profile listing was not parsed"
output="$(XDG_CONFIG_HOME="$tmp/config" "$profiles" current)"
[[ "$output" == mango ]] || fail "current profile was not read"
output="$(SMIA_DESKTOP_STATE=desktop XDG_CONFIG_HOME="$tmp/config" \
    XDG_CURRENT_DESKTOP=niri XDG_SESSION_DESKTOP=Hyprland \
    SMIA_TEST_WALKER_CHOICE='Niri (Astral)' "$profiles" select)"
[[ "$output" == $'malm:--state desktop --profile niri-astral apply -y\nsession:--apply-theme' ]] \
    || fail "profile selection did not switch the selected profile"
[[ "$(<"$SMIA_TEST_WALKER_INPUT")" == $'Niri\nNiri (Astral)' ]] \
    || fail "profile selection was not filtered to the running compositor"

output="$(env -u XDG_CURRENT_DESKTOP SMIA_DESKTOP_STATE=desktop \
    XDG_CONFIG_HOME="$tmp/config" XDG_SESSION_DESKTOP=niri \
    SMIA_TEST_WALKER_CHOICE='Niri' "$profiles" select)"
[[ "$output" == $'malm:--state desktop --profile niri apply -y\nsession:--apply-theme' ]] \
    || fail "profile selection did not detect the session desktop"
[[ "$(<"$SMIA_TEST_WALKER_INPUT")" == $'Niri\nNiri (Astral)' ]] \
    || fail "session desktop did not filter profiles"

output="$(env -u XDG_CURRENT_DESKTOP -u XDG_SESSION_DESKTOP SMIA_DESKTOP_STATE=desktop \
    XDG_CONFIG_HOME="$tmp/config" SMIA_TEST_WALKER_CHOICE='Mango (Paper)' "$profiles" select)"
[[ "$output" == $'malm:--state desktop --profile mango-paper apply -y\nsession:--apply-theme' ]] \
    || fail "profile selection did not fall back to the configured compositor"
[[ "$(<"$SMIA_TEST_WALKER_INPUT")" == \
    $'Mango (Default)\nMango (Astral)\nMango (Paper)\nMango (Void)' ]] \
    || fail "configured compositor fallback did not filter profiles"

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
