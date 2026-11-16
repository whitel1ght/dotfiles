/**
 * Claude Code PreToolUse hooks for pi's bash tool: the ones enabled Claude plugins and
 * ~/.claude/settings.json register for `Bash`, run with Claude's hook input and exit-code
 * contract, so a gate written for Claude (the ECFX /mr-description gate) gates pi too.
 */
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export interface Hook {
  command: string;
  /** Claude's `if` permission rule, e.g. `Bash(glab *)`. */
  if?: string;
  timeout?: number;
  /** CLAUDE_PLUGIN_ROOT for plugin hooks. */
  root?: string;
  source: string;
}

export function claudeDir(): string {
  return process.env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude");
}

function readJson(path: string): any {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return undefined;
  }
}

/** A Claude matcher is a regex over the tool name; empty or `*` matches every tool. */
export function matcherMatches(matcher: string | undefined, tool: string): boolean {
  if (!matcher || matcher === "*") return true;
  try {
    return new RegExp(`^(?:${matcher})$`).test(tool);
  } catch {
    return matcher === tool;
  }
}

function collect(hooks: any, tool: string, source: string, root?: string): Hook[] {
  const out: Hook[] = [];
  for (const group of hooks?.PreToolUse ?? []) {
    if (!matcherMatches(group.matcher, tool)) continue;
    for (const h of group.hooks ?? []) {
      if (h.type !== "command" || !h.command) continue;
      out.push({ command: h.command, if: h.if, timeout: h.timeout, root, source });
    }
  }
  return out;
}

/** Every PreToolUse hook for `Bash`, from settings.json and from each enabled plugin. */
export function loadHooks(dir = claudeDir()): Hook[] {
  const settings = readJson(join(dir, "settings.json")) ?? {};
  const hooks = collect(settings.hooks, "Bash", "settings.json");
  const enabled: Record<string, boolean> = settings.enabledPlugins ?? {};
  const installed = readJson(join(dir, "plugins", "installed_plugins.json"))?.plugins ?? {};
  for (const [key, installs] of Object.entries<any>(installed)) {
    if (enabled[key] !== true) continue;
    const root = installs?.[0]?.installPath;
    if (!root) continue;
    const file = join(root, "hooks", "hooks.json");
    if (existsSync(file)) hooks.push(...collect(readJson(file)?.hooks, "Bash", key, root));
  }
  return hooks;
}

/**
 * Claude's `if` narrows a hook to matching commands. Only `Bash(<word> ...)` is read, as
 * "the command mentions <word>"; anything else runs the hook. Over-running is safe: the
 * hook script makes its own decision.
 */
export function ifMatches(rule: string | undefined, command: string): boolean {
  const m = rule?.match(/^Bash\((\S+)/);
  if (!m) return true;
  const word = m[1].replace(/[*:].*$/, "");
  return !word || command.includes(word);
}

export interface Verdict {
  block: boolean;
  reason?: string;
}

/**
 * Claude's contract: exit 2 blocks with stderr as the reason; exit 0 with a JSON
 * `hookSpecificOutput.permissionDecision` of `deny` blocks too; anything else lets the
 * call through.
 */
export function runHook(hook: Hook, input: object, cwd: string): Verdict {
  const env = { ...process.env };
  if (hook.root) env.CLAUDE_PLUGIN_ROOT = hook.root;
  const r = spawnSync("bash", ["-c", hook.command], {
    cwd,
    env,
    input: JSON.stringify(input),
    encoding: "utf8",
    timeout: (hook.timeout ?? 60) * 1000,
  });
  if (r.status === 2) return { block: true, reason: (r.stderr || "").trim() || `blocked by ${hook.source}` };
  if (r.status === 0) {
    const out = (() => {
      try {
        return JSON.parse(r.stdout || "");
      } catch {
        return undefined;
      }
    })();
    const d = out?.hookSpecificOutput;
    if (d?.permissionDecision === "deny") {
      return { block: true, reason: d.permissionDecisionReason || `blocked by ${hook.source}` };
    }
  }
  return { block: false };
}

export function check(hooks: Hook[], command: string, cwd: string, sessionId: string): Verdict {
  const input = {
    session_id: sessionId,
    cwd,
    hook_event_name: "PreToolUse",
    tool_name: "Bash",
    tool_input: { command },
  };
  for (const hook of hooks) {
    if (!ifMatches(hook.if, command)) continue;
    const v = runHook(hook, input, cwd);
    if (v.block) return v;
  }
  return { block: false };
}
