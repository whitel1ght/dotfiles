import assert from "node:assert/strict";
import { test } from "node:test";
import { WakeQueue } from "./src/wake-queue.ts";

test("drain returns everything deferred, once", () => {
  const queue = new WakeQueue<{ id: string }>();
  queue.defer({ id: "a" });
  queue.defer({ id: "b" });
  assert.deepEqual(queue.drain().map((i) => i.id), ["a", "b"]);
  assert.equal(queue.size, 0);
  assert.deepEqual(queue.drain(), []);
});

test("a consumed item is never delivered", () => {
  const queue = new WakeQueue<{ id: string }>();
  queue.defer({ id: "a" });
  queue.defer({ id: "b" });
  assert.equal(queue.consume("a"), true);
  assert.equal(queue.consume("a"), false);
  assert.deepEqual(queue.drain().map((i) => i.id), ["b"]);
});
