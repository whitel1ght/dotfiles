require("tokyonight").setup({
  lualine_bold = true,
  transparent = true,
  styles = {
    sidebars = "transparent",
    floats = "transparent",
  },
  on_colors = function(colors)
    colors.bg_statusline = colors.none
    colors.border = '#626780'
  end,
  on_highlights = function(highlights, colors)
    highlights.LineNr = { fg = '#9da0b0', bold = true }
    highlights.LineNrAbove = { fg = '#626780'}
    highlights.LineNrBelow = { fg = '#626780'}
  end
})

vim.api.nvim_create_autocmd("UIEnter", {
  pattern = "*",
  callback = function()
    vim.api.nvim_set_hl(0, "Folded", { bg = "none" })
  end
})

vim.cmd[[colorscheme tokyonight]]
