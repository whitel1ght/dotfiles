#!/bin/bash
# Tests for bin/docs-check. A sandbox git repo stands in for dotfiles and a
# sandbox folder for ~/wiki/tools, so the real manual and repo are untouched.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/docs-check"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
expect() { # expect <exit> <label> <cmd...>
    local want=$1 label=$2; shift 2
    out="$("$@" 2>&1)"; local got=$?
    [ "$got" -eq "$want" ] && pass "$label" || fail "$label" "exit $got, want $want: $out"
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
REPO="$SANDBOX/dotfiles"
DOCS="$SANDBOX/tools"
mkdir -p "$REPO/bin" "$REPO/nvim/lua" "$DOCS"
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git -C "$REPO" init -q -b main
printf '#!/bin/sh\n' > "$REPO/bin/localai"
printf '#!/bin/sh\n' > "$REPO/bin/localai.test.sh"
printf -- '-- cfg\n' > "$REPO/nvim/lua/init.lua"
printf 'readme\n' > "$REPO/README.md"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m init

cat > "$DOCS/local-ai.md" <<'EOF'
# Local AI
<!-- covers: bin/localai nvim/* -->
Run `localai` to start.
EOF
cat > "$DOCS/index.md" <<'EOF'
# The system
<!-- covers: -->
EOF
SYSTEM="$SANDBOX/system"
DEC="$SANDBOX/decisions"
OTHER="$SANDBOX/other"
mkdir -p "$SYSTEM" "$DEC/src" "$OTHER/src"
for r in "$DEC" "$OTHER"; do
    git -C "$r" init -q -b main; printf 'x\n' > "$r/src/a.txt"; git -C "$r" add -A && git -C "$r" commit -q -m init
done
export SYSTEM_PAGES="$SYSTEM" SYSTEM_REPOS="dotfiles=$REPO:decisions=$DEC"
run() { (cd "$REPO" && SYSTEM_DOCS="$DOCS" "$SCRIPT" "$@"); }
runin() { local dir=$1; shift; (cd "$dir" && SYSTEM_DOCS="$DOCS" "$SCRIPT" "$@"); }
msg() { printf '%s\n' "$1" > "$SANDBOX/msg"; echo "$SANDBOX/msg"; }
age_page() { touch -t 202001010000 "$DOCS/$1"; }

echo "docs-check commit-msg"

printf 'more\n' >> "$REPO/README.md"; git -C "$REPO" add README.md
expect 0 "uncovered change passes" run commit-msg "$(msg 'docs: readme')"
git -C "$REPO" commit -q -m readme

age_page local-ai.md
printf 'echo 2\n' >> "$REPO/bin/localai"; git -C "$REPO" add bin/localai
expect 1 "covered change with a stale page is blocked" run commit-msg "$(msg 'feat: localai flag')"
case "$out" in *"local-ai.md"*) pass "names the page to update" ;; *) fail "names the page to update" "$out" ;; esac

expect 0 "'Docs: none' in the message lets it through" run commit-msg "$(msg $'refactor: tidy\n\nDocs: none')"

touch "$DOCS/local-ai.md"
expect 0 "page updated after the change passes" run commit-msg "$(msg 'feat: localai flag')"
git -C "$REPO" commit -q -m flag

age_page local-ai.md
printf -- '-- more\n' >> "$REPO/nvim/lua/init.lua"; git -C "$REPO" add nvim/lua/init.lua
expect 1 "glob covers nested files" run commit-msg "$(msg 'feat: nvim')"
git -C "$REPO" reset -q

age_page local-ai.md
git -C "$REPO" rm -q bin/localai
expect 1 "deleting a covered file with a stale page is blocked" run commit-msg "$(msg 'chore: drop localai')"
touch "$DOCS/local-ai.md"
expect 0 "deletion passes once the page was just edited" run commit-msg "$(msg 'chore: drop localai')"
git -C "$REPO" reset -q; git -C "$REPO" checkout -q -- bin/localai

expect 0 "missing docs folder never blocks a commit" bash -c "cd '$REPO' && SYSTEM_DOCS='$SANDBOX/nope' '$SCRIPT' commit-msg '$(msg x)'"

echo "docs-check system pages"

cat > "$SYSTEM/daily.md" <<'EOF'
# Daily
<!-- covers: dotfiles:bin/localai -->
EOF
cat > "$SYSTEM/journal.md" <<'EOF'
# Journal
<!-- covers: decisions:src/* -->
EOF
cat > "$SYSTEM/map.md" <<'EOF'
<!-- covers: dotfiles:bin/localai -->
EOF
age_sys() { touch -t 202001010000 "$SYSTEM/$1"; }

age_page local-ai.md; age_sys daily.md
printf 'echo 3\n' >> "$REPO/bin/localai"; git -C "$REPO" add bin/localai
touch "$DOCS/local-ai.md"
expect 1 "system page required" run commit-msg "$(msg 'feat: localai')"
case "$out" in *"daily.md"*) pass "names the system page" ;; *) fail "names the system page" "$out" ;; esac
case "$out" in *"map.md"*) fail "map.md is not a part page" "$out" ;; *) pass "map.md is not a part page" ;; esac

age_page local-ai.md; touch "$SYSTEM/daily.md"
expect 0 "Docs: internal skips only the tools page" run commit-msg "$(msg $'chore: x\n\nDocs: internal')"
age_sys daily.md; touch "$DOCS/local-ai.md"
expect 1 "Docs: internal still needs the system page" run commit-msg "$(msg $'chore: x\n\nDocs: internal')"
expect 0 "Docs: none skips both" run commit-msg "$(msg $'chore: x\n\nDocs: none')"
touch "$SYSTEM/daily.md"
expect 0 "both pages fresh passes" run commit-msg "$(msg 'feat: localai')"

printf 'y\n' >> "$DEC/src/a.txt"; git -C "$DEC" add src/a.txt
age_sys journal.md
expect 1 "repo-qualified glob in another repo, stale page" runin "$DEC" commit-msg "$(msg 'feat: dec')"
touch "$SYSTEM/journal.md"
expect 0 "repo-qualified glob in another repo, fresh page" runin "$DEC" commit-msg "$(msg 'feat: dec')"

git -C "$REPO" reset -q; git -C "$REPO" checkout -q -- bin/localai
git -C "$REPO" worktree add -q "$SANDBOX/wt/feature" -b feature
WT="$SANDBOX/wt/feature"
printf 'echo wt\n' >> "$WT/bin/localai"; git -C "$WT" add bin/localai
age_sys daily.md; touch "$DOCS/local-ai.md"
expect 1 "worktree resolves to its repo, stale page" runin "$WT" commit-msg "$(msg 'feat: wt')"
touch "$SYSTEM/daily.md"
expect 0 "worktree resolves to its repo, fresh page" runin "$WT" commit-msg "$(msg 'feat: wt')"
git -C "$WT" reset -q

printf 'z\n' >> "$OTHER/src/a.txt"; git -C "$OTHER" add src/a.txt
expect 0 "not a system repo" runin "$OTHER" commit-msg "$(msg 'feat: other')"

age_sys daily.md; age_page local-ai.md
printf 'echo 4\n' >> "$REPO/bin/localai"; git -C "$REPO" add bin/localai
expect 0 "no wiki" bash -c "cd '$REPO' && SYSTEM_DOCS='$SANDBOX/nope' SYSTEM_PAGES='$SANDBOX/nope2' '$SCRIPT' commit-msg '$(msg x)'"
git -C "$REPO" reset -q; git -C "$REPO" checkout -q -- bin/localai

git -C "$REPO" rm -q bin/localai
touch "$DOCS/local-ai.md"; age_sys daily.md
expect 1 "deleted covered file needs its system page" run commit-msg "$(msg 'chore: drop localai')"
touch "$SYSTEM/daily.md"
expect 0 "deletion passes once the system page was just edited" run commit-msg "$(msg 'chore: drop localai')"
git -C "$REPO" reset -q; git -C "$REPO" checkout -q -- bin/localai
rm -f "${SYSTEM:?}/daily.md" "${SYSTEM:?}/journal.md" "${SYSTEM:?}/map.md"

echo "docs-check branches, added files, Brewfile, post-merge"

printf '# Daily\n<!-- covers: dotfiles:bin/localai -->\n## Unfinished\n' > "$SYSTEM/daily.md"
touch "$DOCS/local-ai.md"; age_sys daily.md
git -C "$REPO" checkout -q -b feat-x
printf 'echo b\n' >> "$REPO/bin/localai"; git -C "$REPO" add bin/localai; touch "$DOCS/local-ai.md"
expect 1 "branch: no Unfinished entry" run commit-msg "$(msg 'feat: b')"
case "$out" in *'- `dotfiles:feat-x`'*"## Unfinished"*) pass "branch: message says what to add" ;; *) fail "branch: message says what to add" "$out" ;; esac
printf -- '- `dotfiles:feat-x` adds x\n' >> "$SYSTEM/daily.md"; age_sys daily.md
expect 0 "branch: an Unfinished entry is enough" run commit-msg "$(msg 'feat: b')"
printf '# Daily\n<!-- covers: dotfiles:bin/localai -->\n## Unfinished\n- `dotfiles:other` adds y\n' > "$SYSTEM/daily.md"; age_sys daily.md
expect 1 "branch: an entry for another branch does not count" run commit-msg "$(msg 'feat: b')"
rm "$SYSTEM/daily.md"
age_page local-ai.md
expect 1 "branch: tools-only coverage keeps today's rule" run commit-msg "$(msg 'feat: b')"
git -C "$REPO" reset -q; git -C "$REPO" checkout -q -- bin/localai; git -C "$REPO" checkout -q main
touch "$DOCS/local-ai.md"

printf '#!/bin/sh\n' > "$REPO/bin/newtool"; git -C "$REPO" add bin/newtool
expect 1 "added file nobody covers" run commit-msg "$(msg 'feat: newtool')"
case "$out" in *"bin/newtool"*"covers line"*) pass "added file: names it and the covers line" ;; *) fail "added file: names it and the covers line" "$out" ;; esac
expect 0 "added file: Docs: none skips" run commit-msg "$(msg $'feat: newtool\n\nDocs: none')"
git -C "$REPO" reset -q; rm "$REPO/bin/newtool"
for f in bin/newtool.test.sh tests/x.sh docs/x.md sub/README.md README.md.bak.lock Cargo.lock; do
    mkdir -p "$(dirname "$REPO/$f")"; printf 'x\n' > "$REPO/$f"
    git -C "$REPO" add "$f"
    expect 0 "added file: $f is exempt" run commit-msg "$(msg 'chore: add')"
    git -C "$REPO" reset -q; rm "$REPO/$f"
done
rm -rf "$REPO/tests" "$REPO/docs" "$REPO/sub"

printf '# Tests\n<!-- covers: bin/localai* tests/* -->\n' > "$DOCS/tests-page.md"; age_page tests-page.md
printf 'echo t\n' >> "$REPO/bin/localai.test.sh"; mkdir -p "$REPO/tests"; printf 'x\n' > "$REPO/tests/a.sh"
git -C "$REPO" add bin/localai.test.sh tests/a.sh
expect 0 "a test-only change under a covered glob needs no page" run commit-msg "$(msg 'test: localai')"
git -C "$REPO" reset -q; git -C "$REPO" checkout -q -- bin/localai.test.sh; rm -rf "$REPO/tests" "$DOCS/tests-page.md"

printf 'brew "git"\n' > "$REPO/Brewfile"; git -C "$REPO" add Brewfile; git -C "$REPO" commit -q -m brewfile
printf 'brew "koekeishiya/formulae/zoxide"\n' >> "$REPO/Brewfile"; git -C "$REPO" add Brewfile
expect 1 "new Brewfile entry nobody mentions" run commit-msg "$(msg 'feat: zoxide')"
case "$out" in *zoxide*) pass "Brewfile: names the entry" ;; *) fail "Brewfile: names the entry" "$out" ;; esac
printf 'Jump with `zoxide`.\n' >> "$DOCS/local-ai.md"
expect 0 "Brewfile entry mentioned in a page" run commit-msg "$(msg 'feat: zoxide')"
git -C "$REPO" reset -q; git -C "$REPO" checkout -q -- Brewfile

git -C "$REPO" checkout -q -b feature2
printf 'x\n' >> "$REPO/README.md"; git -C "$REPO" commit -q -am "feature2 work"
git -C "$REPO" checkout -q main
printf '# Daily\n<!-- covers: dotfiles:bin/localai -->\n## Unfinished\n- `dotfiles:feature2` adds x\n' > "$SYSTEM/daily.md"
git -C "$REPO" merge -q --ff-only feature2
out="$(run post-merge 2>&1)"; got=$?
[ "$got" -eq 0 ] && [ "$out" = "$SYSTEM/daily.md" ] && pass "post-merge prints the page naming the branch" || fail "post-merge prints the page naming the branch" "exit $got: $out"
git -C "$REPO" checkout -q -b feature3
printf 'y\n' >> "$REPO/README.md"; git -C "$REPO" commit -q -am "feature3 work"
git -C "$REPO" checkout -q main
git -C "$REPO" merge -q --ff-only feature3
out="$(run post-merge 2>&1)"; got=$?
[ "$got" -eq 0 ] && [ -z "$out" ] && pass "post-merge prints nothing when no page names it" || fail "post-merge prints nothing when no page names it" "exit $got: $out"
rm -f "$SYSTEM/daily.md"

git -C "$REPO" checkout -q -b feat-y
printf 'z\n' >> "$REPO/README.md"; git -C "$REPO" commit -q -am "feat-y work"
git -C "$REPO" checkout -q main
printf 'w\n' >> "$REPO/bin/localai.test.sh"; git -C "$REPO" commit -q -am "main work"
printf '# Daily\n<!-- covers: dotfiles:bin/localai -->\n## Unfinished\n- `dotfiles:feat-y` adds x\n' > "$SYSTEM/daily.md"
git -C "$REPO" merge -q --no-ff feat-y -m "Merge branch 'feat-y'"
out="$(run post-merge 2>&1)"; got=$?
[ "$got" -eq 0 ] && [ "$out" = "$SYSTEM/daily.md" ] && pass "post-merge after a non-fast-forward merge" || fail "post-merge after a non-fast-forward merge" "exit $got: $out"
rm -f "$SYSTEM/daily.md"

printf '#!/bin/sh\n' > "$REPO/bin/newtool"; printf 'brew "zoxide"\n' >> "$REPO/Brewfile"; git -C "$REPO" add bin/newtool Brewfile
expect 0 "no wiki: new file and Brewfile entry never block" bash -c "cd '$REPO' && SYSTEM_DOCS='$SANDBOX/nope' SYSTEM_PAGES='$SANDBOX/nope2' '$SCRIPT' commit-msg '$(msg x)'"
git -C "$REPO" reset -q; rm "$REPO/bin/newtool"; git -C "$REPO" checkout -q -- Brewfile

echo "docs-check coverage"

expect 0 "clean when every script is documented" run coverage
printf '#!/bin/sh\n' > "$REPO/bin/webui"; git -C "$REPO" add bin/webui; git -C "$REPO" commit -q -m webui
expect 1 "flags a script no page mentions" run coverage
case "$out" in *"bin/webui"*) pass "names the undocumented script" ;; *) fail "names the undocumented script" "$out" ;; esac
case "$out" in *"localai.test.sh"*) fail "test files are not required to be documented" "$out" ;; *) pass "test files are not required to be documented" ;; esac
printf 'Run `webui`.\n' >> "$DOCS/local-ai.md"
expect 0 "a mention anywhere in the manual counts" run coverage

sed -i '' 's#<!-- covers: bin/localai nvim/\* -->#<!-- covers: bin/localai nvim/* bin/gone -->#' "$DOCS/local-ai.md"
expect 1 "flags a covers entry that matches nothing" run coverage
case "$out" in *"bin/gone"*) pass "names the stale covers entry" ;; *) fail "names the stale covers entry" "$out" ;; esac

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
