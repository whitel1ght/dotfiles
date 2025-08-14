local fh = require('floating-help')

fh.setup({
  -- Defaults
  width = 140,   -- Whole numbers are columns/rows
  height = 0.9, -- Decimals are a percentage of the editor
  position = 'C',   -- NW,N,NW,W,C,E,SW,S,SE (C==center)
  border = 'double', -- rounded,double,single
  onload = function(query_type) end, -- optional callback to be executed after help contents has been loaded
})

-- Create a keymap for toggling the help window
vim.keymap.set('n', '<leader>hh', fh.toggle)
