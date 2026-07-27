# Components

This workspace contains the active reproducible source and build tools for
Smia's `render-lua-data` Malm component. The component turns Malm's typed
Hyprland data into deterministic Lua.

Start with [`render-lua-data/README.md`](render-lua-data/README.md) for the data
contract and output format.

## Layout

| Path | Purpose |
|---|---|
| `render-lua-data/` | Component source, tests, and WIT interface. |
| `component-builder/` | Packs the core WebAssembly module and checks its component shape. |
| `component-builder/malm-host-check/` | Admits and invokes the result through the real Malm host. |
| `Cargo.toml` and `Cargo.lock` | Locked Rust workspace. |
| `rust-toolchain.toml` | Rust 1.95.0 and the `wasm32-unknown-unknown` target. |
| `../tools/render-lua-data-component` | Supported verify and update command. |

## Requirements

- Rustup, Cargo, Rust 1.95.0, and `wasm32-unknown-unknown`.
- A matching Malm 0.4.0 checkout at `../malm` beside Smia.
- The locked Cargo dependencies already present in the local Cargo cache. The
  reproducible build runs offline.

`MALM_ROOT` may name the Malm checkout, but it must match the Cargo path
dependencies used by `malm-host-check`.

## Verify

Run from the Smia repository root:

```sh
MALM_ROOT=/path/to/malm tools/render-lua-data-component verify
```

Verification:

1. Builds native packing and Malm host-check helpers.
2. Builds the component in two copied workspaces with separate Cargo homes,
   target directories, homes, and temporary directories.
3. Removes inherited compiler wrappers and flags, remaps build paths, and
   rejects embedded host paths.
4. Requires both component byte streams to be identical.
5. Checks the exact WIT interface and component import and export shape.
6. Admits and invokes the component through Malm.
7. Compares the rebuilt component and manifest with the checked files under
   `vendor/`.

## Update

Use update only after an intentional component change:

```sh
MALM_ROOT=/path/to/malm tools/render-lua-data-component update
```

This runs the same checks, then replaces the checked component and manifest.
The component digest in `malm-pack.kdl`, the Malm lock, and affected golden
output must also agree with the new artifact. Follow the component checklist in
[`CONTRIBUTING.md`](../CONTRIBUTING.md).
