return {
  {
    "folke/tokyonight.nvim",
    priority = 1000,
    opts = {
      style = "moon",
      transparent = false,
      styles = {
        comments = { italic = true },
      },
      on_colors = function(colors)
        colors.bg = "#0f111a"
        colors.bg_dark = "#0f111a"
        colors.bg_sidebar = "#0f111a"
        colors.bg_float = "#161928"
        colors.bg_statusline = "#161928"
        colors.bg_popup = "#262b42"
        colors.bg_highlight = "#1e2235"
        colors.fg = "#c8d3f5"
        colors.fg_gutter = "#444a73"
        colors.border = "#444a73"
        colors.blue = "#82aaff"
        colors.cyan = "#86e1fc"
        colors.green = "#c3e88d"
        colors.magenta = "#c099ff"
        colors.red = "#ff757f"
        colors.yellow = "#ffc777"
      end,
      on_highlights = function(hl, colors)
        hl.Comment = { fg = "#c099ff", italic = true }
        hl.LineNr = { fg = "#828bb8" }
        hl.CursorLineNr = { fg = "#82aaff", bold = true }
        hl.CursorLine = { bg = "#1e2235" }
        hl.Visual = { bg = "#2d3f76" }
        hl.Search = { fg = "#0f111a", bg = "#ffc777" }
        hl.IncSearch = { fg = "#0f111a", bg = "#ffffff" }
        hl.NormalFloat = { fg = "#c8d3f5", bg = "#161928" }
        hl.FloatBorder = { fg = "#444a73", bg = "#161928" }
        hl.DiagnosticHint = { fg = "#828bb8" }
      end,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "tokyonight-moon",
    },
  },
}
