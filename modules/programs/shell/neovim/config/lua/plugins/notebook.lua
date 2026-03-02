-- Notebook / REPL stack: molten-nvim + jupytext.nvim + quarto-nvim
-- Provides inline Jupyter output, .ipynb editing, and code-cell execution.

return {
  -- molten-nvim: Jupyter kernel integration with inline output
  {
    "benlubas/molten-nvim",
    lazy = false,
    build = ":UpdateRemotePlugins",
    init = function()
      vim.g.molten_image_provider = "image.nvim"
      vim.g.molten_auto_open_output = false
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_lines_off_by_1 = true
      vim.g.molten_wrap_output = true
      vim.g.molten_output_win_max_height = 20
    end,
    keys = {
      { ",mi", "<cmd>MoltenInit<cr>", desc = "Molten init kernel" },
      { ",md", "<cmd>MoltenDeinit<cr>", desc = "Molten deinit kernel" },
      { ",mR", "<cmd>MoltenRestart!<cr>", desc = "Molten restart kernel" },
      { ",mI", "<cmd>MoltenInterrupt<cr>", desc = "Molten interrupt kernel" },
      { ",ms", "<cmd>MoltenShowOutput<cr>", desc = "Molten show output" },
      { ",mh", "<cmd>MoltenHideOutput<cr>", desc = "Molten hide output" },
      { ",mo", "<cmd>noautocmd MoltenEnterOutput<cr>", desc = "Molten enter output" },
      { ",rl", "<cmd>MoltenEvaluateLine<cr>", desc = "Evaluate line" },
      { ",re", "<cmd>MoltenReevaluateCell<cr>", desc = "Re-evaluate cell" },
      { ",r", ":<C-u>MoltenEvaluateVisual<cr>gv", mode = "v", desc = "Evaluate selection" },
    },
  },

  -- jupytext.nvim: transparently edit .ipynb as markdown/python
  {
    "GCBallesteros/jupytext.nvim",
    lazy = false,
    opts = {
      style = "hydrogen",
      output_extension = "auto",
      force_ft = nil,
    },
  },

  -- quarto-nvim: code-cell runner and LSP in fenced blocks (merges with community pack)
  {
    "quarto-dev/quarto-nvim",
    optional = true,
    opts = {
      codeRunner = {
        enabled = true,
        default_method = "molten",
      },
      lspFeatures = {
        enabled = true,
        languages = { "python", "bash", "r" },
      },
    },
    keys = {
      { ",rc", function() require("quarto.runner").run_cell() end, desc = "Run cell" },
      { ",ra", function() require("quarto.runner").run_above() end, desc = "Run cell and above" },
      { ",rA", function() require("quarto.runner").run_all() end, desc = "Run all cells" },
      { ",rb", function() require("quarto.runner").run_below() end, desc = "Run cell and below" },
      { "]c", function() require("quarto.runner").next_cell() end, desc = "Next cell" },
      { "[c", function() require("quarto.runner").prev_cell() end, desc = "Previous cell" },
    },
  },
}
