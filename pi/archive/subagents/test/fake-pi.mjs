// Stands in for `pi --mode json`: behaves according to the --model it is given.
// A ping (the one-line "Reply with exactly: ok" prompt) is answered unless the
// model is meant to fail pings too.
const args = process.argv.slice(2);
const model = args[args.indexOf("--model") + 1];
const task = args.at(-1);
const isPing = task === "Reply with exactly: ok";
const emit = (event) => process.stdout.write(JSON.stringify(event) + "\n");
const say = (text, extra = {}) =>
  emit({ type: "message_end", message: { role: "assistant", model, content: text ? [{ type: "text", text }] : [], stopReason: "stop", usage: { cost: { total: 0.001 } }, ...extra } });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

emit({ type: "session" });
switch (isPing && !["fake/crash", "fake/reject", "fake/hang"].includes(model) ? "ping" : model) {
  case "ping":
    say("ok");
    break;
  case "fake/crash":
    process.stderr.write("Error: no API key for provider fake\n");
    process.exit(1);
  case "fake/reject":
    say("", { stopReason: "error", errorMessage: "401 Invalid API key." });
    break;
  case "fake/hang":
    await sleep(30_000);
    break;
  case "fake/stall":
    emit({ type: "message_update" });
    await sleep(30_000);
    break;
  case "fake/fail-run":
    emit({ type: "tool_execution_start", toolName: "edit", args: { path: "a.ts" } });
    emit({ type: "tool_execution_end", toolName: "edit" });
    say("", { stopReason: "error", errorMessage: "500 upstream overloaded" });
    break;
  case "fake/slow":
    emit({ type: "tool_execution_start", toolName: "bash", args: { command: "sleep 30" } });
    await sleep(30_000);
    break;
  case "fake/slow-tool":
    emit({ type: "tool_execution_start", toolName: "bash", args: { command: "npm test" } });
    await sleep(1500);
    emit({ type: "tool_execution_end", toolName: "bash" });
    say("tests pass");
    break;
  default:
    if (task.includes("SLOWLY")) await sleep(1000);
    emit({ type: "tool_execution_start", toolName: "read", args: { path: "README.md" } });
    emit({ type: "tool_execution_end", toolName: "read" });
    say(`env=${process.env.PI_SUBAGENT} tools=${args.includes("--no-tools") ? "none" : args[args.indexOf("--tools") + 1]} lean=${args.includes("--no-extensions")}\n${task}`);
}
emit({ type: "agent_settled" });
