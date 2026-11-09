import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  ASK,
  QuestionMirror,
  WAIT,
  answerArgs,
  callOptions,
  outcomeOf,
  parseQuestions,
  queueDir,
  questionLines,
  readCard,
  routeInput,
  widgetLine,
  type Question,
} from "./question.ts";

const CARD = {
  id: "D-548",
  question: "Ship it?",
  options: [
    { n: 1, text: "The agent ships it", recommended: true },
    { n: 2, text: "You ship it" },
  ],
  source: "pi · dotfiles",
};
const Q: Question = parseQuestions(JSON.stringify([CARD]))[0];

function setup(cards: () => unknown[], show = "") {
  let now = 0;
  const log: string[] = [];
  const m = new QuestionMirror({
    list: async () => JSON.stringify(cards()),
    show: async () => show,
    now: () => now,
    opened: (q) => void log.push(`opened ${q.id}`),
    render: (open) => void log.push(`render ${open.map((q) => q.id).join(",")}`),
    closed: (q, outcome, here) => void log.push(`closed ${q.id} ${outcome}${here ? " here" : ""}`),
  });
  return { m, log, later: (ms: number) => void (now += ms) };
}

test("list --json: open question cards only, options with their recommended mark", () => {
  const qs = parseQuestions(
    JSON.stringify([CARD, { ...CARD, id: "D-1", kind: "answer" }, { ...CARD, id: "D-2", status: "answered" }]),
  );
  assert.deepEqual(qs.map((q) => q.id), ["D-548"]);
  assert.deepEqual(qs[0].options, [
    { n: 1, text: "The agent ships it", recommended: true },
    { n: 2, text: "You ship it", recommended: false },
  ]);
  assert.deepEqual(parseQuestions("not json"), []);
});

test("an ask_user call is matched to the card asking the same question, shown once, then closed by a deck answer", async () => {
  let cards: unknown[] = [];
  const { m, log } = setup(() => cards, "status: answered\n\n## Answer\n2 — You ship it\nat: now\n");
  m.onToolCall(ASK, { question: " Ship it? ", options: ["a", "b"] });
  await m.tick();
  assert.deepEqual(log, []);
  cards = [CARD, { ...CARD, id: "D-9", question: "Other session?" }];
  await m.tick();
  await m.tick();
  assert.deepEqual(log, ["opened D-548", "render D-548"]);
  cards = [];
  await m.tick();
  assert.deepEqual(log.slice(2), ["closed D-548 2 — You ship it", "render "]);
  assert.equal(m.active, false);
});

test("a card answered in the session is reported as answered here", async () => {
  let cards: unknown[] = [CARD];
  const { m, log } = setup(() => cards, "status: answered\n\n## Answer\nyes, ship\n");
  m.onToolCall(WAIT, { id: "D-548" });
  await m.tick();
  m.answeredHere("D-548");
  cards = [];
  await m.tick();
  assert.deepEqual(log, ["opened D-548", "render D-548", "closed D-548 yes, ship here", "render "]);
});

test("an answer here that failed to write is taken back, so a later deck answer is not called here", async () => {
  let cards: unknown[] = [CARD];
  const { m, log } = setup(() => cards, "status: answered\n\n## Answer\n1 — The agent ships it\n");
  m.onToolCall(WAIT, { id: "D-548" });
  await m.tick();
  m.answeredHere("D-548");
  m.answeredHere("D-548", false);
  cards = [];
  await m.tick();
  assert.equal(log[2], "closed D-548 1 — The agent ships it");
});

test("a question never filed is dropped after a while; a failed list changes nothing", async () => {
  const { m, log, later } = setup(() => []);
  m.onToolCall(ASK, { question: "Refused?" });
  later(31_000);
  await m.tick();
  assert.equal(m.active, false);

  const failing = new QuestionMirror({
    list: async () => "",
    show: async () => "",
    now: () => 0,
    opened: () => void log.push("opened"),
    render: () => void log.push("render"),
    closed: () => void log.push("closed"),
  });
  failing.onToolCall(WAIT, { id: "D-548" });
  await failing.tick();
  assert.deepEqual(log, []);
  assert.equal(failing.active, true);
});

test("a card named by wait_for_answer but already gone shows nothing", async () => {
  const { m, log } = setup(() => []);
  m.onToolCall(WAIT, { id: "D-1" });
  await m.tick();
  assert.deepEqual(log, []);
  assert.equal(m.active, false);
});

test("an option number picks it; anything else is the user's own words", () => {
  assert.deepEqual(answerArgs(Q, " 2 "), ["answer", "D-548", "2"]);
  assert.deepEqual(answerArgs(Q, "3"), ["tell", "D-548", "3"]);
  assert.deepEqual(answerArgs(Q, "go with 1 but wait for CI"), ["tell", "D-548", "go with 1 but wait for CI"]);
});

test("a typed message answers the newest open question; it reaches the agent only when the agent is not waiting on it", () => {
  const other = { ...Q, id: "D-600", question: "Later one?" };
  assert.deepEqual(routeInput([Q, other], "1", true), { id: "D-600", args: ["answer", "D-600", "1"] });
  assert.deepEqual(routeInput([Q], "1", true), { id: "D-548", args: ["answer", "D-548", "1"] });
  const r = routeInput([Q], "yes", false);
  assert.deepEqual(r?.args, ["tell", "D-548", "yes"]);
  assert.match(r?.passThrough ?? "", /D-548.*yes$/);
  assert.equal(routeInput([], "yes", true), undefined);
  assert.equal(routeInput([Q], "/reload", true), undefined);
  assert.equal(routeInput([Q], "  ", true), undefined);
});

test("question lines number the options and star the recommended one; the widget names the card", () => {
  assert.deepEqual(questionLines(Q), ["✋ D-548 · Ship it?", "   1) The agent ships it ★", "   2) You ship it"]);
  assert.deepEqual(callOptions({ options: ["a", "b"], recommended: 2 }), [
    { n: 1, text: "a", recommended: false },
    { n: 2, text: "b", recommended: true },
  ]);
  assert.match(widgetLine([Q]), /D-548 is open/);
  assert.match(widgetLine([Q, { ...Q, id: "D-600" }]), /D-600 is open \(\+1 more open\)/);
  assert.equal(widgetLine([]), "");
});

test("outcome: the answer's first line, withdrawn, or the status", () => {
  assert.equal(outcomeOf("status: answered\n\n## Answer\n1 — The agent ships it\nat: x\n"), "1 — The agent ships it");
  assert.equal(outcomeOf("status: withdrawn\n"), "withdrawn");
  assert.equal(outcomeOf(""), "closed");
});

test("a card is read from the queue or from done/<day>/", () => {
  const dir = mkdtempSync(join(tmpdir(), "q-"));
  writeFileSync(join(dir, "D-1.md"), "open one");
  mkdirSync(join(dir, "done", "2026-11-09"), { recursive: true });
  writeFileSync(join(dir, "done", "2026-11-09", "D-2.md"), "filed one");
  assert.equal(readCard("D-1", dir), "open one");
  assert.equal(readCard("D-2", dir), "filed one");
  assert.equal(readCard("D-3", dir), "");
  assert.equal(queueDir({ DECISIONS_DIR: "/q" }), "/q");
  assert.equal(queueDir({ RUN_DAY_STATE_DIR: "/s" }), "/s/decisions");
});
