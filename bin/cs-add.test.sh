#!/bin/bash
# Tests for bin/cs-add. Runs against a fixture git repo via CS_ADD_REPO, so
# nothing here touches a real checkout or a real Claude session.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADD="$TEST_DIR/cs-add"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [ "$expected" = "$actual" ]; then pass "$label"
    else fail "$label" "expected [$expected] got [$actual]"; fi
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    case "$haystack" in
        *"$needle"*) pass "$label" ;;
        *) fail "$label" "[$needle] not found in [$haystack]" ;;
    esac
}

assert_lacks() {
    local haystack="$1" needle="$2" label="$3"
    case "$haystack" in
        *"$needle"*) fail "$label" "[$needle] unexpectedly found in [$haystack]" ;;
        *) pass "$label" ;;
    esac
}

is_link() { [ -L "$1" ] && echo yes || echo no; }
exists()  { [ -e "$1" ] && echo yes || echo no; }

make_skill() {
    mkdir -p "$1"
    printf -- '---\nname: %s\ndescription: Fixture skill.\n---\n# %s\n' \
        "$(basename "$1")" "$(basename "$1")" > "$1/SKILL.md"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fixture repo, standing in for a project a session is running against.
REPO="$TMP/repo"
mkdir -p "$REPO/.git/info" "$REPO/.claude/skills"
make_skill "$REPO/.claude/skills/committed-skill"   # a skill the repo owns
echo "*.log" > "$REPO/.git/info/exclude"            # pre-existing unrelated content

# A bundle and a standalone skill to link from.
make_skill "$TMP/bundle/skills/alpha"
make_skill "$TMP/bundle/skills/beta"
make_skill "$TMP/solo/gamma"

make_agent() {
    mkdir -p "$(dirname "$1")"
    printf -- '---\nname: %s\ndescription: Fixture agent.\ntools: Read\n---\nProbe.\n' \
        "$(basename "$1" .md)" > "$1"
}
make_agent "$TMP/bundle/agents/alpha-expert.md"
make_agent "$TMP/bundle/agents/beta-expert.md"
# Not agents: the repo keeps prose in agents/ too, and linking it would register
# two bogus agent types.
printf '# notes\n' > "$TMP/bundle/agents/README.md"
printf '# index\n' > "$TMP/bundle/agents/MODULE_INDEX.md"
make_agent "$TMP/agentsonly/agents/lone-expert.md"

export CS_ADD_REPO="$REPO"
SK="$REPO/.claude/skills"
EX="$REPO/.git/info/exclude"

echo "adding"
out_bundle="$("$ADD" "$TMP/bundle" 2>&1)"; out="$out_bundle"
assert_contains "$out" "linked 2 skill(s)" "a bundle links every skill it holds"
assert_eq "yes" "$(is_link "$SK/alpha")" "alpha is linked"
assert_eq "yes" "$(is_link "$SK/beta")" "beta is linked"
assert_contains "$out" "next rescans" "the rescan delay is stated, not assumed"

out="$("$ADD" "$TMP/solo/gamma" 2>&1)"
assert_contains "$out" "linked 1 skill(s)" "a lone SKILL.md directory links as one skill"
assert_eq "yes" "$(is_link "$SK/gamma")" "gamma is linked"

echo "agents"
AG="$REPO/.claude/agents"
assert_eq "yes" "$(is_link "$AG/alpha-expert.md")" "a bundle's agents are linked too"
assert_contains "$out_bundle" "linked 2 agent(s)" "the agent count is reported"
assert_contains "$out_bundle" "NEW session" "agents are said to need a restart, not a rescan"
assert_eq "no" "$(exists "$AG/README.md")" "prose in agents/ is not linked as an agent"
assert_eq "no" "$(exists "$AG/MODULE_INDEX.md")" "the module index is not linked as an agent"

out="$("$ADD" "$TMP/agentsonly" 2>&1)"
assert_contains "$out" "linked 1 agent(s)" "a bundle with only agents still works"
assert_eq "yes" "$(is_link "$AG/lone-expert.md")" "the agents-only bundle is linked"

out="$("$ADD" "$TMP/agentsonly/agents/lone-expert.md" 2>&1)"
assert_contains "$out" "agent(s)" "a bare .md path links as one agent"

echo "git exclude"
ex="$(cat "$EX")"
assert_contains "$ex" "/.claude/skills/alpha" "the link is excluded from git"
assert_contains "$ex" "/.claude/skills/gamma" "later links join the same block"
assert_contains "$ex" "*.log" "unrelated exclude content is preserved"
assert_eq "1" "$(grep -c 'cs-add session skills >>>' "$EX")" "only one marker block exists"

echo "idempotence"
"$ADD" "$TMP/bundle" >/dev/null 2>&1
assert_eq "1" "$(grep -cxF '/.claude/skills/alpha' "$EX")" "re-adding does not duplicate the entry"

echo "listing"
out="$("$ADD" --list 2>&1)"
assert_contains "$out" "alpha" "--list names an activated skill"
assert_contains "$out" "$TMP/bundle/skills/alpha" "--list shows where it points"
assert_lacks "$out" "committed-skill" "--list ignores skills the repo owns"

echo "refusals"
out="$("$ADD" "$TMP/bundle/skills" 2>&1)"; rc=$?
assert_eq "1" "$rc" "a directory that is neither skill nor bundle fails"

make_skill "$TMP/clash/skills/committed-skill"
out="$("$ADD" "$TMP/clash" 2>&1)"; rc=$?
assert_eq "1" "$rc" "a name the repo already owns is refused"
assert_contains "$out" "not a cs-add link" "the refusal says why"
assert_eq "no" "$(is_link "$SK/committed-skill")" "the repo's own skill is untouched"

out="$("$ADD" +nosuchplugin 2>&1)"; rc=$?
assert_eq "1" "$rc" "an unknown plugin name fails"
assert_contains "$out" "No installed plugin" "the failure names the problem"

out="$("$ADD" --remove committed-skill 2>&1)"; rc=$?
assert_eq "1" "$rc" "removing a skill cs-add did not create is refused"
assert_eq "yes" "$(exists "$SK/committed-skill")" "that skill survives the attempt"

echo "adoption"
# Another installer got there first. Its link is indistinguishable from the one
# cs-add would write, so refusing over the missing bookkeeping entry would leave
# the skill unusable for no gain.
make_skill "$TMP/preexisting/adopted"
ln -sfn "$TMP/preexisting/adopted" "$SK/adopted"
out="$("$ADD" "$TMP/preexisting/adopted" 2>&1)"; rc=$?
assert_eq "0" "$rc" "a link already pointing at the source is adopted, not refused"
assert_contains "$out" "adopting it" "the adoption is announced"
assert_contains "$out" "--clear will now unlink it" "the new ownership is stated"
assert_contains "$(cat "$EX")" "/.claude/skills/adopted" "the adopted link joins the record"
assert_eq "$TMP/preexisting/adopted" "$(readlink "$SK/adopted")" "the adopted link still points where it did"

# A name that is taken by a link to something else is a genuine clash, and stays
# a refusal — adoption is only ever a no-op on disk.
make_skill "$TMP/preexisting/clashing"
make_skill "$TMP/elsewhere/clashing"
ln -sfn "$TMP/elsewhere/clashing" "$SK/clashing"
out="$("$ADD" "$TMP/preexisting/clashing" 2>&1)"; rc=$?
assert_eq "1" "$rc" "a link pointing somewhere else is still refused"
assert_contains "$out" "$TMP/elsewhere/clashing" "the refusal names what it actually points at"
assert_eq "$TMP/elsewhere/clashing" "$(readlink "$SK/clashing")" "the foreign link is left alone"
assert_lacks "$(cat "$EX")" "/.claude/skills/clashing" "the refused name is not recorded"

# Spelling the same directory through a symlinked parent is the same directory.
ln -sfn "$TMP/preexisting" "$TMP/preexisting-alias"
make_skill "$TMP/preexisting/aliased"
ln -sfn "$TMP/preexisting-alias/aliased" "$SK/aliased"
out="$("$ADD" "$TMP/preexisting/aliased" 2>&1)"; rc=$?
assert_eq "0" "$rc" "a link spelled through a symlinked parent is adopted"

echo "plugins"
# Two cached versions, only one of them installed: reading installPath must beat
# globbing the cache, which would be a coin toss between them.
make_skill "$TMP/plugincache/demo-1.0/skills/delta"
make_skill "$TMP/plugincache/demo-0.9/skills/stale"
cat > "$TMP/installed.json" <<EOF
{
  "version": 2,
  "plugins": {
    "demo@market":   [{ "installPath": "$TMP/plugincache/demo-1.0" }],
    "gone@market":   [{ "installPath": "$TMP/plugincache/absent" }],
    "twin@market-a": [{ "installPath": "$TMP/plugincache/demo-1.0" }],
    "twin@market-b": [{ "installPath": "$TMP/plugincache/demo-1.0" }]
  }
}
EOF
export CS_ADD_INSTALLED="$TMP/installed.json"

out="$("$ADD" +demo 2>&1)"
assert_contains "$out" "linked 1 skill(s): delta" "a +plugin links the installed version's skills"
assert_eq "yes" "$(is_link "$SK/delta")" "delta is linked"
assert_eq "no" "$(exists "$SK/stale")" "the stale cached version is not used"
assert_contains "$out" "no namespacing" "the loss of namespacing is stated"
assert_contains "$out" "hooks" "the unloaded hooks are stated"

out="$("$ADD" +twin 2>&1)"; rc=$?
assert_eq "1" "$rc" "an ambiguous plugin name fails"
assert_contains "$out" "ambiguous" "the ambiguity lists candidates"

out="$("$ADD" +gone 2>&1)"; rc=$?
assert_eq "1" "$rc" "a plugin whose install path is missing fails"
assert_contains "$out" "missing install path" "the failure says the path is gone"

out="$("$ADD" +demo@market 2>&1)"
assert_contains "$out" "delta" "a fully qualified plugin id also resolves"

cat > "$TMP/installed-multi.json" <<EOF
{ "version": 2, "plugins": { "both@market": [
    { "scope": "user",    "installPath": "$TMP/plugincache/demo-1.0" },
    { "scope": "project", "installPath": "$TMP/plugincache/demo-0.9" } ] } }
EOF
out="$(CS_ADD_INSTALLED="$TMP/installed-multi.json" "$ADD" +both 2>&1)"
assert_contains "$out" "several scopes" "a plugin installed at several scopes warns"
assert_eq "no" "$(exists "$SK/stale")" "the warning does not stop it using the first entry"

# Linking a plugin the user already has enabled produces a silent duplicate:
# the skills are present either way, so nothing visibly changes and the command
# looks broken. Say so instead.
echo '{"enabledPlugins":{"demo@market":true}}' > "$TMP/settings-on.json"
out="$(CS_ADD_SETTINGS="$TMP/settings-on.json" "$ADD" +demo 2>&1)"
assert_contains "$out" "already has these skills" "an already-enabled plugin warns about duplicates"
assert_contains "$out" "cs session" "the warning says where it is actually useful"

echo '{"enabledPlugins":{"other@market":true}}' > "$TMP/settings-off.json"
out="$(CS_ADD_SETTINGS="$TMP/settings-off.json" "$ADD" +demo 2>&1)"
assert_lacks "$out" "already has these skills" "a plugin that is not enabled does not warn"

echo "removal"
"$ADD" --remove beta >/dev/null 2>&1
assert_eq "no" "$(exists "$SK/beta")" "--remove unlinks"
assert_lacks "$(cat "$EX")" "/.claude/skills/beta" "--remove drops the exclude entry"
assert_eq "yes" "$(is_link "$SK/alpha")" "--remove leaves the others alone"

"$ADD" --remove alpha-expert >/dev/null 2>&1
assert_eq "no" "$(exists "$AG/alpha-expert.md")" "--remove reaches an agent by its bare name"

"$ADD" --clear >/dev/null 2>&1
assert_eq "no" "$(exists "$SK/alpha")" "--clear unlinks everything it added"
assert_eq "no" "$(exists "$SK/gamma")" "--clear reaches later additions too"
assert_eq "yes" "$(exists "$SK/committed-skill")" "--clear never touches the repo's own skills"
assert_eq "no" "$(exists "$AG/beta-expert.md")" "--clear unlinks agents as well"
assert_eq "no" "$(exists "$AG/lone-expert.md")" "--clear reaches every linked agent"
ex="$(cat "$EX")"
assert_lacks "$ex" "cs-add session skills" "--clear removes the marker block"
assert_contains "$ex" "*.log" "--clear preserves unrelated exclude content"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
