return {
  "nvim-neo-tree/neo-tree.nvim",
  dependencies = {
    { "AstroNvim/astroui", opts = { icons = { Location = "" } } },
    {
      "AstroNvim/astrocore",
      opts = function(_, opts)
        local maps = opts.mappings
        local prefix = "<Leader>r"
        maps.n[prefix] = {
          desc = require("astroui").get_icon("Location", 1, true) .. "Reveal",
          "<cmd>Neotree reveal<cr>",
        }
      end,
    },
  },
  opts = {
    use_popups_for_input = true,
    popup_border_style = "double",
    enable_git_status = true,
    enable_diagnostics = true,
    window = {
      width = 30,
      mappings = {
        v = "open_vsplit",
        s = "open_split",
        m = {
          "move",
          config = {
            show_path = "relative",
          },
        },
      },
    },
    filesystem = {
      follow_current_file = {
        enabled = false,
      },
      use_libuv_file_watcher = true,
      watch_for_changes = true,
      refresh_delay = 100,
    },
    event_handlers = {
      {
        event = "git_event",
        handler = function()
          -- Force refresh on git events
          require("neo-tree.sources.git_status").refresh()
        end,
      },
    },
  },
}
