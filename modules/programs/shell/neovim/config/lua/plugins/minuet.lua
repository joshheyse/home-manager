local anthropic = require "util.anthropic"

---@type LazySpec
return {
  "milanglacier/minuet-ai.nvim",
  event = "BufReadPost",
  opts = {
    provider = "claude",
    notify = "error",
    virtualtext = {
      auto_trigger_ft = { "*" },
      auto_trigger_ignore_ft = {
        "gitcommit",
        "gitrebase",
        "TelescopePrompt",
        "snacks_picker_input",
        "snacks_input",
        "help",
        "qf",
        "checkhealth",
        "lazy",
        "mason",
        "minuet",
        "codecompanion",
      },
      keymap = {
        accept = "<C-l>",
        accept_line = "<C-j>",
        next = "<A-]>",
        prev = "<A-[>",
        dismiss = "<C-e>",
      },
    },
    provider_options = {
      claude = {
        end_point = anthropic.messages_url(),
        api_key = anthropic.api_key_env,
        model = anthropic.models.haiku,
        max_tokens = 512,
        optional = {},
      },
    },
    throttle = 1000,
    debounce = 500,
  },
}
