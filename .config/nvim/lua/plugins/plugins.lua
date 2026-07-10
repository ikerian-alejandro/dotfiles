return {
  -- Devcontainer support
  {
    "erichlf/devcontainer-cli.nvim",
    dependencies = { "akinsho/toggleterm.nvim" },
    init = function()
      require("devcontainer-cli").setup({
        interactive = false,
        remove_existing_container = false,
        -- Uses the devcontainer CLI dotfiles support: https://github.com/devcontainers/cli/pull/362
        dotfiles_repository = "https://github.com/ikerian-alejandro/dotfiles.git",
        --dotfiles_branch = "main", -- Not supported by the devcontainer CLI
        dotfiles_targetPath = "/tmp/dotfiles",
        shell = "sh",
      })
      require("config.devcontainer_reopen").setup()
    end,
  },

  -- Git support
  { "sindrets/diffview.nvim" },
  { "lewis6991/gitsigns.nvim", opts = { current_line_blame = true } },
  {
    "afonsofrancof/worktrees.nvim",
    event = "VeryLazy",
    opts = {
      base_path = "../..", -- Relative to .git dir

      path_template = "worktree-{branch}",

      mappings = {
        create = "<leader>gwc",
        delete = "<leader>gwd",
        switch = "<leader>gws",
      },
    },
  },

  -- LSP support
  {
    "mrjones2014/codesettings.nvim",
    opts = { live_reload = true },
  },
  {
    "mason-org/mason.nvim",
    opts = {
      ensure_installed = {
        -- Required for Nix linting with the Nix extra
        "statix",
        -- Required for LSP servers to work
        -- make-ls is not in Mason yet, it should be provided externally
        "typos-lsp",
        "graphql-language-service-cli",
      },
    },
  },

  -- Customize the status line with different buttons
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      opts.sections.lualine_z = {
        {
          function()
            return ""
          end,
          cond = function()
            return vim.uv.fs_stat("/.dockerenv") ~= nil
          end,
        },
      }
    end,
  },

  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        -- By default, show hidden and Git-ignored files
        sources = {
          explorer = {
            hidden = true,
            ignored = true,
          },
          files = {
            hidden = true,
            ignored = true,
          },
        },
      },
    },
  },

  -- Use the gruvbox theme
  { "ellisonleao/gruvbox.nvim" },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "gruvbox",
    },
  },
}
