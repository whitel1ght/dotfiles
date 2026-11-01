#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/vendor/example/.claude-plugin" "$ROOT/skills/alpha"
cat > "$ROOT/vendor.json" <<'EOF'
{
  "sources": [{
    "name": "example",
    "repo": "https://example.invalid/skills.git",
    "ref": "main",
    "skills": ["skills/example"]
  }]
}
EOF
printf '{"name":"example","version":"1.0.0"}\n' > "$ROOT/vendor/example/.claude-plugin/plugin.json"
printf '# Alpha skill\n' > "$ROOT/skills/alpha/SKILL.md"

# Offline generation must not inspect Git remotes or alter vendored source files.
mkdir -p "$ROOT/bin"
cat > "$ROOT/bin/git" <<'EOF'
#!/usr/bin/env bash
echo "unexpected git invocation: $*" >&2
exit 90
EOF
chmod +x "$ROOT/bin/git"
PATH="$ROOT/bin:/usr/bin:/bin" VENDOR_ROOT="$ROOT" bash "$REPO/vendor-sync.sh" --offline > "$ROOT/output"
[ -L "$ROOT/personal/skills/alpha" ]
grep -q '"name": "personal"' "$ROOT/personal/.claude-plugin/plugin.json"
jq -e '.plugins[] | select(.name == "personal" and .source == "./personal")' \
    "$ROOT/.claude-plugin/marketplace.json" >/dev/null
jq -e '.plugins[] | select(.name == "example" and .source == "./vendor/example")' \
    "$ROOT/.claude-plugin/marketplace.json" >/dev/null
grep -q 'no network used' "$ROOT/output"
printf 'vendor-sync offline tests passed\n'
