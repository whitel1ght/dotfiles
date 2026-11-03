#!/bin/bash
# Tests for bin/mr-watch. glab is stubbed on PATH, so nothing here reaches
# GitLab; the stub logs every POST it receives. Worktrees are throwaway repos.
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$TEST_DIR/mr-watch"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; echo "         $2"; }
assert_contains() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3" "[$2] not in [$1]" ;; esac; }
assert_lacks() { case "$1" in *"$2"*) fail "$3" "[$2] unexpectedly in [$1]" ;; *) pass "$3" ;; esac; }
assert_eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3" "expected [$1] got [$2]"; }

SANDBOX="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$SANDBOX"' EXIT
STUBS="$SANDBOX/stubs"; FIX="$SANDBOX/fixtures"; STATE="$SANDBOX/state"; PROJ="$SANDBOX/projects"
mkdir -p "$STUBS" "$FIX" "$PROJ"

note() { # id author created [system] [resolvable] [resolved] [inline-path]
    printf '{"id":%s,"author":{"username":"%s"},"created_at":"%s","system":%s,"resolvable":%s,"resolved":%s,"body":"body %s","position":%s}' \
        "$1" "$2" "$3" "${4:-false}" "${5:-false}" "${6:-false}" "$1" \
        "$([ -n "${7:-}" ] && printf '{"new_path":"%s","new_line":7}' "$7" || echo null)"
}

# MR 10 on "api": a new human review, plus everything that must not count.
# MR 20 on "web": only old notes, answered by me since.
cat > "$FIX/mrs.json" <<'EOF'
[{"project_id":1,"iid":10,"references":{"full":"grp/api!10"},"title":"api change","source_branch":"feat/a","updated_at":"2026-09-25T10:00:00Z","web_url":"u10"},
 {"project_id":1,"iid":30,"draft":true,"references":{"full":"grp/api!30"},"title":"wip","source_branch":"feat/c","updated_at":"2026-09-25T10:00:00Z","web_url":"u30"},
 {"project_id":1,"iid":40,"references":{"full":"grp/api!40"},"title":"approved","source_branch":"feat/d","updated_at":"2026-09-25T10:00:00Z","web_url":"u40"},
 {"project_id":1,"iid":50,"references":{"full":"grp/api!50"},"title":"no rules","source_branch":"feat/e","updated_at":"2026-09-25T10:00:00Z","web_url":"u50"},
 {"project_id":2,"iid":20,"references":{"full":"grp/web!20"},"title":"web change","source_branch":"feat/b","updated_at":"2026-09-25T10:00:00Z","web_url":"u20"}]
EOF
cat > "$FIX/disc-1-10.json" <<EOF
[{"id":"dreview","notes":[$(note 101 alice 2026-09-25T09:00:00Z)]},
 {"id":"dinline","notes":[$(note 102 alice 2026-09-25T09:01:00Z false true false src/A.java),$(note 103 me 2026-09-25T08:00:00Z false true false)]},
 {"id":"dresolved","notes":[$(note 104 bob 2026-09-25T09:02:00Z false true true)]},
 {"id":"dbot","notes":[$(note 105 group_4893950_bot_abc 2026-09-25T09:03:00Z)]},
 {"id":"dsys","notes":[$(note 106 alice 2026-09-25T09:04:00Z true)]},
 {"id":"dmine","notes":[$(note 107 me 2026-09-25T07:00:00Z)]},
 {"id":"dignored","notes":[$(note 108 renovate 2026-09-25T09:05:00Z)]}]
EOF
cat > "$FIX/disc-2-20.json" <<EOF
[{"id":"dold","notes":[$(note 201 carol 2026-09-24T09:00:00Z)]},
 {"id":"dreplied","notes":[$(note 202 me 2026-09-24T10:00:00Z)]}]
EOF

echo '{"approved":true,"approved_by":[{"user":{"username":"alice"}}]}' > "$FIX/approvals-40"
echo '{"approved":true,"approved_by":[]}' > "$FIX/approvals-50"

cat > "$STUBS/glab" <<'EOF'
#!/bin/bash
[ -n "${GLAB_DOWN:-}" ] && exit 1
if [ "$2" = --method ]; then
    body="${6#body=@}"; [ "$body" = - ] && body=/dev/stdin
    printf '%s %s\n' "$4" "$(tr '\n' ' ' < "$body")" >> "$FIX/posts.log"; echo '{}'; exit 0
fi
case "$*" in
    "api user") echo '{"username":"me"}' ;;
    *merge_requests\?scope*) cat "$FIX/mrs.json" ;;
    */approvals) cat "$FIX/approvals-$(echo "$*" | sed -E 's#.*merge_requests/([0-9]+)/approvals#\1#')" 2>/dev/null \
        || echo '{"approved":false,"approved_by":[]}' ;;
    *projects/1/*/discussions*) cat "$FIX/disc-1-10.json" ;;
    *projects/2/*/discussions*) cat "$FIX/disc-2-20.json" ;;
esac
EOF
chmod +x "$STUBS/glab"

# api has a clean worktree on feat/a; web's clone has no worktree for feat/b.
git init -q -b main "$PROJ/api" && git -C "$PROJ/api" commit -q --allow-empty -m init
git -C "$PROJ/api" worktree add -q -b feat/a "$SANDBOX/wt-a"
git init -q -b main "$PROJ/web" && git -C "$PROJ/web" commit -q --allow-empty -m init

run() { run_at "$PROJ" "$STATE" "$@"; }
# run_at ROOT STATE args — same, against another projects root and state dir
run_at() {
    local root="$1" state="$2"; shift 2
    PATH="$STUBS:$PATH" FIX="$FIX" MR_WATCH_STATE="$state" PROJECTS_DIR="$root" \
    MR_WATCH_IGNORE="renovate" "$SCRIPT" "$@" 2>&1
}

echo "mr-watch — check"
out="$(run check --since 2026-09-20T00:00:00Z)"; rc=$?
assert_eq 0 "$rc" "exits 0 when something is new"
assert_contains "$out" "grp/api!10: 2 new note(s) from @alice in 2 thread(s)" "counts new human notes and their threads"
assert_lacks "$out" "grp/web!20" "skips an MR whose notes I answered since"
assert_lacks "$out" "grp/api!30" "skips draft MRs"
assert_lacks "$out" "grp/api!40" "skips approved MRs"
assert_contains "$out" "grp/api!50" "an MR needing no approvals isn't approved until someone approves"
assert_contains "$out" "worktree: $SANDBOX/wt-a (clean)" "finds the branch's worktree"
round=$(ls -d "$STATE"/rounds/1-10-* | head -1)
review=$(cat "$round/review.md")
assert_contains "$review" "### NEW @alice, 2026-09-25T09:00:00Z, note 101" "marks the new note in review.md"
assert_contains "$review" "## Discussion dinline — inline src/A.java:7" "names the file and line of an inline thread"
assert_contains "$review" "### @me, 2026-09-25T08:00:00Z, note 103" "keeps my earlier note in the thread as context"
assert_lacks "$review" "dresolved" "leaves out resolved threads"
assert_lacks "$review" "group_4893950_bot" "leaves out bot notes"
assert_lacks "$review" "note 106" "leaves out system notes"
assert_lacks "$review" "renovate" "leaves out MR_WATCH_IGNORE users"
assert_eq "2026-09-25T09:01:00Z" "$(cat "$round/watermark")" "the watermark is the newest new note"

out="$(run check --since 2026-09-26T00:00:00Z)"; rc=$?
assert_eq 1 "$rc" "exits 1 when nothing is new"

echo "mr-watch — worktree states"
echo x > "$SANDBOX/wt-a/scratch"
out="$(run check --since 2026-09-20T00:00:00Z)"
assert_contains "$out" "(DIRTY: 1 changed files)" "flags a dirty worktree"
rm "$SANDBOX/wt-a/scratch"
tmp="$FIX/disc-2-20.json.tmp"
sed 's/"iid":20,/"iid":20,/; s/2026-09-24T10:00:00Z/2026-09-23T10:00:00Z/' \
  "$FIX/disc-2-20.json" > "$tmp"
mv "$tmp" "$FIX/disc-2-20.json"
out="$(run check --since 2026-09-20T00:00:00Z)"
assert_contains "$out" "worktree: none (clone $PROJ/web)" "says when the branch has no worktree"

# Give feat/a an upstream, then move the remote from another clone (as if pushed from another machine).
git init -q --bare "$SANDBOX/api-origin.git"
git -C "$SANDBOX/wt-a" remote add origin "$SANDBOX/api-origin.git" 2>/dev/null || true
git -C "$SANDBOX/wt-a" push -q -u origin feat/a
git clone -q -b feat/a "$SANDBOX/api-origin.git" "$SANDBOX/other"
git -C "$SANDBOX/other" commit -q --allow-empty -m "pushed elsewhere"
git -C "$SANDBOX/other" push -q
out="$(run check --since 2026-09-20T00:00:00Z)"
assert_contains "$out" "worktree: $SANDBOX/wt-a (clean, fast-forwarded 1 commits)" "fast-forwards a worktree that is behind its upstream"
assert_eq "$(git -C "$SANDBOX/other" rev-parse HEAD)" "$(git -C "$SANDBOX/wt-a" rev-parse HEAD)" "the worktree is at the pushed commit"
out="$(run check --since 2026-09-20T00:00:00Z)"
assert_contains "$out" "worktree: $SANDBOX/wt-a (clean)" "an up-to-date worktree is plain clean"
git -C "$SANDBOX/wt-a" commit -q --allow-empty -m "local only"
out="$(run check --since 2026-09-20T00:00:00Z)"
assert_contains "$out" "worktree: $SANDBOX/wt-a (clean, 1 unpushed commits)" "reports commits not on the remote"
git -C "$SANDBOX/other" commit -q --allow-empty -m "pushed elsewhere again"
git -C "$SANDBOX/other" push -q
out="$(run check --since 2026-09-20T00:00:00Z)"
assert_contains "$out" "worktree: $SANDBOX/wt-a (STALE: diverged from origin/feat/a, 1 ahead, 1 behind)" "flags a worktree that diverged from its upstream"
assert_eq "local only" "$(git -C "$SANDBOX/wt-a" log -1 --format=%s)" "leaves a diverged worktree untouched"
git -C "$SANDBOX/wt-a" reset -q --hard origin/feat/a
mv "$SANDBOX/api-origin.git" "$SANDBOX/api-origin.moved"
out="$(run check --since 2026-09-20T00:00:00Z)"
assert_contains "$out" "worktree: $SANDBOX/wt-a (STALE: fetch failed)" "a failed fetch is stale, not clean"
mv "$SANDBOX/api-origin.moved" "$SANDBOX/api-origin.git"

echo "mr-watch — ack and reply"
rm -rf "$STATE/rounds"
run check --since 2026-09-20T00:00:00Z >/dev/null
round=$(ls -d "$STATE"/rounds/1-10-* | head -1)
web=$(ls -d "$STATE"/rounds/2-20-* | head -1)
out="$(run reply "$round")"
assert_contains "$out" "no response.md" "refuses to post without a response"
printf '| B1 | Fixed | `abc1234` | done |\n' > "$round/response.md"
printf 'dinline\tFixed in `abc1234`.\n' > "$round/threads.tsv"
printf 'the web reply\n' > "$web/response.md"
out="$(run held)"
assert_contains "$out" "grp/api!10" "held lists a written, unposted reply"
out="$(run reply "$round")"
assert_contains "$out" "posted to grp/api!10: summary reply + 1 thread reply" "reports what it posted"
posts=$(cat "$FIX/posts.log")
assert_contains "$posts" "projects/1/merge_requests/10/notes | B1 | Fixed" "posts the summary as an MR note"
assert_contains "$posts" "projects/1/merge_requests/10/discussions/dinline/notes Fixed in" "replies inside the inline thread"
assert_eq "2026-09-25T09:01:00Z" "$(cat "$STATE/seen/1-10")" "reply acks the round"
out="$(run reply "$round")"
assert_contains "$out" "already posted" "never posts a round twice"
out="$(run held)"
assert_lacks "$out" "grp/api!10" "a posted round is no longer held"
assert_contains "$out" "grp/web!20" "an unposted round still is"

run ack "$web" >/dev/null
for r in "$STATE"/rounds/1-50-*; do run ack "$r" >/dev/null; done
out="$(run check --since 2026-09-20T00:00:00Z)"; rc=$?
assert_eq 1 "$rc" "acked rounds don't come back"
assert_eq 2 "$(wc -l < "$FIX/posts.log" | tr -d ' ')" "ack posts nothing"

cat > "$FIX/disc-1-10.json" <<EOF
[{"id":"dreview","notes":[$(note 101 alice 2026-09-25T09:00:00Z),$(note 109 alice 2026-09-25T12:00:00Z)]}]
EOF
out="$(run check)"
assert_contains "$out" "grp/api!10: 1 new note(s)" "a later note in an acked thread is new again"

echo "mr-watch — clones one folder deeper"
# As on Ubuntu: the clones are grouped, ~/projects/ecfx/{ecfx-backend,...},
# with nothing at ~/projects/<repo>. Same MR fixtures, separate root and state.
NEST="$SANDBOX/nested-projects"; NSTATE="$SANDBOX/nested-state"
mkdir -p "$NEST/ecfx"
git init -q -b main "$NEST/ecfx/api" && git -C "$NEST/ecfx/api" commit -q --allow-empty -m init
git -C "$NEST/ecfx/api" worktree add -q -b feat/a "$SANDBOX/wt-nested"
out="$(run_at "$NEST" "$NSTATE" check --since 2026-09-20T00:00:00Z)"; rc=$?
assert_eq 0 "$rc" "finds the MRs with every clone one folder deeper"
assert_contains "$out" "worktree: $SANDBOX/wt-nested (clean)" "resolves a nested clone's worktree"
assert_lacks "$out" "no clone at $NEST/api" "no false 'no clone' line for a nested clone"
assert_contains "$out" "worktree: none (no clone at $NEST/web)" "still says so when there is no clone at all"
echo x > "$SANDBOX/wt-nested/scratch"
out="$(run_at "$NEST" "$NSTATE" check --since 2026-09-20T00:00:00Z)"
assert_contains "$out" "worktree: $SANDBOX/wt-nested (DIRTY: 1 changed files)" "sees the nested worktree's changes"
rm "$SANDBOX/wt-nested/scratch"
# A worktrees directory that happens to hold a directory of the repo's name must
# not be mistaken for the clone.
mkdir -p "$NEST/worktrees/api/ABC-1"
out="$(run_at "$NEST" "$NSTATE" check --since 2026-09-20T00:00:00Z)"
assert_contains "$out" "worktree: $SANDBOX/wt-nested (clean)" "skips the worktrees directory when looking deeper"
# A clone at the flat path wins over the nested one of the same name.
git init -q -b main "$NEST/api" && git -C "$NEST/api" commit -q --allow-empty -m init
git -C "$NEST/api" worktree add -q -b feat/a "$SANDBOX/wt-flat"
out="$(run_at "$NEST" "$NSTATE" check --since 2026-09-20T00:00:00Z)"
assert_contains "$out" "worktree: $SANDBOX/wt-flat (clean)" "the flat clone wins when both depths have one"

echo "mr-watch — a projects root that itself sits in a dot directory"
# $HOME/.local/projects style: the dot component is in the ROOT, not below it, so
# it must not hide the grouped clones (the skip rule only looks below the root).
DROOT="$SANDBOX/.local/projects"; DSTATE="$SANDBOX/dot-state"
mkdir -p "$DROOT/ecfx"
git init -q -b main "$DROOT/ecfx/api" && git -C "$DROOT/ecfx/api" commit -q --allow-empty -m init
git -C "$DROOT/ecfx/api" worktree add -q -b feat/a "$SANDBOX/wt-dot"
out="$(run_at "$DROOT" "$DSTATE" check --since 2026-09-20T00:00:00Z)"
assert_contains "$out" "worktree: $SANDBOX/wt-dot (clean)" "resolves a nested clone under a root with a dot component"
assert_lacks "$out" "no clone at $DROOT/api" "and does not fall back to the flat path"
# A dot directory BELOW the root is still skipped, as before.
mkdir -p "$DROOT/.cache/api" && cp -R "$DROOT/ecfx/api/.git" "$DROOT/.cache/api/.git"
out="$(run_at "$DROOT" "$DSTATE" check --since 2026-09-20T00:00:00Z)"
assert_contains "$out" "worktree: $SANDBOX/wt-dot (clean)" "a dot directory below the root is still skipped"

echo "repo_path — one function, four copies"
# The four helpers must stay standalone (they are symlinked into ~/.local/bin on
# their own), so repo_path is copied rather than shared: pin the copies together.
repo_path_body() { sed -n '/^repo_path() {$/,/^}$/p' "$TEST_DIR/$1"; }
REF="$(repo_path_body mr-watch)"
[ -n "$REF" ] && pass "bin/mr-watch has a repo_path" || fail "bin/mr-watch has a repo_path" "not found"
for helper in wt jt dev; do
  if [ "$(repo_path_body "$helper")" = "$REF" ]; then
    pass "bin/$helper carries the same repo_path"
  else
    fail "bin/$helper carries the same repo_path" "body differs from bin/mr-watch's"
  fi
done

echo "mr-watch — GitLab down"
GLAB_DOWN=1 run check >/dev/null; rc=$?
assert_eq 2 "$rc" "exits 2 when GitLab is unreachable"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
