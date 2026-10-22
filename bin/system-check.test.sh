#!/bin/bash
# Tests for bin/system-check. Sandbox repos, pages, bin folders, settings and
# fake command outputs stand in for the real ones, and HOME is a sandbox
# folder, so nothing on this machine is read or written.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/system-check"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home"
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

REPO="$SANDBOX/dotfiles"
DEC="$SANDBOX/decisions"
DOCS="$SANDBOX/tools"
SYSTEM="$SANDBOX/system"
FAKE="$SANDBOX/fake"
PLUGINS="$SANDBOX/plugins"
PI="$SANDBOX/pi-agent"
mkdir -p "$REPO/bin" "$REPO/notes" "$REPO/pi/extensions" "$REPO/claude/.claude-plugin" "$DEC/src" \
    "$DOCS" "$SYSTEM" "$FAKE" "$PLUGINS" "$PI/npm" "$PI/git/github.com/obra/superpowers" \
    "$PI/git/github.com/someone/handgit" "$HOME/bin" "$HOME/.local/bin" "$HOME/.pi/agent" "$SANDBOX/state"

# dotfiles: two scripts, a part-only file, a tracked pi extension, the files the install check reads.
git -C "$REPO" init -q -b main
printf '#!/bin/sh\n' > "$REPO/bin/tool"
printf '#!/bin/sh\n' > "$REPO/bin/wt"
printf 'plan\n' > "$REPO/notes/plan.txt"
printf 'readme\n' > "$REPO/README.md"
printf '// ext\n' > "$REPO/pi/extensions/tracked.ts"
cat > "$REPO/Brewfile" <<'EOF'
tap "bufbuild/buf"
brew "git"
brew "mole"
brew "bufbuild/buf/buf"
cask "ghostty"
cask "sing-box"
EOF
cat > "$REPO/install.sh" <<'EOF'
#!/bin/bash
#   claude plugin install personal@my-dotfiles --scope project
if command -v claude >/dev/null 2>&1; then
    claude plugin marketplace add "$DOTFILES_DIR/claude" >/dev/null 2>&1 \
        || claude plugin marketplace update my-dotfiles >/dev/null 2>&1
fi
EOF
cat > "$REPO/claude/.claude-plugin/marketplace.json" <<'EOF'
{"name": "my-dotfiles", "plugins": [{"name": "personal"}, {"name": "daily"}]}
EOF
cat > "$REPO/pi/settings.json" <<'EOF'
{"packages": ["npm:pi-web-access", "npm:@scope/pkg@1.2.0", "git:github.com/obra/superpowers", "npm:not-installed"]}
EOF
git -C "$REPO" add -A && git -C "$REPO" commit -q -m init
git -C "$REPO" branch feat-merged
git -C "$REPO" checkout -q -b feat-open
printf 'wip\n' >> "$REPO/notes/plan.txt"; git -C "$REPO" commit -q -am wip
git -C "$REPO" checkout -q main

git -C "$DEC" init -q -b main
printf 'x\n' > "$DEC/src/a.txt"; git -C "$DEC" add -A && git -C "$DEC" commit -q -m init

# Pages: a tools page with one stale covers entry, a whole part page, a part
# page missing a heading, an over-budget map and a README with no headings.
cat > "$DOCS/terminal.md" <<'EOF'
# Terminal
<!-- covers: bin/* install.sh bin/gone -->
Run `tool`, or `wt` for worktrees.
EOF
part() { # part <file> <covers> [heading to leave out]
    {
        echo "<!-- covers: $2 -->"; echo "# Part"
        for h in "What it does" "Moving parts" "State it keeps" "How it connects" "Why" "Lessons and pitfalls" "Unfinished"; do
            [ "$h" = "${3:-}" ] || printf '## %s\nText.\n' "$h"
        done
    } > "$SYSTEM/$1"
}
part daily.md "notes/* decisions:src/*"
cat >> "$SYSTEM/daily.md" <<'EOF'
- `dotfiles:feat-merged` merged long ago
- `dotfiles:feat-gone` branch deleted
- `dotfiles:feat-open` still being built
EOF
part broken.md "notes/*" "Why"
head -c 4000 /dev/zero | tr '\0' 'x' > "$SYSTEM/map.md"
printf 'Read me.\n' > "$SYSTEM/README.md"
cat > "$SYSTEM/known.txt" <<'EOF'
# acknowledged entries
stray acked   # kept on purpose
EOF

# Bin folders: a link into dotfiles, a plain file, an acknowledged file, and a
# folder linked into dotfiles holding one tracked and one untracked file.
ln -s "$REPO/bin/tool" "$HOME/bin/linked"
printf '#!/bin/sh\n' > "$HOME/bin/plain-tool"
printf '#!/bin/sh\n' > "$HOME/bin/acked"
ln -s "$REPO/bin/wt" "$HOME/.local/bin/wt"
ln -s "$REPO/pi/extensions" "$HOME/.pi/agent/extensions"
printf '// foreign\n' > "$REPO/pi/extensions/stray-ext.ts"

STOP_CMD='[ -n "$ORCA_TEST_VAR" ] && echo stop'
STATUS_CMD='/opt/elsewhere/statusline.sh'
jq -n --arg tool "$REPO/bin/tool" --arg stop "$STOP_CMD" --arg status "$STATUS_CMD" '{
  hooks: {
    PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $tool}]}],
    WorktreeCreate: [{hooks: [{type: "command", command: "~/.local/bin/wt hook-create"}]}],
    Stop: [{hooks: [{type: "command", command: $stop}]}]
  },
  statusLine: {type: "command", command: $status}
}' > "$SANDBOX/settings.json"
sha8() { printf '%s' "$1" | shasum | cut -c1-8; }

# Hand installs: fake brew output, pi's install folder, Claude's plugin files.
cat > "$FAKE/brew_bundle_check_--verbose_--no-upgrade.out" <<'EOF'
brew bundle can't satisfy your Brewfile's dependencies.
→ Formula mole needs to be installed.
→ Cask sing-box needs to be installed.
Satisfy missing dependencies with `brew bundle install`.
EOF
printf 'git\nhandmade\nbufbuild/buf/buf\n' > "$FAKE/brew_leaves_--installed-on-request.out"
printf 'ghostty\nhandcask\n' > "$FAKE/brew_list_--cask_-1.out"
cat > "$PI/npm/package.json" <<'EOF'
{"dependencies": {"pi-web-access": "^1", "@scope/pkg": "^1", "hand-pkg": "^1"}}
EOF
cat > "$PLUGINS/installed_plugins.json" <<'EOF'
{"version": 2, "plugins": {"daily@my-dotfiles": [{"scope": "user"}], "stale@my-dotfiles": [{"scope": "user"}],
 "superpowers@official": [{"scope": "user"}]}}
EOF
cat > "$PLUGINS/known_marketplaces.json" <<'EOF'
{"my-dotfiles": {"source": {"source": "directory", "path": "/x"}}, "official": {"source": {"source": "github", "repo": "a/b"}}}
EOF

export SYSTEM_REPOS="dotfiles=$REPO:decisions=$DEC" SYSTEM_DOCS="$DOCS" SYSTEM_PAGES="$SYSTEM" \
    CLAUDE_SETTINGS="$SANDBOX/settings.json" SYSTEM_CHECK_FAKE="$FAKE" SYSTEM_CHECK_PLUGINS="$PLUGINS" \
    SYSTEM_CHECK_PI="$PI" SYSTEM_CHECK_DIRS="$HOME/bin:$HOME/.local/bin:$HOME/.pi/agent/extensions:$HOME/missing"

sc() { # sc <state name> [args...]: sets out and code
    out="$(SYSTEM_CHECK_STATE="$SANDBOX/state/$1" "$SCRIPT" "${@:2}" 2>"$SANDBOX/err")"; code=$?
}
ids() { jq -c '[.new[].id]' <<<"$out" 2>/dev/null || echo "not JSON: $out $(cat "$SANDBOX/err")"; }
has() { # has <label> <id>
    if jq -e --arg id "$2" '.new | any(.id == $id)' <<<"$out" >/dev/null 2>&1; then pass "$1"; else fail "$1" "no $2 in $(ids)"; fi
}
hasnt() { # hasnt <label> <id prefix>
    if jq -e --arg id "$2" '.new | all(.id | startswith($id) | not)' <<<"$out" >/dev/null 2>&1; then pass "$1"; else fail "$1" "$2 in $(ids)"; fi
}
field() { jq -r "$1" <<<"$out" 2>/dev/null; }

echo "system-check: first run"
sc s1
[ "$code" -eq 0 ] && pass "exits 0" || fail "exits 0" "exit $code: $(cat "$SANDBOX/err")"
[ "$(field .baseline)" = "true" ] && pass "no state file means a baseline run" || fail "no state file means a baseline run" "$out"
[ -f "$SANDBOX/state/s1" ] && pass "writes the state file" || fail "writes the state file" "missing"
for f in check id detail; do
    [ "$(field "[.new[] | has(\"$f\")] | all")" = "true" ] && pass "every finding has $f" || fail "every finding has $f" "$out"
done

echo "stray"
has "a plain file in a bin folder is stray" "stray:~/bin/plain-tool"
hasnt "a link into a system repo is not stray" "stray:~/bin/linked"
hasnt "a name in known.txt is not stray" "stray:~/bin/acked"
hasnt "a link resolving to a tracked file is not stray" "stray:~/.local/bin/wt"
has "an untracked file in a linked folder is stray" "stray:~/.pi/agent/extensions/stray-ext.ts"
hasnt "a tracked file in a linked folder is not stray" "stray:~/.pi/agent/extensions/tracked.ts"

echo "foreign"
has "a hook naming no system repo is foreign" "foreign:Stop:$(sha8 "$STOP_CMD")"
has "the statusLine command is checked" "foreign:statusLine:$(sha8 "$STATUS_CMD")"
hasnt "a hook naming a repo path is not foreign" "foreign:PreToolUse:"
hasnt "a hook through a ~/.local/bin link into a repo is not foreign" "foreign:WorktreeCreate:"
case "$(field '.new[] | select(.id | startswith("foreign:Stop:")) | .detail')" in
    *ORCA*|*orca*) pass "names the app the content points to" ;; *) fail "names the app the content points to" "$out" ;;
esac

echo "lint"
has "a part page missing a heading" "lint:heading:broken.md:## Why"
hasnt "a whole part page passes" "lint:heading:daily.md"
hasnt "README is not a part page" "lint:heading:README.md"
has "map over budget" "lint:map-budget"
has "a covers entry matching nothing" "lint:terminal.md: covers entry matches nothing: bin/gone"

echo "branch"
has "an Unfinished branch merged into trunk" "branch:daily.md:dotfiles:feat-merged"
has "an Unfinished branch that no longer exists" "branch:daily.md:dotfiles:feat-gone"
hasnt "an unmerged branch is fine" "branch:daily.md:dotfiles:feat-open"

echo "install"
has "a Brewfile formula not installed" "install:brewfile-missing:formula:mole"
has "a Brewfile cask not installed" "install:brewfile-missing:cask:sing-box"
has "a leaf formula not in the Brewfile" "install:brew-extra:formula:handmade"
hasnt "a tap formula in the Brewfile is known" "install:brew-extra:formula:bufbuild"
hasnt "a Brewfile formula installed is fine" "install:brew-extra:formula:git"
has "a cask not in the Brewfile" "install:brew-extra:cask:handcask"
has "a pi package in settings not installed" "install:pi-missing:npm:not-installed"
has "a pi npm package installed by hand" "install:pi-extra:npm:hand-pkg"
has "a pi git package installed by hand" "install:pi-extra:git:github.com/someone/handgit"
hasnt "a versioned pi package that is installed is fine" "install:pi-missing:npm:@scope"
hasnt "a pi git package in settings is fine" "install:pi-extra:git:github.com/obra"
has "a plugin of a foreign marketplace" "install:plugin-extra:superpowers@official"
has "a plugin the dotfiles marketplace does not list" "install:plugin-extra:stale@my-dotfiles"
hasnt "a plugin the dotfiles marketplace lists is fine" "install:plugin-extra:daily@my-dotfiles"
has "a marketplace dotfiles does not set up" "install:marketplace-extra:official"
hasnt "the dotfiles marketplace is fine" "install:marketplace-extra:my-dotfiles"

echo "second run"
sc s1
[ "$code" -eq 0 ] && [ "$(field '.new | length')" = "0" ] && pass "same state reports new: []" || fail "same state reports new: []" "$out"
[ "$(field .baseline)" = "false" ] && pass "not a baseline once state exists" || fail "not a baseline once state exists" "$out"
[ "$(field '.known > 0')" = "true" ] && pass "known counts the findings already seen" || fail "known counts the findings already seen" "$out"

echo "optout"
commit() { # commit <repo> <file> <message>
    printf 'more\n' >> "$1/$2"; git -C "$1" add "$2"; git -C "$1" commit -q -m "$3"; git -C "$1" rev-parse HEAD
}
none_sha=$(commit "$REPO" bin/tool $'chore: tidy\n\nDocs: none')
internal_tools=$(commit "$REPO" install.sh $'feat: install\n\nDocs: internal')
internal_part=$(commit "$REPO" notes/plan.txt $'feat: plan\n\ndocs: Internal')
plain=$(commit "$REPO" bin/tool 'feat: tool')
uncovered=$(commit "$REPO" README.md $'docs: readme\n\nDocs: none')
dec_none=$(commit "$DEC" src/a.txt $'fix: a\n\nDocs: none')
test_only=$(commit "$REPO" bin/tool.test.sh $'test: tool\n\nDocs: none')
sc s1
has "'Docs: none' commit touching a covered path" "optout:dotfiles:$none_sha"
has "'Docs: internal' commit touching a tools-covered path" "optout:dotfiles:$internal_tools"
hasnt "'Docs: internal' commit touching only a system-covered path" "optout:dotfiles:$internal_part"
hasnt "commit without an opt-out" "optout:dotfiles:$plain"
hasnt "opt-out commit touching nothing covered" "optout:dotfiles:$uncovered"
has "opt-out commit in another system repo" "optout:decisions:$dec_none"
hasnt "opt-out commit touching only a test file under a covered glob" "optout:dotfiles:$test_only"
sc s1
[ "$(field '.new | length')" = "0" ] && pass "commits already scanned are not scanned again" || fail "commits already scanned are not scanned again" "$out"

echo "dirty"
printf 'edit\n' >> "$REPO/bin/tool"
printf '#!/bin/sh\n' > "$REPO/bin/fresh"
printf 'edit\n' >> "$REPO/README.md"
sc s1
has "a covered file changed outside git" "dirty:dotfiles:bin/tool"
has "an untracked file in a covered path" "dirty:dotfiles:bin/fresh"
hasnt "an uncovered change is not reported" "dirty:dotfiles:README.md"
git -C "$REPO" checkout -q -- bin/tool README.md; rm "$REPO/bin/fresh"

echo "--baseline"
sc s2 --baseline
[ "$code" -eq 0 ] && [ "$(field .baseline)" = "true" ] && pass "--baseline on a fresh state is a baseline" || fail "--baseline on a fresh state is a baseline" "$out"
sc s2
[ "$(field '.new | length')" = "0" ] && [ "$(field .baseline)" = "false" ] && pass "the run after --baseline is empty" || fail "the run after --baseline is empty" "$out"

echo "known foreign"
printf 'foreign ORCA_  # trying it out\n' >> "$SYSTEM/known.txt"
sc s3
hasnt "a foreign substring in known.txt is not reported" "foreign:Stop:"
has "other foreign entries still are" "foreign:statusLine:$(sha8 "$STATUS_CMD")"

echo "failing commands"
SYSTEM_CHECK_FAKE="$SANDBOX/empty-fake" sc s4
[ "$code" -eq 0 ] && pass "a failing command does not crash the run" || fail "a failing command does not crash the run" "exit $code: $(cat "$SANDBOX/err")"
[ "$(field '[.new[] | select(.id | startswith("install:failed:"))] | length > 0')" = "true" ] \
    && pass "a failing command is a finding" || fail "a failing command is a finding" "$(ids)"
has "the other checks still run" "install:pi-extra:npm:hand-pkg"
SYSTEM_CHECK_FAKE="$SANDBOX/empty-fake" sc s4
[ "$(field '[.new[] | select(.id | startswith("install:failed:"))] | length > 0')" = "true" ] \
    && pass "a check that stays broken is reported on every run" || fail "a check that stays broken is reported on every run" "$(ids)"
sc s7
SYSTEM_CHECK_FAKE="$SANDBOX/empty-fake" sc s7
hasnt "a failed check does not report its old findings" "install:brewfile-missing:"
sc s7
hasnt "nor once it works again: its findings were kept" "install:brewfile-missing:"

echo "recurring findings"
sc s6
printf 'edit\n' >> "$REPO/bin/tool"
sc s6
has "a finding is reported when it appears" "dirty:dotfiles:bin/tool"
sc s6
hasnt "not again while it stays" "dirty:dotfiles:bin/tool"
git -C "$REPO" checkout -q -- bin/tool
sc s6
hasnt "nor once it is gone" "dirty:dotfiles:bin/tool"
printf 'edit\n' >> "$REPO/bin/tool"
sc s6
has "again when it comes back" "dirty:dotfiles:bin/tool"
git -C "$REPO" checkout -q -- bin/tool

echo "optout failure"
ART="$SANDBOX/articles"
git -C "$SANDBOX" init -q -b main articles
for n in a b; do printf '%s\n' "$n" > "$ART/$n"; git -C "$ART" add "$n"; git -C "$ART" commit -q -m "$n"; done
export SYSTEM_REPOS="dotfiles=$REPO:decisions=$DEC:articles=$ART"
sc s8
before="$(jq -r .last.articles "$SANDBOX/state/s8")"
for n in c d; do printf '%s\n' "$n" > "$ART/$n"; git -C "$ART" add "$n"; git -C "$ART" commit -q -m "$n"; done
broken="$(git -C "$ART" rev-parse HEAD~1)"
rm -f "$ART/.git/objects/${broken:0:2}/${broken:2}"
sc s8
[ "$code" -eq 0 ] && pass "an unreadable commit range does not crash the run" || fail "an unreadable commit range does not crash the run" "exit $code: $(cat "$SANDBOX/err")"
has "a failed optout scan is a finding" "optout:failed:articles"
[ "$(jq -r .last.articles "$SANDBOX/state/s8")" = "$before" ] && pass "a failed optout scan leaves last where it was" \
    || fail "a failed optout scan leaves last where it was" "$(cat "$SANDBOX/state/s8")"
sc s8
has "and is reported again on the next run" "optout:failed:articles"
export SYSTEM_REPOS="dotfiles=$REPO:decisions=$DEC"

echo "bad input"
printf '{"last": [], "seen": 5}\n' > "$SANDBOX/state/s9"
sc s9
[ "$code" -eq 0 ] && [ "$(field .baseline)" = "true" ] && pass "a malformed state file counts as no state" \
    || fail "a malformed state file counts as no state" "exit $code: $out $(cat "$SANDBOX/err")"
printf '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "/opt/x/\xff hook"}]}]}}\n' > "$SANDBOX/bad-settings.json"
CLAUDE_SETTINGS="$SANDBOX/bad-settings.json" sc s10
[ "$code" -eq 0 ] && [ "$(field '.new | length > 0')" = "true" ] && pass "settings that are not UTF-8 still give JSON" \
    || fail "settings that are not UTF-8 still give JSON" "exit $code: $out $(cat "$SANDBOX/err")"

echo "no system pages"
SYSTEM_PAGES="$SANDBOX/no-system" sc s5
[ "$code" -eq 0 ] && [ "$(field '.new | length')" = "0" ] && pass "a missing system folder gives new: [] and exit 0" \
    || fail "a missing system folder gives new: [] and exit 0" "exit $code: $out $(cat "$SANDBOX/err")"

echo "docs-check coverage is unchanged"
out="$(cd "$REPO" && "$TEST_DIR/docs-check" coverage 2>&1)"; code=$?
[ "$code" -eq 1 ] && case "$out" in *"bin/gone"*) true ;; *) false ;; esac \
    && pass "docs-check coverage still prints problems and exits 1" || fail "docs-check coverage still prints problems and exits 1" "exit $code: $out"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
