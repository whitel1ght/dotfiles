#!/usr/bin/env bash
# Fixture test for scripts/inventory: a fake ~/.claude and pi dir, then exact rows.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
C="$T/claude"; P="$T/pi"; H="$T/pihome"

mkdir -p "$C/commands" "$C/plugins/on/commands" "$C/plugins/on/skills/s1" "$C/plugins/on/skills/s2" \
  "$C/plugins/on/skills/s3" "$C/plugins/on/skills/s4" "$C/plugins/on/skills/s5" "$P/skills/s3" "$P/skills/s4" "$P/skills/s5" \
  "$C/plugins/on/agents" "$C/plugins/on/hooks" "$C/plugins/off/commands" \
  "$C/skills/synced/acct1/sx" "$C/skills/synced/acct2/sx" \
  "$P/prompts" "$P/skills/s1" "$H/git/x/skills/s2"
echo x > "$C/commands/c1.md"; echo x > "$C/commands/c2.md"
echo x > "$C/plugins/on/commands/pc.md"; echo x > "$C/plugins/off/commands/hidden.md"
echo x > "$C/plugins/on/skills/s1/SKILL.md"; echo x > "$C/plugins/on/skills/s2/SKILL.md"
echo x > "$C/plugins/on/agents/a1.md"
echo x > "$C/skills/synced/acct1/sx/SKILL.md"; echo x > "$C/skills/synced/acct2/sx/SKILL.md"
echo '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[]}]},"modules":["./m.tsx"]}' > "$C/plugins/on/hooks/hooks.json"
echo '{"plugins":{"on@m":[{"installPath":"'"$C/plugins/on"'"}],"off@m":[{"installPath":"'"$C/plugins/off"'"}]}}' \
  > "$C/plugins/installed_plugins.json"
echo '{"enabledPlugins":{"on@m":true},"hooks":{"WorktreeCreate":[{"hooks":[{"type":"command","command":"wt hook-create"}]}]}}' \
  > "$C/settings.json"
echo x > "$P/prompts/c1.md"; echo x > "$P/skills/s1/SKILL.md"; echo x > "$H/git/x/skills/s2/SKILL.md"
# s1: same content as Claude's. s3: reformatted frontmatter only. s4: changed, recorded
# as adapted. s5: changed, recorded against an older source.
printf -- '---\nname: S3 Skill\ndescription: Does a thing well.\n---\nbody\n' > "$C/plugins/on/skills/s3/SKILL.md"
printf -- '---\nname: s3\ndescription: >-\n  Does a thing\n  well.\n---\n\nbody  \n' > "$P/skills/s3/SKILL.md"
echo 'claude' > "$C/plugins/on/skills/s4/SKILL.md"; echo 'pi' > "$P/skills/s4/SKILL.md"
echo 'claude v2' > "$C/plugins/on/skills/s5/SKILL.md"; echo 'pi' > "$P/skills/s5/SKILL.md"
d4="$("$HERE/scripts/skill-digest" "$C/plugins/on/skills/s4")"
cat > "$T/parity.md" <<'P'
- `hook:on/PreToolUse[Bash]` — covered.
- `skill:sx` — not wanted.
- `command:c2x` — a near miss that must not accept c2.
- `adapted:s5` 000000000000 — adapted against an older source.
P
echo "- \`adapted:s4\` $d4 — pi wording." >> "$T/parity.md"

got="$(CLAUDE_DIR="$C" PI_DIR="$P" PI_HOME="$H" PARITY="$T/parity.md" "$HERE/scripts/inventory" | cut -f1-3)"
want="$(printf '%s\n' \
  'command	c1	ported' 'command	c2	MISSING' \
  'command	pc	MISSING' 'skill	s1	ported' 'skill	s2	ported' 'agent	a1	MISSING' \
  'skill	s3	ported' 'skill	s4	adapted' 'skill	s5	stale' \
  'hook	on/PreToolUse[Bash]	accepted' 'hook	on/module:m.tsx	MISSING' \
  'plugin	off@m	disabled' 'skill	sx	accepted' 'hook	user/WorktreeCreate	MISSING')"
if [ "$(sort <<<"$got")" = "$(sort <<<"$want")" ]; then echo "PASS inventory"; else
  echo "FAIL inventory"; diff <(sort <<<"$want") <(sort <<<"$got") || true; exit 1; fi
