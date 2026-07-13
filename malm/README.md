# smia — Malm configuration (v2)

The config is composed from **modules** that fill **slots**; **profiles**
pick which modules are active and tune them through typed `with` blocks,
native **fragments**, and keyed **collection patches**. Every file is small
and single-purpose; start at the repo-root `malm.kdl` and follow the
includes.

The core v2 rule: **KDL controls structure; templates contain
target-language text and typed substitutions only.** There is no `{{#if}}`,
`{{#each}}`, or `{{#range}}` inside text — structure lives in
`when` / `each` / `range` nodes around `emit-*`
parts, and templates carry only `{{<codec> <name>}}` substitutions.

```text
malm.kdl            config + meta + assets + global.font-* + includes
malm/
  slots.kdl            slot registry: the roles a session needs filled
  modules.kdl          index → modules/<name>/<name>.kdl (one package per module)
  profiles.kdl         index → profiles/<family>/<family>.kdl
  machines/<name>.kdl  machine layer: TYPED global.display-* geometry per
                       host (ints/floats); root includes exactly one machine file
  modules/<name>/      ONE self-contained package per module — its <name>.kdl plus
                       every template part / fragment / native tree it deploys.
                       Open one folder, see the whole app. Examples:
                          lock-idle/ { lock-idle.kdl }
                         waybar/    { waybar.kdl, config-default.jsonc, styles/ }
                         niri/      { niri.kdl (structural KDL + bind collection),
                                      effects-default.kdl }
  profiles/<family>/   ONE self-contained package per profile family, symmetric
                       with modules — its <family>.kdl composition plus that
                       family's NATIVE fragment assets. Examples:
                         desktop/ { desktop.kdl }   (module defaults ARE this look)
                         astral/  { astral.kdl, waybar/ swayosd/ hypr/ niri/ }
                         ember/   { ember.kdl,  waybar/ swayosd/ niri/ }
install/               bootstrap / installer (not a malm source)
gnist/themes/        gnist ENGINE palette blob (data/ + templates/); the
                       gnist-core module deploys it, and its `{{ }}` are engine
                       tokens malm copies verbatim — never renders
```

## The module contract

A module has five clearly separated sections:

```kdl
module "lock-idle" {
    description "Screen locking and idle policy"
    slot "…"                        // optional: the role it fills

    requires { command "hyprlock" } // checked by `malm doctor`
    inputs   { … }                  // the typed public API
    fragments { … }                 // profile-replaceable native files
    outputs  { … }                  // config-file / text-file / file / dir / symlink
}
```

1. **One app per module.** The package holds the `<name>.kdl` and every
   template part / fragment it deploys, including its session fragment in
   `gnist/session.d/<name>` for `smia-session`.
2. **Inputs are module-scoped.** `blur-size`, not `lock-blur-size` —
   profiles set them inside `use "lock-idle" { with { blur-size 9 } }` and
   diagnostics qualify them as `lock-idle.blur-size`.
3. **Values are typed all the way down.** bool / int / float / string /
   path / list / record / keyed collection. Optionals (`optional=#true`)
   model true omission — `#null` clears them, `when-set` guards
   them; there are no `""`/`0` sentinels and no implicit truthiness.
4. **Fragments are native.** A profile-replaceable file (waybar config or
   niri effects) is a `fragment` slot composed verbatim —
   real syntax, real comments, no substitution.
5. **Sources are `./`-relative.** They resolve against the declaring file's
   directory, so a package is relocatable; `..` and absolute paths are
   rejected. (Repo-relative paths are tolerated only for the documented
   shared payload dirs, e.g. `gnist/themes/`.)

Enforced mechanically: `scripts/lint-contract.sh` + `malm check
--all-profiles` (every module API, every profile override, every patch,
every fragment, every reference, every generated document) +
`scripts/verify.sh` (renders the full matrix into a throwaway HOME without
applying it; `--snapshot` provides byte-diff refactor proofs).

CI discovers selectable non-abstract profiles from their declarations and uses
`malm render`, never `apply`. Each profile is rendered twice to compare its
manifest, then rendered shell, TOML, XML, and Malm-declared native formats
are validated. See [`../docs/malm-v2.md`](../docs/malm-v2.md).

```sh
malm check --all-profiles           # validate everything
malm plan   --profile mango-astral  # dry-run
malm vars   --profile mango-astral  # resolved inputs with provenance
malm render --profile mango-astral --output /tmp/render   # deterministic manifest
malm doctor --profile mango-astral  # requires{} report
malm apply  --profile mango-astral  # deploy

# The full profile matrix:
#   default          stock desktop + mango
#   niri / hypr      same desktop with compositor swapped
#   mango-astral     premium mango + astral ✦-banner lock
#   niri-astral      premium niri + astral effects
#   hypr-astral      premium Hyprland + astral rules/binds
#   mango-ember      fireside warmth on mango + ❖ lock
#   niri-ember       fireside warmth on niri + ember effects
```

## Model

| Concept | Role |
|---|---|
| `slots {}` | registry of roles (`compositor`, `bar`, …; all `max=1`); two active providers for one slot is a check-time error |
| `module "x" { … }` | inert, reusable; five-section contract above |
| `profile "p" { extends …; use "x" { with{} fragments{} patch{} } }` | composes modules; `replace slot="…" module="…"` swaps providers along the chain |
| `variables { global.* }` | cross-module design tokens — fonts, display geometry; the only user values a module can read besides its own inputs |

Modules are **isolated**: outputs render with built-ins (`malm.target`,
`profile.name`, `machine.hostname`, `instance.name`, `instance.module`) +
`global.*` + the module's own typed inputs — never another module's state.

Profile merge rules: parents are processed in written order, ancestors once;
child values override ancestors; **conflicting sibling-parent values are
errors** unless the child resolves them; instances are identified by alias;
slot replacement is explicit.

## Patterns worth stealing

- **Typed scalars as inputs** — anything a profile tunes numerically
  (gaps, blur, timeouts) is a typed input with a default; `malm vars`
  shows source attribution for every value.
- **Optionals instead of sentinels** — hyprlock's `blur-size`, `mark`, and
  the idle listeners are `optional=#true`: unset leaves no trace in the
  output (`when-set` guards the lines), and a profile disables a
  listener with `keyboard-dim-seconds #null`.
- **Keyed collections for patchable lists** — Mango and Niri binds and Mango
  rules are collection items with stable keys. Profiles patch by
  key (`replace "focus-left" …`, `remove "screenshot"`, `append "mine" …`)
  instead of restating lists; position is preserved on replace. Mango items
  contain generic `repeat "bind"`, `repeat "windowrule"`, or
  `repeat "layerrule"` directives ready for key/value splicing.
- **Structured Lua program** — Hyprland 0.55 generates one validated
  `hyprland.lua` directly from generic Lua calls, objects, functions,
  expressions, and control flow. Malm understands Lua structure but has no
  Hyprland schema or API-specific nodes. The generated program sandbox-loads
  and validates the closed Gnist theme table and never calls
  `require("hyprland")`.
- **Generic format generators** — TOML, INI, XML, CSS, key/value, line-list,
  scalar, JSON, JSONC, Lua, and KDL outputs are typed `config-file`
  documents.
  Application modules map their options into these shared serializers instead
  of owning formats or dialects. Hyprlock, Hypridle, and Mango add native
  validators to generic key/value output; Kanshi adds its validator to generic line-list.
  Ordinary nodes are fields/groups, repeated fields/groups use `repeat`,
  valueless assignments use `empty`, and line-list/scalar roots use `value`.
- **Structural KDL generation** — niri's config.kdl and binds.kdl are
  `config-file` documents with `format="kdl" version=1`: ordinary nodes
  serialize to the target, `(ref)"gaps"` inserts typed scalars, and
  `splice "binds"` expands the bind collection. The finished document is re-parsed as KDL syntax version
  1 before it can reach disk. `version` selects target syntax, not an
  application dialect; `config-file` remains generic-only.
- **Fragments for whole-surface swaps** — waybar's config/style, niri's
  effects, and swayosd's stylesheet are native files a profile
  replaces with `fragments { replace "config" source="./waybar/config.jsonc" }`
  (the `./` resolves against the profile's own folder).
- **Validated static fragments** — profile-selected JSONC and GTK CSS remain
  native source files because they contain no generated values. Malm
  validates them before composition instead of translating static syntax into
  KDL for its own sake.
- **Templates only for executable code** — Bash startup files and generated
  scripts retain substitution-only templates. Generated data belongs in a
  typed format generator.
- **App-level includes for runtime theming** — colors are never rendered by
  Malm. Outputs `source=`/`include=`/`import` the file Gnist maintains
  under `~/.config/gnist/themes/current/`, so `gnist set` changes themes
  without a `malm apply`. The generated Hyprland program sandbox-loads a
  data-only Lua table from that directory and applies its closed color schema
  with `hl.config`; themes cannot add behavior.
- **`{{literal "…"}}` for target-language braces** — waybar's own
  `{{title}}` tokens live in native fragments (or `{{literal "{{title}}"}}`
  in a template) and reach the output verbatim.

## Profile families

`desktop` is the shared base (extended, never selected). `default`, `niri`,
`hypr` take module defaults; the compositor variants use
`replace slot="compositor" module="…"`. `astral` holds shared premium
styling and is extended by `mango-astral` / `niri-astral` / `hypr-astral`;
`ember` is the warm-aesthetic family, extended by `mango-ember` /
`niri-ember`. `with` values merge along the `extends` chain — later
profiles state only what differs.

### Aesthetic register (per family)

- **default** — hairline edge-to-edge bar; radius 0; line-work selection.
- **astral** — vertical translucent rail; neon glow on accent; `✦` mark;
  zoom-into-place entrances; cool blue-tinted shadows.
- **ember** — floating horizontal bar with margin on all sides; warm amber
  glow; `❖` mark; slide-in / fade-out motion; warm-tinted shadows;
  gruvbox default palette.

## Local overrides

`~/.config/malm/local.kdl` is included last (optional) and layers on
top: explicit `extend-profile` blocks add local settings and later `with`
values win. Replace cross-cutting `global.*` constants with
`override=#true`; for per-profile knobs target a module input or patch a collection:

```kdl
variables { global.display-internal-scale 2.0 override=#true }

extend-profile "mango-astral" {
    use "mango" {
        with { gappoh 20 }
        patch { collection "binds" {
            replace "focus-left" {
                repeat "bind" "SUPER,Left,focusdir,left"
            }
        } }
    }
}
```

Machine geometry and the tracked-versus-local override workflow are detailed
in [`../docs/machines.md`](../docs/machines.md).
