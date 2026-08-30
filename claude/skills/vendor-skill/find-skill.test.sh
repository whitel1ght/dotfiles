#!/bin/bash
# Tests for find-skill.sh. No network: fixtures are local git repos.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIND="$TEST_DIR/find-skill.sh"
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

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    case "$haystack" in
        *"$needle"*) fail "$label" "[$needle] unexpectedly present in [$haystack]" ;;
        *) pass "$label" ;;
    esac
}

# rc <cmd...> -> echoes the exit code
rc() { "$@" >/dev/null 2>&1; echo $?; }

# A repo with skills nested under categories, like mattpocock/skills.
make_nested_repo() {
    local dir="$1"
    mkdir -p "$dir/skills/engineering/tdd" \
             "$dir/skills/engineering/code-review" \
             "$dir/skills/productivity/grilling" \
             "$dir/docs"
    printf -- '---\nname: tdd\n---\n'         > "$dir/skills/engineering/tdd/SKILL.md"
    printf -- '---\nname: code-review\n---\n' > "$dir/skills/engineering/code-review/SKILL.md"
    printf -- '---\nname: grilling\n---\n'    > "$dir/skills/productivity/grilling/SKILL.md"
    printf 'not a skill\n'                    > "$dir/docs/README.md"
    git -C "$dir" init -q
    git -C "$dir" config user.email t@example.com
    git -C "$dir" config user.name T
    git -C "$dir" config uploadpack.allowFilter true
    git -C "$dir" add -A
    git -C "$dir" commit -qm fixture
}

# A repo whose root IS a single skill.
make_root_repo() {
    local dir="$1"
    mkdir -p "$dir"
    printf -- '---\nname: solo\n---\n' > "$dir/SKILL.md"
    git -C "$dir" init -q
    git -C "$dir" config user.email t@example.com
    git -C "$dir" config user.name T
    git -C "$dir" config uploadpack.allowFilter true
    git -C "$dir" add -A
    git -C "$dir" commit -qm fixture
}

# A repo with no skills at all.
make_empty_repo() {
    local dir="$1"
    mkdir -p "$dir"
    printf 'nothing here\n' > "$dir/README.md"
    git -C "$dir" init -q
    git -C "$dir" config user.email t@example.com
    git -C "$dir" config user.name T
    git -C "$dir" config uploadpack.allowFilter true
    git -C "$dir" add -A
    git -C "$dir" commit -qm fixture
}

ROOT="$(mktemp -d)"
make_nested_repo "$ROOT/nested"
make_root_repo "$ROOT/rootskill"
make_empty_repo "$ROOT/empty"
NESTED="file://$ROOT/nested"
ROOTSKILL="file://$ROOT/rootskill"
EMPTY="file://$ROOT/empty"

echo "== URL expansion =="

EXPANDED="$(bash -c "source '$FIND' >/dev/null 2>&1; expand_repo_url 'mattpocock/skills'" 2>/dev/null)"
assert_eq "https://github.com/mattpocock/skills.git" "$EXPANDED" \
    "owner/repo shorthand expands to a github https url"

EXPANDED="$(bash -c "source '$FIND' >/dev/null 2>&1; expand_repo_url 'https://gitlab.com/g/p.git'" 2>/dev/null)"
assert_eq "https://gitlab.com/g/p.git" "$EXPANDED" \
    "a full https url passes through untouched"

EXPANDED="$(bash -c "source '$FIND' >/dev/null 2>&1; expand_repo_url 'git@github.com:o/r.git'" 2>/dev/null)"
assert_eq "git@github.com:o/r.git" "$EXPANDED" \
    "an ssh remote passes through untouched"

EXPANDED="$(bash -c "source '$FIND' >/dev/null 2>&1; expand_repo_url 'file:///tmp/x'" 2>/dev/null)"
assert_eq "file:///tmp/x" "$EXPANDED" \
    "a file:// url passes through untouched"

echo "== --url mode (canonical url for manifest lookups) =="

OUT="$(bash "$FIND" --url mattpocock/skills 2>/dev/null)"
assert_eq "https://github.com/mattpocock/skills.git" "$OUT" \
    "--url prints the canonical url for a shorthand"
assert_eq "0" "$(rc bash "$FIND" --url mattpocock/skills)" "--url exits 0"
OUT="$(bash "$FIND" --url git@github.com:o/r.git 2>/dev/null)"
assert_eq "git@github.com:o/r.git" "$OUT" "--url passes an ssh remote through"
assert_eq "2" "$(rc bash "$FIND" --url)" "--url with no repo exits 2"

echo "== listing (no name given) =="

OUT="$(bash "$FIND" "$NESTED" 2>/dev/null)"
assert_contains "$OUT" "skills/engineering/tdd" "listing includes a nested skill path"
assert_contains "$OUT" "skills/productivity/grilling" "listing includes a second category"
assert_not_contains "$OUT" "SKILL.md" "listing prints directories, not SKILL.md paths"
assert_not_contains "$OUT" "docs" "listing excludes directories without a SKILL.md"
assert_eq "3" "$(printf '%s\n' "$OUT" | grep -c .)" "listing prints exactly the three skills"

OUT="$(bash "$FIND" "$ROOTSKILL" 2>/dev/null)"
assert_eq "." "$OUT" "a repo whose root is a skill lists as ."

echo "== matching a name =="

OUT="$(bash "$FIND" "$NESTED" tdd 2>/dev/null)"
assert_eq "skills/engineering/tdd" "$OUT" "exact basename match returns the one path"

OUT="$(bash "$FIND" "$NESTED" grill 2>/dev/null)"
assert_eq "skills/productivity/grilling" "$OUT" "substring falls back to a unique match"

OUT="$(bash "$FIND" "$NESTED" code 2>/dev/null)"
assert_eq "skills/engineering/code-review" "$OUT" "substring matching works mid-name"

# A name is a SKILL name, not a path fragment. 'engineering' is a directory in
# every one of these paths, but it is nobody's skill name.
assert_eq "1" "$(rc bash "$FIND" "$NESTED" engineering)" \
    "a path component is not a skill name"
assert_eq "1" "$(rc bash "$FIND" "$NESTED" skills)" \
    "the containing directory is not a skill name"

echo "== exact match wins over substring =="

mkdir -p "$ROOT/nested/skills/engineering/tdd-helper"
printf -- '---\nname: tdd-helper\n---\n' > "$ROOT/nested/skills/engineering/tdd-helper/SKILL.md"
git -C "$ROOT/nested" add -A && git -C "$ROOT/nested" commit -qm "add tdd-helper"
OUT="$(bash "$FIND" "$NESTED" tdd 2>/dev/null)"
assert_eq "skills/engineering/tdd" "$OUT" \
    "an exact basename match wins over a longer skill containing it"

# 'dd' matches both tdd and tdd-helper by basename, and neither exactly.
OUT="$(bash "$FIND" "$NESTED" dd 2>/dev/null)"
assert_eq "2" "$(printf '%s\n' "$OUT" | grep -c .)" "an ambiguous substring prints every match"
assert_contains "$OUT" "skills/engineering/tdd-helper" "ambiguous output includes the longer name"

echo "== exit codes =="

assert_eq "0" "$(rc bash "$FIND" "$NESTED" tdd)"   "a single match exits 0"
assert_eq "0" "$(rc bash "$FIND" "$NESTED")"        "a listing exits 0"
assert_eq "1" "$(rc bash "$FIND" "$NESTED" nosuch)" "no match exits 1"
assert_eq "1" "$(rc bash "$FIND" "$EMPTY")"         "a repo with no skills exits 1"
assert_eq "2" "$(rc bash "$FIND" "file://$ROOT/does-not-exist")" "an unreachable repo exits 2"
assert_eq "2" "$(rc bash "$FIND")"                  "a missing repo argument exits 2"

echo "== servers without partial-clone support =="

# git only warns ("filtering not recognized by server, ignoring") and clones in
# full — it does not fail — so there is no fallback path to test. What matters is
# that the warning on stderr does not derail us and ls-tree still works.
git -C "$ROOT/nested" config uploadpack.allowFilter false
OUT="$(bash "$FIND" "$NESTED" tdd 2>/dev/null)"
assert_eq "skills/engineering/tdd" "$OUT" \
    "works against a server that refuses partial clone"
assert_eq "0" "$(rc bash "$FIND" "$NESTED" tdd)" \
    "a refused --filter does not change the exit code"
git -C "$ROOT/nested" config uploadpack.allowFilter true

echo "== repo root resolution through a symlink =="

REAL_ROOT="$(cd "$TEST_DIR/../../.." && pwd -P)"
LINKED="$ROOT/linked-find-skill.sh"
ln -s "$FIND" "$LINKED"
RESOLVED="$(bash -c "source '$LINKED' >/dev/null 2>&1; repo_root" 2>/dev/null)"
assert_eq "$REAL_ROOT" "$RESOLVED" \
    "repo_root resolves to the real dotfiles repo when invoked through a symlink"

RESOLVED="$(bash -c "source '$FIND' >/dev/null 2>&1; repo_root" 2>/dev/null)"
assert_eq "$REAL_ROOT" "$RESOLVED" \
    "repo_root resolves correctly when invoked directly"

echo
echo "passed: $PASS  failed: $FAIL"
rm -rf "$ROOT"
[ "$FAIL" -eq 0 ]
