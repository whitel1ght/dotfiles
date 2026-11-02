---
description: Mark this session as "the system" session, which reviews ideas from ~/wiki/IDEA.md when it is idle
disable-model-invocation: true
---

# The system session

This session is now "the system" session: the parallel session that improves the user's setup
during the day. The daily plugin has recorded it (`~/.local/state/ideas/system.session`); a
later `/daily:system` in another session moves the mark there.

When this session has been idle for about 15 minutes (no message from the user, no agents
running), the plugin sends `[ideas] idle review: run /daily:ideas`, once per idle stretch, and
only when `ideas due` has something. Run `/daily:ideas` then.

Reply with one line: "This is the system session; I'll review ideas from IDEA.md when idle."
