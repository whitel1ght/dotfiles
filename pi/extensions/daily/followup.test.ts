import { test } from "node:test";
import assert from "node:assert/strict";

import { FollowupDelivery, decisionsSession } from "./followup.ts";
import { followupPrompt } from "./mod/followup.ts";

const CARD = { id: "D-180", kind: "answer", status: "open", question: "Why is CI red?", session: "pid:42", followup: "and the flaky one?", discussion_count: 1 };

function setup(stdout: () => string) {
  const sent: string[] = [];
  const f = new FollowupDelivery({ list: async () => stdout(), session: "pid:42", send: (text) => void sent.push(text) });
  return { f, sent };
}

test("the session id is the one the decisions MCP server stamps: DECISIONS_OWNER, CLAUDE_CODE_SESSION_ID, then pid", () => {
  assert.equal(decisionsSession({ DECISIONS_OWNER: "me", CLAUDE_CODE_SESSION_ID: "cc" }, 42), "me");
  assert.equal(decisionsSession({ DECISIONS_OWNER: "", CLAUDE_CODE_SESSION_ID: "cc" }, 42), "cc");
  assert.equal(decisionsSession({}, 42), "pid:42");
});

test("a follow-up on this session's answer card is sent once, a newer one again", async () => {
  let cards = [CARD];
  const { f, sent } = setup(() => JSON.stringify(cards));
  await f.tick();
  await f.tick();
  assert.deepEqual(sent, [followupPrompt([CARD])]);
  const next = { ...CARD, followup: "and the other test?", discussion_count: 3 };
  cards = [next];
  await f.tick();
  assert.deepEqual(sent, [followupPrompt([CARD]), followupPrompt([next])]);
});

test("another session's card or a failed list sends nothing", async () => {
  for (const stdout of [JSON.stringify([{ ...CARD, session: "pid:7" }]), ""]) {
    const { f, sent } = setup(() => stdout);
    await f.tick();
    assert.deepEqual(sent, []);
  }
});
