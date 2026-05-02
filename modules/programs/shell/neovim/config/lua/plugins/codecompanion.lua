local anthropic = require "util.anthropic"

local function make_adapter(model)
  local overrides = {
    env = { api_key = anthropic.api_key_env },
    schema = { model = { default = model } },
  }
  local url = anthropic.messages_url_override()
  if url then overrides.url = url end
  return require("codecompanion.adapters").extend("anthropic", overrides)
end

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
      anthropic = function() return make_adapter(anthropic.models.sonnet) end,
      anthropic_haiku = function() return make_adapter(anthropic.models.haiku) end,
    },
    strategies = {
      inline = { adapter = "anthropic_haiku" },
      chat = { adapter = "anthropic" },
      agent = { adapter = "anthropic" },
    },
  },
}
