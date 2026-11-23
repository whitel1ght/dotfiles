---
description: Mark this session as a learning one; it is saved in full to ~/wiki/learning/sessions/ when it closes
model: haiku
allowed-tools: Bash(~/.local/bin/session-save:*)
disable-model-invocation: true
---

Run exactly this, once, and nothing else:

```bash
~/.local/bin/session-save mark --harness claude "$CLAUDE_CODE_SESSION_ID"
```

If it printed `marked`, reply in one line: "Marked: this session saves to ~/wiki/learning/sessions/
when it closes (after /clear, mark again)." Otherwise show its error line.
