---
description: Save this session in full to ~/wiki/learning/sessions/ now (and again when it closes)
argument-hint: [title]
model: haiku
allowed-tools: Bash(~/.local/bin/session-save:*)
disable-model-invocation: true
---

Run exactly this, once, and nothing else (an empty title keeps the session's own):

```bash
~/.local/bin/session-save mark --harness claude "$CLAUDE_CODE_SESSION_ID" && ~/.local/bin/session-save save --harness claude --session "$CLAUDE_CODE_SESSION_ID" --title "$ARGUMENTS"
```

Reply in one line with the path it printed: "Saved: <path>; it saves again when the session closes."
If it printed no path, the session has no message of yours yet: say so. On an error, show its line.
