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

      -- Project-local .vscode/launch.json needs no explicit load: nvim-dap's
      -- built-in `dap.launch.json` config provider reads it on demand at
      -- `continue()` time (:help dap-providers). That also picks up edits and
      -- `:cd` changes, which the old load-once-at-startup call did not.
      --
      -- The type -> filetype mapping that used to live here is gone with it:
      -- the provider returns every launch.json entry regardless of buffer
      -- filetype, and `dap.ext.vscode.type_to_filetypes` is only consulted by
      -- the deprecated loader.
      --
      -- overseer.nvim enables preLaunchTask / postDebugTask support
      -- automatically via its setup() call (dap = true by default).
    end,
  },
}
