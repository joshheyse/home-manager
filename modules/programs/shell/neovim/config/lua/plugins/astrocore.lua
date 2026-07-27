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
        foldexpr = "v:lua.vim.treesitter.foldexpr()", -- set Treesitter based folding
        foldmethod = "expr",
        linebreak = true, -- linebreak soft wrap at words
        list = true, -- show whitespace characters
        -- listchars = { tab = " ", extends = "⟩", precedes = "⟨", trail = "·", eol = "﬋" },
        showbreak = "↪ ",
        tabstop = 2,
        shiftwidth = 2,
        softtabstop = 2,
        expandtab = true,
        exrc = true, -- enable project-local .nvim.lua
        secure = true, -- prompt before loading untrusted files
      },
      g = { -- vim.g.<key>
        -- configure global vim variables (vim.g)
        -- NOTE: `mapleader` and `maplocalleader` must be set in the AstroNvim opts or before `lazy.setup`
        -- This can be found in the `lua/lazy_setup.lua` file
      },
    },
    -- Autocommands
    autocmds = {
      -- TODO: Remove when Claude Code respects $EDITOR/$VISUAL for Ctrl+G (issue #18990)
      -- Enable word wrap for Claude Code Ctrl+G editor (claude-prompt-*.md in $TMPDIR)
      claude_prompt_wrap = {
        {
          event = "BufReadPost",
          pattern = "*/claude-prompt-*.md",
          callback = function() vim.opt_local.wrap = true end,
        },
      },
    },
    -- Mappings can be configured through AstroCore as well.
    -- NOTE: keycodes follow the casing in the vimdocs. For example, `<Leader>` must be capitalized
    mappings = {
      -- first key is the mode
      n = {
        -- second key is the lefthand side of the map

        -- AI group
        ["<Leader>a"] = { desc = "󰧑 AI" },

        -- Molten / Notebook group
        ["<Leader>m"] = { desc = " Notebook" },

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

        -- Substitute/replace functions. Use uppercase `<Leader>F` so this
        -- doesn't shadow AstroNvim/Telescope's `<Leader>s...` symbol maps or
        -- AstroNvim's `<Leader>R` rename-file mapping.
        -- NOTE: keep the `<Leader>` prefix capitalized. AstroNvim's own maps use
        -- `<Leader>`, and a lowercase `<leader>` key is a *distinct* Lua table key,
        -- so it never overrides the default -- both get set on the same lhs and the
        -- winner depends on `pairs()` order. Capitalized keys collide cleanly.
        ["<Leader>F"] = { desc = "Find/replace" },

        ["<Leader>Fw"] = {
          function()
            local word = vim.fn.expand "<cword>"
            vim.ui.input({
              prompt = "Replace '" .. word .. "' with: ",
              default = word,
            }, function(replacement)
              if replacement then vim.cmd("%s/\\<" .. word .. "\\>/" .. replacement .. "/gc") end
            end)
          end,
          desc = "Replace word under cursor (buffer)",
        },

        ["<Leader>Fr"] = {
          function()
            vim.ui.input({ prompt = "Regex pattern: " }, function(pattern)
              if not pattern or pattern == "" then return end
              vim.ui.input({ prompt = "Replace with: " }, function(replacement)
                if replacement == nil then return end
                vim.cmd("%s#\\v" .. vim.fn.escape(pattern, "#") .. "#" .. vim.fn.escape(replacement, "#") .. "#gc")
              end)
            end)
          end,
          desc = "Replace regex (buffer)",
        },

        -- Path yank functions
        ["<Leader>y"] = { desc = "Yank Paths" },

        ["<Leader>yr"] = {
          function() require("paths").yank_path() end,
          desc = "Yank relative path to clipboard",
        },

        ["<Leader>ya"] = {
          function() require("paths").yank_absolute_path() end,
          desc = "Yank absolute path to clipboard",
        },

        ["<Leader>yp"] = {
          function() require("paths").yank_repo_path() end,
          desc = "Yank git repo absolute path to clipboard",
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
