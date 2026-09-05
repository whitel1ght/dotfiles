#!/bin/bash
# Tests for reddittui-setup.sh. Never touches the real install and never hits
# the network: a fake release tree is served over file:// through the
# REDDITTUI_BASE_URL seam, and the binary is installed into a throwaway
# REDDITTUI_BIN_DIR.
#
# The checksum guard is the reason this file exists. Pulling a prebuilt binary
# instead of building one puts the whole trust of the install on that one
# comparison, so the tests below assert not just that a bad download reports an
# error but that nothing lands in the bin directory when it does.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/reddittui-setup.sh"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    case "$haystack" in
        *"$needle"*) pass "$label" ;;
        *) fail "$label" "[$needle] not found in [$haystack]" ;;
    esac
}

assert_installed() {
    local label="$1"
    if [ -x "$ROOT/bin/reddittui" ]; then pass "$label"
    else fail "$label" "no binary at $ROOT/bin/reddittui"; fi
}

assert_not_installed() {
    local label="$1"
    if [ -e "$ROOT/bin/reddittui" ]; then
        fail "$label" "a binary was installed at $ROOT/bin/reddittui"
    else
        pass "$label"
    fi
}

VERSION="v0.3.9"
ASSET="reddit-tui_Darwin_$(uname -m).tar.gz"
case "$(uname -m)" in
    arm64|x86_64) ;;
    *) echo "SKIP: unsupported test architecture $(uname -m)"; exit 0 ;;
esac
# GoReleaser names the x86_64 asset with the uname spelling, which matches.
CHECKSUMS="reddit-tui_${VERSION#v}_checksums.txt"

# Fresh sandbox holding a fake release tree and an empty bin directory. The
# payload is a stub shell script rather than a real Mach-O binary: the script
# only ever chmods it and runs `-version`, so nothing here needs to be native.
new_sandbox() {
    ROOT="$(mktemp -d)"
    mkdir -p "$ROOT/bin" "$ROOT/rel/$VERSION" "$ROOT/payload"

    cat > "$ROOT/payload/reddittui" <<STUB
#!/bin/bash
[ "\${1:-}" = "-version" ] && echo "reddittui version $VERSION"
STUB
    chmod +x "$ROOT/payload/reddittui"
    tar czf "$ROOT/rel/$VERSION/$ASSET" -C "$ROOT/payload" reddittui

    (cd "$ROOT/rel/$VERSION" && shasum -a 256 "$ASSET" > "$CHECKSUMS")

    export REDDITTUI_BIN_DIR="$ROOT/bin"
    export REDDITTUI_BASE_URL="file://$ROOT/rel"
    export REDDITTUI_CONFIG="$ROOT/config/reddittui.toml"
    # Never let status() reach the real GitHub API.
    export REDDITTUI_API_URL="file://$ROOT/nonexistent"
}

cleanup_sandbox() { [ -n "${ROOT:-}" ] && rm -rf "$ROOT"; }

run() { "$SCRIPT" "$@" 2>&1; }

echo "reddittui-setup.sh"

# --- happy path ---------------------------------------------------------------
new_sandbox
out="$(run install)"
assert_contains "$out" "Checksum verified" "install verifies the checksum"
assert_contains "$out" "Installed reddittui $VERSION" "install reports the version"
assert_installed "install places the binary in the bin directory"

# --- idempotence --------------------------------------------------------------
# The version check shells out to the installed binary, so this also proves the
# installed file is executable and answers -version.
out="$(run install)"
assert_contains "$out" "already installed" "re-running install is a no-op"

# --- status -------------------------------------------------------------------
out="$(run status)"
assert_contains "$out" "reddittui: $VERSION" "status reports the installed version"
assert_contains "$out" "config" "status reports the config file state"
cleanup_sandbox

# --- corrupt payload ----------------------------------------------------------
# The checksums file is honest; the tarball is not. This is the case that would
# otherwise install an attacker-supplied binary.
new_sandbox
printf 'corrupted' | gzip > "$ROOT/rel/$VERSION/$ASSET"
out="$(run install)"
assert_contains "$out" "Checksum mismatch" "corrupt payload is rejected"
assert_not_installed "corrupt payload installs nothing"
cleanup_sandbox

# --- missing checksums file ---------------------------------------------------
# A genuine tarball is still refused when there is nothing to verify it against.
new_sandbox
rm "$ROOT/rel/$VERSION/$CHECKSUMS"
out="$(run install)"
assert_contains "$out" "refusing to install unverified" "missing checksums file is refused"
assert_not_installed "unverifiable payload installs nothing"
cleanup_sandbox

# --- unknown release tag ------------------------------------------------------
new_sandbox
out="$(REDDITTUI_VERSION=v99.99.99 run install)"
assert_contains "$out" "Download failed" "an unknown tag fails clearly"
assert_not_installed "a failed download installs nothing"
cleanup_sandbox

# --- an archive without the expected binary -----------------------------------
new_sandbox
rm "$ROOT/rel/$VERSION/$ASSET"
tar czf "$ROOT/rel/$VERSION/$ASSET" -C "$ROOT/payload" --transform 's/reddittui/wrongname/' reddittui 2>/dev/null \
    || (cd "$ROOT/payload" && mv reddittui wrongname && tar czf "$ROOT/rel/$VERSION/$ASSET" wrongname)
(cd "$ROOT/rel/$VERSION" && shasum -a 256 "$ASSET" > "$CHECKSUMS")
out="$(run install)"
assert_contains "$out" "did not contain a reddittui binary" "a renamed payload is caught"
assert_not_installed "a bad archive installs nothing"
cleanup_sandbox

# --- status with nothing installed --------------------------------------------
new_sandbox
out="$(run status)"
assert_contains "$out" "not installed" "status reports a missing install"
cleanup_sandbox

# --- unknown command ----------------------------------------------------------
out="$(run bogus)"
assert_contains "$out" "Unknown command" "an unknown command is rejected"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
