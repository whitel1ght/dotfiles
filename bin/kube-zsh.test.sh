#!/bin/bash
# Tests for zsh/kube.zsh (the kubectl prod guard). kubectl is a stub on PATH that answers
# `config current-context` with $STUB_CTX and logs every other call, so no cluster is touched.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$TEST_DIR/../zsh/kube.zsh"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }
assert_has() { case "$2" in *"$1"*) pass "$3" ;; *) fail "$3" "[$1] not in [$2]" ;; esac; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${SANDBOX:?}"' EXIT
cat >"$SANDBOX/kubectl" <<EOF
#!/bin/sh
if [ "\$1 \$2" = "config current-context" ]; then echo "\$STUB_CTX"; exit 0; fi
echo "\$*" >>"$SANDBOX/calls"
EOF
chmod +x "$SANDBOX/kubectl"

# ctx, args… → runs kubectl through the guard; prints stderr, sets RC
run() {
  local ctx="$1"; shift
  : >"$SANDBOX/calls"
  OUT="$(STUB_CTX="$ctx" PATH="$SANDBOX:$PATH" zsh -f -c 'source "$1"; shift; kubectl "$@"' _ "$GUARD" "$@" 2>&1)"
  RC=$?
  CALLS="$(cat "$SANDBOX/calls")"
}

echo "kube.zsh"
run prod01 get pods
assert_eq "1" "$RC" "bare kubectl on prod01 is refused"
assert_eq "" "$CALLS" "and never reaches the binary"
assert_has "kubectl --context prod01 get pods" "$OUT" "the message shows the line to type"

run prod01 --context prod01 get pods
assert_eq "0" "$RC" "an explicit --context runs on prod"
assert_eq "--context prod01 get pods" "$CALLS" "with the arguments unchanged"

run prod01 -n duploservices-prod01 logs x --context=prod01
assert_eq "-n duploservices-prod01 logs x --context=prod01" "$CALLS" "--context=… anywhere on the line counts"

run prod01 config use-context dev01
assert_eq "config use-context dev01" "$CALLS" "config subcommands pass on prod (switching away must work)"

run prod01 version --client
assert_eq "version --client" "$CALLS" "version passes"

run staging01 get pods
assert_eq "get pods" "$CALLS" "a non-prod context runs unguarded"

run dev01 get pods
assert_eq "0" "$RC" "dev01 runs"

zsh -f -c 'source "$1"; alias k9prod' _ "$GUARD" | grep -q -- '--readonly' \
  && pass "k9prod opens k9s read-only" || fail "k9prod opens k9s read-only" "alias missing --readonly"

echo ".zshrc loads it through the ~/.zshrc symlink"
mkdir -p "$SANDBOX/repo" "$SANDBOX/home"
grep -F 'kube.zsh"' "$TEST_DIR/../zsh/.zshrc" >"$SANDBOX/repo/.zshrc"
cp "$GUARD" "$SANDBOX/repo/kube.zsh"
ln -s "$SANDBOX/repo/.zshrc" "$SANDBOX/home/.zshrc"
assert_eq "kubectl: function" "$(zsh -f -c 'source "$1"; whence -w kubectl' _ "$SANDBOX/home/.zshrc")" "the source line resolves the symlink to the repo's zsh/"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
