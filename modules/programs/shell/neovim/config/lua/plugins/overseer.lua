-- Task runner (neovim equivalent of VS Code tasks.json).
-- Auto-discovers tasks from justfiles, makefiles, CMakeLists.txt, cargo, npm, etc.
-- Handles preLaunchTask in .vscode/launch.json so builds run before debug sessions.
return {
  "stevearc/overseer.nvim",
  cmd = { "OverseerRun", "OverseerToggle", "OverseerTaskAction", "OverseerInfo" },
  dependencies = {
    {
      "AstroNvim/astrocore",
      opts = {
        mappings = {
          n = {
            ["<Leader>o"] = { desc = "Overseer" },
            ["<Leader>or"] = { "<Cmd>OverseerRun<CR>", desc = "Run task" },
            ["<Leader>ot"] = { "<Cmd>OverseerToggle<CR>", desc = "Toggle task list" },
            ["<Leader>oa"] = { "<Cmd>OverseerTaskAction<CR>", desc = "Task action" },
          },
        },
      },
    },
  },
  opts = {},
}
