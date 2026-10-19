-- The decisions view (bin/decisions, tmux prefix+y): answer what /run-day is waiting on.
-- It reads `decide list --json` and writes only through `decide answer` / `decide ask`, which
-- tell the session through its inbox. The keys are in FOOTER; ⏎ is "the option under the
-- cursor, else the recommended one" and on a queue row shows that decision.
local M = {}
local api = vim.api
local popup = require('whitelight.popup')
local ns = api.nvim_create_namespace('decisions')

local FOOTER = 'J/K next · 1-9 answer · ⏎ ★ · a ask · s skip · o MR · r reload · q close'

-- Replaced in tests.
M.input = function(prompt, cb) vim.ui.input({ prompt = prompt }, cb) end
M.open_url = function(url) vim.ui.open(url) end

-- items: the queue as shown (skipped ones last); cur: the id on the card; idx: its row.
local S = { items = {}, skipped = {}, cur = nil, idx = 1, err = nil, rows = {}, qline = nil }

local function decide(args)
  local cmd = { vim.env.DECIDE or 'decide' }
  vim.list_extend(cmd, args)
  local ok, r = pcall(function() return vim.system(cmd, { text = true }):wait() end)
  if not ok then return 1, '', tostring(r) end
  return r.code, r.stdout or '', vim.trim(r.stderr or '')
end

local function width_of(s) return vim.fn.strdisplaywidth(s) end

local function fit(s, w)
  if w < 1 then return '' end
  if width_of(s) <= w then return s .. string.rep(' ', w - width_of(s)) end
  return vim.fn.strcharpart(s, 0, w - 1) .. '…'
end

local function wrap(text, width, first, rest)
  first, rest = first or '', rest or ''
  local out, line, empty = {}, first, true
  for word in tostring(text):gmatch('%S+') do
    local cand = empty and (line .. word) or (line .. ' ' .. word)
    if not empty and width_of(cand) > width then
      table.insert(out, line)
      line = rest .. word
    else
      line = cand
    end
    empty = false
  end
  if not empty then table.insert(out, line) end
  return out
end

-- Paragraphs and list items keep their shape; a wrapped list item hangs under its text.
local function wrap_block(text, width, indent)
  local out = {}
  for _, l in ipairs(vim.split(vim.trim(text), '\n')) do
    if vim.trim(l) == '' then
      table.insert(out, '')
    else
      local lead = l:match('^%s*')
      local bullet = l:match('^%s*[-*] ') or l:match('^%s*%d+%. ') or lead
      vim.list_extend(out, wrap(l, width, indent .. lead, indent .. string.rep(' ', #bullet)))
    end
  end
  return out
end

local function load()
  local code, out, err = decide({ 'list', '--json' })
  local items
  if code ~= 0 then
    S.err = err ~= '' and err or ('decide exited ' .. code)
  else
    local ok, decoded = pcall(vim.json.decode, out, { luanil = { object = true, array = true } })
    if ok then S.err, items = nil, decoded else S.err = 'decide list --json: ' .. tostring(decoded) end
  end
  items = items or {}
  local skip = {}
  for i, id in ipairs(S.skipped) do skip[id] = i end
  local front, back = {}, {}
  for _, d in ipairs(items) do table.insert(skip[d.id] and back or front, d) end
  table.sort(back, function(x, y) return skip[x.id] < skip[y.id] end)
  S.items = vim.list_extend(front, back)
  local found
  for i, d in ipairs(S.items) do
    if d.id == S.cur then found = i end
  end
  S.idx = found or math.max(math.min(S.idx, #S.items), 1)
  S.cur = S.items[S.idx] and S.items[S.idx].id or nil
end

local function render()
  local buf, win = M.buf, M.win
  if not (buf and api.nvim_buf_is_valid(buf) and win and api.nvim_win_is_valid(win)) then return end
  local width = math.max(api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff - 1, 20)
  local lines, hls, rows, folds = {}, {}, {}, {}
  local function add(l, hl, row)
    table.insert(lines, l)
    if hl then table.insert(hls, { #lines - 1, hl }) end
    rows[#lines] = row
  end
  local n = #S.items
  popup.set_title(win, n == 0 and 'decisions · nothing waiting' or ('decisions · %d waiting'):format(n))
  S.qline = nil

  if S.err then
    add('decide failed:', 'ErrorMsg')
    for _, l in ipairs(vim.split(S.err, '\n')) do add('  ' .. l, 'ErrorMsg') end
  elseif n == 0 then
    for _ = 1, math.floor((api.nvim_win_get_height(win) - 1) / 2) do add('') end
    local msg = 'nothing waiting on you'
    add(string.rep(' ', math.max(math.floor((width - #msg) / 2), 0)) .. msg, 'DecisionsDim')
  else
    for i, d in ipairs(S.items) do
      local left = ('%s%-5s %-11s %-13s '):format(i == S.idx and '▸ ' or '  ', d.id,
        d.key ~= '' and d.key or 'offplan', d.mr_short ~= '' and d.mr_short or '-')
      local right = (d.blocks ~= '' and ('  blocks ' .. d.blocks) or '') .. ('  %4s'):format(d.age)
        .. (d.question_back and ' ?' or '  ')
      add(left .. fit(d.question, width - width_of(left) - width_of(right)) .. right,
        i == S.idx and 'DecisionsCurrent' or nil, { kind = 'queue', id = d.id })
    end
    add(string.rep('─', width), 'DecisionsDim')

    local d = S.items[S.idx]
    local head = { d.key ~= '' and d.key or 'offplan' }
    if d.mr_short ~= '' then table.insert(head, d.mr_short) end
    table.insert(head, 'asked ' .. d.age .. ' ago')
    if d.blocks ~= '' then table.insert(head, 'blocks ' .. d.blocks) end
    add(d.id .. ' · ' .. table.concat(head, ' · '), 'DecisionsHeader')
    add('')
    S.qline = #lines + 1
    for _, l in ipairs(wrap(d.question, width)) do add(l, 'DecisionsQuestion') end
    add('')
    for _, o in ipairs(d.options) do
      local first = (o.recommended and '★ ' or '  ') .. o.n .. '  '
      for j, l in ipairs(wrap(o.text, width, first, '     ')) do
        add(l, nil, { kind = 'option', n = o.n })
        if j == 1 and o.recommended then table.insert(hls, { #lines - 1, 'DecisionsStar', 0, #'★' }) end
      end
    end

    local function section(name, body, open)
      add('')
      local start = #lines + 1
      add('▾ ' .. name, 'DecisionsSection')
      for _, l in ipairs(body) do add(l) end
      table.insert(folds, { start, #lines, open })
    end
    if vim.trim(d.context or '') ~= '' then
      local body = wrap_block(d.context, width, '  ')
      section(('Context · %d lines'):format(#body), body, false)
    end
    local disc = d.discussion or {}
    if #disc > 0 then
      local body = {}
      for _, e in ipairs(disc) do
        vim.list_extend(body, wrap(('%s %s: %s'):format(e.at, e.who, e.text), width, '  ', '        '))
      end
      -- open when the session answered you last: that reply is what you came back for
      section(('Discussion · %d %s'):format(#disc, #disc == 1 and 'entry' or 'entries'), body,
        disc[#disc].who == 'session')
    end
  end

  S.rows = rows
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    if h[4] then
      api.nvim_buf_set_extmark(buf, ns, h[1], h[3], { end_col = h[4], hl_group = h[2] })
    else
      api.nvim_buf_set_extmark(buf, ns, h[1], 0, { line_hl_group = h[2] })
    end
  end
  api.nvim_win_call(win, function()
    pcall(vim.cmd, 'normal! zE')
    for _, f in ipairs(folds) do
      vim.cmd(('%d,%dfold'):format(f[1], f[2]))
      if f[3] then vim.cmd(('%dfoldopen'):format(f[1])) end
    end
  end)
end

local function to_question()
  -- the queue stays in sight above the card
  if S.qline and api.nvim_win_is_valid(M.win) then
    api.nvim_win_call(M.win, function() vim.fn.winrestview({ topline = 1, lnum = S.qline, col = 0 }) end)
  end
end

function M.reload()
  if not (M.buf and api.nvim_buf_is_valid(M.buf)) then return end
  local before = S.cur
  load()
  render()
  if S.cur ~= before then to_question() end
end

local function go(i)
  if #S.items == 0 then return end
  S.idx = (i - 1) % #S.items + 1
  S.cur = S.items[S.idx].id
  render()
  to_question()
end

local function map(buf, lhs, fn) vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true, silent = true }) end

-- A small float pinned to the bottom of the view; focus returns to the view when it closes.
local function small(lines, hl)
  local w = api.nvim_win_get_width(M.win)
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  local win = api.nvim_open_win(buf, true, {
    relative = 'win', win = M.win, row = math.max(api.nvim_win_get_height(M.win) - #lines - 2, 0), col = 1,
    width = math.max(w - 4, 10), height = #lines, border = 'rounded', style = 'minimal',
  })
  vim.wo[win].winhighlight = 'FloatBorder:PopupBorder,NormalFloat:Normal'
  vim.wo[win].statuscolumn = ' '
  for i = 0, #lines - 2 do
    if hl then api.nvim_buf_set_extmark(buf, ns, i, 0, { line_hl_group = hl }) end
  end
  api.nvim_buf_set_extmark(buf, ns, #lines - 1, 0, { line_hl_group = 'DecisionsDim' })
  local function close()
    if api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
    if M.win and api.nvim_win_is_valid(M.win) then api.nvim_set_current_win(M.win) end
  end
  return buf, close
end

-- A message that waits for any key.
local function notice(msg, hl)
  M._notice = msg
  local lines = vim.split(msg, '\n')
  table.insert(lines, 'any key to go on')
  local buf, close = small(lines, hl)
  local function done()
    M._notice = nil
    close()
  end
  for c = 33, 126 do map(buf, c == 60 and '<lt>' or string.char(c), done) end
  for _, k in ipairs({ '<Space>', '<CR>', '<Esc>', '<BS>', '<Tab>' }) do map(buf, k, done) end
end

local function current() return S.items[S.idx] end

local function confirm(n)
  local d = current()
  if not d then return end
  if n == 'rec' then
    n = d.recommended
    if not n then
      return notice(('%s has no recommended option: press 1-%d'):format(d.id, #d.options), 'WarningMsg')
    end
  end
  local opt
  for _, o in ipairs(d.options) do
    if o.n == n then opt = o end
  end
  if not opt then return notice(('%s has no option %d'):format(d.id, n), 'WarningMsg') end

  local function send(note)
    local args = { 'answer', d.id, tostring(n) }
    if note then table.insert(args, note) end
    local code, _, err = decide(args)
    if code ~= 0 then return notice(err ~= '' and err or 'decide answer failed', 'ErrorMsg') end
    M.reload()
  end
  local w = api.nvim_win_get_width(M.win) - 6
  local buf, close = small({
    fit(('%s → %d  %s'):format(d.id, n, opt.text), w),
    '⏎ send · n add a note · esc cancel',
  }, 'DecisionsQuestion')
  map(buf, '<CR>', function() close(); send() end)
  map(buf, 'n', function()
    close()
    M.input('note: ', function(note)
      if note == nil then return end
      note = vim.trim(note)
      send(note ~= '' and note or nil)
    end)
  end)
  map(buf, '<Esc>', close)
  map(buf, 'q', close)
end

local function ask()
  local d = current()
  if not d then return end
  M.input('question for the session: ', function(q)
    if q == nil or vim.trim(q) == '' then return end
    local code, _, err = decide({ 'ask', d.id, vim.trim(q) })
    if code ~= 0 then return notice(err ~= '' and err or 'decide ask failed', 'ErrorMsg') end
    M.reload()
  end)
end

local function skip()
  local d = current()
  if not d then return end
  S.skipped = vim.tbl_filter(function(id) return id ~= d.id end, S.skipped)
  table.insert(S.skipped, d.id)
  S.cur = nil
  M.reload()
end

local function open_mr()
  local d = current()
  if not d then return end
  if d.mr == '' then return notice(d.id .. ' has no MR') end
  M.open_url(d.mr)
end

local function enter()
  local row = S.rows[api.nvim_win_get_cursor(0)[1]]
  if row and row.kind == 'queue' then
    for i, d in ipairs(S.items) do
      if d.id == row.id then return go(i) end
    end
  elseif row and row.kind == 'option' then
    confirm(row.n)
  else
    confirm('rec')
  end
end

function M.foldtext() return (vim.fn.getline(vim.v.foldstart):gsub('^▾', '▸')) end

function M.open()
  for name, link in pairs({
    DecisionsCurrent = 'CursorLine', DecisionsDim = 'Comment', DecisionsHeader = 'Comment',
    DecisionsQuestion = 'Title', DecisionsStar = 'DiagnosticWarn', DecisionsSection = 'Special',
  }) do
    api.nvim_set_hl(0, name, { link = link, default = true })
  end
  M.buf = api.nvim_create_buf(false, true)
  vim.bo[M.buf].bufhidden = 'wipe'
  vim.bo[M.buf].filetype = 'decisions'
  M.win = popup.float(M.buf, 'decisions', FOOTER, function() render() end)
  local wo = vim.wo[M.win]
  wo.wrap, wo.number, wo.relativenumber, wo.list, wo.cursorline = false, false, false, false, false
  wo.signcolumn, wo.foldcolumn, wo.foldmethod = 'no', '0', 'manual'
  wo.foldtext = "v:lua.require'whitelight.decisions'.foldtext()"
  wo.fillchars = 'fold: ,eob: '
  wo.statuscolumn = ' ' -- a column of air inside the frame
  vim.o.laststatus = 0 -- the empty window under the float has nothing to say
  vim.opt.fillchars:append({ eob = ' ' })

  local b = M.buf
  map(b, 'J', function() go(S.idx + 1) end)
  map(b, ']]', function() go(S.idx + 1) end)
  map(b, 'K', function() go(S.idx - 1) end)
  map(b, '[[', function() go(S.idx - 1) end)
  for i = 1, 9 do map(b, tostring(i), function() confirm(i) end) end
  map(b, '<CR>', enter)
  map(b, 'a', ask)
  map(b, 's', skip)
  map(b, 'o', open_mr)
  map(b, 'r', M.reload)
  map(b, 'q', function() api.nvim_win_close(M.win, true) end)
  map(b, '<Esc>', function() api.nvim_win_close(M.win, true) end)

  load()
  render()
  to_question()

  -- A decision filed (or answered elsewhere) while the view is open shows up at once.
  local dir = vim.fn.expand(vim.env.RUN_DAY_STATE_DIR or '~/.local/state/run-day') .. '/decisions'
  vim.fn.mkdir(dir, 'p')
  local ev, timer = vim.uv.new_fs_event(), vim.uv.new_timer()
  if ev and timer then
    ev:start(dir, {}, function()
      timer:stop()
      timer:start(150, 0, vim.schedule_wrap(M.reload))
    end)
  end
end

return M
