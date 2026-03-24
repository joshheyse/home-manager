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

--- Connect molten to the shared kernel if available, else show picker.
local function init_kernel()
  local dir = ks.get_bridge_runtime_dir()
  if dir then
    local conn_path = dir .. "/connection"
    local f = io.open(conn_path, "r")
    if f then
      local connection_file = f:read "*l"
      f:close()
      if connection_file and connection_file ~= "" and vim.uv.fs_stat(connection_file) then
        vim.cmd("MoltenInit " .. connection_file)
        return
      end
    end
  end

  -- No shared kernel available, fall back to picker
  vim.cmd "MoltenInit"
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
      -- Kernel
      { "<leader>mi", init_kernel, desc = "Init kernel" },
      { "<leader>mk", "<cmd>MoltenInit<cr>", desc = "Switch kernel" },
      { "<leader>mr", "<cmd>MoltenRestart!<cr>", desc = "Restart kernel" },
      { "<leader>mx", "<cmd>MoltenInterrupt<cr>", desc = "Interrupt kernel" },

      -- Run code
      { "<leader>mc", run_cell, desc = "Run cell" },
      { "<leader>mn", run_cell_and_advance, desc = "Run cell & advance" },
      { "<leader>ma", run_all, desc = "Run all cells" },

      -- Output
      { "<leader>mo", "<cmd>noautocmd MoltenEnterOutput<cr>", desc = "Enter output window" },

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
