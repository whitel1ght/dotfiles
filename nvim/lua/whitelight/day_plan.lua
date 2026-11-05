-- The plan popup (bin/day-plan, tmux prefix+e): the diary in a float that fills the popup
-- (whitelight.popup draws the frame). `gp` opens the plan picker (bin/plan-pick) in a float on
-- top; the `<!-- pN -->` comment ids are concealed in the plan window only.
local M = {}

local function pick()
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = math.max(math.floor(vim.o.columns * 0.8), 1),
    height = math.max(math.floor(vim.o.lines * 0.8), 1),
    row = math.floor(vim.o.lines * 0.1),
    col = math.floor(vim.o.columns * 0.1),
    border = 'rounded',
    style = 'minimal',
  })
  vim.wo[win].winhighlight = 'FloatBorder:PopupBorder,NormalFloat:Normal'
  vim.fn.jobstart({ vim.fn.expand('$HOME/.local/bin/plan-pick') }, {
    term = true,
    on_exit = function()
      if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
      if vim.api.nvim_buf_is_valid(buf) then vim.api.nvim_buf_delete(buf, { force = true }) end
    end,
  })
  vim.cmd('startinsert')
end

function M.float(title)
  local base = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(base)
  -- before the first redraw a file opened without +cmd can report line 0
  cursor[1] = math.max(cursor[1], 1)
  local buf = vim.api.nvim_get_current_buf()
  local win = require('whitelight.popup').float(0, title)
  vim.wo[win].conceallevel = 2
  vim.wo[win].concealcursor = 'nc'
  vim.api.nvim_win_call(win, function()
    vim.fn.matchadd('Conceal', [[\s*<!-- p\d\+ -->]], 10, -1, { conceal = '' })
  end)
  vim.keymap.set('n', 'gp', pick, { buffer = buf, desc = 'plan picker' })
  vim.api.nvim_win_set_cursor(win, cursor)
  vim.cmd('normal! zt')
  return win
end

return M
