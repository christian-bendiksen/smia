# Smia system models

This directory is a nested Malm configuration for Smia's AerynOS system models.
It is tracked in the `smia-system-models` state, separately from the root desktop
configuration, even though both configurations come from the same repository.

Malm owns the generated model and helper commands in the home directory. Moss
changes remain a separate, explicit action.

## Profiles

Choose one compositor and one kernel:

| Profile | Compositor | Kernel |
|---|---|---|
| `mango-desktop` | Mango | `linux-desktop` |
| `mango-gaming` | Mango | `linux-gaming` |
| `niri-desktop` | Niri | `linux-desktop` |
| `niri-gaming` | Niri | `linux-gaming` |
| `hyprland-desktop` | Hyprland | `linux-desktop` |
| `hyprland-gaming` | Hyprland | `linux-gaming` |

Each concrete model profile writes:

```text
~/.local/share/smia-system-models/system-model.kdl
~/.local/share/smia-system-models/profile
~/.local/bin/smia-system-model
```

The model is the imported Moss source of truth, not an incremental package list.
It includes the selected kernel and compositor along with the shared firmware,
portals, fonts, desktop applications, and bootstrap tools required by Smia.

## Bootstrap

The `install` profile writes only `smia` and `smia-install`. Apply it from the
repository root as documented in the main [README](../README.md), then run:

```sh
smia install mango-desktop --plan
smia install mango-desktop
```

Use `--astral` for the matching Astral desktop profile. The full installer first
previews the generated model, Moss transition, and root desktop deployment. It
then applies the model state, asks Moss to import the model, applies the desktop
state, and checks required commands with `malm doctor`.

## Review And Apply

After installation, inspect and activate the generated model directly with:

```sh
smia system-model path
smia system-model plan
smia system-model apply
```

`plan` runs a Moss dry run. `apply` imports the model through `sudo` and leaves
Moss's normal confirmation behavior intact. Applying or updating the Malm state
alone never changes system packages.

Update the tracked model configuration with:

```sh
malm --state smia-system-models update
smia system-model plan
```

Switch model profiles with:

```sh
malm --state smia-system-models --profile niri-gaming apply
smia system-model plan
```

The direct `smia-system-model` command remains available for recovery.

## Local Overrides

Create `~/.config/malm/smia-system-models.kdl` for machine-specific repositories
or packages. Every package in the imported model, including `malm`, must exist
in one of its declared indexes. If Malm was installed from a local repository,
expose that repository to every model through `model-base`:

```kdl
extend-profile "model-base" {
    use "system-model" {
        patch {
            collection "repositories" {
                append "local" {
                    local {
                        description "Local packages"
                        uri "file:///home/me/.cache/local_repo/x86_64/stone.index"
                        priority 100
                    }
                }
            }
            collection "packages" {
                append "gamescope" { gamescope }
            }
        }
    }
}
```

Extending `model-base` affects all six concrete profiles. Extend
`model-mango`, `model-niri`, or `model-hyprland` for one compositor, or extend a
concrete profile when a change should affect only one combination.

Repository and package inputs are ordered `collection<kdl-document>` values.
Their keys are internal patch handles and do not appear in the generated KDL.
The `kernel`, `compositor`, and `portal-backend` keys can be replaced
independently, keeping profile layers composable.

## Local Development

Validate every nested profile from the repository root:

```sh
malm --repo system-models --state smia-system-models check --all-profiles
```

Render a profile without applying it:

```sh
malm \
    --repo system-models \
    --state smia-system-models \
    --profile mango-gaming \
    render --output /tmp/smia-system-models
```

The preview model is written under
`/tmp/smia-system-models/HOME/.local/share/smia-system-models/`.

## License

This project is available under the [MIT License](../LICENSE).
