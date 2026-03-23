-- Notebook / REPL stack: molten-nvim + jupytext.nvim
-- Provides inline Jupyter output and .ipynb editing via hydrogen cell markers (# %%).

local ks = require "util.kernel-status"

--- Find the start and end lines of the current `# %%` cell.
--- Returns (start, end) as 1-indexed line numbers, where start is the line
--- after the `# %%` marker and end is the last line before the next marker (or EOF).
local function get_cell_range()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] -- 1-indexed
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local total = #lines

  -- Find cell start: search upward for `# %%`
  local cell_start = 1
  for i = row, 1, -1 do
    if lines[i]:match "^# %%%%" then
      cell_start = i + 1
      break
    end
  end

  -- Find cell end: search downward for next `# %%`
  local cell_end = total
  for i = row + 1, total do
    if lines[i]:match "^# %%%%" then
      cell_end = i - 1
      break
    end
  end

  -- Skip leading/trailing blank lines
  while cell_start <= cell_end and lines[cell_start]:match "^%s*$" do
    cell_start = cell_start + 1
  end
  while cell_end >= cell_start and lines[cell_end]:match "^%s*$" do
    cell_end = cell_end - 1
  end

  return cell_start, cell_end
end

--- Run the current `# %%` cell with MoltenEvaluateRange.
local function run_cell()
  local start, finish = get_cell_range()
  if start > finish then return end
  ks.molten_busy = true
  vim.cmd.redrawstatus()
  vim.fn.MoltenEvaluateRange(start, finish)
end

--- Run all `# %%` cells in the buffer sequentially.
local function run_all()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local total = #lines
  local i = 1
  while i <= total do
    -- Find next cell marker
    if lines[i]:match "^# %%%%" then
      local cell_start = i + 1
      -- Skip blank lines at start
      while cell_start <= total and lines[cell_start]:match "^%s*$" do
        cell_start = cell_start + 1
      end
      -- Find cell end
      local cell_end = total
      for j = i + 1, total do
        if lines[j]:match "^# %%%%" then
          cell_end = j - 1
          break
        end
      end
      -- Skip trailing blank lines
      while cell_end >= cell_start and lines[cell_end]:match "^%s*$" do
        cell_end = cell_end - 1
      end
      if cell_start <= cell_end then vim.fn.MoltenEvaluateRange(cell_start, cell_end) end
      i = cell_end + 1
    else
      i = i + 1
    end
  end
end

--- Init kernel, restart, and run all cells.
local function restart_and_run_all()
  vim.cmd "MoltenInit"
  vim.defer_fn(function()
    vim.cmd "MoltenRestart!"
    vim.defer_fn(run_all, 500)
  end, 500)
end

--- Navigate to the next `# %%` cell marker.
local function next_cell()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i = row + 1, #lines do
    if lines[i]:match "^# %%%%" then
      vim.api.nvim_win_set_cursor(0, { i + 1, 0 })
      return
    end
  end
end

--- Navigate to the previous `# %%` cell marker.
local function prev_cell()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  -- Find the marker for the current cell first, then the one before it
  local current_marker = nil
  for i = row, 1, -1 do
    if lines[i]:match "^# %%%%" then
      current_marker = i
      break
    end
  end
  if not current_marker then return end
  for i = current_marker - 1, 1, -1 do
    if lines[i]:match "^# %%%%" then
      vim.api.nvim_win_set_cursor(0, { i + 1, 0 })
      return
    end
  end
  -- No previous marker; jump to top of file
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

--- Run current cell then advance to the next cell.
local function run_cell_and_advance()
  run_cell()
  next_cell()
end

--- Get the text content of the current cell as a string.
local function get_cell_text()
  local start, finish = get_cell_range()
  if start > finish then return nil end
  local lines = vim.api.nvim_buf_get_lines(0, start - 1, finish, false)
  return table.concat(lines, "\n")
end

--- Execute code via jupyter-bridge exec, showing result in a notification.
local function bridge_exec(code)
  if not code or code == "" then return end
  ks.bridge_busy = true
  vim.cmd.redrawstatus()
  vim.fn.jobstart({ "jupyter-bridge", "exec" }, {
    stdin = { code, "" },
    stdout_buffered = true,
    on_stdout = function(_, data)
      if not data then return end
      local text = table.concat(data, "\n")
      if text == "" then return end
      local ok, result = pcall(vim.json.decode, text)
      if not ok then return end
      -- Extract displayable output
      local parts = {}
      for _, out in ipairs(result.outputs or {}) do
        if out.type == "stream" then
          table.insert(parts, out.text)
        elseif out.type == "execute_result" and out.data then
          table.insert(parts, out.data["text/plain"] or "")
        elseif out.type == "error" then
          table.insert(parts, out.ename .. ": " .. out.evalue)
        end
      end
      if #parts > 0 then
        local msg = table.concat(parts, "")
        local level = result.status == "ok" and vim.log.levels.INFO or vim.log.levels.ERROR
        vim.schedule(function() vim.notify(msg, level, { title = "jupyter-bridge" }) end)
      end
    end,
    on_exit = function()
      vim.schedule(function()
        ks.bridge_busy = false
        vim.cmd.redrawstatus()
      end)
    end,
  })
end

--- Execute the current cell on the jupyter-bridge kernel.
local function bridge_exec_cell()
  if vim.fn.executable "jupyter-bridge" ~= 1 then
    vim.notify("jupyter-bridge not found", vim.log.levels.WARN)
    return
  end
  bridge_exec(get_cell_text())
end

--- Execute the entire buffer on the jupyter-bridge kernel.
local function bridge_exec_buffer()
  if vim.fn.executable "jupyter-bridge" ~= 1 then
    vim.notify("jupyter-bridge not found", vim.log.levels.WARN)
    return
  end
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  bridge_exec(table.concat(lines, "\n"))
end

--- Connect molten to the shared kernel managed by jupyter-bridge.
--- Reads the connection file path from the bridge runtime dir.
local function connect_shared_kernel()
  local dir = ks.get_bridge_runtime_dir()
  if not dir then
    vim.notify("jupyter-bridge runtime dir not found", vim.log.levels.WARN)
    return
  end

  local conn_path = dir .. "/connection"
  local f = io.open(conn_path, "r")
  if not f then
    vim.notify("No connection file yet — open a notebook in Lab first", vim.log.levels.WARN)
    return
  end

  local connection_file = f:read "*l"
  f:close()
  if not connection_file or connection_file == "" then
    vim.notify("Connection file is empty", vim.log.levels.WARN)
    return
  end

  vim.cmd("MoltenInit " .. connection_file)
end

--- Manually trigger jupytext --sync on the current file.
local function jupytext_sync()
  if vim.fn.executable "jupytext" ~= 1 then
    vim.notify("jupytext not found", vim.log.levels.WARN)
    return
  end
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then return end
  vim.fn.jobstart({ "jupytext", "--sync", path }, {
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          vim.notify("jupytext synced", vim.log.levels.INFO)
        else
          vim.notify("jupytext sync failed (exit " .. code .. ")", vim.log.levels.ERROR)
        end
      end)
    end,
  })
end

return {
  -- molten-nvim: Jupyter kernel integration with inline output
  {
    "benlubas/molten-nvim",
    lazy = false,
    build = ":UpdateRemotePlugins",
    init = function()
      vim.g.molten_image_provider = "image.nvim"
      vim.g.molten_auto_open_output = false
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_lines_off_by_1 = true
      vim.g.molten_wrap_output = true
      vim.g.molten_output_win_max_height = 20

      -- Clear molten_busy when kernel returns to idle
      vim.api.nvim_create_autocmd("User", {
        pattern = "MoltenKernelReady",
        callback = function()
          ks.molten_busy = false
          vim.cmd.redrawstatus()
        end,
      })

      -- Initialize kernel status polling for bridge daemon
      ks.setup()
    end,
    keys = {
      -- Kernel management: <Space>m
      { "<leader>mi", "<cmd>MoltenInit<cr>", desc = "Init kernel" },
      { "<leader>mI", connect_shared_kernel, desc = "Init shared kernel" },
      { "<leader>md", "<cmd>MoltenDeinit<cr>", desc = "Deinit kernel" },
      { "<leader>mr", "<cmd>MoltenRestart!<cr>", desc = "Restart kernel" },
      { "<leader>mx", "<cmd>MoltenInterrupt<cr>", desc = "Interrupt kernel" },

      -- Output
      { "<leader>ms", "<cmd>MoltenShowOutput<cr>", desc = "Show output" },
      { "<leader>mh", "<cmd>MoltenHideOutput<cr>", desc = "Hide output" },
      { "<leader>mo", "<cmd>noautocmd MoltenEnterOutput<cr>", desc = "Enter output window" },

      -- Run code
      { "<leader>mc", run_cell, desc = "Run cell" },
      { "<leader>mn", run_cell_and_advance, desc = "Run cell & advance" },
      { "<leader>ml", "<cmd>MoltenEvaluateLine<cr>", desc = "Run line" },
      { "<leader>mv", ":<C-u>MoltenEvaluateVisual<cr>gv", mode = "v", desc = "Run selection" },
      { "<leader>me", "<cmd>MoltenReevaluateCell<cr>", desc = "Re-evaluate cell" },
      { "<leader>ma", run_all, desc = "Run all cells" },
      { "<leader>mR", restart_and_run_all, desc = "Restart kernel & run all" },

      -- Jupyter bridge (no-op if jupyter-bridge not installed)
      { "<leader>mb", bridge_exec_cell, desc = "Bridge exec cell" },
      { "<leader>mB", bridge_exec_buffer, desc = "Bridge exec buffer" },

      -- Jupytext sync (no-op if jupytext not installed)
      { "<leader>mS", jupytext_sync, desc = "Sync with jupytext" },

      -- Cell navigation
      { "]c", next_cell, desc = "Next cell" },
      { "[c", prev_cell, desc = "Previous cell" },
    },
  },

  -- jupytext.nvim: transparently edit .ipynb as markdown/python
  {
    "GCBallesteros/jupytext.nvim",
    lazy = false,
    opts = {
      style = "hydrogen",
      output_extension = "auto",
      force_ft = nil,
    },
    config = function(_, opts)
      require("jupytext").setup(opts)

      -- Sync .py -> .ipynb on save so Jupyter Lab auto-reloads
      vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup("JupytextSync", { clear = true }),
        pattern = "*.py",
        callback = function(ev)
          local py_path = ev.match
          local ipynb_path = py_path:gsub("%.py$", ".ipynb")

          -- Sync if a paired .ipynb exists or jupytext.toml is present
          local should_sync = vim.uv.fs_stat(ipynb_path) ~= nil
          if not should_sync then
            -- Walk up to find jupytext.toml
            local dir = vim.fs.dirname(py_path)
            local found = vim.fs.find("jupytext.toml", { path = dir, upward = true, limit = 1 })
            should_sync = #found > 0
          end

          if should_sync then
            vim.fn.jobstart({ "jupytext", "--sync", py_path }, {
              detach = true,
              on_stderr = function(_, data)
                if data and data[1] ~= "" then
                  vim.schedule(
                    function() vim.notify("jupytext sync: " .. table.concat(data, "\n"), vim.log.levels.WARN) end
                  )
                end
              end,
            })
          end
        end,
      })
    end,
  },
}
