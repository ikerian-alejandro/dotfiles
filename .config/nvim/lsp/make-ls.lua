---@type vim.lsp.Config
return {
  cmd = { "make-ls" },
  root_markers = { "Makefile", "makefile", "GNUmakefile" },
  filetypes = { "make" },
}
