# learning-sessions

Keeps a pi session the user marked as a learning one in full in `~/wiki/learning/sessions/`, through `bin/session-save` (D-1288). The Claude Code side is `/learn-mark`, `/learn-save` and a `SessionEnd` hook.

- **`/learn-mark`:** marks the session (`session-save mark --harness pi <id>`); it is saved when it ends.
- **`/learn-save [title]`:** marks it and saves it now (`session-save save --harness pi --session <id> --transcript <session file>`); the notification shows the file's path.
- **On quit:** `session_shutdown` saves a marked session again. Subagents (`PI_SUBAGENT`) are skipped.
- **Limits:** each `session-save` call has a 10 s ceiling, since quitting waits for the handler; any error is a notification, never a thrown error.
- **File format, redaction, naming:** see `bin/session-save` and `~/wiki/work/system/learning-sessions.md`.

Env override (tests): `SESSION_SAVE_BIN`.
