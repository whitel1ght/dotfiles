import assert from "node:assert/strict";
import test from "node:test";
import sessionModels from "./index.ts";

function harness() {
  let handler;
  sessionModels({ on(event, callback) {
    assert.equal(event, "context_with_system");
    handler = callback;
  } });
  const model = (provider, id) => ({ provider, id });
  const a = model("openai", "coding");
  const b = model("cheap", "reader");
  const ctx = {
    scopedModels: [{ model: a }, { model: b }],
    model: a,
    modelRegistry: { getAvailable: () => [a, b, model("other", "excluded")] },
  };
  const event = { messages: [
    { role: "system", content: "Existing instructions", sections: { rules: "Keep these" }, timestamp: 1 },
    { role: "user", content: "Do work", timestamp: 2 },
  ] };
  return { handler, ctx, event, a, b };
}

test("exposes only selected models that are still available, preserving the transcript", () => {
  const { handler, ctx, event, a } = harness();
  ctx.modelRegistry.getAvailable = () => [a, { provider: "other", id: "excluded" }];
  const before = structuredClone(event);
  const result = handler(event, ctx);
  const section = result.messages[0].sections.subagent_models;
  assert.match(section, /openai\/coding/);
  assert.doesNotMatch(section, /cheap\/reader|other\/excluded/);
  assert.equal(result.messages[0].content, "Existing instructions");
  assert.equal(result.messages[0].sections.rules, "Keep these");
  assert.deepEqual(result.messages.slice(1), event.messages.slice(1));
  assert.deepEqual(event, before);
});

test("refreshes scope on each request instead of caching an old list", () => {
  const { handler, ctx, event, b } = harness();
  const first = handler(event, ctx);
  ctx.scopedModels = [{ model: b }, { model: b }];
  const second = handler({ messages: first.messages }, ctx);
  const section = second.messages[0].sections.subagent_models;
  assert.doesNotMatch(section, /openai\/coding/);
  assert.equal(section.match(/cheap\/reader/g)?.length, 1);
});

test("empty scope matches upstream's current-model-only fallback", () => {
  const { handler, ctx, event } = harness();
  ctx.scopedModels = [];
  const section = handler(event, ctx).messages[0].sections.subagent_models;
  assert.match(section, /openai\/coding/);
  assert.doesNotMatch(section, /cheap\/reader|other\/excluded/);
});

test("does not broaden a selected scope when all selected models are unavailable", () => {
  const { handler, ctx, event } = harness();
  ctx.modelRegistry.getAvailable = () => [{ provider: "other", id: "excluded" }];
  const section = handler(event, ctx).messages[0].sections.subagent_models;
  assert.match(section, /Do not launch/);
  assert.doesNotMatch(section, /openai\/coding|cheap\/reader|other\/excluded/);
});

test("missing parent and empty scope fail closed", () => {
  const { handler, ctx, event } = harness();
  ctx.scopedModels = [];
  ctx.model = undefined;
  assert.match(handler(event, ctx).messages[0].sections.subagent_models, /Do not launch/);
});
