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
        colors.bg = "#0F1114"
        colors.bg_dark = "#0F1114"
        colors.bg_sidebar = "#0F1114"
        colors.bg_float = "#16191D"
        colors.bg_statusline = "#16191D"
        colors.bg_popup = "#232830"
        colors.bg_highlight = "#1C2026"
        colors.fg = "#F2F4F6"
        colors.fg_gutter = "#3A414B"
        colors.border = "#3A414B"
        colors.blue = "#2DD4BF"
        colors.cyan = "#4DD0E1"
        colors.green = "#5BC98A"
        colors.magenta = "#B39DDB"
        colors.red = "#E5636C"
        colors.yellow = "#2DD4BF"
      end,
      on_highlights = function(hl, colors)
        hl.Comment = { fg = "#B39DDB", italic = true }
        hl.LineNr = { fg = "#98A1AB" }
        hl.CursorLineNr = { fg = "#2DD4BF", bold = true }
        hl.CursorLine = { bg = "#1C2026" }
        hl.Visual = { bg = "#3A414B" }
        hl.Search = { fg = "#0F1114", bg = "#2DD4BF" }
        hl.IncSearch = { fg = "#0F1114", bg = "#FFFFFF" }
        hl.NormalFloat = { fg = "#F2F4F6", bg = "#16191D" }
        hl.FloatBorder = { fg = "#3A414B", bg = "#16191D" }
        hl.DiagnosticHint = { fg = "#98A1AB" }
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
