-- The frame of the nvim tmux popups (the plan popup): a float that fills the popup, with a
-- rounded lavender border, the title in its top edge and hints in the bottom one, like the fzf
-- popups. The popups have no tmux border, because a busy pane underneath paints over a tmux
-- popup's top border row.
local M = {}

local function geometry()
  return {
    relative = 'editor',
    row = 0,
    col = 0,
    width = math.max(vim.o.columns - 2, 1),
    -- the last row stays free: with cmdheight=0 (set.lua) nvim draws messages over it
    height = math.max(vim.o.lines - math.max(vim.o.cmdheight, 1) - 2, 1),
  }
end

local function label(text, hl) return { { ' ' .. text .. ' ', hl } } end

-- float(buf, title, footer?, on_resize?) opens buf in the frame and returns the window.
-- Closing the window (:q) closes nvim, asking about unsaved changes.
function M.float(buf, title, footer, on_resize)
  vim.api.nvim_set_hl(0, 'PopupBorder', { fg = '#bb9af7' })
  vim.api.nvim_set_hl(0, 'PopupTitle', { fg = '#7aa2f7', bold = true })
  vim.api.nvim_set_hl(0, 'PopupFooter', { fg = '#565f89' })
  local cfg = vim.tbl_extend('force', geometry(), {
    border = 'rounded',
    title = label(title, 'PopupTitle'),
    title_pos = 'left',
  })
  if footer then
    cfg.footer = label(footer, 'PopupFooter')
    cfg.footer_pos = 'right'
  end
  local win = vim.api.nvim_open_win(buf, true, cfg)
  vim.wo[win].winhighlight = 'FloatBorder:PopupBorder,NormalFloat:Normal'
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(win),
    once = true,
    callback = function()
      vim.schedule(function() vim.cmd('confirm qa') end)
    end,
  })
  -- Opened from a -c command, before the UI attaches and says how big the popup is, so the
  -- first size is a guess: fit it again once the screen is there, and on every resize.
  vim.api.nvim_create_autocmd({ 'UIEnter', 'VimResized' }, {
    callback = function()
      if not vim.api.nvim_win_is_valid(win) then return true end
      vim.api.nvim_win_set_config(win, geometry())
      if on_resize then on_resize() end
    end,
  })
  return win
end

function M.set_title(win, title)
  vim.api.nvim_win_set_config(win, { title = label(title, 'PopupTitle'), title_pos = 'left' })
end

return M
