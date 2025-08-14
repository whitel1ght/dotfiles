local keymap = vim.keymap
vim.g.mapleader = " "

keymap.set('n', '<Esc>', ':noh<cr>') -- clear search highlights
keymap.set('n', '<leader>p', 'cw<C-r>0')
keymap.set('n', '<leader>s', ':%s///g<Left><Left>') -- replace pattern
keymap.set('n', 'n', 'nzz') -- center the screen after jumping to next search result
keymap.set('n', 'N', 'Nzz') -- center the screen after jumping to previous search result
keymap.set('n', '<C-d>', '<C-d>zz') -- move the screen down after half a page and center it
keymap.set('n', '<C-u>', '<C-u>zz') -- move the screen up after half a page and center it
keymap.set({'n', 'v', 'x'}, '<leader>y', '"+y<cr>')
keymap.set({'n', 'v', 'x'}, '<leader>d', '"+d<cr>')

-- tabs
keymap.set('n', '<C-n>', ':tabn<cr>')
keymap.set('n', '<C-p>', ':tabp<cr>')

-- motions
keymap.set('n', '<Tab>', '%')
keymap.set('', '0', '^')
keymap.set('', '<leader>4', '$')
keymap.set('', '<leader>d', '<C-d>zz')
keymap.set('', '<leader>u', '<C-u>zz')
keymap.set('', '<C-d>', '<C-d>zz')
keymap.set('', '<C-u>', '<C-u>zz')

-- window navigation
vim.keymap.set('n', '<leader>ww', [[<cmd>only<cr>]]) -- close all windows except current one

-- resize windows
keymap.set("n", "<Up>", [[<cmd>horizontal resize +5<cr>]]) -- make the window biger vertically
keymap.set("n", "<Down>", [[<cmd>horizontal resize -5<cr>]]) -- make the window smaller vertically
keymap.set("n", "<Right>", [[<cmd>vertical resize +5<cr>]]) -- make the window bigger horizontally by pressing shift and =
keymap.set("n", "<Left>", [[<cmd>vertical resize -5<cr>]]) -- make the window smaller horizontally by pressing shift and -

-- move lines up and down with alt-j and alt-k
keymap.set('n', '<C-k>', 'mz:m-2<cr>`z')
keymap.set('n', '˚', 'mz:m-2<cr>`z')
keymap.set('n', '<C-j>', 'mz:m+<cr>`z')
keymap.set('n', '∆', 'mz:m+<cr>`z')
keymap.set('v', '<C-j>', ":m'>+<cr>`<my`>mzgv`yo`z")
keymap.set('v', '∆', ":m'>+<cr>`<my`>mzgv`yo`z")
keymap.set('v', '<C-k>', ":m'<-2<cr>`>my`<mzgv`yo`z")
keymap.set('v', '˚', ":m'<-2<cr>`>my`<mzgv`yo`z")

-- buffers
keymap.set('n', '<leader>]', ':bnext<cr>')
keymap.set('n', '<leader>[', ':bprev<cr>')
keymap.set('n', '<leader>q', ':bd<cr>')
keymap.set('n', '<leader>ba', ':bufdo bd<cr>')

-- insert
keymap.set('i', ':w', '<esc>:w<cr>')
keymap.set('i', 'jh', '<Esc>')

keymap.set('t', '<Esc>', "<C-\\><C-n>")

-- diagnostics/quickfix (formerly trouble.nvim style)
keymap.set('n', '<leader>tt', vim.diagnostic.setqflist, {desc = 'Diagnostics to Quickfix'})
keymap.set('n', '<leader>to', function() vim.diagnostic.open_float(0, {border="single"}) end, {desc = 'Diagnostics popup'})

-- flash.nvim jump like lightspeed
keymap.set('n', 's', function() require('flash').jump() end, {desc = 'Flash jump'})
keymap.set('n', 'S', function() require('flash').jump({search = {forward = false}}) end, {desc = 'Flash jump backwards'})
