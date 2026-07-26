-- Grep the current visual selection with live_grep_args.
--
-- The plugin's own `shortcuts.grep_visual_selection` silently drops everything
-- past the first line (it does `visual[1] or ""`). ripgrep is line-oriented, so
-- a multi-line pattern can't match anyway -- but the truncation should be
-- visible rather than silent, hence the warning below.
local function grep_visual_selection()
  local _, ls, cs = unpack(vim.fn.getpos "v")
  local _, le, ce = unpack(vim.fn.getpos ".")
  ls, le = math.min(ls, le), math.max(ls, le)
  cs, ce = math.min(cs, ce), math.max(cs, ce)

  local lines = vim.api.nvim_buf_get_text(0, ls - 1, cs - 1, le - 1, ce, {})
  if #lines > 1 then vim.notify("Selection spans multiple lines; grepping the first line only", vim.log.levels.WARN) end

  local text = vim.trim(lines[1] or "")
  if text == "" then
    vim.notify("Empty selection", vim.log.levels.WARN)
    return
  end

  require("telescope").extensions.live_grep_args.live_grep_args {
    -- -F so regex metacharacters in the selection are matched literally
    default_text = require("telescope-live-grep-args.helpers").quote(text) .. " -F ",
  }
end

return {
  "nvim-telescope/telescope-live-grep-args.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    {
      "AstroNvim/astrocore",
      -- NOTE: this must stay a *function*, not a plain table. AstroNvim's snacks
      -- spec contributes its `<Leader>fw` via an opts function, and lazy.nvim
      -- applies opts functions after merging plain opts tables -- so a table here
      -- would lose. Also keep `<Leader>` capitalized: a lowercase `<leader>` key
      -- is a distinct Lua table key, which makes it a race rather than an
      -- override (see the note in astrocore.lua).
      opts = function(_, opts)
        local maps = opts.mappings

        -- Override AstroNvim's snacks grep: live_grep_args lets you append raw
        -- ripgrep flags to the prompt (e.g. `"foo" --iglob *.lua -t rust`).
        maps.n["<Leader>fw"] = {
          function() require("telescope").extensions.live_grep_args.live_grep_args() end,
          desc = "Find words (with args)",
        }

        -- <Leader>fW (hidden + ignored) and <Leader>fc (word under cursor,
        -- --word-regexp) are intentionally left to AstroNvim's snacks defaults.

        -- AstroNvim binds no visual-mode grep, so this is the only one.
        maps.v["<Leader>fv"] = { grep_visual_selection, desc = "Find visual selection" }
      end,
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
