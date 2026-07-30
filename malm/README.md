# The Forge: Malm Configuration

This directory contains the Malm authoring source for Smia. It defines the
desktop files, commands, services, themes, and generated AerynOS system model.
The root [README](../README.md) covers installation. This guide covers how the
Forge is put together and where to change it.

For Malm language and command details, see the
[Malm repository](https://github.com/christian-bendiksen/malm) and its
[command line reference](https://github.com/christian-bendiksen/malm/blob/main/docs/cli.md).

## Source Flow

The source is loaded in this order:

```text
malm-pack.kdl
    -> malm.kdl
    -> malm/slots.kdl
    -> malm/modules.kdl
    -> malm/machines/laptop-4k.kdl
    -> malm/profiles.kdl
    -> ~/.config/malm/local.kdl
```

1. [`malm-pack.kdl`](../malm-pack.kdl) limits what enters the deployed pack. It
   names `malm.kdl`, captures `malm/`, `gnist/`, and required vendored files,
   and declares the format components.
2. [`malm.lock`](../malm.lock) locks the exact pack and component identities.
3. [`malm.kdl`](../malm.kdl) sets the target, metadata, shared variables, and
   assets. It then includes the rest of the source in a deliberate order.
4. [`slots.kdl`](slots.kdl) declares roles that allow one active provider, such
   as compositor, launcher, portal, shell, and bar.
5. [`modules.kdl`](modules.kdl) loads module definitions. A loaded module is
   inert until a profile uses it.
6. [`machines/laptop-4k.kdl`](machines/laptop-4k.kdl) supplies display values and
   extends the already loaded Kanshi module.
7. [`profiles.kdl`](profiles.kdl) loads providers, desktops, appearances, and
   gaming variants. A selected profile activates modules and resolves outputs.
8. The optional `~/.config/malm/local.kdl` overlay is declared last. When the
   file exists, plan creation reads it and records its bytes as a plan input.

This order matters. The machine can extend `kanshi` only after that module has
been declared. Profiles can use and replace modules only after all providers
have been declared.

## Where To Edit

| Change | Source |
|---|---|
| Shared fonts, assets, selected machine, or root metadata | `malm.kdl` |
| A desktop role and its provider limit | `malm/slots.kdl` |
| An application, command, service, or generated file | `malm/modules/<name>/` |
| Module include list | `malm/modules.kdl` |
| Display names, sizes, refresh rates, scales, or Kanshi layouts | `malm/machines/laptop-4k.kdl` |
| Stock desktop composition | `malm/profiles/desktop/desktop.kdl` |
| Compositor replacement and portal or package choice | `malm/profiles/providers/providers.kdl` |
| Astral values and fragments | `malm/profiles/astral/` |
| Studio values and fragments | `malm/profiles/studio/` |
| Gaming kernel variants | `malm/profiles/system/system.kdl` |
| Built-in theme data | `gnist/themes/data/<theme>/` |
| Personal machine values that should not be committed | `~/.config/malm/local.kdl` |

Edit the owner of a value. Do not copy a whole module into a profile for one
small difference. Set an input, patch a keyed collection, or replace a named
fragment instead.

## Modules And Profiles

Each module owns one application or one small concern. It can declare:

- A slot that it provides.
- Typed inputs and reusable types.
- Required commands.
- Replaceable native fragments.
- Files and generated outputs.

The active source gives useful examples:

- `desktop` uses the shared modules and Mango as the default compositor.
- `niri-provider` replaces the compositor slot with Niri, selects the GNOME
  portal backend, and changes the compositor package in `system-model`.
- `hyprland-provider` does the same for Hyprland and its portal backend.
- `kernel-gaming` changes only the keyed `kernel` package to `linux-gaming`.
- The `menu` module exposes a keyed `items` collection, so a profile can remove
  one built-in menu entry without copying the whole menu.
- The `hypr` module keeps bindings as a typed keyed collection and renders them
  as `hl.bind` calls in `hypr/hyprland.lua`.

Profiles should describe differences. Put defaults in modules, common desktop
composition in abstract profiles, and compositor-specific changes in provider
or concrete profiles.

## Profile Structure

There are 25 concrete profiles. `install` is the minimal bootstrap. The
other 24 combine compositor, appearance, and kernel choices.

| Family | Desktop kernel | Gaming kernel |
|---|---|---|
| Stock Mango | `mango` | `mango-gaming` |
| Stock Niri | `niri` | `niri-gaming` |
| Stock Hyprland | `hyprland` | `hyprland-gaming` |
| Astral Mango | `mango-astral` | `mango-gaming-astral` |
| Astral Niri | `niri-astral` | `niri-gaming-astral` |
| Astral Hyprland | `hyprland-astral` | `hyprland-gaming-astral` |
| Studio Mango | `mango-studio` | `mango-gaming-studio` |
| Studio Niri | `niri-studio` | `niri-gaming-studio` |
| Studio Hyprland | `hyprland-studio` | `hyprland-gaming-studio` |

These profiles are abstract and cannot be selected directly:

- `desktop` holds the shared desktop.
- `astral` holds shared Astral appearance and behavior.
- `studio` holds shared Studio appearance and behavior.
- `niri-provider` and `hyprland-provider` replace compositor, portal, and
  compositor package choices.
- `kernel-gaming` replaces the kernel package.

Inspect the source without changing deployed state:

```sh
malm source check --source .
malm source vars --source . --profile mango
malm source render --source . --profile mango --output /tmp/smia-render
```

Prepare a saved plan when deployment behavior also needs to be checked:

```sh
malm plan create --source . --profile mango --namespace default
malm plan show PLAN_ID
```

## Desktop And System Model

The desktop and package model are selected by the same profile and reviewed in
the same Malm plan. They still have separate apply boundaries.

The `system-model` module writes
`~/.local/share/smia-system-models/system-model.kdl`. Malm owns this file but
does not import it. The public helper keeps Moss explicit:

```sh
smia system-model path
smia system-model plan
smia system-model apply
```

Provider profiles change the compositor package. Gaming profiles change the
kernel package. This keeps package choices next to the desktop choices without
letting an unprivileged Malm apply make a privileged Moss change.

## Malm And Gnist

Malm owns stable deployment state. It installs theme data, application
templates, Gnist bindings, profile metadata, and files that point applications
at the current theme.

Gnist owns runtime theme state. It renders the selected palette, switches the
stable `gnist/themes/current` path, changes wallpaper and desktop settings, and
reloads applications. A normal `gnist set THEME` must not need a Malm deploy.

Malm format components cannot replace this runtime work. Components run only
while a plan is prepared. They have no filesystem, environment, network,
process, clock, randomness, or apply-time access. They receive only a typed
document, explicit options, and declared resource bytes.

### Add A Theme

1. Add `gnist/themes/data/<name>/colors.toml` and at least one file under
   `backgrounds/`.
2. Add any theme-owned static files, such as `icons.theme`, `neovim.lua`,
   `btop.theme`, or `vscode.json`. Add `light.mode` or `dark.mode` when the
   theme needs an explicit color-scheme choice.
3. Add a matching `dir` output to `malm/modules/gnist/gnist.kdl`. Theme folders
   are listed there one by one so Malm can own built-ins without owning themes
   installed by the user.
4. If an application needs a new generated theme file, put its template and
   binding in that application's module, not in the `gnist` module.
5. Deploy a plan, run `gnist set <name>`, and check the affected applications.
6. Run the complete checks in [`CONTRIBUTING.md`](../CONTRIBUTING.md).

## Generated Outputs

The default target is `~/.config`. A bare destination such as `waybar/config`
lands below that target. A destination beginning with `~/` can write elsewhere,
as the generated system model does.

Use these rules:

- Edit KDL inputs, native fragments, templates, or source files. Do not edit a
  deployed file marked as generated; Malm will replace it.
- Keep static JSONC, CSS, Lua, and KDL fragments in their native format when no
  generation is needed.
- Use typed renderers for structured generated data.
- Use templates for executable text or small substitutions.
- Declare every external command in the owning module's `requires` block. Malm
  combines active requirements into `smia/requirements.commands`.

The `hypr` module renders `hypr/hyprland.lua` as idiomatic Hyprland Lua: a
`format="lua"` program body includes `hyprland.lua.tpl` for the static structure
and interpolated scalars, then emits one `hl.bind` call per typed bind. The
`hypr/binds.list` cheatsheet comes from the same `binds` input, so the two
cannot drift. No component is involved, so every profile is source-renderable.

## Local Overrides

The root declares `~/.config/malm/local.kdl` as an optional overlay. If the file
exists, plan creation applies it and records it for review. `malm source vars`
and `malm source render` ignore it unless passed `--overlays`.

Override a machine value:

```kdl
variables {
    global.display-internal-scale 2.0 override=#true
}
```

Change an existing profile:

```kdl
extend-profile "mango-astral" {
    use "terminals" {
        with {
            opacity 0.9
        }
    }
}
```

Change the generated package model:

```kdl
extend-module "system-model" {
    inputs {
        input "packages" type="collection<package>" {
            defaults {
                item "local-tool" name="my-package"
            }
        }
    }
}
```

Keep modules, outputs, and included source files in the repository. The overlay
is for local values, not a second configuration tree.

## Menu Plugins

`smia menu` discovers executable `*.sh` files in this order. The first valid
plugin ID wins.

1. `$XDG_CONFIG_HOME/smia/menu.d`
2. `$XDG_DATA_HOME/smia/menu.d`
3. `$HOME/.local/share/smia/menu.d`
4. `smia/menu.d` below each directory in `$XDG_DATA_DIRS`

The filename without `.sh` is the plugin ID. It may contain lowercase letters,
numbers, and hyphens. A plugin needs a unique static label. Order is an unsigned
number and defaults to `50`.

```bash
#!/usr/bin/env bash
# smia-menu-label: My Tool
# smia-menu-order: 45

set -euo pipefail
exec my-tool
```

Local plugins must be executable. A local file can replace an installed plugin
by using the same filename. Only the selected plugin is run.

The built-in IDs are `toggles`, `keys`, `network`, `profiles`, `themes`,
`wallpaper`, `defaults`, `services`, and `power`. Profiles can remove managed
built-ins through the menu module:

```kdl
extend-profile "mango" {
    use "menu" {
        patch {
            collection "items" {
                remove "network"
                remove "services"
            }
        }
    }
}
```

Removing a managed built-in does not block a local plugin with the same ID.
Plugins can use the menu host for submenus and notifications:

```bash
choice=$(printf '%s\n' One Two | "${SMIA_MENU_COMMAND:-smia-menu}" pick "Choose")
"${SMIA_MENU_COMMAND:-smia-menu}" notify "Selected" "$choice"
```

Exit with `${SMIA_MENU_BACK_STATUS:-10}` to return from a submenu to the top
level. Other nonzero statuses are reported as plugin failures.
