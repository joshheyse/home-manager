-- Customize Mason

---@type LazySpec
return {
  -- use mason-tool-installer for automatically installing Mason packages
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    -- overrides `require("mason-tool-installer").setup(...)`
    opts = {
      -- All LSPs, formatters, linters, and debuggers come from nix
      -- (see programs.neovim.extraPackages in the home-manager module).
      -- Mason is kept installed only as an ad-hoc escape hatch via `:Mason`
      -- for trying servers that are not packaged in nixpkgs.
      ensure_installed = {},
      auto_update = false,
      run_on_start = false,
    },
  },
}
