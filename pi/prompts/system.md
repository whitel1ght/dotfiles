---
description: Mark this session as "the system" session, which reviews ideas from ~/wiki/IDEA.md when it is idle
---

# The system session

This session is now "the system" session: the parallel session that improves the user's setup
during the day. The daily extension has recorded it (`~/.local/state/ideas/system.session`); a
later `/system` in another session moves the mark there.

When this session has been idle for about 15 minutes (no message from the user, no turn
running), the extension sends `[ideas] idle review: read ~/.pi/agent/prompts/ideas.md and follow
it`, once per idle stretch, and only when `ideas due` has something. Follow that file then (it is
the `/ideas` prompt).

Reply with one line: "This is the system session; I'll review ideas from IDEA.md when idle."
