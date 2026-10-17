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

mkdir -p "$DOT/pi/extensions" "$DOT/claude" "$DOT/pi/skills/alpha" "$DOT/pi/modules" "$HOME_DIR"
mkdir -p "$DOT/pi/agents"
printf '# pi agent\n' > "$DOT/pi/agents/reviewer.md"
mkdir -p "$DOT/pi/prompts"; printf '# o\n' > "$DOT/pi/prompts/orchestrate.md"
for f in settings.json models.json mcp-servers.json subagents.json subagent-models.json subagent-model-guide.md subagents-research.md; do printf '{}\n' > "$DOT/pi/$f"; done
printf 'append\n' > "$DOT/pi/APPEND_SYSTEM.md"
printf 'model policy\n' > "$DOT/pi/model-selection.md"
printf '// ext\n'  > "$DOT/pi/extensions/tool.ts"
printf '# me\n'    > "$DOT/claude/CLAUDE.md"
printf '# skill\n' > "$DOT/pi/skills/alpha/SKILL.md"
printf '# module\n' > "$DOT/pi/modules/ui-project-context.md"
printf '{"providers":{}}\n' > "$DOT/pi/billion-context.json"

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
for f in settings.json models.json mcp-servers.json model-selection.md APPEND_SYSTEM.md; do
    assert_link "$DEST/$f" "$DOT/pi/$f" "links $f"
done
assert_link "$DEST/AGENTS.md" "$DOT/claude/CLAUDE.md" "links CLAUDE.md as AGENTS.md"
assert_link "$DEST/skills" "$DOT/pi/skills" "links skills/"
assert_link "$HOME_DIR/.agents/modules" "$DOT/pi/modules" "links modules/ into the cross-runtime ~/.agents"
assert_link "$HOME_DIR/.config/billion-context/billion-context.json" "$DOT/pi/billion-context.json" \
    "links billion-context.json"
assert_link "$DEST/extensions" "$DOT/pi/extensions" "links extensions/"
assert_link "$DEST/agents" "$DOT/pi/agents" "links Pi-specific agent definitions"
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

echo "retired subagent links"
for name in subagents.json subagent-models.json subagent-model-guide.md subagents-research.md; do
    rm -f "$DEST/$name"
    ln -s "$DOT/pi/$name" "$DEST/$name"
    run_plink -n >/dev/null
    assert_link "$DEST/$name" "$DOT/pi/$name" "dry run preserves retired $name link"
    run_plink >/dev/null
    [ ! -L "$DEST/$name" ] && [ ! -e "$DEST/$name" ] \
        && pass "removes owned retired $name link" || fail "removes owned retired $name link" "still there"
    rm -f "$DEST/$name"
    printf 'user-owned\n' > "$DEST/$name"
    run_plink >/dev/null
    [ ! -L "$DEST/$name" ] && [ "$(cat "$DEST/$name")" = "user-owned" ] \
        && pass "preserves real $name" || fail "preserves real $name" "replaced"
    rm -f "$DEST/$name"
    ln -s /foreign/config "$DEST/$name"
    run_plink >/dev/null
    assert_link "$DEST/$name" /foreign/config "preserves foreign $name link"
    rm -f "$DEST/$name"
done

echo "idempotence"
out="$(run_plink)"
case "$out" in *"nothing to do"*) pass "second run reports nothing to do" ;;
                *) fail "second run reports nothing to do" "$out" ;; esac
[ -e "$DEST/settings.json.backup" ] && fail "second run makes no backup" "backup appeared" \
    || pass "second run makes no backup"

echo "repair"
ln -sfn /nonexistent/wrong "$DEST/skills"
out="$(run_plink)"
assert_link "$DEST/skills" "$DOT/pi/skills" "re-points a wrong/broken link"
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

# --- team skills, generated from a claude-components clone
CC="$SANDBOX/claude-components"
mkdir -p "$DOT/pi/gen" "$CC/.claude-plugin" "$CC/plugins/shared/skills/shipit"
cp "$TEST_DIR/../pi/gen/pi_skills.py" "$DOT/pi/gen/"
printf '{"name":"x","plugins":[{"name":"shared","source":"./plugins/shared"}]}\n' > "$CC/.claude-plugin/marketplace.json"
printf -- '---\nname: Ship It\ndescription: d\n---\nbody\n' > "$CC/plugins/shared/skills/shipit/SKILL.md"
rm -rf "$DEST/skills-team"
CLAUDE_COMPONENTS_DIR="$CC" run_plink -n >/dev/null
[ ! -e "$DEST/skills-team" ] && pass "dry run does not generate team skills" \
    || fail "dry run does not generate team skills" "skills-team was created"
CLAUDE_COMPONENTS_DIR="$CC" run_plink >/dev/null
grep -qx 'name: shipit' "$DEST/skills-team/shipit/SKILL.md" 2>/dev/null \
    && pass "generates team skills from claude-components" \
    || fail "generates team skills from claude-components" "no $DEST/skills-team/shipit/SKILL.md"
out="$(CLAUDE_COMPONENTS_DIR="$SANDBOX/nope" run_plink 2>&1)"; status=$?
[ "$status" -eq 0 ] && pass "missing claude-components does not fail plink" \
    || fail "missing claude-components does not fail plink" "exit $status"
case "$out" in *"claude-components not found"*) pass "says why team skills were skipped" ;;
    *) fail "says why team skills were skipped" "$out" ;; esac

# --- agents: team ones generated, pi-only ones linked in
cp "$TEST_DIR/../pi/gen/pi_agents.py" "$DOT/pi/gen/"
mkdir -p "$CC/plugins/shared/agents"
printf -- '---\nname: git-expert\ndescription: d\nmodel: opus\ncolor: red\n---\nbody\n' > "$CC/plugins/shared/agents/git-expert.md"
CLAUDE_COMPONENTS_DIR="$CC" run_plink >/dev/null
[ -d "$DEST/agents" ] && [ ! -L "$DEST/agents" ] && pass "agents/ becomes a generated folder" \
    || fail "agents/ becomes a generated folder" "$(ls -ld "$DEST/agents")"
grep -qx 'tools: read, bash, grep, find, ls' "$DEST/agents/git-expert.md" 2>/dev/null \
    && pass "generates team agents with pi's header" || fail "generates team agents with pi's header" "no git-expert.md"
[ "$(readlink "$DEST/agents/reviewer.md")" = "$DOT/pi/agents/reviewer.md" ] \
    && pass "links the pi-only agents in" || fail "links the pi-only agents in" "$(ls -l "$DEST/agents" 2>&1)"
CLAUDE_COMPONENTS_DIR="$SANDBOX/nope" run_plink >/dev/null 2>&1
[ -f "$DEST/agents/git-expert.md" ] && [ ! -L "$DEST/agents" ] \
    && pass "a missing clone keeps the generated agents" || fail "a missing clone keeps the generated agents" "replaced"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
