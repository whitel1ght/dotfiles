return {
  "rachartier/tiny-glimmer.nvim",
  event = "VeryLazy",
  priority = 10,
  config = function()
    require("tiny-glimmer").setup({
      overwrite = {
        auto_map = true,
        yank = {
          enabled = true,
          default_animation = "fade"
        }
      },
      animations = {
        fade = {
          from_color = "#ffffff",  -- White
          to_color = "#292e42"     -- TokyoNight bg_highlight (subtle)
        }
      }
    })
  end,
}