-- Persistent notification log
-- Writes all vim.notify calls to ~/.local/state/nvim/notifications.log
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

local function wrap_notify()
  local current = vim.notify
  if current._notify_logged then return end
  vim.notify = function(msg, level, opts)
    log_to_file(msg, level)
    return current(msg, level, opts)
  end
  vim.notify._notify_logged = true
end

-- Wrap immediately for early startup notifications
wrap_notify()

-- Re-wrap after VeryLazy so we sit on top of noice.nvim's replacement
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  once = true,
  callback = function() vim.schedule(wrap_notify) end,
})
