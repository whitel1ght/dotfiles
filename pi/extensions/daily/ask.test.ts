import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { AskBackstop, piSubRunning } from "./ask.ts";
import { ASK_NUDGE, BUSY_NOTE, FORM_DENY } from "./mod/ask.ts";

function setup(agents = 0) {
  const notes: string[] = [];
  const nudges: string[] = [];
  const s = { agents };
  const ask = new AskBackstop({
    agentsRunning: () => s.agents,
    note: (text) => void notes.push(text),
    nudge: (text) => void nudges.push(text),
  });
  return { ask, notes, nudges, s };
}

const said = (text: string) => [{ role: "assistant", content: [{ type: "text", text }] }];

test("the question form is blocked and points to the deck", () => {
  const { ask } = setup();
  assert.deepEqual(ask.onToolCall("ask_user_question"), { block: true, reason: FORM_DENY });
  assert.equal(ask.onToolCall("bash"), undefined);
});

test("input during a run or beside running agents gets the tell_user note", () => {
  const t = setup();
  t.ask.onInput("interactive", "steer");
  assert.deepEqual(t.notes, [BUSY_NOTE]);
  t.ask.onInput("interactive", undefined);
  assert.equal(t.notes.length, 1, "idle input: no note");
  t.s.agents = 1;
  t.ask.onInput("interactive", undefined);
  assert.equal(t.notes.length, 2);
  t.ask.onInput("extension", "steer");
  assert.equal(t.notes.length, 2, "extension input is not the user's");
});

test("a run that ends asking with no card filed is nudged once per user message", () => {
  const t = setup();
  t.ask.onInput("interactive", undefined);
  t.ask.onAgentEnd(said("Done. Shall I merge it?"));
  t.ask.onAgentEnd(said("Merge it?"));
  assert.deepEqual(t.nudges, [ASK_NUDGE]);
  t.ask.onInput("interactive", undefined);
  t.ask.onAgentEnd(said("Merge now?"));
  assert.equal(t.nudges.length, 2);
});

test("no nudge after ask_user, or when the run ends without asking", () => {
  const t = setup();
  t.ask.onInput("interactive", undefined);
  t.ask.onAgentEnd(said("Merged."));
  t.ask.onToolCall("mcp__decisions__ask_user");
  t.ask.onAgentEnd(said("asked in decisions: D-7. Merge it?"));
  assert.deepEqual(t.nudges, []);
});

test("the last assistant text is read, whatever came after it", () => {
  const t = setup();
  t.ask.onInput("interactive", undefined);
  t.ask.onAgentEnd([...said("Shall I merge it?"), { role: "toolResult", content: [{ type: "text", text: "ok." }] }]);
  assert.equal(t.nudges.length, 1);
});

test("pi-sub agents of this session without an exit count as running", () => {
  const dir = mkdtempSync(join(tmpdir(), "pi-sub-"));
  const agent = (id: string, owner: string, exited: boolean) => {
    mkdirSync(join(dir, id));
    writeFileSync(join(dir, id, "meta.json"), JSON.stringify({ id, owner_session: owner }));
    if (exited) writeFileSync(join(dir, id, "exit.json"), "{}");
  };
  agent("a1", "me", false);
  agent("a2", "me", true);
  agent("a3", "other", false);
  mkdirSync(join(dir, "broken"));
  assert.equal(piSubRunning("me", dir), 1);
  assert.equal(piSubRunning("me", join(dir, "missing")), 0);
  rmSync(dir, { recursive: true, force: true });
});
