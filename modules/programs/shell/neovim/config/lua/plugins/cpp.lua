-- C/C++ Development Configuration
--
-- Uses clangd, compiler, and lldb-dap from PATH (Nix, Homebrew, system, etc.)
-- No Mason dependencies - all tools come from the system/Nix shell.

-- Check if tools are available in PATH
local has_clangd = vim.fn.exepath "clangd" ~= ""
local has_lldb_dap = vim.fn.exepath "lldb-dap" ~= ""

-- Find compiler path for --query-driver (prefer clang++ over g++)
local function get_compiler_path()
  for _, compiler in ipairs { "clang++", "g++" } do
    local path = vim.fn.exepath(compiler)
    if path ~= "" then return path end
  end
  return nil
end

local compiler_path = has_clangd and get_compiler_path() or nil

return {
  {
    "AstroNvim/astrolsp",
    optional = true,
    opts = function(_, opts)
      local clangd_cmd = {
        "clangd",
        "--background-index",
        "--clang-tidy",
        "--header-insertion=iwyu",
        "--completion-style=detailed",
        "--function-arg-placeholders",
        "--fallback-style=llvm",
        "--pch-storage=disk",
        "-j",
        "16",
      }

      -- Add query-driver if a compiler is in PATH
      if compiler_path then table.insert(clangd_cmd, "--query-driver=" .. compiler_path) end

      opts.config = vim.tbl_deep_extend("keep", opts.config, {
        clangd = {
          capabilities = {
            offsetEncoding = "utf-8",
          },
          cmd = clangd_cmd,
        },
      })
      -- Register clangd with lspconfig when available in PATH
      if has_clangd then opts.servers = require("astrocore").list_insert_unique(opts.servers, { "clangd" }) end
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = function(_, opts)
      if opts.ensure_installed ~= "all" then
        opts.ensure_installed =
          require("astrocore").list_insert_unique(opts.ensure_installed, { "cpp", "c", "objc", "cuda", "proto" })
      end
    end,
  },
  {
    "p00f/clangd_extensions.nvim",
    lazy = true,
    dependencies = {
      "AstroNvim/astrocore",
      opts = {
        autocmds = {
          clangd_extensions = {
            {
              event = "LspAttach",
              desc = "Load clangd_extensions with clangd",
              callback = function(args)
                if assert(vim.lsp.get_client_by_id(args.data.client_id)).name == "clangd" then
                  require "clangd_extensions"
                  vim.api.nvim_del_augroup_by_name "clangd_extensions"
                end
              end,
            },
          },
          clangd_extension_mappings = {
            {
              event = "LspAttach",
              desc = "Load clangd_extensions with clangd",
              callback = function(args)
                if assert(vim.lsp.get_client_by_id(args.data.client_id)).name == "clangd" then
                  require("astrocore").set_mappings({
                    n = {
                      ["<Leader>lw"] = {
                        "<Cmd>ClangdSwitchSourceHeader<CR>",
                        desc = "Switch source/header file",
                      },
                    },
                  }, { buffer = args.buf })
                end
              end,
            },
          },
        },
      },
    },
  },
  {
    "Civitasv/cmake-tools.nvim",
    ft = { "c", "cpp", "objc", "objcpp", "cuda", "proto" },
    opts = {},
  },
  -- Configure nvim-dap to use lldb-dap from PATH
  {
    "mfussenegger/nvim-dap",
    optional = true,
    config = function()
      if not has_lldb_dap then return end

      local dap = require "dap"

      dap.adapters.lldb = {
        type = "executable",
        command = "lldb-dap",
        name = "lldb",
      }

      dap.configurations.cpp = {
        {
          name = "Launch (prompt)",
          type = "lldb",
          request = "launch",
          program = function() return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file") end,
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
          args = {},
        },
        {
          name = "Attach to process",
          type = "lldb",
          request = "attach",
          pid = require("dap.utils").pick_process,
          args = {},
        },
      }

      -- Use same config for C and Rust
      dap.configurations.c = dap.configurations.cpp
      dap.configurations.rust = dap.configurations.cpp

      -- Load project-local .vscode/launch.json if present.
      -- Configs are appended after the fallback entries above.
      -- Use "type": "lldb" in launch.json (compatible with VS Code CodeLLDB extension).
      require("dap.ext.vscode").load_launchjs(nil, {
        lldb = { "c", "cpp", "rust" },
      })
    end,
  },
}
