#!/bin/bash
# Tests for bin/plink. Everything runs inside a sandbox HOME, so no real
# ~/.pi/agent is touched.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/plink"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

DOT="$SANDBOX/dotfiles"
HOME_DIR="$SANDBOX/home"
DEST="$HOME_DIR/.pi/agent"

mkdir -p "$DOT/pi/extensions" "$DOT/claude" "$DOT/opencode/skills/alpha" "$DOT/opencode/agents" "$HOME_DIR"
mkdir -p "$DOT/pi/prompts"; printf '# o\n' > "$DOT/pi/prompts/orchestrate.md"
for f in settings.json models.json mcp-servers.json subagents.json subagent-models.json subagent-model-guide.md subagents-research.md; do printf '{}\n' > "$DOT/pi/$f"; done
printf 'append\n' > "$DOT/pi/APPEND_SYSTEM.md"
printf '// ext\n'  > "$DOT/pi/extensions/tool.ts"
printf '# me\n'    > "$DOT/claude/CLAUDE.md"
printf '# skill\n' > "$DOT/opencode/skills/alpha/SKILL.md"
printf '# agent\n' > "$DOT/opencode/agents/reviewer.md"

run_plink() {
    HOME="$HOME_DIR" DOTFILES_DIR="$DOT" PI_AGENT_DIR="$DEST" bash "$SCRIPT" "$@"
}

assert_link() { # dest src label
    if [ -L "$1" ]; then
        [ "$(readlink "$1")" = "$2" ] && pass "$3" \
            || fail "$3" "points to $(readlink "$1")"
    else
        fail "$3" "not a symlink"
    fi
}

echo "plink — create"
# State Pi owns must survive: it is not ours to link or remove.
mkdir -p "$DEST/sessions"
printf 'secret\n' > "$DEST/auth.json"
run_plink >/dev/null
for f in settings.json models.json mcp-servers.json subagents.json subagent-models.json subagent-model-guide.md subagents-research.md APPEND_SYSTEM.md; do
    assert_link "$DEST/$f" "$DOT/pi/$f" "links $f"
done
assert_link "$DEST/AGENTS.md" "$DOT/claude/CLAUDE.md" "links CLAUDE.md as AGENTS.md"
assert_link "$DEST/skills" "$DOT/opencode/skills" "links the shared skills"
assert_link "$DEST/extensions" "$DOT/pi/extensions" "links extensions/"
assert_link "$DEST/agents" "$DOT/opencode/agents" "links the shared agent profiles"
[ ! -L "$DEST/auth.json" ] && [ "$(cat "$DEST/auth.json")" = "secret" ] \
    && pass "leaves auth.json alone" || fail "leaves auth.json alone" "auth.json changed"
[ -d "$DEST/sessions" ] && [ ! -L "$DEST/sessions" ] \
    && pass "leaves sessions/ alone" || fail "leaves sessions/ alone" "sessions/ changed"

echo "old mcp.json link"
ln -s "$DOT/pi/mcp.json" "$DEST/mcp.json"
out="$(run_plink)"
[ ! -e "$DEST/mcp.json" ] && [ ! -L "$DEST/mcp.json" ] && pass "removes the old mcp.json link" \
    || fail "removes the old mcp.json link" "still there"
printf '{}\n' > "$DEST/mcp.json"
run_plink >/dev/null
[ -f "$DEST/mcp.json" ] && pass "leaves a real mcp.json alone" || fail "leaves a real mcp.json alone" "gone"
rm -f "$DEST/mcp.json"

echo "idempotence"
out="$(run_plink)"
case "$out" in *"nothing to do"*) pass "second run reports nothing to do" ;;
                *) fail "second run reports nothing to do" "$out" ;; esac
[ -e "$DEST/settings.json.backup" ] && fail "second run makes no backup" "backup appeared" \
    || pass "second run makes no backup"

echo "repair"
ln -sfn /nonexistent/wrong "$DEST/skills"
out="$(run_plink)"
assert_link "$DEST/skills" "$DOT/opencode/skills" "re-points a wrong/broken link"
case "$out" in *"re-pointed"*) pass "reports the re-point" ;;
                *) fail "reports the re-point" "$out" ;; esac

echo "real file backup"
rm "$DEST/settings.json"
printf '{"lastChangelogVersion":"1"}\n' > "$DEST/settings.json"
run_plink >/dev/null
[ -f "$DEST/settings.json.backup" ] && grep -q lastChangelogVersion "$DEST/settings.json.backup" \
    && pass "backs up a real file" || fail "backs up a real file" "no settings.json.backup with its content"
assert_link "$DEST/settings.json" "$DOT/pi/settings.json" "links over the backup"

echo "dry run"
ln -sfn /nonexistent/wrong "$DEST/skills"
out="$(run_plink -n)"
[ "$(readlink "$DEST/skills")" = "/nonexistent/wrong" ] \
    && pass "dry run leaves links untouched" \
    || fail "dry run leaves links untouched" "link changed to $(readlink "$DEST/skills")"
case "$out" in *"would re-point"*) pass "dry run reports the pending change" ;;
                *) fail "dry run reports the pending change" "$out" ;; esac

echo "dry run on a fresh machine"
FRESH="$SANDBOX/fresh/.pi/agent"
HOME="$HOME_DIR" DOTFILES_DIR="$DOT" PI_AGENT_DIR="$FRESH" bash "$SCRIPT" -n >/dev/null
[ ! -e "$FRESH" ] && pass "dry run creates no directories" || fail "dry run creates no directories" "$FRESH exists"

echo "flags"
run_plink --bogus >/dev/null 2>&1
[ $? -eq 2 ] && pass "unknown option exits 2" || fail "unknown option exits 2" "wrong status"

DOTFILES_DIR=/nonexistent HOME="$HOME_DIR" PI_AGENT_DIR="$DEST" bash "$SCRIPT" >/dev/null 2>&1
[ $? -eq 1 ] && pass "missing source exits 1" || fail "missing source exits 1" "wrong status"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
