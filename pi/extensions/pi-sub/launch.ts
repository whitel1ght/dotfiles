// Launches a detached child `pi --mode json` as a subagent. The wrapper
// (run.mjs) owns the child's lifetime: launch() only spawns it detached and
// records the meta. Node built-ins only, so run.mjs can stay plain node.

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

import type { Role } from "./roles.ts";
import { newId, stateDir, writeMeta, type Meta } from "./state.ts";

export type LaunchOpts = {
  role: Role;
  /** "provider/model" — split at the first slash; bare ids get no --provider. */
  model: string;
  label: string;
  task: string;
  cwd: string;
  skills: string[];
  extras: string[];
  ownerSession: string;
  ownerPid: number;
  maxMinutes: number;
  /** Idle-flag threshold in minutes; 0 disables (the caller resolves defaults). */
  idleMinutes?: number;
};

const runMjs = fileURLToPath(new URL("./run.mjs", import.meta.url));

/** Where the pi-lens / pi-web-access / pi-playwright packages live. */
export function npmRoot(): string {
  return process.env.PI_SUB_NPM_ROOT ?? join(homedir(), ".pi", "agent", "npm", "node_modules");
}

/**
 * Extension/skill arguments for a role. Write-capable roles get pi-lens with
 * its writing side effects disabled; "web" and "playwright" extras map to
 * their installed packages (playwright has no extension, only a skill).
 */
export function extraExtensions(role: Role, extras: string[]): string[] {
  const argv: string[] = [];
  if (role.writeCapable) {
    argv.push("-e", join(npmRoot(), "pi-lens/dist/index.js"), "--no-autofix", "--no-autoformat", "--no-tests");
  }
  for (const extra of extras) {
    if (extra === "web") argv.push("-e", join(npmRoot(), "pi-web-access/dist"));
    else if (extra === "playwright") argv.push("--skill", join(npmRoot(), "pi-playwright/skills/playwright-browser"));
  }
  return argv;
}

/**
 * The exact child argv: `pi --mode json ... <task>`. The returned argv[0] is
 * "pi" — run.mjs spawns `$PI_SUB_PI_BIN ?? "pi"` with the rest. A task that
 * starts with "-" is passed verbatim, behind pi's `--` separator so it is
 * still treated as the message.
 */
export function buildArgv(o: {
  role: Role;
  model: string;
  task: string;
  skills: string[];
  extras: string[];
  promptFile: string;
}): string[] {
  const [provider, model] = o.model.includes("/")
    ? [o.model.slice(0, o.model.indexOf("/")), o.model.slice(o.model.indexOf("/") + 1)]
    : [undefined, o.model];
  const argv = [
    "pi",
    "--mode", "json",
    "--no-session",
    "--no-extensions",
    "--no-skills",
    "--no-context-files",
    "--no-prompt-templates",
    "--tools", o.role.tools.join(","),
  ];
  if (provider !== undefined) argv.push("--provider", provider);
  argv.push("--model", model, "--append-system-prompt", o.promptFile);
  for (const skill of o.skills) argv.push("--skill", skill);
  argv.push(...extraExtensions(o.role, o.extras));
  if (o.task.startsWith("-")) argv.push("--");
  argv.push(o.task);
  return argv;
}

/**
 * Spawn the wrapper detached in its own process group. The wrapper's pid is
 * its pgid (POSIX detached spawn), so one kill(-pgid) reaches the wrapper
 * and the pi child together. The child outlives this process: stdio is
 * ignored and the handle is unref'd.
 */
export function launch(o: LaunchOpts): Meta {
  if (!existsSync(o.cwd)) {
    throw new Error(`pi-sub: cwd does not exist: ${o.cwd}`);
  }
  const id = newId(new Date());
  const dir = join(stateDir(), id);
  mkdirSync(dir, { recursive: true });
  const promptFile = join(dir, "prompt.md");
  writeFileSync(promptFile, `${o.role.body}\n`);
  const argv = buildArgv({
    role: o.role,
    model: o.model,
    task: o.task,
    skills: o.skills,
    extras: o.extras,
    promptFile,
  });
  const meta: Meta = {
    id,
    role: o.role.name,
    model: o.model,
    label: o.label,
    task: o.task,
    cwd: o.cwd,
    skills: o.skills,
    extras: o.extras,
    pid: 0,
    pgid: 0,
    started_at: new Date().toISOString(),
    owner_session: o.ownerSession,
    owner_pid: o.ownerPid,
    idle_minutes: o.idleMinutes ?? 0,
    max_minutes: o.maxMinutes,
    argv,
  };
  // Written before the spawn: run.mjs reads it as soon as it starts.
  writeMeta(meta);
  const child = spawn(process.execPath, [runMjs, dir], {
    detached: true,
    stdio: "ignore",
    cwd: o.cwd,
    env: { ...process.env, PI_SUBAGENT: "1", PI_SUB_ID: id },
  });
  // A failed spawn emits 'error' only after launch() returns; this listener
  // keeps it from crashing the host, while the pid check below reports it.
  child.on("error", () => {});
  if (child.pid === undefined) {
    // Remove the dir so a dead spawn does not linger as a "running" agent.
    rmSync(dir, { recursive: true, force: true });
    throw new Error(`pi-sub: could not start wrapper: ${process.execPath} ${runMjs} (cwd: ${o.cwd})`);
  }
  child.unref();
  meta.pid = child.pid;
  meta.pgid = child.pid;
  writeMeta(meta);
  return meta;
}
