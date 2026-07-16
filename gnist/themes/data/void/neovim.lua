return {
  {
    "neanias/everforest-nvim",
    priority = 1000,
    opts = {
      style = "hard",
      background = "dark",
      transparent_background_level = 0,
      italics = false,
      ui_contrast = "high",
      colours_override = function(palette)
        palette.bg_dim = "#000000"
        palette.bg0 = "#000000"
        palette.bg1 = "#080808"
        palette.bg2 = "#111111"
        palette.bg3 = "#191919"
        palette.bg4 = "#242424"
        palette.bg5 = "#666666"
        palette.fg = "#E6E6E6"
        palette.red = "#D16D6D"
        palette.orange = "#C7A96B"
        palette.yellow = "#C7A96B"
        palette.green = "#8FAF87"
        palette.aqua = "#82B4B4"
        palette.blue = "#8BA7C7"
        palette.purple = "#AA8EBA"
        palette.grey0 = "#242424"
        palette.grey1 = "#777777"
        palette.grey2 = "#E6E6E6"
      end,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "everforest", background = "hard" },
  },
}
