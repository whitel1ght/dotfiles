import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { check, ifMatches, loadHooks, matcherMatches } from "./hooks.ts";

function fakeClaude(): string {
  const dir = mkdtempSync(join(tmpdir(), "claude-hooks-"));
  const on = join(dir, "plugins", "on");
  const off = join(dir, "plugins", "off");
  for (const root of [on, off]) {
    mkdirSync(join(root, "hooks"), { recursive: true });
    writeFileSync(
      join(root, "hooks", "hooks.json"),
      JSON.stringify({
        hooks: {
          PreToolUse: [
            {
              matcher: "Bash",
              hooks: [{ type: "command", command: '"${CLAUDE_PLUGIN_ROOT}/hooks/gate.sh"', if: "Bash(glab *)" }],
            },
            { matcher: "Edit|Write", hooks: [{ type: "command", command: "exit 2" }] },
          ],
        },
      }),
    );
    // Blocks `glab mr create`, reading Claude's hook input from stdin.
    writeFileSync(
      join(root, "hooks", "gate.sh"),
      '#!/bin/bash\ncmd=$(jq -r .tool_input.command)\ncase "$cmd" in *"glab mr create"*) echo "run /mr-description first" >&2; exit 2;; esac\n',
      { mode: 0o755 },
    );
  }
  writeFileSync(
    join(dir, "plugins", "installed_plugins.json"),
    JSON.stringify({ plugins: { "on@m": [{ installPath: on }], "off@m": [{ installPath: off }] } }),
  );
  writeFileSync(
    join(dir, "settings.json"),
    JSON.stringify({
      enabledPlugins: { "on@m": true, "off@m": false },
      hooks: {
        PreToolUse: [
          {
            matcher: "Bash",
            hooks: [
              {
                type: "command",
                command: `case "$(cat)" in *'rm -rf'*) echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"no rm"}}';; esac`,
              },
            ],
          },
        ],
      },
    }),
  );
  return dir;
}

test("matcherMatches reads a matcher as an anchored regex", () => {
  assert.ok(matcherMatches("Bash", "Bash"));
  assert.ok(matcherMatches("Edit|Bash", "Bash"));
  assert.ok(matcherMatches("*", "Bash"));
  assert.ok(matcherMatches(undefined, "Bash"));
  assert.ok(!matcherMatches("Edit|Write", "Bash"));
  assert.ok(!matcherMatches("Bas", "Bash"));
});

test("ifMatches narrows on the command word, and runs the hook when it cannot tell", () => {
  assert.ok(ifMatches("Bash(glab *)", "cd x && glab mr create"));
  assert.ok(!ifMatches("Bash(glab *)", "git status"));
  assert.ok(ifMatches(undefined, "git status"));
  assert.ok(ifMatches("Edit(*)", "git status"));
});

test("loadHooks takes Bash hooks from settings and enabled plugins only", () => {
  const hooks = loadHooks(fakeClaude());
  assert.deepEqual(
    hooks.map((h) => h.source),
    ["settings.json", "on@m"],
  );
  assert.match(hooks[1].root!, /plugins\/on$/);
});

test("check follows Claude's exit-code and JSON contracts", () => {
  const hooks = loadHooks(fakeClaude());
  const cwd = tmpdir();
  assert.deepEqual(check(hooks, "glab mr list", cwd, "s"), { block: false });
  assert.deepEqual(check(hooks, "git status", cwd, "s"), { block: false });
  assert.deepEqual(check(hooks, "cd x && glab mr create --fill", cwd, "s"), {
    block: true,
    reason: "run /mr-description first",
  });
  assert.deepEqual(check(hooks, "rm -rf build", cwd, "s"), { block: true, reason: "no rm" });
});
