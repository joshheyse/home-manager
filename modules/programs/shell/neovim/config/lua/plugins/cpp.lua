-- C/C++ Development Configuration
--
-- Uses clangd and compiler from PATH (Nix, Homebrew, system, etc.)
-- Configures --query-driver with clang++ or g++ from PATH for proper header resolution.

-- Check if clangd is available in PATH
local has_clangd = vim.fn.exepath "clangd" ~= ""

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
    dependencies = {
      {
        "jay-babu/mason-nvim-dap.nvim",
        opts = function(_, opts)
          opts.ensure_installed = require("astrocore").list_insert_unique(opts.ensure_installed, { "codelldb" })
        end,
      },
    },
    opts = {},
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = require("astrocore").list_insert_unique(opts.ensure_installed, { "codelldb" })
    end,
  },
}
