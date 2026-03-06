---@type LazySpec
return {
  "milanglacier/minuet-ai.nvim",
  event = "InsertEnter",
  opts = {
    provider = "claude",
    notify = "error",
    virtualtext = {
      auto_trigger_ft = { "*" },
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
        api_key = "ANTHROPIC_API_KEY",
        model = "claude-haiku-4-5-20251001",
        max_tokens = 512,
        optional = {
          stop_sequences = { "\n\n" },
        },
      },
    },
    throttle = 1000,
    debounce = 500,
  },
}
