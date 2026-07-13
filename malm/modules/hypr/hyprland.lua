-- Hyprland entry point (hand-written Lua; deployed verbatim by Malm).
--
-- Behavior lives here and is edited as plain Lua. The VALUES this file
-- applies — monitor geometry, config tables, binds, curves — are rendered by
-- Malm into ~/.config/hypr/config.lua from the module's typed inputs, so
-- profiles and the machine layer keep theming them without touching code.

local function fail(message)
    error("hyprland: " .. message, 0)
end

local function expect(value, kind, where)
    if type(value) ~= kind then
        fail(where .. " must be " .. kind)
    end
    return value
end

local HOME = expect(os.getenv("HOME"), "string", "HOME")
local cfg = dofile(HOME .. "/.config/hypr/config.lua")

hl.monitor(cfg.monitor)
hl.config(cfg.config)

for name, value in pairs(cfg.env) do
    hl.env(name, value)
end

hl.on("hyprland.start", function()
    hl.exec_cmd(cfg.startup_cmd)
end)

for name, points in pairs(cfg.curves) do
    hl.curve(name, { type = "bezier", points = points })
end

for _, animation in ipairs(cfg.animations) do
    hl.animation(animation)
end

for _, gesture in ipairs(cfg.gestures) do
    hl.gesture(gesture)
end

for _, device in ipairs(cfg.devices) do
    hl.device(device)
end

for _, rule in ipairs(cfg.window_rules) do
    hl.window_rule(rule)
end

-- A bind row is { chord = "...", action = "dotted.path.in.hl.dsp",
-- arg = scalar-or-table (optional), opts = table (optional) }.
local function dispatcher(action)
    local target = hl.dsp
    for part in action:gmatch("[^%.]+") do
        target = target[part]
        if target == nil then
            fail("unknown dispatcher `" .. action .. "`")
        end
    end
    return target
end

for _, bind in ipairs(cfg.binds) do
    local dispatch = dispatcher(bind.action)
    local invocation
    if bind.arg ~= nil then
        invocation = dispatch(bind.arg)
    else
        invocation = dispatch()
    end
    hl.bind(bind.chord, invocation, bind.opts)
end

for workspace = 1, cfg.workspaces.count do
    local key = workspace % 10
    hl.bind(cfg.workspaces.mod .. " + " .. key, hl.dsp.focus({ workspace = workspace }))
    hl.bind(cfg.workspaces.mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = workspace }))
end

-- ---------------------------------------------------------------------------
-- Theme bridge: load the gnist theme table defensively, then apply it.
-- ---------------------------------------------------------------------------

local function expect_keys(value, allowed, where)
    expect(value, "table", where)
    for key in pairs(value) do
        if not allowed[key] then
            fail(where .. " contains unknown key " .. tostring(key))
        end
    end
end

local function inert(value, where, depth)
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then
        return
    end
    if kind ~= "table" then
        fail(where .. " contains non-data value " .. kind)
    end
    if depth > 12 or getmetatable(value) ~= nil then
        fail(where .. " contains deep or metatable-backed data")
    end
    for key, child in pairs(value) do
        local key_kind = type(key)
        if key_kind ~= "string" and key_kind ~= "number" then
            fail(where .. " contains a non-scalar key")
        end
        inert(child, where, depth + 1)
    end
end

local function load_inert(path, where)
    local chunk, load_error = loadfile(path, "t", {})
    if not chunk then
        fail("cannot load " .. where .. ": " .. tostring(load_error))
    end
    local ok, value = pcall(chunk)
    if not ok then
        fail("cannot evaluate " .. where .. ": " .. tostring(value))
    end
    expect(value, "table", where)
    inert(value, where, 0)
    return value
end

local theme_path = HOME .. "/.config/gnist/themes/current/hyprland.lua"
local theme = load_inert(theme_path, "theme")
expect_keys(theme, { general = true, group = true }, "theme")
if theme.general ~= nil then
    expect_keys(theme.general, { col = true }, "theme.general")
    expect_keys(theme.general.col, { active_border = true, inactive_border = true }, "theme.general.col")
    for key, value in pairs(theme.general.col) do
        expect(value, "string", "theme.general.col." .. key)
    end
end
if theme.group ~= nil then
    expect_keys(theme.group, { col = true }, "theme.group")
    expect_keys(theme.group.col, { border_active = true, border_inactive = true }, "theme.group.col")
    for key, value in pairs(theme.group.col) do
        expect(value, "string", "theme.group.col." .. key)
    end
end
hl.config(theme)
