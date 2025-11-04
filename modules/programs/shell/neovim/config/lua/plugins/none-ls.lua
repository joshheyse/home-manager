-- Customize None-ls sources

---@type LazySpec
return {
  "nvimtools/none-ls.nvim",
  opts = function(_, opts)
    -- opts variable is the default configuration table for the setup function call
    local null_ls = require "null-ls"

    -- Check supported formatters and linters
    -- https://github.com/nvimtools/none-ls.nvim/tree/main/lua/null-ls/builtins/formatting
    -- https://github.com/nvimtools/none-ls.nvim/tree/main/lua/null-ls/builtins/diagnostics

    -- Only insert new sources, do not replace the existing ones
    -- (If you wish to replace, use `opts.sources = {}` instead of the `list_insert_unique` function)
    opts.sources = require("astrocore").list_insert_unique(opts.sources, {
      -- Nix formatter (Mason-installed)
      null_ls.builtins.formatting.alejandra,

      -- Nix linters (Nix-installed via devShell, available through direnv)
      null_ls.builtins.diagnostics.deadnix, -- Detects unused code
      null_ls.builtins.diagnostics.statix, -- General Nix linting
      null_ls.builtins.code_actions.statix, -- Auto-fix suggestions
    })
  end,
}
