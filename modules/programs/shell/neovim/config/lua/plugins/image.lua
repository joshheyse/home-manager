return {
  "3rd/image.nvim",
  opts = {
    kitty_method = "unicode-placeholders",
    max_height_window_percentage = math.huge,
    max_width_window_percentage = math.huge,
    window_overlap_clear_enabled = true,
    window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
    tmux_show_only_in_original_window = true,
  },
  config = function(_, opts)
    require("image").setup(opts)
    -- Prevent image.nvim from treating PDFs as images (avoids ImageMagick
    -- conversion that conflicts with mupager's own PDF rendering).
    local magic = require "image.utils.magic"
    local orig_detect = magic.detect_format
    magic.detect_format = function(path)
      local fmt = orig_detect(path)
      if fmt == "pdf" then return nil end
      return fmt
    end
  end,
}
