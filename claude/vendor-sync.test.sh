#!/bin/bash
# Tests for vendor-sync.sh. No network: fixtures are local git repos.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC="$TEST_DIR/vendor-sync.sh"
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

# assert_fails <expected-exit> <label> -- <cmd...>
assert_fails() {
    local expected="$1" label="$2"; shift 3
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    if [ "$rc" = "$expected" ]; then pass "$label"
    else fail "$label" "expected exit $expected got $rc; output: $out"; fi
}

# Build a fixture upstream repo with two skills and a LICENSE.
# uploadpack.allowAnySHA1InWant is required so the sync can fetch a bare SHA.
make_fixture_repo() {
    local dir="$1"
    mkdir -p "$dir/skills/productivity/grilling" "$dir/skills/engineering/wayfinder"
    printf -- '---\nname: grilling\ndescription: Fixture grilling skill.\n---\n# grilling\n' \
        > "$dir/skills/productivity/grilling/SKILL.md"
    printf -- '---\nname: wayfinder\ndescription: Fixture wayfinder skill.\n---\n# wayfinder\n' \
        > "$dir/skills/engineering/wayfinder/SKILL.md"
    printf 'MIT License\n' > "$dir/LICENSE"
    git -C "$dir" init -q
    git -C "$dir" config user.email test@example.com
    git -C "$dir" config user.name Test
    git -C "$dir" config uploadpack.allowAnySHA1InWant true
    git -C "$dir" add -A
    git -C "$dir" commit -qm "fixture"
}

# Fresh sandbox for one test case. Sets ROOT, UPSTREAM, and UPSTREAM_URL.
new_sandbox() {
    ROOT="$(mktemp -d)"
    UPSTREAM="$ROOT/upstream"
    # file:// forces the git transport so --depth is honoured.
    UPSTREAM_URL="file://$UPSTREAM"
    make_fixture_repo "$UPSTREAM"
    mkdir -p "$ROOT/dotfiles"
}

write_manifest() { printf '%s\n' "$1" > "$ROOT/dotfiles/vendor.json"; }

run_sync() { VENDOR_ROOT="$ROOT/dotfiles" bash "$SYNC" "$@"; }

echo "== Task 1: manifest validation =="

new_sandbox
write_manifest '{ not json'
assert_fails 1 "malformed manifest is a hard error" -- run_sync

new_sandbox
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "dup", "repo": "$UPSTREAM_URL", "skills": [
  "skills/productivity/grilling", "skills/engineering/grilling" ] } ] }
JSON
)"
assert_fails 1 "basename collision within a source is a hard error" -- run_sync

new_sandbox
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fix", "repo": "$UPSTREAM_URL", "skills": [] } ] }
JSON
)"
assert_fails 1 "empty skills list is a hard error" -- run_sync

echo
echo "== Task 2: ref resolution and skip =="

new_sandbox
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fix", "repo": "$UPSTREAM_URL", "ref": "HEAD",
  "skills": [ "skills/productivity/grilling" ] } ] }
JSON
)"
EXPECTED_SHA="$(git -C "$UPSTREAM" rev-parse HEAD)"
ACTUAL_SHA="$(VENDOR_ROOT="$ROOT/dotfiles" bash -c \
    "source '$SYNC' >/dev/null 2>&1; resolve_ref '$UPSTREAM_URL' HEAD" 2>/dev/null)"
assert_eq "$EXPECTED_SHA" "$ACTUAL_SHA" "resolve_ref returns upstream HEAD sha"

# Pre-seed a lockfile at the current sha; sync must report a skip.
mkdir -p "$ROOT/dotfiles/vendor/fix/skills/grilling"
touch "$ROOT/dotfiles/vendor/fix/skills/grilling/SKILL.md"
cat > "$ROOT/dotfiles/vendor.lock.json" <<JSON
{ "sources": { "fix": { "repo": "$UPSTREAM_URL", "ref": "HEAD",
  "resolved": "$EXPECTED_SHA", "fetchedAt": "2026-01-01T00:00:00Z",
  "license": "LICENSE",
  "skills": { "grilling": "skills/productivity/grilling" } } } }
JSON
OUT="$(run_sync 2>&1)"
assert_contains "$OUT" "up to date" "unchanged sha is skipped"

echo
echo "== Task 3: fetch and replace =="

new_sandbox
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fix", "repo": "$UPSTREAM_URL", "ref": "HEAD",
  "skills": [ "skills/productivity/grilling", "skills/engineering/wayfinder" ] } ] }
JSON
)"
run_sync >/dev/null 2>&1
assert_eq "yes" \
    "$([ -f "$ROOT/dotfiles/vendor/fix/skills/grilling/SKILL.md" ] && echo yes || echo no)" \
    "fresh fetch places grilling at its basename"
assert_eq "yes" \
    "$([ -f "$ROOT/dotfiles/vendor/fix/skills/wayfinder/SKILL.md" ] && echo yes || echo no)" \
    "fresh fetch places wayfinder at its basename"
assert_contains "$(cat "$ROOT/dotfiles/vendor/fix/skills/grilling/SKILL.md")" \
    "name: grilling" "vendored SKILL.md is byte-exact upstream content"

# Upstream deletes a file inside a vendored skill; sync must propagate it.
echo "extra" > "$UPSTREAM/skills/productivity/grilling/EXTRA.md"
git -C "$UPSTREAM" add -A && git -C "$UPSTREAM" commit -qm "add extra"
run_sync >/dev/null 2>&1
assert_eq "yes" \
    "$([ -f "$ROOT/dotfiles/vendor/fix/skills/grilling/EXTRA.md" ] && echo yes || echo no)" \
    "added upstream file appears"
git -C "$UPSTREAM" rm -q "skills/productivity/grilling/EXTRA.md"
git -C "$UPSTREAM" commit -qm "remove extra"
run_sync >/dev/null 2>&1
assert_eq "no" \
    "$([ -f "$ROOT/dotfiles/vendor/fix/skills/grilling/EXTRA.md" ] && echo yes || echo no)" \
    "deleted upstream file is removed (wholesale replacement)"

# A path with no SKILL.md must abort that source and leave prior content intact.
# We seed a previously-vendored skill not in the failing manifest to guard
# that an unsafe wipe-first variant would lose it, thus guarding the
# staging-before-swap property regardless of path order.
new_sandbox
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fix", "repo": "$UPSTREAM_URL", "ref": "HEAD",
  "skills": [ "skills/productivity/grilling", "skills/engineering/wayfinder" ] } ] }
JSON
)"
run_sync >/dev/null 2>&1
# Now remove wayfinder from the manifest but add a broken path.
mkdir -p "$UPSTREAM/skills/broken" && echo hi > "$UPSTREAM/skills/broken/notes.md"
git -C "$UPSTREAM" add -A && git -C "$UPSTREAM" commit -qm "add broken"
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fix", "repo": "$UPSTREAM_URL", "ref": "HEAD",
  "skills": [ "skills/productivity/grilling", "skills/broken" ] } ] }
JSON
)"
assert_fails 2 "path without SKILL.md fails the source" -- run_sync
assert_eq "yes" \
    "$([ -f "$ROOT/dotfiles/vendor/fix/skills/grilling/SKILL.md" ] && echo yes || echo no)" \
    "failed source leaves grilling intact"
assert_eq "yes" \
    "$([ -f "$ROOT/dotfiles/vendor/fix/skills/wayfinder/SKILL.md" ] && echo yes || echo no)" \
    "failed source leaves wayfinder intact (guards wholesale replacement staging)"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
