RightWin = function ()
  local current_window = vim.api.nvim_get_current_win()
  vim.cmd('wincmd l')

  if current_window == vim.api.nvim_get_current_win() then
    vim.cmd('wincmd v')
    vim.cmd('wincmd l')
  end
end

LeftWin = function ()
  local current_window = vim.api.nvim_get_current_win()
  vim.cmd('wincmd h')

  if current_window == vim.api.nvim_get_current_win() then
    vim.cmd('wincmd v')
    vim.cmd('wincmd h')
  end
end

TopWin = function ()
  local current_window = vim.api.nvim_get_current_win()
  vim.cmd('wincmd k')

  if current_window == vim.api.nvim_get_current_win() then
    vim.cmd('wincmd s')
    vim.cmd('wincmd k')
  end
end

BottomWin = function ()
  local current_window = vim.api.nvim_get_current_win()
  vim.cmd('wincmd j')

  if current_window == vim.api.nvim_get_current_win() then
    vim.cmd('wincmd s')
    vim.cmd('wincmd j')
  end
end
