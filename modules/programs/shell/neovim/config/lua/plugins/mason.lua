-- Customize Mason

---@type LazySpec
return {
  -- use mason-tool-installer for automatically installing Mason packages
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    -- overrides `require("mason-tool-installer").setup(...)`
    opts = {
      -- Make sure to use the names found in `:Mason`
      ensure_installed = {
        -- install language servers
        "lua-language-server",
        "nil", -- Nix language server

        -- install formatters
        "stylua",
        "alejandra", -- Nix formatter

        -- install debuggers
        "debugpy",

        -- install any other package
        "tree-sitter-cli",

        -- NOTE: deadnix and statix are not available in Mason
        -- They are installed via Nix (in devShell and via direnv)
      },
      -- Auto-update installed tools
      auto_update = false,
      -- Run on start (wait for Mason registry to load)
      run_on_start = true,
      -- Delay before checking/installing (gives Mason time to initialize)
      start_delay = 3000,
    },
  },
}
