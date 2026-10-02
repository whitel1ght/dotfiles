import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { expandMentions, kb, type Attached, type Skipped } from "./src/expand.ts";

const TYPE = "inline-files";

interface Details {
  attached: Attached[];
  skipped: Skipped[];
}

// Only when the model has no tools: one that has them reads @files itself, and
// inlining would just spend its context. The files travel as a message of their
// own, so the transcript keeps the prompt as typed. See README.md.
export default function (pi: ExtensionAPI) {
  pi.on("before_agent_start", (event, ctx) => {
    if (pi.getActiveTools().length) return;
    const { content, attached, skipped } = expandMentions(event.prompt, ctx.cwd);
    if (!content) return;
    return { message: { customType: TYPE, content, display: true, details: { attached, skipped } } };
  });

  pi.registerMessageRenderer<Details>(TYPE, (message, options, theme) => {
    const { attached = [], skipped = [] } = message.details ?? {};
    const parts = [
      ...attached.map((a) => `${a.mention} (${kb(a.bytes)})`),
      ...skipped.map((s) => theme.fg("warning", `${s.mention}: ${s.reason}`)),
    ];
    let text = theme.fg("muted", `📎 ${parts.join(", ")}`);
    if (options.expanded && typeof message.content === "string") text += `\n${theme.fg("dim", message.content)}`;
    else if (attached.length) text += theme.fg("dim", "  (ctrl+o to show)");
    return new Text(text, options.outputPad, 0);
  });
}
