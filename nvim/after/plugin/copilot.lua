require('copilot').setup({
  panel = {
    enabled = false,
    auto_refresh = false,
    keymap = {
      jump_prev = "[[",
      jump_next = "]]",
      accept = "<CR>",
      refresh = "gr",
      open = "<M-CR>"
    },
    layout = {
      position = "bottom", -- | top | left | right
      ratio = 0.4
    },
  },
  suggestion = {
    enabled = true,
    auto_trigger = false,
    debounce = 75,
    keymap = {
      accept = false, -- we'll set up our own Tab mapping
      accept_word = false,
      accept_line = false,
      next = "<C-]>",
      prev = "<C-[>",
      dismiss = "<esc>",
    },
  },
  filetypes = {
    yaml = false,
    markdown = false,
    help = false,
    gitcommit = false,
    gitrebase = false,
    hgcommit = false,
    svn = false,
    cvs = false,
    ["."] = false,
  },
  copilot_node_command = 'node', -- Node.js version must be > 18.x
  server_opts_overrides = {},
})

-- so by default copilot suggestion is disable (auto_trigger prop is false)
-- the mapping is to toggle it on and off
vim.keymap.set('n', '<leader>ct', function ()
  require('copilot.suggestion').toggle_auto_trigger()
end)

-- manual trigger for suggestions
vim.keymap.set('i', '<C-\\>', function ()
  require('copilot.suggestion').next()
end)

-- smart tab: accept copilot if visible, otherwise fallback to cmp
vim.keymap.set('i', '<Tab>', function()
  local copilot = require('copilot.suggestion')
  local cmp = require('cmp')
  
  if copilot.is_visible() then
    copilot.accept()
  elseif cmp.visible() then
    cmp.select_next_item({ behavior = cmp.SelectBehavior.Insert })
  else
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Tab>', true, false, true), 'n', false)
  end
end)
