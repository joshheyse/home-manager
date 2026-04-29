local work_base_url = os.getenv "ANTHROPIC_BASE_URL"
local is_work = work_base_url ~= nil and work_base_url ~= ""

-- Work uses the CTC litellm proxy (Anthropic-compatible /v1/messages endpoint,
-- authenticated with ANTHROPIC_AUTH_TOKEN). Home uses the public Anthropic API
-- with ANTHROPIC_API_KEY.
local api_key_env = is_work and "ANTHROPIC_AUTH_TOKEN" or "ANTHROPIC_API_KEY"
local sonnet_model = is_work and "claude-sonnet-4-6" or "claude-sonnet-4-5"
local haiku_model = is_work and "anthropic.claude-v4-5-haiku" or "claude-haiku-4-5"

local function anthropic_url()
  if not is_work then return nil end
  local base = work_base_url:gsub("/+$", "")
  return base .. "/v1/messages"
end

local function make_adapter(model)
  local overrides = {
    env = { api_key = api_key_env },
    schema = { model = { default = model } },
  }
  local url = anthropic_url()
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
      anthropic = function() return make_adapter(sonnet_model) end,
      anthropic_haiku = function() return make_adapter(haiku_model) end,
    },
    strategies = {
      inline = { adapter = "anthropic_haiku" },
      chat = { adapter = "anthropic" },
      agent = { adapter = "anthropic" },
    },
  },
}
