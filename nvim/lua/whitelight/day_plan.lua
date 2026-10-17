-- The plan popup (bin/day-plan, tmux prefix+e): the diary in a float that fills the popup, with a
-- rounded lavender frame and the title in its top edge, like the fzf popups. The popup itself has
-- no tmux border, because a busy pane underneath paints over a tmux popup's top border row.
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

function M.float(title)
  vim.api.nvim_set_hl(0, 'DayPlanBorder', { fg = '#bb9af7' })
  vim.api.nvim_set_hl(0, 'DayPlanTitle', { fg = '#7aa2f7', bold = true })
  local base = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(base)
  local win = vim.api.nvim_open_win(0, true, vim.tbl_extend('force', geometry(), {
    border = 'rounded',
    title = { { ' ' .. title .. ' ', 'DayPlanTitle' } },
    title_pos = 'left',
  }))
  vim.wo[win].winhighlight = 'FloatBorder:DayPlanBorder,NormalFloat:Normal'
  vim.api.nvim_win_set_cursor(win, cursor)
  vim.cmd('normal! zt')
  -- The float is the whole popup: closing it (:q, :wq) closes nvim, asking about unsaved changes.
  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(win),
    once = true,
    callback = function()
      vim.schedule(function() vim.cmd('confirm qa') end)
    end,
  })
  -- This runs from a -c command, before the UI attaches and says how big the popup is, so the
  -- first size is a guess: fit it again once the screen is there, and on every resize.
  vim.api.nvim_create_autocmd({ 'UIEnter', 'VimResized' }, {
    callback = function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_set_config(win, geometry()) end
    end,
  })
  return win
end

return M
