#!/usr/bin/env bash

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
smia="$root/../cli/smia"
profiles="$root/bin/smia-profiles"
menu="$root/../menu/bin/smia-menu"
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
night_light="$module_root/night-light/night-light.kdl"

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

output_owner_count() {
    local destination="$1" count=0 line
    while IFS= read -r line; do
        case "$line" in
            *"render \"$destination\""*|*"to=\"$destination\""*)
                count=$((count + 1))
                ;;
        esac
    done < <(grep -hE '^[[:space:]]*(render|file|dir|symlink)[[:space:]]' "${module_kdls[@]}")
    printf '%d\n' "$count"
}

mapfile -t template_files < <(printf '%s\n' "$module_root"/**/gnist/*.tpl | sort)
((${#template_files[@]} > 0)) || fail "no module-owned Gnist templates found"
for template_file in "${template_files[@]}"; do
    output="${template_file##*/}"
    owner="file \"./gnist/$output\" to=\"gnist/themes/templates/$output\""
    count="$({ grep -hFc "$owner" "${module_kdls[@]}" || true; } \
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
    count="$(output_owner_count "gnist/bindings.d/$output")"
    [[ "$count" -eq 1 ]] \
        || fail "binding drop-in $output has $count owners"
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

mapfile -t menu_files < <(printf '%s\n' "$module_root"/**/menu.d/*.sh | sort)
((${#menu_files[@]} > 0)) || fail "no module-owned menu plugins found"
menu_outputs=()
for menu_file in "${menu_files[@]}"; do
    [[ "$menu_file" == "$module_root/menu/menu.d/"* ]] \
        || fail "menu plugin is not owned by the menu module: $menu_file"
    grep -Fq '# smia-menu-managed: true' "$menu_file" \
        || fail "built-in menu plugin is not marked as managed: $menu_file"
    output="${menu_file##*/}"
    count="$(output_owner_count "~/.local/share/smia/menu.d/$output")"
    [[ "$count" -eq 1 ]] || fail "menu plugin $output has $count owners"
    menu_outputs+=("$output")
done
duplicates="$(printf '%s\n' "${menu_outputs[@]}" | sort | uniq -d)"
[[ -z "$duplicates" ]] || fail "duplicate menu plugin outputs: $duplicates"

action_outputs=(
    '~/.local/bin/smia-idle'
    '~/.local/bin/smia-dnd'
    '~/.local/bin/smia-record'
    '~/.local/bin/smia-night-light'
    'smia/services.d/night-light'
)
for output in "${action_outputs[@]}"; do
    count="$(output_owner_count "$output")"
    [[ "$count" -eq 1 ]] || fail "output has $count owners: $output"
done
if grep -Fq 'render "smia/session.d/' "$night_light"; then
    fail "night light must not be session-managed; session refreshes must preserve its state"
fi

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
cat > "$tmp/bin/smia-exit42" <<'EOF'
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
assert_status 42 "$smia" exit42
assert_status 127 "$smia" missing
assert_status 126 "$smia" loop
assert_status 2 "$smia" '../bad'

commands="$($smia list --names)"
[[ "$commands" == *echo-args* && "$commands" == *side-effect* ]] \
    || fail "installed commands were not discovered"
$smia help side-effect >/dev/null
[[ ! -e "$SMIA_TEST_SENTINEL" ]] || fail "help or list executed a plugin"

"$menu" --help >/dev/null
"$root/bin/smia-refresh" --help >/dev/null
"$root/bin/smia-session" --help >/dev/null
assert_status 2 "$menu" extra
assert_status 2 "$root/bin/smia-refresh" extra
assert_status 2 "$root/bin/smia-session" --help extra
assert_status 2 "$profiles" unknown
assert_status 2 "$root/bin/smia-update" --bogus
assert_status 2 "$root/bin/smia-status" extra
assert_status 2 "$module_root/menu/bin/smia-idle" bogus
assert_status 2 "$module_root/menu/bin/smia-dnd" bogus
"$root/bin/smia-update" --help >/dev/null || fail "smia-update --help failed"
"$root/bin/smia-status" --help >/dev/null || fail "smia-status --help failed"
"$module_root/menu/bin/smia-idle" --help >/dev/null \
    || fail "smia-idle --help failed"
"$module_root/menu/bin/smia-dnd" --help >/dev/null \
    || fail "smia-dnd --help failed"

bash "$repo_root/tests/smia-profiles.bash" >/dev/null \
    || fail "profile behavior tests failed"
cat >"$tmp/config/smia/profiles" <<'EOF'
hyprland
hyprland-astral
mango
mango-astral
niri
niri-astral
EOF
printf 'mango\n' >"$tmp/config/smia/profile"
export XDG_CONFIG_HOME="$tmp/config"

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
[[ " ${COMPREPLY[*]} " == *" --astral "* ]] \
    || fail "completion missed the install --astral option"

COMP_WORDS=(smia install niri-gaming --allow)
COMP_CWORD=3
_smia_complete
[[ ${#COMPREPLY[@]} -eq 0 ]] \
    || fail "completion advertised removed component authorization"

COMP_WORDS=(smia install niri-gaming --p)
COMP_CWORD=3
_smia_complete
[[ ${#COMPREPLY[@]} -eq 0 ]] \
    || fail "completion advertised removed install options"

COMP_WORDS=(smia update --a)
COMP_CWORD=2
_smia_complete
[[ ${#COMPREPLY[@]} -eq 0 ]] \
    || fail "completion advertised removed update options"

COMP_WORDS=(smia idle t)
COMP_CWORD=2
_smia_complete
[[ " ${COMPREPLY[*]} " == *" toggle "* ]] || fail "completion missed idle commands"

COMP_WORDS=(smia record t)
COMP_CWORD=2
_smia_complete
[[ " ${COMPREPLY[*]} " == *" toggle "* ]] || fail "completion missed record modes"

printf 'smia CLI tests passed\n'
