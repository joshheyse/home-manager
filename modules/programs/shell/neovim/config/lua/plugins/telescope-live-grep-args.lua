return {
  "nvim-telescope/telescope-live-grep-args.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    {
      "AstroNvim/astrocore",
      opts = {
        mappings = {
          n = {
            ["<leader>fw"] = {
              function() require("telescope").extensions.live_grep_args.live_grep_args() end,
              desc = "Find words (with args)",
            },
            ["<leader>fW"] = {
              function() require("telescope").extensions.live_grep_args.live_grep_args() end,
              desc = "Live grep with args",
            },
            ["<leader>fc"] = {
              function() require("telescope-live-grep-args.shortcuts").grep_word_under_cursor() end,
              desc = "Find word under cursor",
            },
            ["<leader>fv"] = {
              function() require("telescope-live-grep-args.shortcuts").grep_visual_selection() end,
              desc = "Find visual selection",
            },
          },
          v = {
            ["<leader>fv"] = {
              function() require("telescope-live-grep-args.shortcuts").grep_visual_selection() end,
              desc = "Find visual selection",
            },
          },
        },
      },
    },
  },
  -- Load extension when telescope loads
  config = function()
    local telescope = require "telescope"
    local lga_actions = require "telescope-live-grep-args.actions"

    telescope.setup {
      extensions = {
        live_grep_args = {
          auto_quoting = true, -- enable/disable auto-quoting
          -- define mappings, e.g.
          mappings = { -- extend mappings
            i = {
              ["<C-k>"] = lga_actions.quote_prompt(),
              ["<C-i>"] = lga_actions.quote_prompt { postfix = " --iglob " },
              ["<C-t>"] = lga_actions.quote_prompt { postfix = " -t " },
              ["<C-r>"] = lga_actions.to_fuzzy_refine,
            },
          },
          -- ... also accepts theme settings, for example:
          -- theme = "dropdown", -- use dropdown theme
          -- theme = { }, -- use own theme spec
          -- layout_config = { mirror=true }, -- mirror preview pane
        },
      },
    }

    -- Load the extension
    telescope.load_extension "live_grep_args"
  end,
}
