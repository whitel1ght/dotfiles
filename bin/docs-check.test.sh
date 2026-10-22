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
