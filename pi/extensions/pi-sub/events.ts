// Parses the events.jsonl a child `pi --mode json` writes: JSONL framing,
// live activity lines, the final answer, and run totals. Node built-ins only
// and no imports at all, so the plain-node wrapper (run.mjs) can import it. Shapes per pi 1.2.0
// docs/json.md; only LF terminates a record, and a trailing CR is allowed.

export type ActivityLine = {
  kind: "tool" | "think" | "stream" | "text";
  text: string;
  at: number;
};

const THINK_CHARS = 100;
const TOOL_ARG_CHARS = 60;

/**
 * Splits a UTF-8-decoded stream into complete JSONL records. Splits on LF
 * only (U+2028 etc. are valid inside JSON strings), keeps any CR in the
 * returned text, and holds a trailing partial record until its LF arrives.
 */
export class LineBuffer {
  private pending = "";

  push(chunk: string): string[] {
    const lines = (this.pending + chunk).split("\n");
    this.pending = lines.pop() ?? "";
    return lines.filter((l) => l.trim() !== "");
  }
}

/** Live display line for one event, or undefined when it changes nothing. */
export function toActivity(ev: object): ActivityLine | undefined {
  const e = ev as Record<string, any>;
  switch (e?.type) {
    case "tool_execution_start":
      return { kind: "tool", text: `${e.toolName}: ${shortArg(e.args)}`, at: Date.now() };
    case "message_update": {
      const ame = e.assistantMessageEvent;
      if (ame?.type === "thinking_delta") {
        return { kind: "think", text: oneLine(String(ame.delta)).slice(0, THINK_CHARS), at: Date.now() };
      }
      if (ame?.type === "text_delta") {
        return { kind: "stream", text: String(ame.delta), at: Date.now() };
      }
      return undefined;
    }
    case "message_end": {
      if (e.message?.role !== "assistant") return undefined;
      const text = textParts(e.message).trim();
      // The authoritative answer; tool-call-only turns say nothing new.
      return text ? { kind: "text", text, at: eventAt(e.message) } : undefined;
    }
    default:
      return undefined;
  }
}

/** Activity lines for a whole run; consecutive text deltas collapse to one stream line. */
export function activity(events: object[]): ActivityLine[] {
  const lines: ActivityLine[] = [];
  for (const ev of events) {
    const line = toActivity(ev);
    if (line === undefined) continue;
    const prev = lines[lines.length - 1];
    if (line.kind === "stream" && prev?.kind === "stream") prev.text += line.text;
    else lines.push(line);
  }
  return lines;
}

/**
 * The answer: the text of the last assistant message that has any. A
 * tool-call-only turn keeps the previous answer.
 */
export function finalText(events: object[]): string {
  let final = "";
  for (const ev of events) {
    const e = ev as Record<string, any>;
    if (e?.type !== "message_end" || e.message?.role !== "assistant") continue;
    const said = textParts(e.message).trim();
    if (said) final = said;
  }
  return final;
}

/** Run totals: tool executions and input tokens over assistant responses. */
export function stats(events: object[]): { toolCalls: number; tokensIn: number } {
  let toolCalls = 0;
  let tokensIn = 0;
  for (const ev of events) {
    const e = ev as Record<string, any>;
    if (e?.type === "tool_execution_start") toolCalls++;
    else if (e?.type === "message_end" && e.message?.role === "assistant") {
      const usage = e.message?.usage ?? {};
      tokensIn +=
        (Number(usage.input) || 0) +
        (Number(usage.cacheRead) || 0) +
        (Number(usage.cacheWrite) || 0);
    }
  }
  return { toolCalls, tokensIn };
}

function textParts(message: Record<string, any>): string {
  return (Array.isArray(message.content) ? message.content : [])
    .filter((p: any) => p?.type === "text" && typeof p.text === "string")
    .map((p: any) => p.text)
    .join("");
}

/** Event timestamp if present (message_end carries one), else now. */
function eventAt(message: Record<string, any>): number {
  return typeof message.timestamp === "number" ? message.timestamp : Date.now();
}

/** First of path/command/pattern, single line, at most 60 chars. */
function shortArg(args: unknown): string {
  if (!args || typeof args !== "object") return "";
  const a = args as Record<string, unknown>;
  const first = a.path ?? a.command ?? a.pattern;
  const text = typeof first === "string" ? first : JSON.stringify(args) ?? "";
  return oneLine(text).slice(0, TOOL_ARG_CHARS);
}

function oneLine(text: string): string {
  return text.replace(/\s+/g, " ").trim();
}
