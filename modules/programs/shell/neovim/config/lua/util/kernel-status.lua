-- Shared kernel status state for statusline integration.
-- Tracks molten and jupyter-bridge kernel activity without shelling out.

local M = {
  -- Molten state (updated by notebook.lua wrappers)
  molten_busy = false,

  -- Bridge state (updated by PID file check + exec wrappers)
  bridge_running = false,
  bridge_busy = false,

  -- Connection file kernel name (e.g. "kernel-5094b45f")
  bridge_kernel_name = nil,

  -- Cached runtime dir (computed once per repo)
  _bridge_runtime_dir = nil,
}

--- Compute the jupyter-bridge runtime directory for the current git repo.
--- Returns nil if not in a git repo or jupyter-bridge is not installed.
function M.get_bridge_runtime_dir()
  if M._bridge_runtime_dir then return M._bridge_runtime_dir end
  if vim.fn.executable "jupyter-bridge" ~= 1 then return nil end

  local obj = vim.system({ "git", "rev-parse", "--show-toplevel" }, { text = true }):wait()
  if obj.code ~= 0 then return nil end

  local repo_root = vim.trim(obj.stdout)
  -- sha256 first 8 chars of repo root
  local hash_obj = vim.system({ "sha256sum" }, { stdin = repo_root, text = true }):wait()
  if hash_obj.code ~= 0 then return nil end

  local hash = hash_obj.stdout:sub(1, 8)
  M._bridge_runtime_dir = "/tmp/jupyter-bridge-" .. hash
  return M._bridge_runtime_dir
end

--- Check if the bridge daemon PID is alive by reading the PID file.
--- Pure filesystem check, no shell invocation.
function M.check_bridge_alive()
  local dir = M.get_bridge_runtime_dir()
  if not dir then
    M.bridge_running = false
    return false
  end

  local pid_file = dir .. "/pid"
  local f = io.open(pid_file, "r")
  if not f then
    M.bridge_running = false
    return false
  end

  local pid = f:read "*l"
  f:close()
  if not pid then
    M.bridge_running = false
    return false
  end

  -- Check /proc/<pid> on Linux
  local stat = vim.uv.fs_stat("/proc/" .. pid)
  M.bridge_running = stat ~= nil

  -- Read kernel name from connection file
  if M.bridge_running then
    local conn_file = dir .. "/connection"
    local cf = io.open(conn_file, "r")
    if cf then
      local conn_path = cf:read "*l"
      cf:close()
      if conn_path then
        -- Extract "kernel-xxxx" from "/path/to/kernel-xxxx.json"
        M.bridge_kernel_name = conn_path:match "([^/]+)%.json$"
      end
    end
  else
    M.bridge_kernel_name = nil
  end

  return M.bridge_running
end

--- Get the molten kernel names for the current buffer (cheap call).
function M.molten_kernels()
  local ok, molten_status = pcall(require, "molten.status")
  if not ok then return "" end
  return molten_status.kernels()
end

--- Check if molten is initialized in the current buffer.
function M.molten_initialized()
  local ok, molten_status = pcall(require, "molten.status")
  if not ok then return false end
  return molten_status.initialized() ~= ""
end

--- Build the statusline provider string.
--- Returns "" when no kernel activity is relevant.
function M.provider()
  local parts = {}

  -- Molten kernel status
  local kernels = M.molten_kernels()
  if kernels ~= "" then
    local icon = M.molten_busy and "" or ""
    table.insert(parts, icon .. " " .. kernels)
  end

  -- Bridge daemon status
  if M.bridge_running then
    local icon = M.bridge_busy and "" or ""
    local label = M.bridge_kernel_name or "bridge"
    table.insert(parts, icon .. " " .. label)
  end

  return table.concat(parts, "  ")
end

--- Whether the component should be visible at all.
function M.condition() return M.molten_initialized() or M.bridge_running end

-- Set up periodic bridge status check (every 5s) and on BufEnter.
-- Deferred to avoid running at require-time.
function M.setup()
  -- Check bridge status on BufEnter
  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("KernelStatusBridge", { clear = true }),
    callback = function() M.check_bridge_alive() end,
  })

  -- Periodic timer for bridge status (5s)
  local timer = vim.uv.new_timer()
  if timer then
    timer:start(
      5000,
      5000,
      vim.schedule_wrap(function()
        local was = M.bridge_running
        M.check_bridge_alive()
        -- Redraw statusline if state changed
        if was ~= M.bridge_running then vim.cmd.redrawstatus() end
      end)
    )
  end
end

return M
