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

assert_lacks() {
    local haystack="$1" needle="$2" label="$3"
    case "$haystack" in
        *"$needle"*) fail "$label" "[$needle] unexpectedly found in [$haystack]" ;;
        *) pass "$label" ;;
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

exists() { [ -e "$1" ] && echo yes || echo no; }
is_file() { [ -f "$1" ] && echo yes || echo no; }
is_dir() { [ -d "$1" ] && echo yes || echo no; }
is_link() { [ -L "$1" ] && echo yes || echo no; }

# Build a fixture upstream repo with two skills and a LICENSE, on `main`.
# uploadpack.allowAnySHA1InWant is required so the sync can fetch a bare SHA.
make_fixture_repo() {
    local dir="$1"
    mkdir -p "$dir/skills/productivity/grilling" "$dir/skills/engineering/wayfinder"
    printf -- '---\nname: grilling\ndescription: Fixture grilling skill.\n---\n# grilling\n' \
        > "$dir/skills/productivity/grilling/SKILL.md"
    printf -- '---\nname: wayfinder\ndescription: Fixture wayfinder skill.\n---\n# wayfinder\n' \
        > "$dir/skills/engineering/wayfinder/SKILL.md"
    printf 'MIT License\n\nCopyright (c) 2026 Fixture\n' > "$dir/LICENSE"
    git -C "$dir" init -q
    # Pin the default branch name so ref tests do not depend on init.defaultBranch.
    git -C "$dir" symbolic-ref HEAD refs/heads/main
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

# Call one function from vendor-sync.sh directly, without running main().
call_sync_fn() {
    VENDOR_ROOT="$ROOT/dotfiles" bash -c \
        'source "$1" >/dev/null 2>&1; shift; "$@"' _ "$SYNC" "$@"
}

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

# A name starting with `-` is read as an option by anything it is passed to.
new_sandbox
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "-rf", "repo": "$UPSTREAM_URL",
  "skills": [ "skills/productivity/grilling" ] } ] }
JSON
)"
assert_fails 1 "source name starting with a dash is a hard error" -- run_sync

new_sandbox
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "bad name", "repo": "$UPSTREAM_URL",
  "skills": [ "skills/productivity/grilling" ] } ] }
JSON
)"
assert_fails 1 "source name with an invalid character is a hard error" -- run_sync

new_sandbox
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "a/b", "repo": "$UPSTREAM_URL",
  "skills": [ "skills/productivity/grilling" ] } ] }
JSON
)"
assert_fails 1 "source name containing a slash is a hard error" -- run_sync

echo
echo "== Task 2: ref resolution and skip =="

new_sandbox
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fix", "repo": "$UPSTREAM_URL", "ref": "HEAD",
  "skills": [ "skills/productivity/grilling" ] } ] }
JSON
)"
EXPECTED_SHA="$(git -C "$UPSTREAM" rev-parse HEAD)"
assert_eq "$EXPECTED_SHA" "$(call_sync_fn resolve_ref "$UPSTREAM_URL" HEAD)" \
    "resolve_ref returns upstream HEAD sha"
assert_eq "$EXPECTED_SHA" "$(call_sync_fn resolve_ref "$UPSTREAM_URL")" \
    "resolve_ref defaults to HEAD when no ref is given"
assert_fails 1 "resolve_ref fails on a missing ref" -- \
    call_sync_fn resolve_ref "$UPSTREAM_URL" nosuchref

# `git ls-remote <repo> main` tail-matches whole path components, so it also
# returns refs/heads/changeset-release/main — which sorts first.
new_sandbox
git -C "$UPSTREAM" checkout -q -b changeset-release/main
echo bot > "$UPSTREAM/BOT.md"
git -C "$UPSTREAM" add -A && git -C "$UPSTREAM" commit -qm "bot release"
git -C "$UPSTREAM" checkout -q main
MAIN_SHA="$(git -C "$UPSTREAM" rev-parse main)"
SIBLING_SHA="$(git -C "$UPSTREAM" rev-parse changeset-release/main)"
assert_eq "changeset-release/main" \
    "$(git ls-remote "$UPSTREAM_URL" main | head -n1 | sed 's|.*refs/heads/||')" \
    "fixture reproduces the ambiguous-sibling ordering"
assert_eq "$MAIN_SHA" "$(call_sync_fn resolve_ref "$UPSTREAM_URL" main)" \
    "resolve_ref picks refs/heads/main over an ambiguous sibling branch"
assert_eq "$SIBLING_SHA" "$(call_sync_fn resolve_ref "$UPSTREAM_URL" changeset-release/main)" \
    "resolve_ref still addresses a ref containing a slash"

# An annotated tag's own ls-remote line carries the tag object id, not a commit.
git -C "$UPSTREAM" tag -a v1.0.0 -m "release" main
TAG_OBJECT="$(git -C "$UPSTREAM" rev-parse v1.0.0)"
TAG_COMMIT="$(git -C "$UPSTREAM" rev-parse 'v1.0.0^{commit}')"
assert_lacks "$TAG_OBJECT" "$TAG_COMMIT" \
    "fixture annotated tag object differs from its commit"
assert_eq "$TAG_COMMIT" "$(call_sync_fn resolve_ref "$UPSTREAM_URL" v1.0.0)" \
    "annotated tag resolves to its commit, not the tag object"
git -C "$UPSTREAM" tag light main
assert_eq "$MAIN_SHA" "$(call_sync_fn resolve_ref "$UPSTREAM_URL" light)" \
    "lightweight tag resolves to its commit"

# End to end: the shipped lockfile pinned the sibling branch under ref "main".
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fix", "repo": "$UPSTREAM_URL", "ref": "main",
  "skills": [ "skills/productivity/grilling" ] } ] }
JSON
)"
run_sync >/dev/null 2>&1
assert_eq "$MAIN_SHA" "$(jq -r '.sources.fix.resolved' "$ROOT/dotfiles/vendor.lock.json")" \
    "sync pins the exact branch, not an ambiguous sibling"

# An unchanged sha must not re-fetch. Timestamps are pinned to a known past
# value first, so any rewrite shows up as a changed mtime.
new_sandbox
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fix", "repo": "$UPSTREAM_URL", "ref": "HEAD",
  "skills": [ "skills/productivity/grilling" ] } ] }
JSON
)"
run_sync >/dev/null 2>&1
SKIP_PJ="$ROOT/dotfiles/vendor/fix/.claude-plugin/plugin.json"
SKIP_SKILL="$ROOT/dotfiles/vendor/fix/skills/grilling/SKILL.md"
SKIP_README="$ROOT/dotfiles/vendor/fix/README.md"
find "$ROOT/dotfiles/vendor/fix" -exec touch -t 202001010000 {} +
BEFORE_PJ="$(stat -f %m "$SKIP_PJ")"
BEFORE_SKILL="$(stat -f %m "$SKIP_SKILL")"
BEFORE_README="$(stat -f %m "$SKIP_README")"
OUT="$(run_sync 2>&1)"
assert_contains "$OUT" "up to date" "unchanged sha is skipped"
assert_eq "$BEFORE_PJ" "$(stat -f %m "$SKIP_PJ")" \
    "skip leaves plugin.json untouched (mtime)"
assert_eq "$BEFORE_SKILL" "$(stat -f %m "$SKIP_SKILL")" \
    "skip leaves the vendored SKILL.md untouched (mtime)"
assert_eq "$BEFORE_README" "$(stat -f %m "$SKIP_README")" \
    "skip leaves the generated README untouched (mtime)"

echo
echo "== Task 3: fetch and replace =="

new_sandbox
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fix", "repo": "$UPSTREAM_URL", "ref": "HEAD",
  "skills": [ "skills/productivity/grilling", "skills/engineering/wayfinder" ] } ] }
JSON
)"
run_sync >/dev/null 2>&1
assert_eq "yes" "$(is_file "$ROOT/dotfiles/vendor/fix/skills/grilling/SKILL.md")" \
    "fresh fetch places grilling at its basename"
assert_eq "yes" "$(is_file "$ROOT/dotfiles/vendor/fix/skills/wayfinder/SKILL.md")" \
    "fresh fetch places wayfinder at its basename"

# Byte-exactness: compare against what upstream actually holds at that commit.
ARCHIVE="$ROOT/archive"
mkdir -p "$ARCHIVE"
git -C "$UPSTREAM" archive HEAD skills/productivity/grilling skills/engineering/wayfinder \
    | tar -x -C "$ARCHIVE"
assert_eq "" \
    "$(diff -r "$ARCHIVE/skills/productivity/grilling" \
              "$ROOT/dotfiles/vendor/fix/skills/grilling" 2>&1)" \
    "vendored SKILL.md is byte-exact upstream content"
assert_eq "" \
    "$(diff -r "$ARCHIVE/skills/engineering/wayfinder" \
              "$ROOT/dotfiles/vendor/fix/skills/wayfinder" 2>&1)" \
    "vendored wayfinder tree is byte-exact upstream content"

# Upstream deletes a file inside a vendored skill; sync must propagate it.
echo "extra" > "$UPSTREAM/skills/productivity/grilling/EXTRA.md"
git -C "$UPSTREAM" add -A && git -C "$UPSTREAM" commit -qm "add extra"
run_sync >/dev/null 2>&1
assert_eq "yes" "$(is_file "$ROOT/dotfiles/vendor/fix/skills/grilling/EXTRA.md")" \
    "added upstream file appears"
git -C "$UPSTREAM" rm -q "skills/productivity/grilling/EXTRA.md"
git -C "$UPSTREAM" commit -qm "remove extra"
run_sync >/dev/null 2>&1
assert_eq "no" "$(is_file "$ROOT/dotfiles/vendor/fix/skills/grilling/EXTRA.md")" \
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
assert_eq "yes" "$(is_file "$ROOT/dotfiles/vendor/fix/skills/grilling/SKILL.md")" \
    "failed source leaves grilling intact"
assert_eq "yes" "$(is_file "$ROOT/dotfiles/vendor/fix/skills/wayfinder/SKILL.md")" \
    "failed source leaves wayfinder intact (guards wholesale replacement staging)"

# A first-ever failure must not leave an empty wrapper for install.sh to link.
new_sandbox
mkdir -p "$UPSTREAM/skills/broken" && echo hi > "$UPSTREAM/skills/broken/notes.md"
git -C "$UPSTREAM" add -A && git -C "$UPSTREAM" commit -qm "add broken"
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fix", "repo": "$UPSTREAM_URL", "ref": "HEAD",
  "skills": [ "skills/broken" ] } ] }
JSON
)"
assert_fails 2 "first-ever sync of a broken path fails the source" -- run_sync
assert_eq "no" "$(exists "$ROOT/dotfiles/vendor/fix")" \
    "a first-ever failed sync leaves no empty wrapper behind"

# Symlinks are copied verbatim by `cp -R`, so a hostile upstream could commit a
# link to an arbitrary path into this public repo. Refuse the tree instead.
new_sandbox
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fix", "repo": "$UPSTREAM_URL", "ref": "HEAD",
  "skills": [ "skills/productivity/grilling" ] } ] }
JSON
)"
run_sync >/dev/null 2>&1
ln -s /etc/passwd "$UPSTREAM/skills/productivity/grilling/leak.md"
ln -s ../../../../.. "$UPSTREAM/skills/productivity/grilling/escape"
git -C "$UPSTREAM" add -A && git -C "$UPSTREAM" commit -qm "add symlinks"
assert_fails 2 "symlink in a fetched tree fails the source" -- run_sync
assert_eq "no" "$(is_link "$ROOT/dotfiles/vendor/fix/skills/grilling/leak.md")" \
    "symlink from upstream is not vendored"
assert_eq "yes" "$(is_file "$ROOT/dotfiles/vendor/fix/skills/grilling/SKILL.md")" \
    "refused tree leaves the previously vendored copy intact"

echo
echo "== Task 4: generated artefacts =="

new_sandbox
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fix", "repo": "$UPSTREAM_URL", "ref": "HEAD",
  "skills": [ "skills/productivity/grilling", "skills/engineering/wayfinder" ] } ] }
JSON
)"
run_sync >/dev/null 2>&1
SHA="$(git -C "$UPSTREAM" rev-parse HEAD)"
PJ="$ROOT/dotfiles/vendor/fix/.claude-plugin/plugin.json"
LOCK="$ROOT/dotfiles/vendor.lock.json"
assert_eq "fix" "$(jq -r .name "$PJ")" "plugin.json name is the source name"
assert_eq "./skills/grilling ./skills/wayfinder" \
    "$(jq -r '.skills | sort | join(" ")' "$PJ")" \
    "plugin.json lists exactly the manifest skills"
assert_eq "0.0.0+${SHA:0:7}" "$(jq -r .version "$PJ")" \
    "plugin.json version carries the resolved sha"

assert_eq "$(cat "$UPSTREAM/LICENSE")" \
    "$(cat "$ROOT/dotfiles/vendor/fix/UPSTREAM-LICENSE" 2>&1)" \
    "upstream licence is copied for attribution"

README_TXT="$(cat "$ROOT/dotfiles/vendor/fix/README.md")"
assert_contains "$README_TXT" "do not edit by hand" \
    "generated README carries the managed-file note"
assert_contains "$README_TXT" "| Source | \`$UPSTREAM_URL\` |" \
    "generated README attributes the upstream repo"
assert_contains "$README_TXT" "| Ref | \`HEAD\` |" \
    "generated README records the requested ref"
assert_contains "$README_TXT" "| Commit | \`$SHA\` |" \
    "generated README records the resolved commit"
assert_contains "$README_TXT" "| Licence | LICENSE (see \`UPSTREAM-LICENSE\`) |" \
    "generated README records the licence and points at the copy"

assert_eq "$SHA" "$(jq -r '.sources.fix.resolved' "$LOCK")" "lockfile records the sha"
assert_eq "LICENSE" "$(jq -r '.sources.fix.license' "$LOCK")" "lockfile records the licence file"
assert_eq "skills/productivity/grilling" \
    "$(jq -r '.sources.fix.skills.grilling' "$LOCK")" \
    "lockfile maps basename to upstream path"
assert_eq "644" "$(stat -f %Lp "$LOCK")" "lockfile stays world-readable"

# A wrapper whose generated metadata went missing must be repaired, not skipped.
rm -f "$PJ"
OUT="$(run_sync 2>&1)"
assert_eq "yes" "$(is_file "$PJ")" \
    "a wrapper missing plugin.json is regenerated on the next sync"

# Dropping a skill from the manifest must re-sync despite an unchanged sha.
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fix", "repo": "$UPSTREAM_URL", "ref": "HEAD",
  "skills": [ "skills/productivity/grilling" ] } ] }
JSON
)"
run_sync >/dev/null 2>&1
assert_eq "no" "$(is_dir "$ROOT/dotfiles/vendor/fix/skills/wayfinder")" \
    "removing a skill from the manifest removes it from the wrapper"

# A licence deleted upstream must not leave a stale copy the README points at.
new_sandbox
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fix", "repo": "$UPSTREAM_URL", "ref": "HEAD",
  "skills": [ "skills/productivity/grilling" ] } ] }
JSON
)"
run_sync >/dev/null 2>&1
git -C "$UPSTREAM" rm -q LICENSE && git -C "$UPSTREAM" commit -qm "drop licence"
run_sync >/dev/null 2>&1
assert_eq "no" "$(is_file "$ROOT/dotfiles/vendor/fix/UPSTREAM-LICENSE")" \
    "a licence removed upstream removes the stale UPSTREAM-LICENSE"
assert_lacks "$(cat "$ROOT/dotfiles/vendor/fix/README.md")" "UPSTREAM-LICENSE" \
    "README drops the licence pointer when upstream ships no licence"

echo
echo "== Task 5: prune and failure semantics =="

new_sandbox
write_manifest "$(cat <<JSON
{ "sources": [
  { "name": "keep", "repo": "$UPSTREAM_URL", "ref": "HEAD",
    "skills": [ "skills/productivity/grilling" ] },
  { "name": "drop", "repo": "$UPSTREAM_URL", "ref": "HEAD",
    "skills": [ "skills/engineering/wayfinder" ] } ] }
JSON
)"
run_sync >/dev/null 2>&1
LOCK="$ROOT/dotfiles/vendor.lock.json"
assert_eq "yes" "$(is_dir "$ROOT/dotfiles/vendor/drop")" "both wrappers created"
assert_eq "$(git -C "$UPSTREAM" rev-parse HEAD)" \
    "$(jq -r '.sources.keep.resolved // "null"' "$LOCK")" \
    "writing the second source's lock entry keeps the first"

write_manifest "$(cat <<JSON
{ "sources": [ { "name": "keep", "repo": "$UPSTREAM_URL", "ref": "HEAD",
  "skills": [ "skills/productivity/grilling" ] } ] }
JSON
)"
run_sync >/dev/null 2>&1
assert_eq "no" "$(is_dir "$ROOT/dotfiles/vendor/drop")" \
    "removed source is pruned from vendor/"
assert_eq "yes" "$(is_dir "$ROOT/dotfiles/vendor/keep")" \
    "remaining source survives prune"
assert_eq "null" "$(jq -r '.sources.drop // "null"' "$LOCK")" \
    "removed source is pruned from the lockfile"

# prune matches on-disk names against the manifest. The name is data: it must
# not be read as a grep option, nor as a regex that shadows a different wrapper.
new_sandbox
mkdir -p "$ROOT/dotfiles/vendor/-rf" && touch "$ROOT/dotfiles/vendor/-rf/marker"
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "-rf", "repo": "$UPSTREAM_URL",
  "skills": [ "skills/productivity/grilling" ] } ] }
JSON
)"
call_sync_fn prune_removed >/dev/null 2>&1
assert_eq "yes" "$(is_file "$ROOT/dotfiles/vendor/-rf/marker")" \
    "prune keeps a manifest source whose name starts with a dash"

# The stale on-disk name is the pattern: `foo.bar` regex-matches the manifest
# line `fooxbar`, so an unescaped grep would keep the orphaned wrapper.
new_sandbox
mkdir -p "$ROOT/dotfiles/vendor/foo.bar" && touch "$ROOT/dotfiles/vendor/foo.bar/marker"
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fooxbar", "repo": "$UPSTREAM_URL",
  "skills": [ "skills/productivity/grilling" ] } ] }
JSON
)"
call_sync_fn prune_removed >/dev/null 2>&1
assert_eq "no" "$(is_dir "$ROOT/dotfiles/vendor/foo.bar")" \
    "prune removes a stale wrapper that a metacharacter name would shadow"

# Unreachable remote: keep the tree, exit 2, do not prune.
new_sandbox
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fix", "repo": "$UPSTREAM_URL", "ref": "HEAD",
  "skills": [ "skills/productivity/grilling" ] } ] }
JSON
)"
run_sync >/dev/null 2>&1
write_manifest "$(cat <<JSON
{ "sources": [ { "name": "fix", "repo": "file:///nonexistent/repo.git", "ref": "HEAD",
  "skills": [ "skills/productivity/grilling" ] } ] }
JSON
)"
assert_fails 2 "unreachable remote exits 2" -- run_sync
assert_eq "yes" "$(is_file "$ROOT/dotfiles/vendor/fix/skills/grilling/SKILL.md")" \
    "unreachable remote leaves committed copy intact"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
