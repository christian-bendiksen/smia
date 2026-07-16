return {
  {
    "neanias/everforest-nvim",
    priority = 1000,
    opts = {
      style = "soft",
      background = "light",
      transparent_background_level = 0,
      italics = true,
      ui_contrast = "low",
      colours_override = function(palette)
        palette.bg_dim = "#EEE9DC"
        palette.bg0 = "#F7F3E8"
        palette.bg1 = "#EEE9DC"
        palette.bg2 = "#E3DDCE"
        palette.bg3 = "#D8D1C2"
        palette.bg4 = "#BDB6A7"
        palette.bg5 = "#716D63"
        palette.fg = "#282620"
        palette.red = "#A33D32"
        palette.orange = "#8A621F"
        palette.yellow = "#8A621F"
        palette.green = "#4D6B3A"
        palette.aqua = "#3F6D68"
        palette.blue = "#2D5E73"
        palette.purple = "#78517C"
        palette.grey0 = "#BDB6A7"
        palette.grey1 = "#716D63"
        palette.grey2 = "#282620"
      end,
    },
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "everforest", background = "soft" },
  },
}
