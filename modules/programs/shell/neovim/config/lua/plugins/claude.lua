---@type LazySpec
return {
  "coder/claudecode.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  event = "VeryLazy",
  keys = {
    { "<Leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Send to Claude Code" },
    { "<Leader>aT", "<cmd>ClaudeCodeTreeAdd<cr>", desc = "Add file to Claude context" },
    { "<Leader>aD", "<cmd>ClaudeCodeTreeDrop<cr>", desc = "Drop file from Claude context" },
  },
  opts = {
    auto_start = true,
    terminal = {
      provider = "none", -- using tmux, not neovim terminal
    },
  },
}
