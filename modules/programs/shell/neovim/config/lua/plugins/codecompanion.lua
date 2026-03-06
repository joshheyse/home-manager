---@type LazySpec
return {
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
  },
  cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions" },
  keys = {
    { "<Leader>ac", "<cmd>CodeCompanionChat Toggle<cr>", desc = "Toggle chat" },
    { "<Leader>aa", "<cmd>CodeCompanionActions<cr>", desc = "Actions menu" },
    { "<Leader>ai", "<cmd>CodeCompanionChat Add<cr>", mode = "v", desc = "Add to chat" },
  },
  opts = {
    adapters = {
      anthropic = function()
        return require("codecompanion.adapters").extend("anthropic", {
          env = { api_key = "ANTHROPIC_API_KEY" },
          schema = {
            model = { default = "claude-sonnet-4-20250514" },
          },
        })
      end,
      anthropic_haiku = function()
        return require("codecompanion.adapters").extend("anthropic", {
          env = { api_key = "ANTHROPIC_API_KEY" },
          schema = {
            model = { default = "claude-haiku-4-5-20251001" },
          },
        })
      end,
    },
    strategies = {
      inline = { adapter = "anthropic_haiku" },
      chat = { adapter = "anthropic" },
      agent = { adapter = "anthropic" },
    },
  },
}
