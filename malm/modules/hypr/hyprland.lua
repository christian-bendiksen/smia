-- This file owns Hyprland behavior; config.lua contains profile data.

local home = os.getenv("HOME")
local cfg = dofile(home .. "/.config/hypr/config.lua")

hl.monitor(cfg.monitor)
hl.config(cfg.config)

for name, value in pairs(cfg.env) do
    hl.env(name, value)
end

hl.on("hyprland.start", function()
    hl.exec_cmd(cfg.startup_cmd)
end)

for _, curve in ipairs(cfg.curves) do
    hl.curve(curve.name, { type = "bezier", points = curve.points })
end

for _, animation in ipairs(cfg.animations) do
    hl.animation(animation)
end

for _, gesture in ipairs(cfg.gestures) do
    hl.gesture(gesture)
end

for _, rule in ipairs(cfg.window_rules) do
    hl.window_rule(rule)
end

local theme_ok, theme = pcall(dofile, home .. "/.config/gnist/themes/current/hyprland.lua")
if theme_ok then
    hl.config(theme)
end

for workspace = 1, cfg.workspaces.count do
    local key = workspace % 10
    hl.bind(cfg.workspaces.mod .. " + " .. key, hl.dsp.focus({ workspace = workspace }))
    hl.bind(cfg.workspaces.mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = workspace }))
end

local function dispatcher(action)
    local target = hl.dsp
    for part in action:gmatch("[^%.]+") do
        target = target[part]
        if target == nil then
            error("hyprland: unknown dispatcher `" .. action .. "`", 0)
        end
    end
    return target
end

local function invocation(bind)
    local dispatch = dispatcher(bind.action)
    if bind.arg.kind == "none" then
        return dispatch()
    end
    if bind.arg.kind == "value" then
        return dispatch(bind.arg.value)
    end
    if bind.arg.kind == "record" then
        local value = {}
        for name, item in pairs(bind.arg) do
            if name ~= "kind" then
                value[name] = item
            end
        end
        return dispatch(value)
    end
    error("hyprland: unknown argument kind `" .. tostring(bind.arg.kind) .. "`", 0)
end

for _, bind in ipairs(cfg.binds) do
    local call = invocation(bind)
    if next(bind.opts) ~= nil then
        hl.bind(bind.chord, call, bind.opts)
    else
        hl.bind(bind.chord, call)
    end
end
