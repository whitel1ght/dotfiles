---
description: Check Slack since the last check, tick plan lines whose message the user has sent, put new requests on the plan (run by the day session's [daily-slack] timer, 15:00-21:30, or by hand)
---

`/start-day` reads Slack once in the morning. This check catches what changed since then. Run it
in the day session: on a `[daily-slack] check N/20` prompt from the watcher (from 15:00 local time,
every 20 min, 20 checks, the last at 21:20), or when the user types it. Slack is read only: never send, react, draft or
edit anything, and file no decision.

Each bash call is a new shell: use literal values, not variables from an earlier call.

1. **Window.** Run `date +%F` and `date +%s`; keep both values (today `T`, now `NOW`). The window
   starts at the Unix seconds in `~/.local/state/run-day/T.slack-checked`; when that file is
   missing, at local midnight (`date -j -v0H -v0M -v0S +%s`). The day starts at local midnight.

2. **Open Slack lines.** Read the plan block of `~/wiki/diary/T.md` (between
   `<!-- start-day:start -->` and `<!-- start-day:end -->`). Collect every open line, top-level or
   child (`[ ]`, `[/]` or `[!]`), that is about a Slack message: one to send ("send the draft in
   Dave's DM (you)", "reply to Nelson", "post in #success"), one to delete, or an answer awaited
   ("asked Dave Berg, waiting"). For each, note the person or channel and its key (the
   `<!-- pN -->` id, else the lowercase ticket key of the line or of its parent).

3. **Search** with the Slack MCP server (registered as `slack`, tools named
   `mcp__slack__<tool>`; discover them from a codemode script with `searchTools` /
   `describeNamespace("mcp__slack")` and use only read and search tools). Keep the raw results
   inside the codemode script and return only the finding lines below.

   A. New messages: the two searches of `/start-day` (its **Slack** section: DMs and group DMs
   with the Jira and GitLab apps excluded, then mentions of the user), `after` = window start,
   paged to the end. Drop bots and app DMs. A conversation needs the user when someone else's
   last message is newer than the user's last message there and asks something of them.

   B. For each open Slack line, from the day start: did the user send that message (a search for
   the user's own messages in that conversation or channel), and did the person awaited answer?

   Findings, one per line:
   `sent | <key> | <line text> | <permalink>` (the user's message that does what the line says)
   `replied | <key> | <line text> | <who> | <permalink> | <gist, at most 12 words>`
   `new | <who> | <channel name or DM> | <permalink> | <what they ask, at most 12 words>`
   `none` when there is nothing; `failed | <why>` when the server or a search fails.
   A draft cannot be seen: never report `sent` for a line about a draft that was only deleted.

4. **Apply** each finding (the rules of `/run-day` section 3 hold: evidence goes to the agent
   file, the plan line changes only its marker):
   - `sent`: a top-level line: `day-agent note <key> done "sent in Slack: <permalink>"`, then
     `[X]`. A child: tick it `[X]` and run `day-agent note <key> progress "sent: <line text>
     <permalink>"`. When that was the item's last open step, close the parent as section 3 says.
   - `replied`: `day-agent note <key> note "<who> replied: <gist> <permalink>"`. A waiting or
     blocked step now has its answer: set the step back to `[ ]` and run Keep busy of `/run-day`
     (section 11), which picks it up.
   - `new`: skip it when a plan line already covers that person and request. A request about a
     ticket on the plan becomes a child under that ticket's line; any other becomes one line under
     **First**: `- [ ] reply to <who>: <what they ask, few words>`. The watcher's new-plan-line
     prompt then runs Keep busy on it; the reply itself is the user's (`me`), an agent may draft it.
   - `failed`: change nothing; leave the `.slack-checked` file as it is, so the next check covers
     this window again, and report the reason.
   Without today's run state (`~/.local/state/run-day/T.md`) change nothing: report only.

5. **Record** the check unless it failed: write `NOW` to `~/.local/state/run-day/T.slack-checked`.

6. **Report** in one line: `slack check: 1 sent (ticked), 1 reply, 2 new on the plan`, naming
   each person; `slack check: nothing new` when the finding was `none`.
