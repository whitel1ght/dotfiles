return {
  'nvim-treesitter/nvim-treesitter',
  build = ':TSUpdate',
  config = function()
    require'nvim-treesitter.configs'.setup {
      modules = {},
      ignore_install = {},
      ensure_installed = { "c", "lua", "vim", "vimdoc", "query", "javascript", "typescript", "vue", "html", "css", "json" },
      sync_install = false,
      auto_install = true,
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
      },
    }
  end
}
