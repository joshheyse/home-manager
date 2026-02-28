return {
  "nvim-telescope/telescope-dap.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "mfussenegger/nvim-dap",
    {
      "AstroNvim/astrocore",
      opts = {
        mappings = {
          n = {
            ["<Leader>df"] = {
              function() require("telescope").extensions.dap.configurations {} end,
              desc = "Find debug configurations",
            },
          },
        },
      },
    },
  },
  config = function() require("telescope").load_extension "dap" end,
}
