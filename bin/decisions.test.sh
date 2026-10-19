#!/bin/bash
# Tests for the decisions view (bin/decisions, nvim/lua/whitelight/decisions.lua). The view
# runs in headless nvim against the real `decide` on a sandbox state dir; a Lua driver feeds
# it keys and reports what the buffer shows and what landed on disk.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$TEST_DIR")"
SCRIPT="$TEST_DIR/decisions"
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "[$3] not in: $2" ;; esac; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export RUN_DAY_STATE_DIR="$SANDBOX/state" INBOX_DIR="$SANDBOX/inbox" DECIDE="$TEST_DIR/decide"

echo "launcher"
has "--help describes the view" "$("$SCRIPT" --help)" "prefix y"

cat > "$SANDBOX/driver.lua" <<'EOF'
package.path = vim.env.REPO .. '/nvim/lua/?.lua;' .. package.path
local D = vim.env.RUN_DAY_STATE_DIR .. '/decisions'
local pass, fail = 0, 0
local function ok(name, cond, detail)
  if cond then pass = pass + 1; io.write('  ok   - ', name, '\n')
  else fail = fail + 1; io.write('  FAIL - ', name, '\n         ', tostring(detail), '\n') end
end
local function sh(args, stdin)
  local r = vim.system(args, { text = true, stdin = stdin or '' }):wait()
  return vim.trim(r.stdout or '')
end
local function add(key, q, opts, rec, blocks)
  local a = { vim.env.DECIDE, 'add', '--key', key, '--question', q }
  for _, o in ipairs(opts) do vim.list_extend(a, { '--option', o }) end
  if rec then vim.list_extend(a, { '--recommend', tostring(rec) }) end
  if blocks then vim.list_extend(a, { '--blocks', blocks }) end
  return sh(a, 'some context line')
end
local function file(id) local f = io.open(D .. '/' .. id .. '.md'); local s = f and f:read('a') or ''; if f then f:close() end; return s end
local function reset() vim.fn.delete(D, 'rf'); vim.fn.mkdir(D, 'p') end

local V = require('whitelight.decisions')
local inputs = {}
V.input = function(_, cb) cb(table.remove(inputs, 1)) end
V.open_url = function(url) V._opened = url end
local function text() return table.concat(vim.api.nvim_buf_get_lines(V.buf, 0, -1, false), '\n') end
local function keys(k) vim.api.nvim_feedkeys(vim.keycode(k), 'xt', false) end
local function settle() vim.wait(400, function() return false end) end

reset()
local a = add('ECFX-1', 'Fix or merge?', { 'fix', 'merge' }, 2, 'merge')
local b = add('ECFX-2', 'Defer it?', { 'yes', 'no' })
V.open()

io.write('render\n')
local t = text()
ok('blocking one is first and current', t:find('▸ ' .. a, 1, true) and t:find(a, 1, true) < t:find(b, 1, true), t)
ok('card shows the question', t:find('Fix or merge?', 1, true), t)
ok('recommended option starred', t:find('★ 2  merge', 1, true), t)
ok('title counts what waits', vim.api.nvim_win_get_config(V.win).title[1][1]:find('2 waiting'), vim.inspect(vim.api.nvim_win_get_config(V.win).title))

io.write('move\n')
keys('J'); ok('J moves to the next decision', text():find('▸ ' .. b, 1, true), text())
keys('K'); ok('K moves back', text():find('▸ ' .. a, 1, true), text())

io.write('answer\n')
keys('1<Esc>'); ok('esc on the confirm line answers nothing', file(a):find('status: open', 1, true), file(a))
keys('7'); ok('a missing option says so', V._notice and V._notice:find('no option 7', 1, true), V._notice)
keys('<Esc>'); ok('and changes nothing', file(a):find('status: open', 1, true), file(a))
vim.api.nvim_win_set_cursor(V.win, { vim.fn.search('^Fix or merge?', 'nw'), 0 })
keys('<CR><CR>'); ok('enter on the card answers the recommended one', file(a):find('2 — merge', 1, true), file(a))
settle(); ok('the next decision takes its place', text():find('▸ ' .. b, 1, true), text())
inputs = { 'after the release' }
keys('1n'); ok('n adds a note', file(b):find('note: after the release', 1, true), file(b))

io.write('empty\n')
settle(); ok('an empty queue says so', text():find('nothing waiting on you', 1, true), text())
local c = add('ECFX-3', 'Which one?', { 'x', 'y' })
vim.wait(3000, function() return text():find('Which one?', 1, true) ~= nil end)
ok('a new decision shows up without a restart', text():find('Which one?', 1, true), text())

io.write('ask, skip, open\n')
inputs = { 'what does x cost?' }
keys('a'); ok('a asks the session back', file(c):find('you: what does x cost?', 1, true), file(c))
local d = add('ECFX-4', 'Later one?', { 'p', 'q' })
V.reload()
keys('s'); ok('s sends the current decision to the end', text():find('▸ ' .. d, 1, true), text())
keys('o'); ok('o without an MR says so', V._notice and V._notice:find('no MR', 1, true), V._notice)
keys('<Esc>')
local cur = vim.api.nvim_win_get_cursor(V.win)[1]
local qrow = vim.fn.search(c .. ' ', 'nw')
vim.api.nvim_win_set_cursor(V.win, { qrow, 0 })
keys('<CR>'); ok('enter on a queue row shows that decision', text():find('▸ ' .. c, 1, true), text())
ok('cursor moved', cur ~= nil)

io.write('folds\n')
local function folded(pat)
  local row = vim.fn.search(pat, 'nw')
  return row > 0 and vim.api.nvim_win_call(V.win, function() return vim.fn.foldclosed(row) end) ~= -1
end
ok('context starts folded', folded('^▾ Context'), text())
sh({ vim.env.DECIDE, 'reply', c, 'x costs a day' })
V.reload()
ok('discussion opens when the session answered last', not folded('^▾ Discussion'), text())
ok('and shows the reply', text():find('session: x costs a day', 1, true), text())

io.write(('passed: %d  failed: %d\n'):format(pass, fail))
vim.cmd('qa!')
EOF

echo "view"
out="$(REPO="$REPO" nvim --headless -u NONE -i NONE -n -l "$SANDBOX/driver.lua" 2>&1)"
printf '%s\n' "$out" | grep -v '^passed:'
n="$(printf '%s\n' "$out" | sed -n 's/^passed: \([0-9]*\)  failed: \([0-9]*\)$/\1 \2/p')"
if [ -n "$n" ]; then
  PASS=$((PASS + ${n% *})); FAIL=$((FAIL + ${n#* }))
else
  fail "the view ran to the end" "$(printf '%s\n' "$out" | tail -5)"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
