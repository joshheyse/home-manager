return {
  "folke/snacks.nvim",
  opts = {
    image = {
      -- Remove pdf from Snacks image viewer formats so mupager handles PDFs
      -- instead of Snacks converting them via ImageMagick.
      formats = {
        "png",
        "jpg",
        "jpeg",
        "gif",
        "bmp",
        "webp",
        "tiff",
        "heic",
        "avif",
        "mp4",
        "mov",
        "avi",
        "mkv",
        "webm",
        -- "pdf", -- handled by mupager
      },
    },
  },
}
