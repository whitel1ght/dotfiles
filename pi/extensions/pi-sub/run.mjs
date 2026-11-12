#!/usr/bin/env node
// Plain-node wrapper for one subagent run: spawns the child `pi` (no shell,
// no detach — one kill(-pgid) reaches both of us), tees its JSONL events and
// stderr into the agent dir, and on close writes result.md then exit.json.
// Usage: node run.mjs <agentDir>. Reads meta.json for argv/cwd; the pi
// binary comes from PI_SUB_PI_BIN (default "pi").

import { spawn } from "node:child_process";
import { existsSync, openSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { finalText } from "./events.ts";
import { atomicWrite } from "./state.ts";

const dir = process.argv[2];
if (!dir) {
  process.stderr.write("usage: node run.mjs <agentDir>\n");
  process.exit(1);
}
let meta;
try {
  meta = JSON.parse(readFileSync(join(dir, "meta.json"), "utf8"));
} catch (err) {
  atomicWrite(join(dir, "result.md"), "");
  const exit = { code: null, signal: null, ended_at: new Date().toISOString(), how: "failed", error: String(err) };
  atomicWrite(join(dir, "exit.json"), `${JSON.stringify(exit, null, 2)}\n`);
  process.exit(1);
}

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

// Exactly one terminal record: the 'error' path (pi missing, bad cwd) marks
// the run ended, so the 'close' that Node still fires (code -2) cannot write
// a second, conflicting exit.json.
let ended = false;

child.on("error", (err) => {
  if (ended) return;
  ended = true;
  // result.md first, then exit.json last: its presence is what pollers
  // treat as "the run ended", so the agent never looks running forever.
  atomicWrite(join(dir, "result.md"), "");
  const exit = { code: null, signal: null, ended_at: new Date().toISOString(), how: "failed", error: String(err) };
  atomicWrite(join(dir, "exit.json"), `${JSON.stringify(exit, null, 2)}\n`);
  process.exit(1);
});

child.on("close", (code, signal) => {
  if (ended) return;
  ended = true;
  const events = readEvents(join(dir, "events.jsonl"));
  const hasAssistant = events.some((ev) => ev.type === "message_end" && ev.message?.role === "assistant");
  atomicWrite(join(dir, "result.md"), finalText(events));
  const stopPath = join(dir, "stop-request.json");
  let how = "failed";
  let by;
  if (existsSync(stopPath)) {
    how = "stopped";
    by = readStopBy(stopPath);
  } else if (code === 0 && hasAssistant) {
    how = "done";
  }
  const error = how === "failed" && code === 0 ? "Pi exited with no assistant response" : undefined;
  const exit = { code, signal, ended_at: new Date().toISOString(), how, ...(by !== undefined ? { by } : {}), ...(error ? { error } : {}) };
  // exit.json goes last: its presence is what pollers treat as "the run ended".
  atomicWrite(join(dir, "exit.json"), `${JSON.stringify(exit, null, 2)}\n`);
  process.exit(how === "failed" ? code || 1 : code ?? 1);
});

// A malformed or half-written stop request must not keep exit.json from
// being written: fall back to how "stopped" with no by.
function readStopBy(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8")).by;
  } catch {
    return undefined;
  }
}

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
