local anthropic = require "util.anthropic"

--- Whether minuet would auto-trigger for `ft`, per the plugin's own config.
local function ft_auto_triggers(ft)
  local vt = require("minuet").config.virtualtext
  if vim.tbl_contains(vt.auto_trigger_ignore_ft, ft) then return false end
  return vim.tbl_contains(vt.auto_trigger_ft, "*") or vim.tbl_contains(vt.auto_trigger_ft, ft)
end

--- Session-wide auto-trigger toggle.
---
--- Minuet only tracks auto-trigger state per buffer (`vim.b.minuet_virtual_text_auto_trigger`),
--- and re-enables it on every `FileType` event, so `:Minuet virtualtext disable` is undone by
--- the next buffer you open. This flips a global flag, applies it to all loaded buffers, and
--- installs a `FileType` autocmd that runs after minuet's to keep new buffers off.
---
--- Manual completion (`<A-]>` / `<A-[>`) is unaffected and works while disabled.
local function toggle_auto_trigger()
  local enabled = vim.g.minuet_auto_trigger == false -- nil (unset) means enabled
  vim.g.minuet_auto_trigger = enabled

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      vim.b[buf].minuet_virtual_text_auto_trigger = enabled and ft_auto_triggers(vim.bo[buf].filetype)
    end
  end

  -- Recreated on each toggle: `clear` keeps it duplicate-free, and registering after
  -- minuet's own FileType autocmd is what lets ours win.
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("minuet_session_toggle", { clear = true }),
    pattern = "*",
    desc = "session-wide minuet auto-trigger override",
    callback = function(args)
      if vim.g.minuet_auto_trigger == false then vim.b[args.buf].minuet_virtual_text_auto_trigger = false end
    end,
  })

  if not enabled then pcall(function() require("minuet.virtualtext").action.dismiss() end) end
  vim.notify("Minuet auto-trigger " .. (enabled and "enabled" or "disabled"), vim.log.levels.INFO)
end

---@type LazySpec
return {
  "milanglacier/minuet-ai.nvim",
  event = "BufReadPost",
  keys = {
    { "<Leader>am", toggle_auto_trigger, desc = "Toggle AI autocomplete" },
  },
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
