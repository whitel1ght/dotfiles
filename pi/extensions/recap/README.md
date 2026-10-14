# recap

A one-line recap above the editor: why you opened the session, where it stands, and the
likely next step.

- `/recap` generates one now. After the agent settles and you stay idle for 2 minutes,
  one is generated automatically. On resume, the saved recap shows if still current.
- It clears when you send a message.
- `/recap status` shows the model and freshness; `/recap config` pins a different model
  (saved to `~/.pi/agent/extensions/recap.json`). Without a pin it uses the session's
  current model.

Only a digest goes to the model (`digest.ts`): your messages, the assistant's visible
replies and the compaction summary, with each tool call reduced to a one-line
`→ tool: arg` and tool output and thinking dropped. It keeps the first entry and the
newest that fit in 30K characters. One request, 160 output tokens, 30 s timeout.

Ours: forked from `@tifan/pi-recap` 0.4.7 (MIT, Tifan Dwi Avianto) on 2026-10-14;
upstream is not tracked. Changes from it: session model instead of a fixed default,
the digest instead of the full context, a 30 s timeout instead of 4 s.

Run `npm test` here.
