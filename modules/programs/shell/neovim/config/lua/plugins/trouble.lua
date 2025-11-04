return {
  {
    "folke/trouble.nvim",
    cmd = { "Trouble" },
    dependencies = {
      { "AstroNvim/astroui", opts = { icons = { Trouble = "󱍼" } } },
      {
        "AstroNvim/astrocore",
        opts = function(_, opts)
          local maps = opts.mappings
          local prefix = "<Leader>x"
          maps.n[prefix] = { desc = require("astroui").get_icon("Trouble", 1, true) .. "Trouble" }
          maps.n[prefix .. "X"] = { "<cmd>Trouble diagnostics toggle<cr>", desc = "Diagnostics (Trouble)" }
          maps.n[prefix .. "x"] =
            { "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "Buffer Diagnostics (Trouble)" }
          maps.n[prefix .. "l"] = { "<cmd>Trouble loclist toggle<cr>", desc = "Location List (Trouble)" }
          maps.n[prefix .. "q"] = { "<cmd>Trouble quickfix toggle<cr>", desc = "Quickfix List (Trouble)" }
          if require("astrocore").is_available "todo-comments.nvim" then
            maps.n["<leader>xt"] = {
              "<cmd>TodoTrouble<cr>",
              desc = "Todo (Trouble)",
            }
            maps.n["<leader>xT"] = {
              "<cmd>TodoTrouble keywords=TODO,FIX,FIXME<cr>",
              desc = "Todo/Fix/Fixme (Trouble)",
            }
          end
        end,
      },
    },
    opts = {
      use_diagnostic_signs = true,
      action_keys = {
        close = { "q", "<ESC>" },
        cancel = "<C-e>",
      },
    },
  },
  {
    "folke/edgy.nvim",
    optional = true,
    opts = function(_, opts)
      if not opts.bottom then opts.bottom = {} end
      table.insert(opts.bottom, "Trouble")
    end,
  },
  {
    "catppuccin",
    optional = true,
    ---@type CatppuccinOptions
    opts = { integrations = { lsp_trouble = true } },
  },
}
