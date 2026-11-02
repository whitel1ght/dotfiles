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
for f in models.json mcp-servers.json model-selection.md APPEND_SYSTEM.md; do
    assert_link "$DEST/$f" "$DOT/pi/$f" "links $f"
done
# settings.json is per-host state (Pi writes changelog markers into it): seeded,
# never linked, so a repo refresh cannot clobber the host's own defaults.
[ -f "$DEST/settings.json" ] && [ ! -L "$DEST/settings.json" ] \
    && pass "seeds settings.json as a regular file" \
    || fail "seeds settings.json as a regular file" "missing or a symlink"
cmp -s "$DEST/settings.json" "$DOT/pi/settings.json" \
    && pass "seeded settings.json matches the repo seed" \
    || fail "seeded settings.json matches the repo seed" "content differs"
assert_link "$DEST/AGENTS.md" "$DOT/claude/CLAUDE.md" "links CLAUDE.md as AGENTS.md"
assert_link "$DEST/skills" "$DOT/pi/skills" "links skills/"
assert_link "$HOME_DIR/.agents/modules" "$DOT/pi/modules" "links modules/ into the cross-runtime ~/.agents"
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
ln -sfn "$DOT/pi/old-skills" "$DEST/skills"
out="$(run_plink)"
assert_link "$DEST/skills" "$DOT/pi/skills" "repairs a broken link owned by this checkout"
case "$out" in *"re-pointed owned link"*) pass "reports the owned-link repair" ;;
                *) fail "reports the re-point" "$out" ;; esac

echo "per-host settings"
rm "$DEST/settings.json"
printf '{"lastChangelogVersion":"1"}\n' > "$DEST/settings.json"
run_plink >/dev/null
[ ! -L "$DEST/settings.json" ] && grep -q lastChangelogVersion "$DEST/settings.json" \
    && pass "leaves a real settings.json with its machine keys" \
    || fail "leaves a real settings.json with its machine keys" "replaced or rewritten"
[ -e "$DEST/settings.json.backup" ] && fail "a real settings.json needs no backup" "backup appeared" \
    || pass "a real settings.json needs no backup"
rm "$DEST/settings.json"
ln -s "$DOT/pi/settings.json" "$DEST/settings.json"
out="$(run_plink -n)"
[ -L "$DEST/settings.json" ] && pass "dry run keeps the legacy settings link" \
    || fail "dry run keeps the legacy settings link" "link replaced"
case "$out" in *"would convert owned settings link"*) pass "dry run reports the pending conversion" ;;
                *) fail "dry run reports the pending conversion" "$out" ;; esac
out="$(run_plink)"
[ -f "$DEST/settings.json" ] && [ ! -L "$DEST/settings.json" ] \
    && pass "converts an owned settings link into a per-host file" \
    || fail "converts an owned settings link into a per-host file" "still a link"
cmp -s "$DEST/settings.json" "$DOT/pi/settings.json" \
    && pass "conversion preserves the settings content" \
    || fail "conversion preserves the settings content" "content differs"
[ -L "$DEST/settings.json.symlink.backup" ] \
    && pass "records the old settings link" \
    || fail "records the old settings link" "no settings.json.symlink.backup"
case "$out" in *"converted owned settings link"*) pass "reports the settings conversion" ;;
                *) fail "reports the settings conversion" "$out" ;; esac
rm -f "$DEST/settings.json" "$DEST/settings.json.symlink.backup"
ln -s /foreign/settings.json "$DEST/settings.json"
run_plink >/dev/null
assert_link "$DEST/settings.json" /foreign/settings.json "preserves a foreign settings link"
rm -f "$DEST/settings.json"
ln -s "$DOT/pi/settings.json" "$DEST/settings.json"

echo "foreign active link"
ln -sfn /foreign/skills "$DEST/skills"
out="$(run_plink)"
assert_link "$DEST/skills" /foreign/skills "preserves a foreign active skills link"
case "$out" in *"foreign link(s) left untouched"*) pass "reports the preserved foreign link" ;;
                *) fail "reports the preserved foreign link" "$out" ;; esac
rm -f "$DEST/skills"
ln -s "$DOT/pi/skills" "$DEST/skills"

echo "dry run"
ln -sfn "$DOT/pi/old-skills" "$DEST/skills"
out="$(run_plink -n)"
[ "$(readlink "$DEST/skills")" = "$DOT/pi/old-skills" ] \
    && pass "dry run leaves links untouched" \
    || fail "dry run leaves links untouched" "link changed to $(readlink "$DEST/skills")"
case "$out" in *"would re-point owned link"*) pass "dry run reports the pending change" ;;
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
