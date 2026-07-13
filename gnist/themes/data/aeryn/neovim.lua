return {
  {
    "neanias/everforest-nvim",
    priority = 1000,
    opts = {
      style = "medium",
      background = "dark",
      transparent_background_level = 0,
      italics = true,
      disable_italic_comments = false,
      ui_contrast = "low",
      colours_override = function(palette)
        palette.bg_dim = "#131714"
        palette.bg0 = "#131714"
        palette.bg1 = "#1B211C"
        palette.bg2 = "#232B24"
        palette.bg3 = "#2C362D"
        palette.bg4 = "#3E4A40"
        palette.bg5 = "#48564A"
        palette.fg = "#D6D3C0"
        palette.red = "#CE7B57"
        palette.orange = "#F3C892"
        palette.yellow = "#E4DFC9"
        palette.green = "#818B6B"
        palette.aqua = "#7FA48C"
        palette.blue = "#929F75"
        palette.purple = "#9AA184"
        palette.grey0 = "#798A51"
        palette.grey1 = "#8C8975"
        palette.grey2 = "#9AA184"
      end,
      on_highlights = function(hl, palette)
        hl.Normal = { fg = "#D6D3C0", bg = "#131714" }
        hl.NormalFloat = { fg = "#D6D3C0", bg = "#1B211C" }
        hl.FloatBorder = { fg = "#798A51", bg = "#1B211C" }
        hl.CursorLine = { bg = "#1B211C" }
        hl.Visual = { fg = "#131714", bg = "#818B6B" }
        hl.Search = { fg = "#131714", bg = "#F3C892" }
        hl.IncSearch = { fg = "#131714", bg = "#F0EDDD" }
        hl.Comment = { fg = "#8C8975", italic = true }
        hl.String = { fg = "#818B6B" }
        hl.Number = { fg = "#F3C892" }
        hl.Boolean = { fg = "#F3C892" }
        hl.Function = { fg = "#929F75" }
        hl.Keyword = { fg = "#9AA184" }
        hl.Type = { fg = "#E4DFC9" }
        hl.Identifier = { fg = "#D6D3C0" }
        hl.Operator = { fg = "#8FB8A3" }
        hl.DiagnosticError = { fg = "#CE7B57" }
        hl.DiagnosticWarn = { fg = "#F3C892" }
        hl.DiagnosticInfo = { fg = "#7FA48C" }
        hl.DiagnosticHint = { fg = "#818B6B" }
        hl.GitSignsAdd = { fg = "#818B6B" }
        hl.GitSignsChange = { fg = "#F3C892" }
        hl.GitSignsDelete = { fg = "#CE7B57" }
      end,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "everforest",
      background = "medium",
    },
  },
}
