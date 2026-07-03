-- Customize Treesitter
--
-- AstroNvim v6: nvim-treesitter's main branch is a parser installer only;
-- treesitter features (highlight, indent, textobjects) are configured through
-- AstroCore's `treesitter` module (see :h astrocore).

---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    treesitter = {
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
      highlight = true,
      indent = true,
      -- Automatically install missing parsers when opening a file
      auto_install = true,
    },
  },
}
