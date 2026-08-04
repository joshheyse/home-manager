-- Verilog / SystemVerilog Development Configuration
--
-- LSP: slang-server from Hudson River Trading, registered through nvim-lspconfig
-- as `slang_server`. This is the only attached SystemVerilog LSP; Verible stays
-- as an external formatter so diagnostics/goto/hover have one semantic owner.
--
-- Formatting: routed through none-ls `verible_verilog_format` (NOT the LSP) so
-- it uses 2-space indentation matching .editorconfig and project `just fmt`
-- recipes. We disable slang-server formatting to avoid fighting on save.
--
-- No Mason dependencies -- everything comes from PATH (nix).

local has_slang_server = vim.fn.exepath "slang-server" ~= ""

-- Keep editor format-on-save in lock-step with `just fmt` / .editorconfig.
local verible_format_args = {
  "--indentation_spaces=2",
  "--formal_parameters_indentation=indent",
  "--port_declarations_indentation=indent",
  "--named_port_indentation=indent",
  "--named_parameter_indentation=indent",
}

return {
  {
    "AstroNvim/astrolsp",
    optional = true,
    opts = function(_, opts)
      opts.config = vim.tbl_deep_extend("keep", opts.config or {}, {
        slang_server = {
          -- AstroLSP v6 uses the native vim.lsp.config backend, where
          -- root_markers is honored directly (the legacy fname-based root_dir
          -- shim is gone -- native root_dir has a different signature). Add
          -- markers that resolve in non-git project dirs and Slang workspaces.
          root_markers = { ".slang", ".git", "flake.nix", "justfile", "Makefile" },
        },
      })
      -- Register slang-server with lspconfig only when it is available in PATH.
      if has_slang_server then
        opts.servers = require("astrocore").list_insert_unique(opts.servers, { "slang_server" })
      end
      -- Format via none-ls (2-space verible) instead of the LSP.
      opts.formatting = opts.formatting or {}
      opts.formatting.disabled =
        require("astrocore").list_insert_unique(opts.formatting.disabled or {}, { "slang_server" })
    end,
  },
  {
    "AstroNvim/astrocore",
    optional = true,
    -- nvim-treesitter main only ships `systemverilog` (the old `verilog`
    -- parser name is gone); it covers both Verilog and SystemVerilog, so map
    -- it onto the `verilog` filetype too.
    init = function() vim.treesitter.language.register("systemverilog", "verilog") end,
    ---@type AstroCoreOpts
    opts = {
      treesitter = { ensure_installed = { "systemverilog" } },
    },
  },
  {
    "nvimtools/none-ls.nvim",
    optional = true,
    opts = function(_, opts)
      local null_ls = require "null-ls"
      -- Formatter: verible (2-space), matching .editorconfig / `just fmt`.
      -- Diagnostics come from slang-server, not none-ls.
      opts.sources = require("astrocore").list_insert_unique(opts.sources, {
        null_ls.builtins.formatting.verible_verilog_format.with {
          extra_args = verible_format_args,
        },
      })
    end,
  },
}
