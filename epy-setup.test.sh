#!/bin/bash
# Tests for epy-setup.sh. Never touches the real epy install: pipx and brew are
# stubbed through their seams, and the patch is applied to a throwaway copy of
# the epy sources pointed at by EPY_SITE_PACKAGES.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/epy-setup.sh"
PATCH="$TEST_DIR/epy/vertical-padding.patch"
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

# The real sources the patch was generated against. Copied per sandbox so each
# test starts from pristine files.
EPY_PKG="$(
    "$HOME/Library/Application Support/pipx/venvs/epy-reader/bin/python" -c \
        'import epy_reader, os; print(os.path.dirname(os.path.dirname(epy_reader.__file__)))' \
        2>/dev/null
)"

if [ -z "$EPY_PKG" ] || [ ! -d "$EPY_PKG/epy_reader" ]; then
    echo "SKIP: epy-reader is not installed; run ./epy-setup.sh install first"
    exit 0
fi

# Fresh sandbox with pipx/brew stubs. Both log their invocations, and the epy
# sources are copied in with the patch reversed so they start unpatched.
new_sandbox() {
    ROOT="$(mktemp -d)"
    CALL_LOG="$ROOT/calls.log"
    : > "$CALL_LOG"

    mkdir -p "$ROOT/site/epy_reader" "$ROOT/py/bin"
    cp "$EPY_PKG"/epy_reader/*.py "$ROOT/site/epy_reader/"
    # The installed copy may already be patched; normalise to pristine.
    patch -d "$ROOT/site" -p1 -R -sf < "$PATCH" >/dev/null 2>&1

    touch "$ROOT/py/bin/python3.12"
    chmod +x "$ROOT/py/bin/python3.12"

    cat > "$ROOT/pipx" <<'STUB'
#!/bin/bash
echo "pipx $*" >> "$CALL_LOG"
case "$1" in
    list)        [ "${STUB_INSTALLED:-1}" = "1" ] && echo "epy-reader 2023.6.11" ;;
    environment) echo "$STUB_VENVS" ;;
    install)     echo "installed" ;;
esac
exit 0
STUB
    chmod +x "$ROOT/pipx"

    cat > "$ROOT/brew" <<'STUB'
#!/bin/bash
echo "brew $*" >> "$CALL_LOG"
[ "$1" = "--prefix" ] && echo "$STUB_PY_PREFIX"
exit 0
STUB
    chmod +x "$ROOT/brew"
}

run() {
    CALL_LOG="$CALL_LOG" \
    STUB_INSTALLED="${STUB_INSTALLED:-1}" \
    STUB_VENVS="$ROOT/venvs" \
    STUB_PY_PREFIX="${STUB_PY_PREFIX:-$ROOT/py}" \
    PIPX="$ROOT/pipx" \
    BREW="$ROOT/brew" \
    PATCH_FILE="$PATCH" \
    EPY_SITE_PACKAGES="$ROOT/site" \
        "$SCRIPT" "$@" 2>&1
}

calls() { cat "$CALL_LOG"; }

# Is the sandbox copy patched? Reverse-dry-run succeeds only when it is.
is_patched() {
    patch -d "$ROOT/site" -p1 -R --dry-run -sf < "$PATCH" >/dev/null 2>&1
}

echo "epy-setup.sh"

# --- install applies the patch -----------------------------------------------
new_sandbox
out="$(run install)"
assert_contains "$out" "Applied vertical padding patch" \
    "install applies the patch to an unpatched tree"
if is_patched; then pass "sources are actually patched afterwards"
else fail "sources are actually patched afterwards" "reverse dry-run failed"; fi
assert_contains "$out" "already installed" \
    "install skips pipx install when the package is present"
assert_lacks "$(calls)" "pipx install" \
    "install does not reinstall an already-present package"

# --- install is idempotent ---------------------------------------------------
out="$(run install)"
assert_contains "$out" "already applied" \
    "a second install reports the patch as already applied"
if is_patched; then pass "second install leaves the tree patched"
else fail "second install leaves the tree patched" "tree changed"; fi

# --- default subcommand ------------------------------------------------------
new_sandbox
out="$(run)"
assert_contains "$out" "Applied vertical padding patch" \
    "no argument defaults to install"

# --- missing package triggers a pinned pipx install --------------------------
new_sandbox
STUB_INSTALLED=0
out="$(run install)"
unset STUB_INSTALLED
assert_contains "$(calls)" "pipx install --python $ROOT/py/bin/python3.12 epy-reader" \
    "install pins pipx to the Homebrew python@3.12"
assert_contains "$(calls)" "brew --prefix python@3.12" \
    "the interpreter path comes from brew, not a hardcoded prefix"

# --- missing python formula --------------------------------------------------
new_sandbox
STUB_INSTALLED=0
STUB_PY_PREFIX="$ROOT/nonexistent"
out="$(run install)"
rc=$?
unset STUB_INSTALLED STUB_PY_PREFIX
assert_eq "1" "$rc" "a missing python@3.12 fails rather than installing on 3.13+"
assert_contains "$out" "brew-install.sh" \
    "the failure points at brew-install.sh"

# --- a stale patch warns instead of half-applying ----------------------------
new_sandbox
echo "unexpected content" > "$ROOT/site/epy_reader/board.py"
out="$(run install)"
rc=$?
assert_eq "1" "$rc" "a patch that no longer matches exits non-zero"
assert_contains "$out" "does not match" \
    "a stale patch is reported as such"
assert_contains "$out" "refresh" \
    "the stale-patch message says what to do"

# --- status ------------------------------------------------------------------
new_sandbox
out="$(run status)"
assert_contains "$out" "NOT applied" \
    "status reports an unpatched tree"
run install >/dev/null
out="$(run status)"
assert_contains "$out" "patch: applied" \
    "status reports a patched tree"

new_sandbox
STUB_INSTALLED=0
out="$(run status)"
unset STUB_INSTALLED
assert_contains "$out" "not installed" \
    "status reports a missing package without failing"

# --- argument handling -------------------------------------------------------
new_sandbox
out="$(run bogus)"
rc=$?
assert_eq "2" "$rc" "unknown subcommand exits 2"
assert_contains "$out" "Usage" \
    "unknown subcommand prints usage"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
