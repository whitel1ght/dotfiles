require('mini.statusline').setup({
  content = {
    active = function()
      local MiniStatusline = require('mini.statusline')

      -- Mode
      local mode, mode_hl = MiniStatusline.section_mode({ trunc_width = 120 })

      -- Git
      local git = MiniStatusline.section_git({ trunc_width = 40 })

      -- Diff
      local diff = MiniStatusline.section_diff({ trunc_width = 75 })

      -- Diagnostics
      local diagnostics = MiniStatusline.section_diagnostics({ trunc_width = 75 })

      -- LSP
      local lsp = MiniStatusline.section_lsp({ trunc_width = 75 })

      -- Custom Path Logic
      local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ':t')
      local path = vim.fn.expand('%:~:.')
      if not vim.startswith(path, cwd) then
        path = cwd .. '/' .. path
      end

      -- File info without fileformat
      local encoding = vim.bo.fileencoding or vim.bo.encoding
      local size = vim.fn.getfsize('%')
      local size_display = (size > 0) and size or ''
      local fileinfo = string.format('%s %s', encoding ~= '' and encoding or 'none', size_display)

      -- Location
      local location = MiniStatusline.section_location({ trunc_width = 75 })

      -- Search count
      local search_count = MiniStatusline.section_searchcount({ trunc_width = 75 })

      return MiniStatusline.combine_groups({
        { hl = mode_hl, strings = { mode } },
        { hl = 'MiniStatuslineDevinfo', strings = { git, diff, diagnostics, lsp } },
        '%<', -- Truncate point
        { hl = 'MiniStatuslineFilename', strings = { path } },
        '%=', -- End left alignment
        { hl = 'MiniStatuslineFileinfo', strings = { fileinfo } },
        { hl = mode_hl, strings = { search_count, location } },
      })
    end,
  },
})
