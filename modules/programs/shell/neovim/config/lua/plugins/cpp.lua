-- C/C++ Development Configuration
--
-- This configuration provides comprehensive C/C++ support with intelligent Nix shell integration.
--
-- Features:
-- - Automatic detection of Nix shell development environments
-- - Uses Nix-provided clangd and compiler when available
-- - Falls back to system/Mason-installed clangd outside Nix shells
-- - Configures clangd with query-driver for proper compiler detection
-- - Prevents Mason conflicts when using Nix-provided tools
--
-- Nix Shell Integration:
-- When IN_NIX_SHELL environment variable is set and both clangd and a compiler
-- (clang++ or g++) are available in PATH, this configuration will:
--   1. Use the Nix shell's clangd binary (full path)
--   2. Set --query-driver to the Nix shell's compiler path
--   3. Prevent Mason from installing its own clangd
--
-- This ensures Neovim uses the exact toolchain your Nix project is configured with,
-- preventing version mismatches and configuration issues.
--
-- Outside Nix Shells:
-- When not in a Nix shell, this configuration will:
--   1. Use system clangd or Mason-installed clangd
--   2. Allow Mason to manage clangd installation (except on Linux ARM)
--   3. Use standard clangd configuration without query-driver
--
-- Plugins Configured:
-- - AstroNvim/astrolsp: LSP configuration with clangd
-- - nvim-treesitter: Syntax highlighting for C/C++/ObjC/CUDA/Proto
-- - williamboman/mason-lspconfig.nvim: LSP installation management
-- - p00f/clangd_extensions.nvim: Enhanced clangd features
-- - Civitasv/cmake-tools.nvim: CMake integration
-- - WhoIsSethDaniel/mason-tool-installer.nvim: Tool installation management

local uname = (vim.uv or vim.loop).os_uname()
local is_linux_arm = uname.sysname == "Linux" and (uname.machine == "aarch64" or vim.startswith(uname.machine, "arm"))

-- Helper function to check if a command exists in PATH
local function command_exists(cmd)
  local handle = io.popen("command -v " .. cmd .. " 2>/dev/null")
  if not handle then return false end
  local result = handle:read "*a"
  handle:close()
  return result ~= ""
end

-- Detect Nix shell environment and find clangd/compiler
local function setup_nix_clangd()
  local in_nix_shell = os.getenv "IN_NIX_SHELL"
  if not in_nix_shell then return nil end

  -- Check if clangd exists in the Nix shell
  if not command_exists "clangd" then return nil end

  -- Find compiler (prefer clang++ over g++)
  local compiler = nil
  if command_exists "clang++" then
    local handle = io.popen "command -v clang++ 2>/dev/null"
    if handle then
      compiler = handle:read("*a"):gsub("%s+$", "")
      handle:close()
    end
  elseif command_exists "g++" then
    local handle = io.popen "command -v g++ 2>/dev/null"
    if handle then
      compiler = handle:read("*a"):gsub("%s+$", "")
      handle:close()
    end
  end

  if not compiler then return nil end

  -- Get the full path to clangd
  local clangd_path = nil
  local handle = io.popen "command -v clangd 2>/dev/null"
  if handle then
    clangd_path = handle:read("*a"):gsub("%s+$", "")
    handle:close()
  end

  if not clangd_path or clangd_path == "" then return nil end

  return { clangd = clangd_path, compiler = compiler }
end

local nix_config = setup_nix_clangd()

return {
  {
    "AstroNvim/astrolsp",
    optional = true,
    opts = function(_, opts)
      local clangd_cmd = {
        nix_config and nix_config.clangd or "clangd",
        "--background-index",
        "--clang-tidy",
        "--header-insertion=iwyu",
        "--completion-style=detailed",
        "--function-arg-placeholders",
        "--fallback-style=llvm",
        "--pch-storage=disk",
        "-j",
        "12",
      }

      -- Add query-driver if we're in a Nix shell with a compiler
      if nix_config and nix_config.compiler then table.insert(clangd_cmd, "--query-driver=" .. nix_config.compiler) end

      opts.config = vim.tbl_deep_extend("keep", opts.config, {
        clangd = {
          capabilities = {
            offsetEncoding = "utf-8",
          },
          cmd = clangd_cmd,
        },
      })
      -- Register clangd with lspconfig directly when using system/Nix clangd (not Mason)
      if is_linux_arm or nix_config or command_exists "clangd" then
        opts.servers = require("astrocore").list_insert_unique(opts.servers, { "clangd" })
      end
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
    "williamboman/mason-lspconfig.nvim",
    optional = true,
    opts = function(_, opts)
      -- Only install clangd via Mason if not available in PATH
      if not is_linux_arm and not nix_config and not command_exists "clangd" then
        opts.ensure_installed = require("astrocore").list_insert_unique(opts.ensure_installed, { "clangd" })
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
      local tools = { "codelldb" }
      -- Don't install clangd via Mason if we're in a Nix shell or on Linux ARM
      if not is_linux_arm and not nix_config then table.insert(tools, "clangd") end
      opts.ensure_installed = require("astrocore").list_insert_unique(opts.ensure_installed, tools)
    end,
  },
}
