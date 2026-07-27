# render-lua-data

`render-lua-data` is the Malm format component used for
`~/.config/hypr/config.lua`. The `hypr` module gives it resolved typed data. It
returns a deterministic Lua 5.4 data module.

The component is capability-free. It has no imports and cannot read files,
environment variables, network data, clocks, random data, processes, or host
state. It runs only while Malm prepares a plan.

## Request

The request must contain:

- Contract version 1.
- Typed document version 1.
- A record at the document root.
- Exactly one string option: `format="lua"`.
- No resources.

It accepts booleans, signed integers, unsigned integers up to `i64::MAX`, finite
floating-point numbers, text, paths, lists, records, and collections.

It rejects null values, invalid paths, duplicate keys, unsupported numbers,
cycles, shared or unreachable arena values, malformed requests, and values over
the contract limits.

## Output

The media type is `text/x-lua`. Output has this shape:

```lua
return {
    identifier = "value",
    ["non-identifier"] = {
        true,
    },
}
```

Tables use four-space indentation, multiple lines, and trailing commas. List
order is kept. Record and collection keys are sorted. A key uses normal Lua
identifier syntax only when it is a valid identifier and not a Lua 5.4 reserved
word. Other keys use bracketed strings.

Strings use fixed Lua escapes. Floating-point values use the shortest decimal
that round-trips to the same value. A `.0` suffix is added when needed to keep a
Lua floating-point literal distinct from an integer literal.

## Build And Verify

Run the supported wrapper from the repository root:

```sh
MALM_ROOT=/path/to/malm tools/render-lua-data-component verify
```

After an intentional source change, update the checked artifact with:

```sh
MALM_ROOT=/path/to/malm tools/render-lua-data-component update
```

Both commands build twice in isolated copied workspaces and require identical
bytes. They also check the WIT shape and invoke the result through Malm. `update`
is the only command that should replace `vendor/render-lua-data.wasm` and
`vendor/render-lua-data.manifest.json`.

See the [components guide](../README.md) for build requirements and
[`CONTRIBUTING.md`](../../CONTRIBUTING.md) for the full update checklist.
