-- Re-apply editorconfig after Python ftplugin overrides indent settings
if vim.b.editorconfig and vim.b.editorconfig.indent_size then
  local size = tonumber(vim.b.editorconfig.indent_size)
  if size then
    vim.bo.shiftwidth = size
    vim.bo.tabstop = size
    vim.bo.softtabstop = size
  end
end
