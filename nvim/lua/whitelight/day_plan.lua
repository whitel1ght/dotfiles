-- The plan popup (bin/day-plan, tmux prefix+e): the diary in a float that fills the popup
-- (whitelight.popup draws the frame).
local M = {}

function M.float(title)
  local base = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(base)
  -- before the first redraw a file opened without +cmd can report line 0
  cursor[1] = math.max(cursor[1], 1)
  local win = require('whitelight.popup').float(0, title)
  vim.api.nvim_win_set_cursor(win, cursor)
  vim.cmd('normal! zt')
  return win
end

return M
