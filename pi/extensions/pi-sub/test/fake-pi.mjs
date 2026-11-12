#!/usr/bin/env node
// Test double for the child `pi` process run.mjs spawns. Echoes its argv as
// JSON events (message_end with assistant text), then exits with FAKE_EXIT
// (default 0). Sleeps FAKE_SLEEP ms first, so tests can race stop-requests
// or signals against a still-running child. Executable so run.mjs can spawn
// it directly (no shell): PI_SUB_PI_BIN=<this file>.

const sleep = Number(process.env.FAKE_SLEEP ?? 0);
if (sleep > 0) await new Promise((resolve) => setTimeout(resolve, sleep));

if (process.env.FAKE_HEADER_ONLY === "1") {
  console.log(JSON.stringify({ type: "session", version: 3, id: "test", timestamp: new Date().toISOString(), cwd: process.cwd() }));
  process.exit(0);
}

const argv = process.argv.slice(2);
const echoed = JSON.stringify({ argv, env: { PI_SUBAGENT: process.env.PI_SUBAGENT, PI_SUB_ID: process.env.PI_SUB_ID } });
const events = [
  { type: "message_end", message: { role: "user", content: argv.join(" ") } },
  { type: "message_end", message: { role: "assistant", content: [{ type: "text", text: echoed }] } },
];
for (const ev of events) console.log(JSON.stringify(ev));
process.stderr.write(`fake-pi argv: ${argv.join(" ")}\n`);
process.exit(Number(process.env.FAKE_EXIT ?? 0));
