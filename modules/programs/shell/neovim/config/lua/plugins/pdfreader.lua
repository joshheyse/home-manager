return {
  "r-pletnev/pdfreader.nvim",
  lazy = false,
  dependencies = {
    "folke/snacks.nvim",
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    -- Override zoom step size before setup so the plugin's keybindings use it
    local Book = require "pdfreader.book"
    local orig_zoom_in = Book.zoom_in
    local orig_zoom_out = Book.zoom_out
    Book.zoom_in = function(self, _) orig_zoom_in(self, 10) end
    Book.zoom_out = function(self, _) orig_zoom_out(self, 10) end

    require("pdfreader").setup()

    -- PDF-specific keybindings (buffer-local, visible in which-key)
    vim.api.nvim_create_autocmd("BufEnter", {
      pattern = "*.pdf",
      group = vim.api.nvim_create_augroup("pdfreader-keys", { clear = true }),
      callback = function()
        local buf = vim.api.nvim_get_current_buf()
        local function map(key, cmd, desc) vim.keymap.set("n", key, cmd, { buffer = buf, desc = desc }) end

        map("g", function()
          vim.ui.input({ prompt = "Page number: " }, function(input)
            if input then vim.cmd("PDFReader setPage " .. input) end
          end)
        end, "Go to page")
        map("t", function() vim.cmd "PDFReader showToc" end, "Table of contents")
        map("b", function() vim.cmd "PDFReader addBookmark" end, "Add bookmark")
        map("B", function() vim.cmd "PDFReader showBookmarks" end, "Show bookmarks")
        map("d", function() vim.cmd "PDFReader setViewMode dark" end, "Dark mode")
        map("T", function() vim.cmd "PDFReader setViewMode text" end, "Text mode")
        map("s", function() vim.cmd "PDFReader setViewMode standard" end, "Standard mode")
        map("r", function() vim.cmd "PDFReader redrawPage" end, "Redraw page")
      end,
    })
  end,
}
