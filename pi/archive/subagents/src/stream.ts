// Follows a child `pi --mode json` run: what it is doing now, what it said
// last, what it cost, and whether its model call failed. Pi exits 0 even when
// the provider rejects every request, so failure is read from the stream.

export interface Activity {
  readonly kind: "tool" | "text";
  readonly text: string;
}

const MAX_ACTIVITY = 200;
const ACTIVITY_CHARS = 200;

export class RunStream {
  turns = 0;
  toolCalls = 0;
  cost = 0;
  model: string | undefined;
  finalText = "";
  stopReason: string | undefined;
  errorMessage: string | undefined;
  settled = false;
  // For the stall watchdog: when the child last said anything at all, and how
  // many of its tool calls are still running (a test suite can be quiet for long).
  lastEventAt: number;
  toolsRunning = 0;
  readonly activity: Activity[] = [];
  // Lines that are not JSON: a crash before the stream started, usually.
  readonly noise: string[] = [];

  private pending: Buffer = Buffer.alloc(0);
  private readonly now: () => number;

  constructor(now: () => number = Date.now) {
    this.now = now;
    this.lastEventAt = now();
  }

  // Records are LF-terminated JSON; LF only, since U+2028 is valid inside a string.
  write(chunk: Buffer): void {
    let data = this.pending.length ? Buffer.concat([this.pending, chunk]) : chunk;
    let newline: number;
    while ((newline = data.indexOf(0x0a)) !== -1) {
      this.line(data.subarray(0, newline).toString("utf8"));
      data = data.subarray(newline + 1);
    }
    this.pending = Buffer.from(data);
  }

  end(): void {
    if (this.pending.length) this.line(this.pending.toString("utf8"));
    this.pending = Buffer.alloc(0);
  }

  // Why the run did not produce an answer, or undefined when it did.
  failure(): string | undefined {
    if (this.stopReason === "error" || this.stopReason === "aborted") {
      return this.errorMessage || `the model call ended with ${this.stopReason}`;
    }
    if (!this.finalText.trim()) return "the subagent finished without a final answer";
    return undefined;
  }

  private line(raw: string): void {
    const text = raw.replace(/\r$/, "");
    if (!text.trim()) return;
    let event: any;
    try {
      event = JSON.parse(text);
    } catch {
      if (this.noise.length < 50) this.noise.push(text.slice(0, 500));
      return;
    }
    this.lastEventAt = this.now();
    switch (event?.type) {
      case "message_end":
        if (event.message?.role === "assistant") this.assistant(event.message);
        break;
      case "tool_execution_start":
        this.toolCalls++;
        this.toolsRunning++;
        this.note("tool", `${event.toolName}: ${summariseArgs(event.args)}`);
        break;
      case "tool_execution_end":
        this.toolsRunning = Math.max(0, this.toolsRunning - 1);
        break;
      case "agent_settled":
        this.settled = true;
        break;
    }
  }

  private assistant(message: any): void {
    this.turns++;
    this.model ??= message.model;
    this.cost += Number(message.usage?.cost?.total) || 0;
    this.stopReason = message.stopReason;
    this.errorMessage = message.errorMessage ?? undefined;
    const said = (Array.isArray(message.content) ? message.content : [])
      .filter((part: any) => part?.type === "text" && typeof part.text === "string")
      .map((part: any) => part.text)
      .join("")
      .trim();
    // The answer is the last thing it said; tool-call-only turns keep the previous one.
    if (said) {
      this.finalText = said;
      this.note("text", said);
    }
  }

  private note(kind: Activity["kind"], text: string): void {
    const flat = text.replace(/\s+/g, " ").trim();
    this.activity.push({ kind, text: flat.length > ACTIVITY_CHARS ? `${flat.slice(0, ACTIVITY_CHARS)}…` : flat });
    if (this.activity.length > MAX_ACTIVITY) this.activity.splice(0, this.activity.length - MAX_ACTIVITY);
  }
}

function summariseArgs(args: unknown): string {
  if (!args || typeof args !== "object") return "";
  const a = args as Record<string, unknown>;
  const first = a.command ?? a.path ?? a.pattern ?? a.file_path;
  return typeof first === "string" ? first : JSON.stringify(args);
}
