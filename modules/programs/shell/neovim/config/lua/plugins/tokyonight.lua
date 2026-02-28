return {
  "folke/tokyonight.nvim",
  name = "tokyonight",
  lazy = false,
  priority = 2000,
  opts = {
    style = "storm",
    transparent = true,
    terminal_colors = true,
    styles = {
      comments = { italic = true, bold = false },
      keywords = { italic = false, bold = true },
      functions = {},
      variables = {},
      -- Background styles. Can be "dark", "transparent" or "normal"
      sidebars = "transparent", -- style for sidebars, see below
      floats = "transparent", -- style for sidebars, see below
    },
    hide_inactive_statusline = false, -- Enabling this option, will hide inactive statuslines and replace them with a thin border instead. Should work with the standard **StatusLine** and **LuaLine**. |
    dim_inactive = false,
    lualine_bold = true, -- When `true`, section headers in the lualine theme will be bold|
    on_highlights = function(hl, c)
      hl.WinSeparator = { fg = c.blue, bold = true }
      -- Dim inactive windows with a semi-transparent dark background
      hl.NormalNC = { bg = "#1a1b2e" }
    end,
  },
  config = function(_, opts)
    local tokyonight = require "tokyonight"
    tokyonight.setup(opts)
    tokyonight.load(opts)
  end,
}
