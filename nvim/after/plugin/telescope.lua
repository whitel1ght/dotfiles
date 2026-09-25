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

-- Project/worktree switcher: `space pp` lists every checkout under ~/projects
-- (top-level dirs and ~/projects/worktrees/<repo>/<branch>) and :cd's into the
-- picked one. Home stays a single long-lived nvim; telescope's find_files /
-- grep_string honour vim's cwd, so <leader>pf/<leader>rg/<leader>ps all follow
-- the switch.
--
-- Grouped into two sections (Worktrees, Projects) with non-selectable headers,
-- and each [repo] tag is coloured per project, so every checkout of the same
-- repo shares a hue. master/main branches render muted so feature branches
-- stand out. Kept as a plain picker rather than a plugin: the required
-- behaviour (list these dirs, cd on enter) is not worth a dependency.
-- Colours are the tokyonight night accents the theme is already using; headers
-- and trunks re-use the tokyonight comment colour.
local PICKY_PALETTE = {
  "#7aa2f7", -- blue
  "#7dcfff", -- cyan
  "#9ece6a", -- green
  "#e0af68", -- yellow
  "#ff9e64", -- orange
  "#f7768e", -- red
  "#bb9af7", -- magenta
  "#9d7cd8", -- purple
  "#1abc9c", -- teal
  "#73daca", -- mint
}

for i, color in ipairs(PICKY_PALETTE) do
  vim.api.nvim_set_hl(0, "PickyRepo" .. i, { fg = color })
end
vim.api.nvim_set_hl(0, "PickyHeader", { fg = "#565f89", bold = true })
vim.api.nvim_set_hl(0, "PickyTrunk", { fg = "#565f89" })

local function git_branch(dir)
  local branch = vim.trim(vim.fn.system({ "git", "-C", dir, "branch", "--show-current" }))
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return branch ~= "" and branch or nil
end

local function in_work_tree(dir)
  local out = vim.trim(vim.fn.system({ "git", "-C", dir, "rev-parse", "--is-inside-work-tree" }))
  if vim.v.shell_error ~= 0 then
    return false
  end
  return out == "true"
end

local function is_trunk(branch)
  return branch == "master" or branch == "main"
end

local function collect_checkouts()
  local worktrees, projects = {}, {}
  local projects_root = vim.fn.expand("$HOME/projects")
  local worktrees_root = projects_root .. "/worktrees"

  if vim.fn.isdirectory(worktrees_root) == 1 then
    for _, repo in ipairs(vim.fn.readdir(worktrees_root)) do
      local repo_dir = worktrees_root .. "/" .. repo
      if vim.fn.isdirectory(repo_dir) == 1 then
        for _, name in ipairs(vim.fn.readdir(repo_dir)) do
          local dir = repo_dir .. "/" .. name
          if vim.fn.isdirectory(dir) == 1 and in_work_tree(dir) then
            table.insert(worktrees, {
              path = dir,
              repo = repo,
              branch = git_branch(dir),
            })
          end
        end
      end
    end
    table.sort(worktrees, function(a, b)
      if a.repo ~= b.repo then
        return a.repo < b.repo
      end
      return (a.branch or "") < (b.branch or "")
    end)
  end

  for _, name in ipairs(vim.fn.readdir(projects_root)) do
    if vim.fn.isdirectory(projects_root .. "/" .. name) == 1
      and not vim.startswith(name, ".")
      and name ~= "worktrees" then
      local dir = projects_root .. "/" .. name
      table.insert(projects, {
        path = dir,
        repo = name,
        branch = git_branch(dir),
      })
    end
  end
  table.sort(projects, function(a, b)
    return a.repo < b.repo
  end)

  return worktrees, projects
end

local function build_rows(worktrees, projects)
  local repos, seen = {}, {}
  local function note(repo)
    if repo and not seen[repo] then
      seen[repo] = true
      table.insert(repos, repo)
    end
  end
  for _, e in ipairs(worktrees) do note(e.repo) end
  for _, e in ipairs(projects) do note(e.repo) end
  table.sort(repos)

  local colors = {}
  for i, repo in ipairs(repos) do
    colors[repo] = "PickyRepo" .. ((i - 1) % #PICKY_PALETTE + 1)
  end

  -- Telescope renders coloured rows through entry_display: one column per tagged
  -- slice of a row, everything left-aligned and space-joined.
  local displayer = require("telescope.pickers.entry_display").create({
    separator = " ",
    items = {
      { remaining = true },
      { remaining = true },
    },
  })

  local rows = {}
  local function header(text, count)
    table.insert(rows, {
      ordinal = "",
      display = function()
        return displayer({ { "── " .. text .. " (" .. count .. ")", "PickyHeader" }, nil })
      end,
    })
  end

  local function row(e)
    local color = colors[e.repo]
    local branch = e.branch or "(no git branch)"
    table.insert(rows, {
      value = e.path,
      ordinal = e.repo .. " " .. branch,
      display = function()
        if e.branch and is_trunk(e.branch) then
          return displayer({ { "[" .. e.repo .. "] ", color }, { branch, "PickyTrunk" } })
        end
        return displayer({ { "[" .. e.repo .. "] ", color }, branch })
      end,
    })
  end

  header("Worktrees", #worktrees)
  for _, e in ipairs(worktrees) do row(e) end
  header("Projects", #projects)
  for _, e in ipairs(projects) do row(e) end
  return rows
end

vim.keymap.set("n", "<leader>pp", function()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local sorters = require("telescope.sorters")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local worktrees, projects = collect_checkouts()
  local rows = build_rows(worktrees, projects)

  pickers.new({}, {
    prompt_title = "Projects / Worktrees",
    finder = finders.new_table({
      results = rows,
      entry_maker = function(entry)
        return {
          value = entry.value,
          ordinal = entry.ordinal,
          display = entry.display,
        }
      end,
    }),
    sorter = sorters.get_generic_fuzzy_sorter({}),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection and selection.value then
          vim.cmd.cd(vim.fn.fnameescape(selection.value))
        end
      end)
      return true
    end,
  }):find()
end, { desc = "Switch project/worktree" })

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

