import { writeFileSync } from "node:fs";
import { formatDuration } from "../../background-terminals/src/format.ts";
import { currentAttempt, currentModel, result, totalCost, totalToolCalls, type Agent, type Attempt } from "./agents.ts";

const RESULT_BYTES = 16 * 1024;
const WAKE_RESULT_BYTES = 8 * 1024;
const RUNNING_ACTIVITY = 10;

export function elapsed(agent: Agent, now = Date.now()): string {
  return formatDuration((agent.endedAt ?? now) - agent.startedAt);
}

export function cost(value: number): string {
  return value ? `$${value < 0.01 ? value.toFixed(4) : value.toFixed(2)}` : "$0";
}

// `agent-1 [done] explore on opencode-go/glm-5.3-flash "find the parser" (45s, 3 tool calls, $0.0021)`
export function describe(agent: Agent, now = Date.now()): string {
  const as = agent.profile ? ` as ${agent.profile}` : "";
  const live = currentAttempt(agent);
  const phase = agent.status === "running" && live?.outcome === "pinging" ? ", pinging" : "";
  const fallbacks = agent.attempts.length - 1;
  const hops = fallbacks > 0 ? `, after ${fallbacks} fallback${fallbacks === 1 ? "" : "s"}` : "";
  const calls = totalToolCalls(agent);
  return (
    `${agent.id} [${agent.status}] ${agent.type}${as} on ${currentModel(agent)} "${agent.title}" ` +
    `(${elapsed(agent, now)}${phase}${hops}, ${calls} tool call${calls === 1 ? "" : "s"}, ${cost(totalCost(agent))})`
  );
}

export function attemptLine(attempt: Attempt): string {
  return `- ${attempt.model}: ${attempt.outcome}${attempt.reason ? ` (${attempt.reason.replace(/\s+/g, " ")})` : ""}`;
}

function attemptsSection(agent: Agent): string | undefined {
  if (agent.attempts.length < 2 && agent.status !== "failed") return undefined;
  return `Models tried:\n${agent.attempts.map(attemptLine).join("\n")}`;
}

export function transcriptNote(agent: Agent): string {
  const paths = agent.attempts.filter((a) => a.terminal).map((a) => `${a.model}: ${a.terminal!.stdout.path}`);
  return paths.length ? `Transcript (pi JSON events): ${paths.join(" , ")}` : "No transcript: no model got as far as running.";
}

// The answer, bounded by bytes. When it is cut, the whole answer goes to a file next to the transcript.
export function boundedResult(agent: Agent, maxBytes: number): string {
  const text = result(agent);
  if (Buffer.byteLength(text) <= maxBytes) return text;
  const path = currentAttempt(agent)!.terminal!.stdout.path.replace(/\.stdout$/, ".result.md");
  try {
    writeFileSync(path, text);
  } catch {}
  const head = Buffer.from(text).subarray(0, maxBytes).toString("utf8").replace(/\uFFFD$/, "");
  return `${head}\n… [cut at ${maxBytes / 1024}KB; the whole answer is in ${path}]`;
}

export function renderOutput(agent: Agent): string {
  const parts = [describe(agent)];
  const attempts = attemptsSection(agent);
  if (attempts) parts.push(attempts);
  if (agent.status === "running") {
    const recent = currentAttempt(agent)?.run?.activity.slice(-RUNNING_ACTIVITY) ?? [];
    parts.push(recent.length ? `Recent activity:\n${recent.map((a) => `- ${a.kind === "tool" ? "→ " : ""}${a.text}`).join("\n")}` : "No activity yet.");
    parts.push("Still running; you will be told when it finishes.");
  } else if (agent.status === "done") {
    parts.push(`--- result ---\n${boundedResult(agent, RESULT_BYTES)}`);
  } else if (agent.failure && !attempts) {
    parts.push(`Failed: ${agent.failure}`);
  }
  parts.push(transcriptNote(agent));
  return parts.join("\n");
}

export function wakeMessage(agents: Agent[]): string {
  return agents
    .map((agent) => {
      const parts = [`Subagent ${describe(agent)} has finished.`];
      const attempts = attemptsSection(agent);
      if (attempts) parts.push(attempts);
      if (agent.status === "done") parts.push(`--- result ---\n${boundedResult(agent, WAKE_RESULT_BYTES)}`);
      parts.push(transcriptNote(agent));
      return parts.join("\n");
    })
    .join("\n\n");
}
