import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { IdeasNudger } from "./ideas.ts";
import { IDLE_MS, PI_NUDGE_TEXT } from "./mod/ideas.ts";

function setup(session = "sess-1", due = true) {
  const home = mkdtempSync(join(tmpdir(), "ideas-"));
  let now = 1_000_000;
  const sent: string[] = [];
  const nudger = new IdeasNudger({
    now: () => now,
    stateHome: () => home,
    session: () => session,
    due: async () => due,
    send: (text) => void sent.push(text),
  });
  return { home, nudger, sent, later: (ms: number) => void (now += ms), cleanup: () => rmSync(home, { recursive: true, force: true }) };
}

test("typing /system marks the session", async () => {
  const s = setup();
  s.nudger.onInput("/system", "interactive");
  assert.equal(readFileSync(join(s.home, "ideas", "system.session"), "utf8"), "sess-1\n");
  s.cleanup();
});

test("an idle marked session is nudged once with pi's command", async () => {
  const s = setup();
  s.nudger.onInput("/system", "interactive");
  s.later(IDLE_MS);
  await s.nudger.tick();
  await s.nudger.tick();
  assert.deepEqual(s.sent, [PI_NUDGE_TEXT]);
  s.cleanup();
});

test("never in a session that is not marked", async () => {
  const s = setup();
  s.later(IDLE_MS);
  await s.nudger.tick();
  assert.deepEqual(s.sent, []);
  s.cleanup();
});

test("not before 15 minutes, nor while a turn runs, nor with nothing due", async () => {
  const s = setup();
  s.nudger.onInput("/system", "interactive");
  s.later(IDLE_MS - 1);
  await s.nudger.tick();
  s.nudger.onAgentStart();
  s.later(IDLE_MS);
  await s.nudger.tick();
  assert.deepEqual(s.sent, []);
  const quiet = setup("sess-2", false);
  quiet.nudger.onInput("/system", "interactive");
  quiet.later(IDLE_MS);
  await quiet.nudger.tick();
  assert.deepEqual(quiet.sent, []);
  s.cleanup();
  quiet.cleanup();
});

test("the user writing again allows the next round; an extension's input does not", async () => {
  const s = setup();
  s.nudger.onInput("/system", "interactive");
  s.later(IDLE_MS);
  await s.nudger.tick();
  s.nudger.onInput("[daily-event] something", "extension");
  s.later(IDLE_MS);
  await s.nudger.tick();
  assert.equal(s.sent.length, 1, "an extension's message is not the user writing");
  s.nudger.onInput("thanks, later for all three", "interactive");
  s.nudger.onAgentStart();
  s.nudger.onAgentEnd();
  s.later(IDLE_MS);
  await s.nudger.tick();
  assert.equal(s.sent.length, 2);
  s.cleanup();
});

test("the user writing while `ideas due` runs cancels the nudge", async () => {
  const home = mkdtempSync(join(tmpdir(), "ideas-"));
  let now = 1_000_000;
  const sent: string[] = [];
  let nudger: IdeasNudger;
  nudger = new IdeasNudger({
    now: () => now,
    stateHome: () => home,
    session: () => "sess-1",
    due: async () => {
      nudger.onInput("one more thing", "interactive");
      return true;
    },
    send: (text) => void sent.push(text),
  });
  nudger.onInput("/system", "interactive");
  now += IDLE_MS;
  await nudger.tick();
  assert.deepEqual(sent, []);
  rmSync(home, { recursive: true, force: true });
});

test("a /system in another session moves the mark there", async () => {
  const a = setup("sess-a");
  const b = setup("sess-b");
  b.nudger = new IdeasNudger({ now: () => 2 * IDLE_MS, stateHome: () => a.home, session: () => "sess-b", due: async () => true, send: (t) => void b.sent.push(t) });
  a.nudger.onInput("/system", "interactive");
  b.nudger.onInput("/system", "interactive");
  a.later(IDLE_MS);
  await a.nudger.tick();
  assert.deepEqual(a.sent, []);
  a.cleanup();
  b.cleanup();
});
