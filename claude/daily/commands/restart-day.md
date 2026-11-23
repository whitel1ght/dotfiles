---
description: Restart the running day session so it picks up changes to the setup (respawn, or --in-place)
argument-hint: [session] [--in-place] [--now] [-n]
model: haiku
allowed-tools: Bash(~/.local/bin/day-restart:*)
disable-model-invocation: true
---

Run exactly this, once, and nothing else:

```bash
~/.local/bin/day-restart --detach $ARGUMENTS
```

It works from any session, the day session itself included: `--detach` waits in the background
for the day session's turn to end, then respawns it (a background session) or has it resume in
place (`--in-place`, or an interactive session). The day session then runs
`/daily:run-day resume restarted` by itself. With `-n` it only says what it would do.

Reply with its output in one line. If it failed or found no day session, show its error line;
"name one" means the user picks a session from `claude agents` and passes its name or id.
