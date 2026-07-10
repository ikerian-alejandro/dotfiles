return {
  ---@type lspconfig.settings.rust_analyzer
  default_settings = {
    ["rust-analyzer"] = {
      cargo = {
        -- Deprecated, but still working RA flag set by LazyVim that changes its stock
        -- behavior, used by other editors
        allFeatures = false,
      },
    },
  },
}
