return {
  'folke/tokyonight.nvim',
  -- Declaration only. The colorscheme used to be applied here as well, which
  -- ran BEFORE after/plugin/tokyonight.lua called setup() with the transparent
  -- and on_highlights options — so the theme was applied once with defaults,
  -- then set up and applied again. after/plugin is now the single place that
  -- configures and applies it, in that order.
  priority = 1000,
  lazy = false,
}