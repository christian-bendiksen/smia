-- Malm installs this loader without taking ownership of the user's init.lua.
-- A missing or invalid theme must not stop Neovim startup.
local path = vim.fn.expand("~/.config/gnist/themes/current/neovim.lua")
local ok, theme = pcall(dofile, path)
return ok and theme or {}
