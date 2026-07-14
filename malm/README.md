# Smia's Malm configuration

This directory contains the Malm side of Smia. It describes the files, programs,
and services that make up each desktop profile.

If you are new to Malm, start with the
[Malm repository](https://github.com/christian-bendiksen/malm). Its README and
docs explain the language, profile inheritance, rendering, state, and deployment.
This README is only about how Smia uses those features.

## Start here

The root [`malm.kdl`](../malm.kdl) file ties everything together. It defines the
target directory, shared values, assets, machine settings, modules, and profiles.

The rest is split by responsibility:

```text
malm.kdl                 Root configuration and includes
malm/slots.kdl           Desktop roles with a single active provider
malm/modules.kdl         Module index
malm/modules/<name>/     One application or concern and its supporting files
malm/profiles.kdl        Profile index
malm/profiles/desktop/   Stock desktop profiles
malm/profiles/astral/    Astral profiles and their native fragments
malm/machines/           Host-specific display and hardware values
```

Most changes begin in one of three places:

- Change an application in `modules/<name>/`.
- Change how applications are combined in `profiles/`.
- Change host-specific values in `machines/`.

## Profiles

Smia has one stock and one Astral profile for each supported compositor:

| Profile | Description |
|---|---|
| `mango` | Mango with the stock Smia appearance. This is the default. |
| `mango-astral` | Mango with the Astral appearance and behavior. |
| `niri` | Niri with the stock Smia appearance. |
| `niri-astral` | Niri with the Astral appearance and effects. |
| `hyprland` | Hyprland with the stock Smia appearance. |
| `hyprland-astral` | Hyprland with the Astral appearance, rules, and bindings. |

`desktop` and `astral` are abstract profiles. They hold shared configuration and
cannot be selected directly.

From the repository root, these are the useful development commands:

```sh
malm profiles --repo . --selectable
malm check --repo . --all-profiles
malm plan --repo . --profile mango-astral
malm vars --repo . --profile mango-astral
malm render --repo . --profile mango-astral --output /tmp/smia-render
```

Use `malm apply` only when you intend to replace the active deployment. See the
[Malm README](https://github.com/christian-bendiksen/malm#readme) for the apply,
tracking, and recovery workflows.

## How the configuration is organized

Each module owns one application or one small desktop concern. Its folder keeps
the module declaration beside any templates, fragments, or files it deploys.
For example, the Waybar module owns the generated configuration and its stock
style, while the Astral profile owns the Astral-specific Waybar files.

Slots describe roles that should only have one provider, such as the compositor
or launcher. A profile can replace the provider without rebuilding the rest of
the desktop. This is how the Niri and Hyprland profiles replace Mango while
keeping the shared desktop modules.

Profiles should mostly describe differences. Defaults belong in modules, shared
desktop behavior belongs in the abstract profiles, and compositor-specific
changes belong in the concrete profile that needs them.

Static configuration stays in its native format when there is no value to
generate. Malm validates those fragments and copies them into place. Generated
configuration uses Malm's typed format renderers. Templates are reserved for
files where textual substitution is actually useful, mostly shell scripts.

Gnist owns runtime colors and themes. Smia deploys the Gnist theme data, then
applications include the current theme where their formats allow it. A theme
change should not require another Malm deployment.

## Patterns worth stealing

These conventions have made the configuration easier to change without breaking
unrelated profiles:

- **Keep one concern in each module.** Put the declaration and all supporting
  files in the same folder so the whole integration is visible in one place.
- **Use typed inputs for real choices.** Gaps, font sizes, timeouts, paths, and
  feature switches should be inputs with sensible defaults. `malm vars` can then
  show both the final value and where it came from.
- **Use optionals instead of sentinel values.** If a setting can be absent, make
  it optional. Do not use an empty string or zero to secretly mean "disabled."
- **Give patchable lists stable keys.** Bindings and rules are keyed collections,
  so a profile can replace or remove one item without copying the entire list.
- **Keep modules isolated.** A module should depend on its own inputs, shared
  globals, and Malm built-ins, not on another module's private state.
- **Prefer native fragments for static files.** JSONC, CSS, and compositor
  fragments remain readable and editable in their original language.
- **Prefer typed renderers for generated data.** TOML, INI, XML, CSS, JSON, KDL,
  Lua, key-value, and line-list output should use the shared format machinery
  instead of custom string assembly.
- **Keep templates thin.** Templates work best for executable text and small
  substitutions. Put loops, conditions, and typed structure in KDL.
- **Separate deployment from runtime theming.** Malm decides what is installed;
  Gnist decides which colors and wallpaper are active right now.
- **Validate every profile.** A change to a shared module can affect all six
  selectable profiles, so run `malm check --all-profiles` before applying it.

## Local overrides

The root configuration optionally includes `~/.config/malm/local.kdl` last. Use
it for settings that belong to one machine or one person and should not be
committed here.

For example:

```kdl
variables {
    global.display-internal-scale 2.0 override=#true
}

extend-profile "mango-astral" {
    use "terminals" {
        with {
            font-size 10
        }
    }
}
```

Remote deployments need explicit permission to read this file. The full trust
model is documented in the
[Malm repository](https://github.com/christian-bendiksen/malm).

## Malm documentation

- [Malm overview and command reference](https://github.com/christian-bendiksen/malm#readme)
- [Profiles and composition](https://github.com/christian-bendiksen/malm/blob/main/docs/profiles.md)
- [Templating and rendering](https://github.com/christian-bendiksen/malm/blob/main/docs/templating.md)
