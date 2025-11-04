-- Customize Treesitter

---@type LazySpec
return {
  "nvim-treesitter/nvim-treesitter",
  opts = {
    ensure_installed = {
      "bash",
      "c",
      "cmake",
      "cpp",
      "css",
      "cuda",
      "dockerfile",
      "helm",
      "html",
      "javascript",
      "jsdoc",
      "json",
      "jsonc",
      "lua",
      "luap",
      "markdown",
      "markdown_inline",
      "nginx",
      "nix",
      "objc",
      "proto",
      "python",
      "query",
      "regex",
      "rust",
      "scss",
      "sql",
      "terraform",
      "toml",
      "tsx",
      "typescript",
      "vim",
      "vimdoc",
      "yaml",
    },
    highlight = {
      enable = true,
      additional_vim_regex_highlighting = false,
    },
    indent = { enable = true },
    incremental_selection = { enable = true },
    -- Enable injections for embedded languages (nginx, sql, bash in Nix strings)
    injections = {
      enable = true,
    },
  },
}
