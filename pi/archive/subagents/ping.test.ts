import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { Pinger, ProcessPing, pingArgs, type PingResult } from "./src/ping.ts";

const fakePi = [process.execPath, join(import.meta.dirname, "test", "fake-pi.mjs")];

test("a ping is a tool-less, prompt-less one-liner that keeps extensions on", () => {
  const args = pingArgs("claude-bridge/claude-haiku-4-5");
  assert.equal(args[args.indexOf("--model") + 1], "claude-bridge/claude-haiku-4-5");
  for (const flag of ["--no-tools", "-ns", "-nc", "-np", "--no-session"]) assert.ok(args.includes(flag), flag);
  assert.ok(!args.includes("--no-extensions"));
});

test("a model that answers passes", async () => {
  const result = await new ProcessPing(fakePi, 5000).ping("fake/ok");
  assert.equal(result.ok, true);
});

test("a provider rejection fails with the provider's reason", async () => {
  const result = await new ProcessPing(fakePi, 5000).ping("fake/reject");
  assert.deepEqual([result.ok, result.reason], [false, "401 Invalid API key."]);
});

test("pi dying before any model call fails with its stderr", async () => {
  const result = await new ProcessPing(fakePi, 5000).ping("fake/crash");
  assert.equal(result.ok, false);
  assert.match(result.reason!, /no API key for provider fake/);
});

test("no answer in time fails, and the child is killed", async () => {
  const started = Date.now();
  const result = await new ProcessPing(fakePi, 400).ping("fake/hang");
  assert.deepEqual([result.ok, result.reason], [false, "no answer within 0s"]);
  assert.ok(Date.now() - started < 3000);
});

test("results are cached, failures for less long, and parallel callers share one ping", async () => {
  let clock = 0;
  let calls = 0;
  const answers: Record<string, boolean> = { good: true, bad: false };
  const fn = async (model: string): Promise<PingResult> => {
    calls++;
    await new Promise((r) => setTimeout(r, 10));
    return { ok: answers[model], ms: 10 };
  };
  const pinger = new Pinger(fn, 300_000, () => clock);
  await Promise.all([pinger.ping("good"), pinger.ping("good"), pinger.ping("good")]);
  assert.equal(calls, 1);
  clock = 200_000;
  await pinger.ping("good");
  assert.equal(calls, 1);
  clock = 400_000;
  await pinger.ping("good");
  assert.equal(calls, 2);

  await pinger.ping("bad");
  clock += 59_000;
  await pinger.ping("bad");
  assert.equal(calls, 3);
  clock += 2_000;
  await pinger.ping("bad");
  assert.equal(calls, 4);

  pinger.forget("good");
  await pinger.ping("good");
  assert.equal(calls, 5);
});
