-- Filter jsonls trailing comma (519) and comment (521) warnings for JSONC files
local original_diagnostic_set = vim.diagnostic.set
vim.diagnostic.set = function(ns, bufnr, diagnostics, opts)
  if vim.bo[bufnr].filetype == "jsonc" then
    diagnostics = vim.tbl_filter(function(d) return d.code ~= 519 and d.code ~= 521 end, diagnostics)
  end
  original_diagnostic_set(ns, bufnr, diagnostics, opts)
end

-- Auto-reload files changed on disk (silent unless buffer has unsaved edits)
vim.o.autoread = true
vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold" }, {
  command = "silent! checktime",
})

-- Persistent notification log
-- Writes all vim.notify calls to ~/.local/state/nvim/notifications.log
-- Hooks into Snacks.notifier.notify rather than replacing vim.notify,
-- so noice.nvim and snacks.nvim keep working normally.
local log_path = vim.fn.stdpath "state" .. "/notifications.log"
vim.fn.mkdir(vim.fn.fnamemodify(log_path, ":h"), "p")

local level_names = { [0] = "TRACE", [1] = "DEBUG", [2] = "INFO", [3] = "WARN", [4] = "ERROR" }

local function log_to_file(msg, level)
  local name = level_names[level or 2] or tostring(level)
  local line = string.format("[%s] [%s] %s\n", os.date "%Y-%m-%d %H:%M:%S", name, tostring(msg))
  local f = io.open(log_path, "a")
  if f then
    f:write(line)
    f:close()
  end
end

vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  once = true,
  callback = function()
    vim.schedule(function()
      local ok, notifier = pcall(function() return Snacks.notifier end)
      if ok and notifier and notifier.notify then
        local original = notifier.notify
        notifier.notify = function(msg, level, opts)
          log_to_file(msg, level)
          return original(msg, level, opts)
        end
      end
    end)
  end,
})
