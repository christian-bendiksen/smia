# Smia (The Forge)

Smia means The Forge. It is the real AerynOS desktop configuration I use and
test. The repository is public so other people can inspect it, copy useful
parts, or adapt the full setup.

Smia supports Mango, Niri, and Hyprland. Malm builds and deploys the selected
desktop and its AerynOS system model. Gnist changes themes at runtime.

## Screenshots

Aeryn Green
<img width="3840" height="2400" alt="AerynOS-green" src="https://github.com/user-attachments/assets/809ec86c-41f5-4bff-b88e-79095cd560bd" />
Aeryn Gold
<img width="3840" height="2400" alt="AerynOS-gold" src="https://github.com/user-attachments/assets/bdbfab56-be22-49d2-97fb-d577ade727a7" />
Astral
<img width="3840" height="2400" alt="Screenshot-2026-07-13_182001" src="https://github.com/user-attachments/assets/720549f1-3138-49a1-b24a-02be23b43b9e" />

## Requirements

- AerynOS with Moss and `sudo` access.
- Malm `>=0.4.0,<0.5` in `PATH`.
- Git and Bash.
- A local Smia checkout for the local install path. The examples use
  `$HOME/Dev/smia`. The remote path does not need one.

The selected system model includes Gnist and the desktop packages. Hyprland
profiles require Hyprland 0.55 or newer.

## Profile Choices

`smia install` accepts one model profile:

| Model profile | Compositor | Kernel |
|---|---|---|
| `mango-desktop` | Mango | `linux-desktop` |
| `mango-gaming` | Mango | `linux-gaming` |
| `niri-desktop` | Niri | `linux-desktop` |
| `niri-gaming` | Niri | `linux-gaming` |
| `hyprland-desktop` | Hyprland | `linux-desktop` |
| `hyprland-gaming` | Hyprland | `linux-gaming` |

Add `--astral` for the matching Astral profile.

The full selectable profiles are:

| Appearance | Desktop kernel | Gaming kernel |
|---|---|---|
| Stock Mango | `mango` | `mango-gaming` |
| Stock Niri | `niri` | `niri-gaming` |
| Stock Hyprland | `hyprland` | `hyprland-gaming` |
| Astral Mango | `mango-astral` | `mango-gaming-astral` |
| Astral Niri | `niri-astral` | `niri-gaming-astral` |
| Astral Hyprland | `hyprland-astral` | `hyprland-gaming-astral` |

## Install

Malm plans are saved review objects. Creating a plan does not change your home
directory. Applying the generated system model through Moss is a separate step.

### From A Local Checkout

Keep a local clone when you want to inspect or adapt the source before
deploying.

1. Clone Smia, initialize the Malm store, and record the source inputs.

```sh
git clone https://github.com/christian-bendiksen/smia.git "$HOME/Dev/smia"
cd "$HOME/Dev/smia"
repo="$(pwd -P)"

malm store init
malm source lock update --source "$repo"
```

`malm store init` needs a private state parent. Create it when it is missing:

```sh
state_parent=${XDG_STATE_HOME:-"$HOME/.local/state"}
install -d -m 700 "$state_parent"
```

Plan preparation reads `malm.lock`. Use `malm source lock create` when the file
is absent. Update the lock again after editing `malm.kdl`, `malm/`, `gnist/`,
pack declarations, or captured vendored files.

2. Prepare, review, and apply the small bootstrap profile. It installs the
   `smia` dispatcher and `smia install` command.

```sh
malm plan create --profile install --source "$repo" --namespace default
malm plan show PLAN_ID
malm plan apply PLAN_ID
```

If review prints an approval digest, the non-interactive form is:

```sh
malm plan apply PLAN_ID --approval SHA256_DIGEST
```

3. Prepare the full desktop and system-model plan. This example selects Niri,
   the gaming kernel, and Astral.

```sh
SMIA_SOURCE_ROOT="$repo" smia install niri-gaming --astral
```

`SMIA_SOURCE_ROOT` must be absolute and defaults to `$HOME/Dev/smia`.

4. Review and apply the returned Malm plan. This deploys configuration and the
   generated model file, but does not run Moss.

```sh
malm plan show PLAN_ID
malm plan apply PLAN_ID
```

5. Review the package transition, then apply it only when it is intended.

```sh
smia system-model plan
smia system-model apply
```

6. Initialize Gnist and start the configured session.

```sh
gnist init
smia session
```

### From A Remote Git Source

Track the repository directly without a local clone. Malm fetches the source
into private scratch space and remembers the moving selector for future updates
with `smia update`.

Tracking resolves the `malm.lock` committed at the tracked revision. That lock
must match its own commit. The `dev` branch carries a matching lock.

1. Initialize the Malm store and track Smia with the desired profile. This
   example selects Mango with the desktop kernel.

```sh
malm store init

track_scratch=$(mktemp -d)
chmod 700 "$track_scratch"
malm plan track \
    --source-url https://github.com/christian-bendiksen/smia.git \
    --selector refs/heads/dev \
    --git-executable /usr/bin/git \
    --root-scratch "$track_scratch" \
    --profile mango \
    --namespace default
rm -rf "$track_scratch"
```

This flow takes the profile names from the second table above, not the
`smia install` model profiles. Replace `mango` with `niri`, `hyprland`, or any
other concrete profile. Gaming variants append `-gaming`. Astral variants append
`-astral`.

2. Review and apply the returned plan. This deploys the desktop, CLI, and
   generated model file, but does not run Moss.

```sh
malm plan show PLAN_ID
malm plan apply PLAN_ID
```

3. Review the package transition, then apply it only when it is intended.

```sh
smia system-model plan
smia system-model apply
```

4. Initialize Gnist and start the configured session.

```sh
gnist init
smia session
```

The tracked namespace can be updated later with `smia update`, which re-fetches
the latest commit and prepares a new review plan.

## Daily Commands

The `smia` dispatcher finds installed `smia-*` commands in `PATH`.

| Command | What it does |
|---|---|
| `smia help [COMMAND]` | Shows dispatcher or command help. |
| `smia list [--names\|--verbose]` | Lists installed Smia commands. |
| `smia status` | Checks Malm drift, services, profile, theme, and required commands. |
| `smia update` | Prepares a plan from the tracked Git source. It never applies it. |
| `smia install MODEL_PROFILE [--astral]` | Prepares a local full-install plan. |
| `smia profiles list [--names]` | Lists appearance profiles. |
| `smia profiles current` | Prints the active profile. |
| `smia profiles select` | Opens the Walker profile picker. |
| `smia profiles switch PROFILE` | Applies a same-compositor appearance switch and refreshes the session. |
| `smia system-model path` | Prints the generated Moss model path. |
| `smia system-model plan` | Runs a Moss dry run for the generated model. |
| `smia system-model apply` | Imports the generated model through Moss. |
| `smia menu` | Opens the Walker system menu. |
| `smia menu list [--verbose]` | Lists discovered menu plugins. |
| `smia menu pick PLACEHOLDER` | Opens Walker for choices read from standard input. |
| `smia menu notify TITLE [BODY]` | Sends a notification with a terminal fallback. |
| `smia dnd toggle` | Toggles Mako do-not-disturb mode. |
| `smia dnd status [--waybar]` | Reports do-not-disturb state. |
| `smia idle toggle` | Toggles the idle inhibitor. |
| `smia idle status [--waybar]` | Reports idle inhibitor state. |
| `smia night-light toggle` | Toggles the night light. |
| `smia night-light start` | Starts the night light. |
| `smia night-light stop` | Stops the night light. |
| `smia night-light status` | Reports night-light state. |
| `smia record toggle [screen\|region]` | Starts or stops recording. |
| `smia record start [screen\|region]` | Starts recording. |
| `smia record stop` | Stops recording. |
| `smia record status [--waybar]` | Reports recording state. |
| `smia theme-links` | Relinks per-application theme files to the current theme. |
| `smia refresh` | Re-renders the current theme and refreshes the session. |
| `smia session [--apply-theme\|--reapply-theme]` | Reconciles session services and theme state. |
| `xdg-terminal-exec [COMMAND]` | Uses the terminal selected in Smia defaults. |

`smia profiles switch` keeps the active desktop or gaming kernel and rejects a
compositor change. Use `smia install MODEL_PROFILE` when changing compositor or
kernel so the desktop and package model are reviewed together.

Portal screen recording needs no extra privilege. Region recording uses direct
KMS capture and may need this one-time setup:

```sh
sudo setcap cap_sys_admin+ep /usr/bin/gsr-kms-server
```

## Updates

`smia update` runs `malm plan refresh` for the `default` namespace. It resolves
the moving Git selector that `malm plan track` saved during the initial remote
install. It does not apply the returned plan, run Moss, or change the session.

The local install path uses `malm plan create` and does not create Git tracking.
Update it by refreshing the checkout, the lock, and the plan for the installed
model profile:

```sh
cd "$HOME/Dev/smia"
git pull
repo="$(pwd -P)"

malm source lock update --source "$repo"
SMIA_SOURCE_ROOT="$repo" smia install niri-gaming --astral
```

Review every update in the same order:

```sh
malm plan show PLAN_ID
malm plan apply PLAN_ID
smia system-model plan
smia system-model apply
smia session
```

To switch a local install to tracked updates, either re-install with the remote
flow above or run `malm plan track` separately for the `default` namespace.

Theme changes do not need a Malm plan:

```sh
gnist set aeryn
```

## Aliases

The generated Bash configuration keeps these aliases:

| Alias | Expands to |
|---|---|
| `theme` | `gnist` |
| `omarchy-theme-install` | `gnist install` |
| `it` | `sudo moss it` |
| `up` | `sudo moss sync -u` |
| `sr` | `moss sr` |

## Learn And Change

- [The Forge configuration guide](malm/README.md)
- [Components](components/README.md)
- [Contributing](CONTRIBUTING.md)

## License

Project software is available under the [MIT License](LICENSE).
