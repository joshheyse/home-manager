return {
  "r-pletnev/pdfreader.nvim",
  lazy = false,
  dependencies = {
    "folke/snacks.nvim",
    "nvim-telescope/telescope.nvim",
  },
  config = function() require("pdfreader").setup() end,
}
