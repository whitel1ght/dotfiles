#!/usr/bin/env node
// Plain-node wrapper for one subagent run: spawns the child `pi` (no shell,
// no detach — one kill(-pgid) reaches both of us), tees its JSONL events and
// stderr into the agent dir, and on close writes result.md then exit.json.
// Usage: node run.mjs <agentDir>. Reads meta.json for argv/cwd; the pi
// binary comes from PI_SUB_PI_BIN (default "pi").

import { spawn } from "node:child_process";
import { existsSync, openSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import { finalText } from "./events.ts";

const dir = process.argv[2];
if (!dir) {
  process.stderr.write("usage: node run.mjs <agentDir>\n");
  process.exit(1);
}
const meta = JSON.parse(readFileSync(join(dir, "meta.json"), "utf8"));

const piBin = process.env.PI_SUB_PI_BIN ?? "pi";
const out = openSync(join(dir, "events.jsonl"), "w");
const err = openSync(join(dir, "stderr.log"), "w");

const child = spawn(piBin, meta.argv.slice(1), {
  cwd: meta.cwd,
  stdio: ["ignore", out, err],
});

// A SIGTERM to the process group reaches the child too; we forward nothing
// extra and stay alive so the close handler below can still record the exit.
process.on("SIGTERM", () => {});

child.on("close", (code, signal) => {
  writeFileSync(join(dir, "result.md"), finalText(readEvents(join(dir, "events.jsonl"))));
  const stopPath = join(dir, "stop-request.json");
  let how = "failed";
  let by;
  if (existsSync(stopPath)) {
    how = "stopped";
    by = JSON.parse(readFileSync(stopPath, "utf8")).by;
  } else if (code === 0) {
    how = "done";
  }
  const exit = { code, signal, ended_at: new Date().toISOString(), how, ...(by !== undefined ? { by } : {}) };
  // exit.json goes last: its presence is what pollers treat as "the run ended".
  writeFileSync(join(dir, "exit.json"), `${JSON.stringify(exit, null, 2)}\n`);
  process.exit(code ?? 1);
});

function readEvents(path) {
  try {
    return readFileSync(path, "utf8")
      .split("\n")
      .filter((line) => line.trim().length > 0)
      .map((line) => JSON.parse(line));
  } catch {
    return [];
  }
}
