-- Verilog / SystemVerilog Development Configuration
--
-- LSP: veridian (from the `veridian` nix package). slang-based diagnostics plus
-- completion, hover, goto-definition and document symbols. The nix package
-- bundles verible + verilator on veridian's own PATH for its extra features.
-- veridian builds against nixpkgs' slang 9.1 via the overlay in the
-- home-manager flake.nix (upstream pins slang 7.0; the API is unchanged).
--
-- Formatting: routed through none-ls `verible_verilog_format` (NOT the LSP) so
-- it uses 2-space indentation matching .editorconfig and the fpga_net `just
-- fmt` recipe. We disable veridian's own formatting to avoid fighting on save.
--
-- No Mason dependencies -- everything comes from PATH (nix).

local has_veridian = vim.fn.exepath "veridian" ~= ""

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
        veridian = {
          -- AstroLSP v6 uses the native vim.lsp.config backend, where
          -- root_markers is honored directly (the legacy fname-based root_dir
          -- shim is gone -- native root_dir has a different signature and the
          -- old one crashes). veridian's upstream default only looks for
          -- `.git`, so add markers that resolve in non-git project dirs
          -- (e.g. a fresh fpga_net).
          root_markers = { ".git", "flake.nix", "justfile", "Makefile", "veridian.yml" },
        },
      })
      -- Register veridian with lspconfig only when it is available in PATH.
      if has_veridian then opts.servers = require("astrocore").list_insert_unique(opts.servers, { "veridian" }) end
      -- Format via none-ls (2-space verible) instead of the LSP.
      opts.formatting = opts.formatting or {}
      opts.formatting.disabled = require("astrocore").list_insert_unique(opts.formatting.disabled or {}, { "veridian" })
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
      -- Diagnostics come from the veridian LSP (slang), not none-ls.
      opts.sources = require("astrocore").list_insert_unique(opts.sources, {
        null_ls.builtins.formatting.verible_verilog_format.with {
          extra_args = verible_format_args,
        },
      })
    end,
  },
}
