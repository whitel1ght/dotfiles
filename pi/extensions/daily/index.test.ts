import assert from "node:assert/strict";
import { chmodSync, existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import daily, { directionsSection, guardVerdict, newlyNeedsYou, runStateSection } from "./index.ts";

const DAY = "2026-01-01";

const PLAN = [
  "# Thu Jan  1 09:00:00 +02 2026",
  "",
  "## Work",
  "",
  "<!-- start-day:start -->",
  "#### Plan",
  "",
  "**Today**",
  "- [ ] ecfx-1001 fix the export",
  "- [/] ecfx-1002 address review on backend !870",
  "<!-- start-day:end -->",
  "",
  "## Notes",
  "",
  "- my own line, never touched",
  "",
].join("\n");

const RUN_STATE = `# run-day ${DAY}
max_agents: 3
- ecfx-1001 | class=auto | agent=- | worktree=- | mr=- | retries=0 | needs_you=no | owner=main
notes:
  ecfx: export order settled
`;

function sandbox(opts: { runState?: boolean } = {}) {
  const root = mkdtempSync(join(tmpdir(), "daily-ext-"));
  const diary = join(root, "wiki", "diary", `${DAY}.md`);
  const stateDir = join(root, "state", "run-day");
  mkdirSync(join(root, "wiki", "diary"), { recursive: true });
  mkdirSync(join(stateDir, "inbox"), { recursive: true });
  writeFileSync(diary, PLAN);
  if (opts.runState !== false) writeFileSync(join(stateDir, `${DAY}.md`), RUN_STATE);
  process.env.RUN_DAY_STATE_DIR = stateDir;
  process.env.WIKI_DIR = join(root, "wiki");
  process.env.RUN_DAY_DATE = DAY;
  return { root, diary, stateDir, runState: join(stateDir, `${DAY}.md`) };
}

function cleanup(root: string) {
  rmSync(root, { recursive: true, force: true });
  delete process.env.RUN_DAY_STATE_DIR;
  delete process.env.WIKI_DIR;
  delete process.env.RUN_DAY_DATE;
}

function tick(diary: string, oldText: string, newText: string, active = true) {
  return guardVerdict("edit", { path: diary, edits: [{ oldText, newText }] }, DAY, active);
}

test("refuses a newly ticked [x] with no evidence", () => {
  const { root, diary } = sandbox();
  const verdict = tick(diary, "- [ ] ecfx-1001 fix the export", "- [x] ecfx-1001 fix the export");
  assert.ok(verdict);
  assert.match(verdict, /refusing to tick \[x\] without evidence/);
  assert.match(verdict, /ecfx-1001 fix the export/);
  cleanup(root);
});

test("accepts the same tick with an MR link, and with a note", () => {
  const { root, diary } = sandbox();
  assert.equal(
    tick(
      diary,
      "- [ ] ecfx-1001 fix the export",
      "- [x] ecfx-1001 fix the export · MR dashboard!2250  [↗][dashboard!2250]",
    ),
    undefined,
  );
  assert.equal(
    tick(diary, "- [ ] ecfx-1001 fix the export", "- [x] ecfx-1001 fix the export · note: user confirmed"),
    undefined,
  );
  cleanup(root);
});

test("leaves an already ticked line and an in-progress change alone", () => {
  const { root, diary } = sandbox();
  assert.equal(tick(diary, "- [/] ecfx-1002", "- [x] ecfx-1002 · merged"), undefined);
  assert.equal(tick(diary, "- [ ] ecfx-1001 fix the export", "- [/] ecfx-1001 fix the export"), undefined);
  cleanup(root);
});

test("applies every edit of a multi-edit call before judging", () => {
  const { root, diary } = sandbox();
  const verdict = guardVerdict(
    "edit",
    {
      path: diary,
      edits: [
        { oldText: "- [ ] ecfx-1001 fix the export", newText: "- [x] ecfx-1001 fix the export · merged" },
        { oldText: "- [/] ecfx-1002", newText: "- [x] ecfx-1002" },
      ],
    },
    DAY,
    true,
  );
  assert.ok(verdict);
  assert.match(verdict, /ecfx-1002/);
  assert.doesNotMatch(verdict, /ecfx-1001/);
  cleanup(root);
});

test("passes through what is not its business", () => {
  const { root, diary } = sandbox();
  // oldText that does not match: the edit tool's own failure, not a tick.
  assert.equal(tick(diary, "- [ ] nope", "- [x] nope"), undefined);
  // another file, another tool, and no active run.
  assert.equal(tick(join(root, "wiki", "index.md"), "- [ ] a", "- [x] a"), undefined);
  assert.equal(guardVerdict("bash", { command: "rm -rf /" }, DAY, true), undefined);
  assert.equal(tick(diary, "- [ ] ecfx-1001 fix the export", "- [x] ecfx-1001 fix the export", false), undefined);
  cleanup(root);
});

test("judges a whole-file write too", () => {
  const { root, diary } = sandbox();
  const bad = PLAN.replace("- [ ] ecfx-1001 fix the export", "- [x] ecfx-1001 fix the export");
  assert.ok(guardVerdict("write", { path: diary, content: bad }, DAY, true));
  cleanup(root);
});

test("injects the run state on every request, and stays silent with no run", () => {
  const { root, runState, stateDir } = sandbox();
  const section = runStateSection();
  assert.ok(section);
  assert.match(section, /A \/run-day session is active for 2026-01-01/);
  assert.match(section, /~\/\.pi\/agent\/prompts\/run-day\.md/);
  assert.match(section, /## Diary plan block/);
  assert.match(section, /ecfx-1002 address review/);
  assert.match(section, /## Run state/);
  assert.match(section, /export order settled/);
  assert.ok(section && section.length <= 6000);

  writeFileSync(join(stateDir, "inbox", `20260101T080000-ECFX-1001-ab12.md`), "---\n---\n");
  writeFileSync(join(stateDir, "inbox", "notes.tmp"), "half written");
  assert.match(runStateSection()!, /1 pending inbox message\(s\)/);

  rmSync(runState);
  assert.equal(runStateSection(), null);
  cleanup(root);
});

test("trims the diary block before the run state", () => {
  const { root, diary, runState } = sandbox();
  writeFileSync(diary, PLAN.replace("**Today**", `**Today**\n${"- [ ] filler line to make the plan block huge\n".repeat(200)}`));
  const section = runStateSection()!;
  assert.ok(section && section.length <= 6000);
  assert.match(section, /## Run state/);
  assert.match(section, /export order settled/);
  cleanup(root);
});

test("announces needs_you once per key", () => {
  const { root } = sandbox();
  const one = RUN_STATE.replace("needs_you=no", "needs_you=yes");
  assert.deepEqual(newlyNeedsYou(one), ["ecfx-1001"]);
  assert.deepEqual(newlyNeedsYou(one), []);
  cleanup(root);
});

test("registers both handlers and blocks only on a bad tick", () => {
  const { root, diary, runState } = sandbox();
  const handlers: Record<string, (event: unknown, ctx: unknown) => unknown> = {};
  daily({
    on(event: string, callback: (event: unknown, ctx: unknown) => unknown) {
      handlers[event] = callback;
    },
  } as never);
  assert.ok(handlers.before_agent_start);
  assert.ok(handlers.tool_call);

  const options = { sections: { rules: "Keep" } as Record<string, string> };
  handlers.before_agent_start({ systemPromptOptions: options }, { ui: undefined });
  assert.equal(options.sections.rules, "Keep");
  assert.match(options.sections.daily_run_state, /run-day session is active/);

  const blocked = handlers.tool_call(
    { toolName: "edit", input: { path: diary, edits: [{ oldText: "- [ ] ecfx-1001 fix the export", newText: "- [x] ecfx-1001 fix the export" }] } },
    {},
  ) as { block: boolean; reason: string };
  assert.equal(blocked.block, true);
  assert.match(blocked.reason, /without evidence/);

  assert.equal(handlers.tool_call({ toolName: "read", input: { path: diary } }, {}), undefined);

  // No active run: no section is set (pi diffs sections by name, so it disappears)
  // and the guard stands down.
  rmSync(runState);
  const next = { sections: {} as Record<string, string> };
  handlers.before_agent_start({ systemPromptOptions: next }, { ui: undefined });
  assert.equal(next.sections.daily_run_state, undefined);
  assert.equal(
    handlers.tool_call(
      { toolName: "edit", input: { path: diary, edits: [{ oldText: "- [/] ecfx-1002", newText: "- [x] ecfx-1002" }] } },
      {},
    ),
    undefined,
  );
  cleanup(root);
});

function directionsSandbox(script: string) {
  const root = mkdtempSync(join(tmpdir(), "daily-dir-"));
  mkdirSync(join(root, "friction"), { recursive: true });
  const file = join(root, "friction", "directions.md");
  const bin = join(root, "friction-ledger");
  const counter = join(root, "calls");
  writeFileSync(bin, script.replaceAll("$COUNTER", counter));
  chmodSync(bin, 0o755);
  process.env.FRICTION_WIKI = join(root, "friction");
  process.env.FRICTION_LEDGER_BIN = bin;
  return { root, file, bin, counter };
}

function directionsCleanup(root: string) {
  rmSync(root, { recursive: true, force: true });
  delete process.env.FRICTION_WIKI;
  delete process.env.FRICTION_LEDGER_BIN;
}

const calls = (counter: string) => (existsSync(counter) ? readFileSync(counter, "utf8").split("\n").filter(Boolean).length : 0);

test("directions: injects the rendered rules, cached until the file changes", () => {
  const { root, file, counter } = directionsSandbox('#!/bin/sh\necho x >> "$COUNTER"\ncat "$(dirname "$0")/friction/directions.md"\n');
  writeFileSync(file, "- rule one\n");
  const first = directionsSection();
  assert.match(first ?? "", /^## Standing directions\n/);
  assert.match(first ?? "", /- rule one/);
  directionsSection();
  directionsSection();
  assert.equal(calls(counter), 1, "cached across requests");
  writeFileSync(file, "- rule two\n");
  utimesSync(file, new Date(Date.now() + 5000), new Date(Date.now() + 5000));
  assert.match(directionsSection() ?? "", /- rule two/);
  assert.equal(calls(counter), 2, "re-read after the mtime changed");
  directionsCleanup(root);
});

test("directions: missing file, missing script or failing script inject nothing", () => {
  const { root, file, bin } = directionsSandbox("#!/bin/sh\necho '- r'\n");
  assert.equal(directionsSection(), null, "no directions file");
  writeFileSync(file, "x");
  rmSync(bin);
  assert.equal(directionsSection(), null, "no script");
  writeFileSync(bin, "#!/bin/sh\nexit 3\n");
  chmodSync(bin, 0o755);
  utimesSync(file, new Date(Date.now() + 9000), new Date(Date.now() + 9000));
  assert.equal(directionsSection(), null, "failing script");
  writeFileSync(bin, "#!/bin/sh\n:\n");
  utimesSync(file, new Date(Date.now() + 12000), new Date(Date.now() + 12000));
  assert.equal(directionsSection(), null, "empty render");
  directionsCleanup(root);
});

test("directions: before_agent_start sets the section, and never throws without one", () => {
  const { root, file } = directionsSandbox("#!/bin/sh\necho '- never retry with the model'\n");
  const handlers: Record<string, (event: unknown, ctx: unknown) => unknown> = {};
  daily({ on: (e: string, cb: (event: unknown, ctx: unknown) => unknown) => void (handlers[e] = cb) } as never);
  writeFileSync(file, "x");
  const options = { sections: {} as Record<string, string> };
  handlers.before_agent_start({ systemPromptOptions: options }, { ui: undefined });
  assert.match(options.sections.standing_directions, /never retry with the model/);
  rmSync(file);
  const next = { sections: {} as Record<string, string> };
  assert.doesNotThrow(() => handlers.before_agent_start({ systemPromptOptions: next }, { ui: undefined }));
  assert.equal(next.sections.standing_directions, undefined);
  directionsCleanup(root);
});
