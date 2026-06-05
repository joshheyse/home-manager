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
}

return {
  {
    "AstroNvim/astrolsp",
    optional = true,
    opts = function(_, opts)
      opts.config = vim.tbl_deep_extend("keep", opts.config or {}, {
        veridian = {
          -- AstroLSP runs in legacy lspconfig mode here (native_lsp_config is
          -- false), where only `root_dir` is honored -- `root_markers` is a
          -- native vim.lsp.config concept and is ignored. veridian's default
          -- root_dir requires a `.git` dir, so it silently fails to start in
          -- non-git project dirs (e.g. a fresh fpga_net). Provide a marker-based
          -- root_dir that always resolves, plus single-file support, so it
          -- attaches anywhere. root_markers is kept for the native path in case
          -- native_lsp_config is enabled in a future AstroNvim.
          root_markers = { ".git", "flake.nix", "justfile", "Makefile", "veridian.yml" },
          single_file_support = true,
          root_dir = function(fname)
            local found = vim.fs.find(
              { "flake.nix", "justfile", "Makefile", ".git", "veridian.yml" },
              { path = fname, upward = true }
            )[1]
            return found and vim.fs.dirname(found) or vim.fs.dirname(fname)
          end,
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
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = function(_, opts)
      if opts.ensure_installed ~= "all" then
        -- The `verilog` parser covers both Verilog and SystemVerilog.
        opts.ensure_installed = require("astrocore").list_insert_unique(opts.ensure_installed, { "verilog" })
      end
    end,
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
