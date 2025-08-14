require('telescope').setup {
  defaults = {
    mappings = {
      i = {
        ["<esc>"] = require('telescope.actions').close,
        ["<C-d>"] = require('telescope.actions').delete_buffer
      },
    },
  },
}

local builtin = require('telescope.builtin')

local git_files = function()
  require('telescope.builtin').git_status(require('telescope.themes').get_dropdown({}))
end

local opened_buffers = function ()
  require('telescope.builtin').buffers(require('telescope.themes').get_dropdown({}))
end

vim.api.nvim_create_user_command('Wiki', function ()
  builtin.find_files({cwd="$HOME".."/wiki"})
end, {})

vim.keymap.set('n', '<leader>fh', builtin.git_bcommits, {})
vim.keymap.set('n', '<leader><leader>', opened_buffers, {})
vim.keymap.set('n', '<leader>cf', builtin.quickfix, {})
vim.keymap.set('n', '<leader>pf', builtin.find_files, {})
vim.keymap.set('n', '<leader>gf', git_files, {})
vim.keymap.set('n', '<leader>rg', builtin.grep_string, {})
vim.keymap.set('n', '<leader>ps', function ()
	builtin.grep_string({ search = vim.fn.input("Grep > ") });
end)

-- transparent background for telescope
vim.api.nvim_create_autocmd("UIEnter", {
  pattern = "*",
  callback = function()
    vim.api.nvim_set_hl(0, "TelescopeBorder", { bg = "none" })
    vim.api.nvim_set_hl(0, "TelescopePromptBorder", { bg = "none" })
    vim.api.nvim_set_hl(0, "TelescopeNormal", { bg = "none" })
    vim.api.nvim_set_hl(0, "TelescopeTitle", { bg ="none" })
    vim.api.nvim_set_hl(0, "TelescopePromptTitle", { bg ="none" })
  end
})

