-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Force a dark background/theme
vim.o.background = "dark"

-- Neovide's embedded Fira Code Nerd Font is only used as the primary font
-- when `guifont` is unset, and it is not part of the per-glyph fallback chain
-- (that chain only queries fonts installed on the OS). So the most reliable
-- way to get all icons working is to install a Nerd Font system-wide and point
-- `guifont` at it explicitly. Install command for Homebrew:
-- brew install --cask font-fira-code-nerd-font
vim.o.guifont = "FiraCode Nerd Font:h14"

-- The SHELL environment variable may not be set in devcontainers, so Neovim may
-- default to /bin/sh. For interactive purposes, however, we want to default to
-- zsh if available, then bash, and finally /bin/sh as a last resort
for _, sh in ipairs({ "/bin/zsh", "/bin/bash", "/bin/sh" }) do
  if vim.fn.executable(sh) == 1 then
    vim.o.shell = sh
    break
  end
end

-- The Ansible LSP requires proper filetype assignment to take priority over the
-- general YAML LSP server. Docker Compose files are also affected. We also add
-- a "redis" filetype, used by dadbod, for Redis commands highlighting in
-- conjunction with our custom redis syntax
vim.filetype.add({
  pattern = {
    [".*/.*[.]ansible[.]ya?ml"] = "yaml.ansible",
    [".*/compose[.]ya?ml"] = "yaml.docker-compose",
    [".*/compose[.][^.]+[.]ya?ml"] = "yaml.docker-compose",
    [".*/.*[.]redis"] = "redis",
  },
})

-- Enable several useful LSP servers, using the built-in Neovim LSP support,
-- https://neovim.io/doc/user/lsp/, which deprecates neovim/nvim-lspconfig
vim.lsp.enable("typos_lsp")
vim.lsp.enable("make-ls")
vim.lsp.enable("graphql")

-- Initialize codesettings for project-specific LSP configuration, for all LSPs
vim.lsp.config("*", {
  before_init = function(_, config)
    require("codesettings").with_local_settings(config.name, config)
  end,
})
