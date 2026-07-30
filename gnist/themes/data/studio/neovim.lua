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
        colors.bg = "#23262B"
        colors.bg_dark = "#23262B"
        colors.bg_sidebar = "#23262B"
        colors.bg_float = "#292D33"
        colors.bg_statusline = "#292D33"
        colors.bg_popup = "#383D44"
        colors.bg_highlight = "#31363D"
        colors.fg = "#EAE7E1"
        colors.fg_gutter = "#828B98"
        colors.border = "#828B98"
        colors.blue = "#96B9E6"
        colors.cyan = "#7DC2D6"
        colors.green = "#8FC5A1"
        colors.magenta = "#B6AEE3"
        colors.red = "#EB9DA2"
        colors.yellow = "#D3AF80"
      end,
      on_highlights = function(hl, colors)
        hl.Comment = { fg = "#B6AEE3", italic = true }
        hl.LineNr = { fg = "#A5ACB5" }
        hl.CursorLineNr = { fg = "#B9C2CC", bold = true }
        hl.CursorLine = { bg = "#31363D" }
        hl.Visual = { bg = "#383D44" }
        hl.Search = { fg = "#23262B", bg = "#B9C2CC" }
        hl.IncSearch = { fg = "#23262B", bg = "#F7F4EE" }
        hl.NormalFloat = { fg = "#EAE7E1", bg = "#292D33" }
        hl.FloatBorder = { fg = "#828B98", bg = "#292D33" }
        hl.DiagnosticHint = { fg = "#A5ACB5" }
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
