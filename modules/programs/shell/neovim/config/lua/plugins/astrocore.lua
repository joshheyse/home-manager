-- AstroCore provides a central place to modify mappings, vim options, autocommands, and more!
-- Configuration documentation can be found with `:h astrocore`
-- NOTE: We highly recommend setting up the Lua Language Server (`:LspInstall lua_ls`)
--       as this provides autocomplete and documentation while editing

---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    -- Configure core features of AstroNvim
    features = {
      large_buf = { size = 1024 * 256, lines = 10000 }, -- set global limits for large files for disabling features like treesitter
      autopairs = true, -- enable autopairs at start
      cmp = true, -- enable completion at start
      diagnostics = { virtual_text = true, virtual_lines = false }, -- diagnostic settings on startup
      highlighturl = true, -- highlight URLs at start
      notifications = true, -- enable notifications at start
    },
    -- Diagnostics configuration (for vim.diagnostics.config({...})) when diagnostics are on
    diagnostics = {
      virtual_text = true,
      underline = true,
    },
    -- vim options can be configured here
    options = {
      opt = { -- vim.opt.<key>
        relativenumber = false, -- sets vim.opt.relativenumber
        number = true, -- sets vim.opt.number
        spell = false, -- sets vim.opt.spell
        signcolumn = "yes", -- sets vim.opt.signcolumn to yes
        wrap = false, -- sets vim.opt.wrap
        conceallevel = 0, -- enable conceal
        foldenable = false,
        foldexpr = "nvim_treesitter#foldexpr()", -- set Treesitter based folding
        foldmethod = "expr",
        linebreak = true, -- linebreak soft wrap at words
        list = true, -- show whitespace characters
        -- listchars = { tab = " ", extends = "⟩", precedes = "⟨", trail = "·", eol = "﬋" },
        showbreak = "↪ ",
        exrc = true, -- enable project-local .nvim.lua
        secure = true, -- prompt before loading untrusted files
      },
      g = { -- vim.g.<key>
        -- configure global vim variables (vim.g)
        -- NOTE: `mapleader` and `maplocalleader` must be set in the AstroNvim opts or before `lazy.setup`
        -- This can be found in the `lua/lazy_setup.lua` file
      },
    },
    -- Mappings can be configured through AstroCore as well.
    -- NOTE: keycodes follow the casing in the vimdocs. For example, `<Leader>` must be capitalized
    mappings = {
      -- first key is the mode
      n = {
        -- second key is the lefthand side of the map

        -- window splits
        ["<Leader>\\"] = { "<cmd>vsplit<cr>", desc = "Vertical split" },
        ["<Leader>-"] = { "<cmd>split<cr>", desc = "Horizontal split" },
        ["<Leader>|"] = { "<cmd>botright vsplit<cr>", desc = "Vertical split (outer)" },
        ["<Leader>_"] = { "<cmd>botright split<cr>", desc = "Horizontal split (outer)" },

        -- navigate buffer tabs
        ["]b"] = {
          function() require("astrocore.buffer").nav(vim.v.count1) end,
          desc = "Next buffer",
        },
        ["[b"] = {
          function() require("astrocore.buffer").nav(-vim.v.count1) end,
          desc = "Previous buffer",
        },

        -- mappings seen under group name "Buffer"
        ["<Leader>bd"] = {
          function()
            require("astroui.status.heirline").buffer_picker(
              function(bufnr) require("astrocore.buffer").close(bufnr) end
            )
          end,
          desc = "Close buffer from tabline",
        },

        ["<leader>fr"] = {
          function()
            local word = vim.fn.expand "<cword>"
            vim.ui.input({
              prompt = "Replace '" .. word .. "' with: ",
              default = word,
            }, function(replacement)
              if replacement then vim.cmd("%s/\\<" .. word .. "\\>/" .. replacement .. "/gc") end
            end)
          end,
          desc = "Find and replace word under cursor (current buffer)",
        },

        ["<leader>fR"] = {
          function()
            local word = vim.fn.expand "<cword>"
            -- First, search for the word using telescope
            require("telescope").extensions.live_grep_args.live_grep_args {
              default_text = "\\b" .. word .. "\\b",
              prompt_title = "Find for replace: " .. word,
              attach_mappings = function(_, map)
                local actions = require "telescope.actions"
                -- Send all results to quickfix with Ctrl+q
                map("i", "<C-q>", function(prompt_bufnr)
                  actions.send_to_qflist(prompt_bufnr)
                  actions.open_qflist(prompt_bufnr)
                  vim.defer_fn(function()
                    vim.ui.input({
                      prompt = "Replace '" .. word .. "' with: ",
                      default = word,
                    }, function(replacement)
                      if replacement then
                        -- Use cdo to replace in all quickfix entries
                        vim.cmd("cdo s/\\<" .. word .. "\\>/" .. replacement .. "/gc | update")
                        vim.notify("Replacement complete. Review changes and save files.", vim.log.levels.INFO)
                      end
                    end)
                  end, 100)
                end)
                -- Replace in selected entries with Ctrl+r
                map("i", "<C-r>", function(prompt_bufnr)
                  actions.send_selected_to_qflist(prompt_bufnr)
                  actions.open_qflist(prompt_bufnr)
                  vim.defer_fn(function()
                    vim.ui.input({
                      prompt = "Replace '" .. word .. "' with: ",
                      default = word,
                    }, function(replacement)
                      if replacement then
                        -- Use cdo to replace in selected quickfix entries
                        vim.cmd("cdo s/\\<" .. word .. "\\>/" .. replacement .. "/gc | update")
                        vim.notify("Replacement complete. Review changes and save files.", vim.log.levels.INFO)
                      end
                    end)
                  end, 100)
                end)
                return true
              end,
            }
          end,
          desc = "Find and replace word under cursor (project wide)",
        },

        -- Path yank functions
        ["<Leader>y"] = { desc = "Yank Paths" },

        ["<Leader>yp"] = {
          function() require("paths").yank_path() end,
          desc = "Yank relative path to clipboard",
        },

        ["<Leader>yu"] = {
          function() require("paths").yank_url() end,
          desc = "Yank GitHub/GitLab URL to clipboard",
        },

        ["<Leader>yU"] = {
          function() require("paths").yank_url_with_branch_selector() end,
          desc = "Yank GitHub/GitLab URL with branch selector",
        },

        -- tables with just a `desc` key will be registered with which-key if it's installed
        -- this is useful for naming menus
        -- ["<Leader>b"] = { desc = "Buffers" },

        -- setting a mapping to false will disable it
        -- ["<C-S>"] = false,
      },
      v = {
        -- Visual mode mappings
        ["<Leader>yu"] = {
          function()
            -- Get visual selection range
            local start_line = vim.fn.line "'<"
            local end_line = vim.fn.line "'>"
            require("paths").yank_url(start_line, end_line)
          end,
          desc = "Yank GitHub/GitLab URL with line range to clipboard",
        },

        ["<Leader>yU"] = {
          function()
            -- Get visual selection range
            local start_line = vim.fn.line "'<"
            local end_line = vim.fn.line "'>"
            require("paths").yank_url_with_branch_selector(start_line, end_line)
          end,
          desc = "Yank GitHub/GitLab URL with branch selector and line range",
        },
      },
    },
  },
}
