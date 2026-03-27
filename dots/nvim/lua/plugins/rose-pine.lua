return {
  {
    "rose-pine/neovim",
    name = "rose-pine",
    priority = 1000,
    opts = {
      variant = "main",
      dark_variant = "main",
      extend_background_behind_borders = true,
      styles = {
        bold = true,
        italic = true,
        transparency = true,
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "rose-pine",
    },
  },
}
