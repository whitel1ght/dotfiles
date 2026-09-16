#!/bin/bash
# Tests for bin/cs. No network and no real claude launch: every assertion runs
# against --show or a sourced function, with a fixture ~/.claude via CS_CLAUDE_DIR.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CS="$TEST_DIR/cs"
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

# Fixture ~/.claude: a settings.json carrying both the parts cs must preserve
# and the enabledPlugins it must drop, plus two installed plugins sharing a
# prefix so ambiguity can be exercised.
make_fixture_claude_dir() {
    local dir="$1"
    mkdir -p "$dir/plugins"
    cat > "$dir/settings.json" <<'EOF'
{
  "permissions": { "allow": ["Bash(echo:*)"], "defaultMode": "auto" },
  "hooks": { "PreToolUse": [] },
  "theme": "auto",
  "enabledPlugins": { "legacy@somewhere": true }
}
EOF
    cat > "$dir/plugins/installed_plugins.json" <<'EOF'
{
  "version": 2,
  "plugins": {
    "superpowers@claude-plugins-official": [],
    "frontend-design@claude-plugins-official": [],
    "dup@marketplace-a": [],
    "dup@marketplace-b": []
  }
}
EOF
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
make_fixture_claude_dir "$TMP/claude"
export CS_CLAUDE_DIR="$TMP/claude"

# Sourcing is safe: cs only runs main when executed directly.
# shellcheck source=/dev/null
source "$CS"

echo "resolve_plugin_id"
assert_eq "a@b" "$(resolve_plugin_id 'a@b' 2>/dev/null)" "a full id passes through untouched"
assert_eq "superpowers@claude-plugins-official" \
    "$(resolve_plugin_id 'superpowers' 2>/dev/null)" "a bare name resolves to its full id"
out="$(resolve_plugin_id 'nope' 2>&1)"; rc=$?
assert_eq "1" "$rc" "an unknown name fails"
assert_contains "$out" "No installed plugin" "an unknown name explains itself"
out="$(resolve_plugin_id 'dup' 2>&1)"; rc=$?
assert_eq "1" "$rc" "an ambiguous name fails rather than guessing"
assert_contains "$out" "ambiguous" "an ambiguous name lists the candidates"

echo "base_settings"
base="$(base_settings)"
assert_lacks "$base" "enabledPlugins" "enabledPlugins is stripped"
assert_contains "$base" "defaultMode" "permissions survive"
assert_contains "$base" "hooks" "hooks survive"

CS_CLAUDE_DIR="$TMP/absent" SETTINGS="$TMP/absent/settings.json" \
    assert_eq "{}" "$(SETTINGS="$TMP/absent/settings.json" base_settings)" \
    "a missing settings.json yields an empty object"

echo 'not json' > "$TMP/bad.json"
out="$(SETTINGS="$TMP/bad.json" base_settings 2>&1)"; rc=$?
assert_eq "1" "$rc" "invalid JSON fails loudly"

echo "build_settings"
built="$(build_settings '{"theme":"auto"}')"
assert_lacks "$built" "enabledPlugins" "no plugins means no enabledPlugins key"
built="$(build_settings '{"theme":"auto"}' 'a@b' 'c@d')"
assert_contains "$built" '"a@b":true' "a selected plugin is enabled"
assert_contains "$built" '"c@d":true' "a second selected plugin is enabled"
assert_contains "$built" '"theme":"auto"' "base keys survive the merge"

echo "argv assembly"
out="$("$CS" --show)"
assert_contains "$out" "--setting-sources" "the bare session drops user settings"
assert_contains "$out" "project,local" "only project and local sources are kept"
assert_lacks "$out" "--plugin-dir" "the bare session loads no plugin dirs"

out="$("$CS" --show --no-project)"
assert_contains "$out" "local" "--no-project still keeps the local source"
assert_lacks "$out" "project,local" "--no-project drops the project source"

out="$("$CS" --show +superpowers)"
assert_contains "$out" '"superpowers@claude-plugins-official":true' \
    "a +name argument reaches enabledPlugins"

mkdir -p "$TMP/bundle/.claude-plugin" "$TMP/bundle/skills"
echo '{"name":"bundle"}' > "$TMP/bundle/.claude-plugin/plugin.json"
out="$("$CS" --show "$TMP/bundle")"
assert_contains "$out" "--plugin-dir" "a directory argument becomes --plugin-dir"
assert_contains "$out" "$TMP/bundle" "the bundle path is passed through"

out="$(cd "$TMP" && "$CS" --show ./bundle)"
assert_contains "$out" "$TMP/bundle" "a relative path is made absolute"

out="$("$CS" --show -- --continue)"
assert_contains "$out" "--continue" "args after -- reach claude"

out="$("$CS" --show "$TMP/nonexistent" 2>&1)"; rc=$?
assert_eq "1" "$rc" "a missing directory fails"
assert_contains "$out" "Not a directory" "a missing directory says so"

echo "hygiene"
count_leftovers() {
    find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'cs-settings.*' 2>/dev/null | wc -l | tr -d ' '
}

before="$(count_leftovers)"
"$CS" --show >/dev/null
assert_eq "$before" "$(count_leftovers)" "--show leaves no settings file behind"

# The launch path is where cleanup actually runs, and it runs from an EXIT trap
# firing after main has returned. A settings path held in a main-local would be
# out of scope by then, which under `set -u` aborts the trap and leaks the file.
mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/claude" <<'EOF'
#!/bin/bash
echo "fake-claude $*"
EOF
chmod +x "$TMP/fakebin/claude"

before="$(count_leftovers)"
out="$(PATH="$TMP/fakebin:$PATH" "$CS" +superpowers 2>&1)"
assert_contains "$out" "fake-claude" "the launch path invokes claude"
assert_lacks "$out" "unbound variable" "cleanup runs without tripping set -u"
assert_eq "$before" "$(count_leftovers)" "a real launch leaves no settings file behind"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
