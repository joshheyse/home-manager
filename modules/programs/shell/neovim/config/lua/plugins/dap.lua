-- Generic DAP configuration: keybindings, adapters, launch.json, overseer integration.
-- Language-specific LSP/treesitter configs live in their own files (cpp.lua, etc.).
-- Adapter types registered here map to .vscode/launch.json "type" fields.
local has_lldb_dap = vim.fn.exepath "lldb-dap" ~= ""

return {
  {
    "mfussenegger/nvim-dap",
    optional = true,
    dependencies = {
      "stevearc/overseer.nvim",
      {
        "AstroNvim/astrocore",
        opts = {
          mappings = {
            n = {
              ["<F5>"] = { function() require("dap").continue() end, desc = "Debugger: Continue" },
              ["<S-F5>"] = { function() require("dap").terminate() end, desc = "Debugger: Stop" },
              ["<F9>"] = { function() require("dap").toggle_breakpoint() end, desc = "Debugger: Toggle breakpoint" },
              ["<F10>"] = { function() require("dap").step_over() end, desc = "Debugger: Step over" },
              ["<F11>"] = { function() require("dap").step_into() end, desc = "Debugger: Step into" },
              ["<S-F11>"] = { function() require("dap").step_out() end, desc = "Debugger: Step out" },
            },
          },
        },
      },
    },
    config = function()
      local dap = require "dap"

      -- Register lldb-dap adapter for C/C++/Rust if available in PATH
      if has_lldb_dap then
        dap.adapters.lldb = {
          type = "executable",
          command = "lldb-dap",
          name = "lldb",
        }

        dap.configurations.cpp = {
          {
            name = "Launch (prompt)",
            type = "lldb",
            request = "launch",
            program = function() return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file") end,
            cwd = "${workspaceFolder}",
            stopOnEntry = false,
            args = {},
          },
          {
            name = "Attach to process",
            type = "lldb",
            request = "attach",
            pid = require("dap.utils").pick_process,
            args = {},
          },
        }

        dap.configurations.c = dap.configurations.cpp
        dap.configurations.rust = dap.configurations.cpp
      end

      -- Enable preLaunchTask / postDebugTask support via overseer.
      -- Must be called before load_launchjs.
      require("overseer").patch_dap(true)

      -- Load project-local .vscode/launch.json if present.
      -- Maps VS Code debug adapter types to neovim filetypes so configs
      -- are available for the correct buffers. Adapters not installed are
      -- silently skipped.
      require("dap.ext.vscode").load_launchjs(nil, {
        lldb = { "c", "cpp", "rust" },
        cppdbg = { "c", "cpp" },
        debugpy = { "python" },
        python = { "python" },
        delve = { "go" },
        go = { "go" },
        ["pwa-node"] = { "javascript", "typescript" },
        node = { "javascript", "typescript" },
      })
    end,
  },
}
