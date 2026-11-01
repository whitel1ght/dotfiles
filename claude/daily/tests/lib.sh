# Shared helpers for the structure tests of prompt files. Source it; do not run it.
PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
# has <file> <fixed string> <label>
has() { grep -qF -- "$2" "$1" && pass "$3" || fail "$3" "[$2] missing from $1"; }
# lacks <file> <fixed string> <label>
lacks() { grep -qF -- "$2" "$1" && fail "$3" "[$2] unexpectedly in $1" || pass "$3"; }
# frontmatter_has <file> <key>
frontmatter_has() {
  awk 'NR==1 && $0!="---"{exit 1} NR>1 && $0=="---"{exit 0} NR>1{print}' "$1" | grep -q "^$2:" \
    && pass "$1 frontmatter has $2" || fail "frontmatter $2" "missing in $1"
}
finish() { echo; echo "passed: $PASS  failed: $FAIL"; [ "$FAIL" -eq 0 ]; }
