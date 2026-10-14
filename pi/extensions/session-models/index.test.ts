import assert from "node:assert/strict";
import test from "node:test";
import sessionModels, { liveModels } from "./index.ts";

const model = (provider: string, id: string) => ({ provider, id });

function harness() {
  const handlers = {};
  sessionModels({ on(event, callback) {
    handlers[event] = callback;
  } });
  const handler = handlers.before_agent_start;
  assert.equal(typeof handler, "function");
  assert.equal(typeof handlers.before_provider_request, "function");
  const model = (provider, id) => ({ provider, id });
  const a = model("openai", "coding");
  const b = model("cheap", "reader");
  const ctx = {
    scopedModels: [{ model: a }, { model: b }],
    model: a,
    modelRegistry: { getAvailable: () => [a, b, model("other", "excluded")] },
  };
  const event = { systemPromptOptions: { sections: { rules: "Keep these" } }, systemPrompt: "Existing instructions" };
  const run = (ev = event) => {
    handler(ev, ctx);
    return ev.systemPromptOptions.sections.subagent_models;
  };
  return { handler, ctx, event, run, a, b, handlers };
}

test("exposes only selected models that are still available, leaving other sections alone", () => {
  const { ctx, event, run, a } = harness();
  ctx.modelRegistry.getAvailable = () => [a, { provider: "other", id: "excluded" }];
  const section = run();
  assert.match(section, /openai\/coding/);
  assert.doesNotMatch(section, /cheap\/reader|other\/excluded/);
  assert.equal(event.systemPromptOptions.sections.rules, "Keep these");
});

test("refreshes the scope on each turn instead of caching an old list", () => {
  const { ctx, run, b } = harness();
  run();
  ctx.scopedModels = [{ model: b }, { model: b }];
  const section = run({ systemPromptOptions: { sections: {} } });
  assert.doesNotMatch(section, /openai\/coding/);
  assert.equal(section.match(/cheap\/reader/g)?.length, 1);
});

test("empty scope matches upstream's current-model-only fallback", () => {
  const { ctx, run } = harness();
  ctx.scopedModels = [];
  const section = run();
  assert.match(section, /openai\/coding/);
  assert.doesNotMatch(section, /cheap\/reader|other\/excluded/);
});

test("does not broaden a selected scope when all selected models are unavailable", () => {
  const { ctx, run } = harness();
  ctx.modelRegistry.getAvailable = () => [{ provider: "other", id: "excluded" }];
  const section = run();
  assert.match(section, /Do not launch/);
  assert.doesNotMatch(section, /openai\/coding|cheap\/reader|other\/excluded/);
});

test("missing parent and empty scope fail closed", () => {
  const { ctx, run } = harness();
  ctx.scopedModels = [];
  ctx.model = undefined;
  assert.match(run(), /Do not launch/);
});

test("liveModels lists the selected, available model ids", () => {
  const a = model("openai", "coding");
  const b = model("cheap", "reader");
  const ctx = {
    scopedModels: [{ model: b }, { model: a }, { model: a }],
    model: a,
    modelRegistry: { getAvailable: () => [a, b, model("other", "excluded")] },
  };
  assert.deepEqual(liveModels(ctx), ["cheap/reader", "openai/coding"]);
});

test("liveModels falls back to the current model on an empty scope", () => {
  const a = model("openai", "coding");
  const ctx = { scopedModels: [], model: a, modelRegistry: { getAvailable: () => [a] } };
  assert.deepEqual(liveModels(ctx), ["openai/coding"]);
});

test("warns once when the section stops reaching the provider request", () => {
  const { handlers } = harness();
  const seen = [];
  const ctx = { ui: { notify: (message, type) => seen.push([message, type]) } };
  const request = (payload) => handlers.before_provider_request({ payload }, ctx);
  request({ messages: [{ role: "system", content: "something else" }] });
  request({ messages: [{ role: "system", content: "still nothing" }] });
  assert.equal(seen.length, 1);
  assert.equal(seen[0][1], "error");
  assert.match(seen[0][0], /NOT in the provider request/);
});

test("stays quiet when the injected section is in the request", () => {
  const { handlers, run } = harness();
  const seen = [];
  const ctx = { ui: { notify: (message) => seen.push(message) } };
  const section = run();
  handlers.before_provider_request(
    { payload: { messages: [{ role: "system", content: `<subagent_models>\n${section}\n</subagent_models>` }] } },
    ctx,
  );
  assert.deepEqual(seen, []);
});

test("the payload check keys on the section text, not on the tag prose can fake", () => {
  const { handlers } = harness();
  const seen = [];
  const ctx = { ui: { notify: (message) => seen.push(message) } };
  handlers.before_provider_request(
    { payload: { messages: [{ role: "system", content: "pick from the live <subagent_models> list" }] } },
    ctx,
  );
  assert.equal(seen.length, 1);
});

test("a broken self-check never fails the request", () => {
  const { handlers } = harness();
  assert.doesNotThrow(() => handlers.before_provider_request({ payload: undefined }, {}));
});
