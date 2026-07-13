-- Malm installs this loader without taking ownership of the user's init.lua.
-- The theme symlink targets the current gnist Neovim payload.
-- Loading failures return an empty table; inspect `require("gnist.theme")`
-- directly when diagnosing a missing or invalid theme payload.
-- Load with `local theme = require("gnist")` from init.lua.
local ok, theme = pcall(require, "gnist.theme")
return ok and theme or {}
