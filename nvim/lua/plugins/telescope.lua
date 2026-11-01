return {
  {
    'nvim-telescope/telescope.nvim',
    -- Was pinned to tag 0.1.5, whose commit dates from September 2023. Nothing
    -- here depends on that release, and holding a two-year-old pin against
    -- Neovim 0.12 buys risk rather than stability.
    dependencies = {
      {'nvim-lua/plenary.nvim'}
    }
  },
  { 'nvim-telescope/telescope-ui-select.nvim' },
}