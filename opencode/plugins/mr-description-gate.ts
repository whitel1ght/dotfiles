import { existsSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"

// Gates MR creation, and MR updates that carry a description, until /mr-description
// has run for the current repo+branch.
//
// WHY THIS SHELLS OUT RATHER THAN REIMPLEMENTING THE CHECK.
//
// The gate's logic lives in claude-components/plugins/shared/hooks/mr-description-review.sh,
// and it is intricate for reasons that are easy to lose in a rewrite: it strips heredoc
// bodies before matching, masks boundary characters that sit inside quoted strings, folds
// newlines into command boundaries, cuts the command into separate `glab` invocations and
// judges each one's flags alone, and distinguishes a body-writing `glab mr update` from a
// metadata-only one. It also fails closed on anything it cannot parse — including its own
// input, if jq is missing. That behaviour is the whole point of the gate, and a
// reimplementation would be a second copy to keep in agreement with the first.
//
// So the script stays the single source of truth for the DECISION and this file only
// adapts the transport: Claude Code calls it as a PreToolUse hook that reads
// `{tool_input:{command}}` on stdin and blocks on exit 2; OpenCode has no PreToolUse hook
// system, so the same script is invoked from `tool.execute.before` and its refusal is
// turned into a thrown Error, which is how a plugin blocks a tool call.
//
// Both tools therefore consult the same file. Fixing a misfire in the shell script fixes
// it for OpenCode too, with no second copy to drift.
//
// Usage: set CLAUDE_COMPONENTS_PLUGIN to override the plugin root.

const PLUGIN_ROOT =
  process.env.CLAUDE_COMPONENTS_PLUGIN ??
  join(homedir(), "projects", "claude-components", "plugins", "shared")

const GATE_SCRIPT = join(PLUGIN_ROOT, "hooks", "mr-description-review.sh")

// Exported as a bare async function rather than wrapped in `plugin()` from
// @opencode-ai/plugin. The wrapper is only a type helper, but importing that package
// here resolves against ~/.config/opencode/node_modules, where it is not installed — and
// the failure is silent: OpenCode reports the plugin as loaded, then registers none of its
// hooks. The gate then appears to work while checking nothing, which is the worst possible
// outcome for a gate. A plain function needs no import and cannot fail this way.
export const MrDescriptionGate = async () => {
  // Resolved per call rather than at import time: the plugin loads before any session
  // exists, and a missing script should surface as a clear warning rather than a module
  // that throws during startup and takes every other plugin down with it.
  const gateAvailable = () => {
    if (!existsSync(GATE_SCRIPT)) return false
    return true
  }

  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "bash") return

      const command = (output.args as { command?: string })?.command
      // Every gated form contains `glab`; the script re-checks this, but skipping the
      // spawn here keeps the hook off the path of every unrelated bash call.
      if (!command || !command.includes("glab")) return

      if (!gateAvailable()) {
        // Deliberately allow rather than block. A machine without the components clone has
        // no mr-description skill either, so there is nothing to gate; blocking every `glab`
        // call would strand work on a false premise. The warning is the signal.
        console.warn(
          `[mr-description-gate] skipped: ${GATE_SCRIPT} not found (set CLAUDE_COMPONENTS_PLUGIN)`,
        )
        return
      }

      const proc = Bun.spawn(["bash", GATE_SCRIPT], {
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
        env: process.env,
      })

      proc.stdin.write(JSON.stringify({ tool_input: { command } }))
      proc.stdin.end()

      const code = await proc.exited
      // 0 = allowed. 2 = the gate refused, with the reason on stderr. Anything else is a
      // malfunction of the script itself (a parse error under bash 3.2, say), which the
      // script also answers with 2; either way the refusal is what the model needs to see.
      if (code === 0) return

      const message = (await new Response(proc.stderr).text()).trim()
      throw new Error(message || "mr-description gate refused this command.")
    },
  }
}
