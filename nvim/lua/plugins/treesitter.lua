return {
  'nvim-treesitter/nvim-treesitter',
  -- Pinned to master deliberately. Upstream's default branch moved to `main`,
  -- which is a full rewrite that DELETES nvim-treesitter.configs — the module
  -- the setup call below uses. Without this pin lazy follows the default
  -- branch, and the next update turns this file into a hard startup error.
  -- Migrating to main means rewriting this to require('nvim-treesitter').setup
  -- plus a FileType autocmd calling vim.treesitter.start(); master still works
  -- and is what this config is written against.
  branch = 'master',
  build = ':TSUpdate',
  config = function()
    require'nvim-treesitter.configs'.setup {
      modules = {},
      ignore_install = {},
      ensure_installed = { "c", "lua", "vim", "vimdoc", "query", "javascript", "typescript", "vue", "html", "htmldjango", "css", "json", "python", "elm", "go", "gomod", "gosum" },
      sync_install = false,
      auto_install = true,
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
      },
    }
  end
}
