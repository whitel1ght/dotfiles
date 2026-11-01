import type { Terminal } from "./manager.ts";
import type { StreamCapture } from "./output.ts";

export type StreamChoice = "stdout" | "stderr" | "both";

export const DEFAULT_TAIL_LINES = 100;
export const MAX_TAIL_LINES = 1000;
// Model-facing output is always bounded, whatever the process printed.
const MAX_STREAM_BYTES = 16 * 1024;
const WAKE_TAIL_LINES = 20;

export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes}B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)}KB`;
  return `${(bytes / 1024 / 1024).toFixed(1)}MB`;
}

export function formatDuration(ms: number): string {
  const seconds = Math.max(0, Math.round(ms / 1000));
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m${String(seconds % 60).padStart(2, "0")}s`;
  return `${Math.floor(minutes / 60)}h${String(minutes % 60).padStart(2, "0")}m`;
}

export function statusText(t: Terminal): string {
  switch (t.status) {
    case "running":
      return "running";
    case "exited":
      return "exited 0";
    case "failed":
      return t.signal ? `killed by ${t.signal}` : `exited ${t.exitCode}`;
    case "stopped":
      return "stopped";
    case "error":
      return `error: ${t.error}`;
  }
}

export function elapsed(t: Terminal, now = Date.now()): string {
  return formatDuration((t.endedAt ?? now) - t.startedAt);
}

// One line per terminal: `bg-1 [running] "dev server" (pid 123, 2m05s, ~/app)`
export function describe(t: Terminal, now = Date.now()): string {
  const pid = t.pid === undefined ? "" : `pid ${t.pid}, `;
  return `${t.id} [${statusText(t)}] "${t.title}" (${pid}${elapsed(t, now)}, ${t.cwd})`;
}

// Last `lines` lines of a text, bounded by bytes as well. Returns whether it cut anything.
export function tailLines(text: string, lines: number, maxBytes = MAX_STREAM_BYTES) {
  const all = text.split("\n");
  if (all.at(-1) === "") all.pop();
  let kept = all.slice(-lines);
  let cut = kept.length < all.length;
  let out = kept.join("\n");
  if (Buffer.byteLength(out) > maxBytes) {
    out = Buffer.from(out).subarray(-maxBytes).toString("utf8");
    // The byte cut can land mid-line; drop the stub.
    out = out.slice(out.indexOf("\n") + 1);
    cut = true;
  }
  return { text: out, cut };
}

function streamSection(name: string, capture: StreamCapture, lines: number): string {
  const { text, cut } = tailLines(capture.text(), lines);
  const partial = cut || capture.tailIsPartial;
  const header = `--- ${name} (${formatBytes(capture.totalBytes)} total${
    partial ? `, showing the last ${text ? text.split("\n").length : 0} lines` : ""
  }) ---`;
  return `${header}\n${text || "(empty)"}`;
}

export function logPaths(t: Terminal): string {
  const note = t.stdout.fileTruncated || t.stderr.fileTruncated ? " (capped; later output is not on disk)" : "";
  return `Full logs: ${t.stdout.path} , ${t.stderr.path}${note}`;
}

export function renderOutput(t: Terminal, stream: StreamChoice, lines = DEFAULT_TAIL_LINES): string {
  const n = Math.min(Math.max(1, Math.floor(lines)), MAX_TAIL_LINES);
  const parts = [describe(t)];
  if (stream !== "stderr") parts.push(streamSection("stdout", t.stdout, n));
  if (stream !== "stdout") parts.push(streamSection("stderr", t.stderr, n));
  parts.push(logPaths(t));
  return parts.join("\n");
}

// What wakes the model when a terminal finishes on its own.
export function wakeMessage(terminals: Terminal[]): string {
  return terminals
    .map((t) => {
      const parts = [`Background terminal ${describe(t)} has finished.`];
      for (const [name, capture] of [["stdout", t.stdout], ["stderr", t.stderr]] as const) {
        const { text } = tailLines(capture.text(), WAKE_TAIL_LINES, 4 * 1024);
        if (text) parts.push(`--- ${name} (last lines) ---\n${text}`);
      }
      parts.push(logPaths(t));
      return parts.join("\n");
    })
    .join("\n\n");
}

// The window of `lines` shown by a scrolling viewer. `fromBottom` 0 follows the tail.
export function sliceWindow(lines: string[], height: number, fromBottom: number) {
  const maxOffset = Math.max(0, lines.length - height);
  const offset = Math.min(Math.max(0, fromBottom), maxOffset);
  const end = lines.length - offset;
  return { lines: lines.slice(Math.max(0, end - height), end), offset, maxOffset };
}
