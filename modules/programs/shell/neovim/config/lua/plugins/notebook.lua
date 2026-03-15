-- Notebook / REPL stack: molten-nvim + jupytext.nvim
-- Provides inline Jupyter output and .ipynb editing via hydrogen cell markers (# %%).

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

--- Restart the kernel and run all cells.
local function restart_and_run_all()
  vim.cmd "MoltenRestart!"
  vim.defer_fn(run_all, 500)
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
    end,
    keys = {
      -- Kernel management: <Space>m
      { "<leader>mi", "<cmd>MoltenInit<cr>", desc = "Init kernel" },
      { "<leader>md", "<cmd>MoltenDeinit<cr>", desc = "Deinit kernel" },
      { "<leader>mr", "<cmd>MoltenRestart!<cr>", desc = "Restart kernel" },
      { "<leader>mx", "<cmd>MoltenInterrupt<cr>", desc = "Interrupt kernel" },

      -- Output
      { "<leader>ms", "<cmd>MoltenShowOutput<cr>", desc = "Show output" },
      { "<leader>mh", "<cmd>MoltenHideOutput<cr>", desc = "Hide output" },
      { "<leader>mo", "<cmd>noautocmd MoltenEnterOutput<cr>", desc = "Enter output window" },

      -- Run code
      { "<leader>mc", run_cell, desc = "Run cell" },
      { "<leader>ml", "<cmd>MoltenEvaluateLine<cr>", desc = "Run line" },
      { "<leader>mv", ":<C-u>MoltenEvaluateVisual<cr>gv", mode = "v", desc = "Run selection" },
      { "<leader>me", "<cmd>MoltenReevaluateCell<cr>", desc = "Re-evaluate cell" },
      { "<leader>ma", run_all, desc = "Run all cells" },
      { "<leader>mR", restart_and_run_all, desc = "Restart kernel & run all" },

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
  },
}
