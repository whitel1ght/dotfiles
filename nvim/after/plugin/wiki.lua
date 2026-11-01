vim.keymap.set('n', '<leader>x', [[<cmd>VimwikiToggleListItem<cr>]])

local topics_subdir = 'interests'
local topics_dir = vim.fn.expand('~/wiki/' .. topics_subdir)

vim.keymap.set('n', '<leader>tp', function()
  local topics = vim.tbl_map(function(file)
    return vim.fn.fnamemodify(file, ':t:r')
  end, vim.fn.glob(topics_dir .. '/topic-*.md', false, true))

  if vim.tbl_isempty(topics) then
    vim.notify('No topics found in ' .. topics_dir, vim.log.levels.WARN)
    return
  end

  vim.ui.select(topics, { prompt = 'Select Parent Topic:' }, function(choice)
    if not choice then return end
    -- root-absolute so the link resolves from any file in the wiki, not just the root
    local link = '/' .. topics_subdir .. '/' .. choice
    local line = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(0, line, line, false, { '* [[' .. link .. ']]' })
  end)
end, { desc = 'Insert Vimwiki Parent Topic' })
