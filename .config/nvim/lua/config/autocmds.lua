-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

vim.api.nvim_create_autocmd("FileType", {
  pattern = "redis",
  callback = function()
    vim.keymap.set({ "n", "x" }, "<Leader>W", "<Plug>(DBUI_SaveQuery)", { silent = true, nowait = true, buf = 0 })
    vim.keymap.set({ "n", "x" }, "<Leader>S", "<Plug>(DBUI_ExecuteQuery)", { silent = true, nowait = true, buf = 0 })
  end,
})
