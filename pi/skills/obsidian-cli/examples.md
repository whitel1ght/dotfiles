# Examples — Obsidian CLI Workflows

Five end-to-end recipes. Each shows the user intent, exact command(s), expected output shape, and the follow-up the skill should do.

In all examples, replace `vault="Obsidian Vault"` with the actual vault name from `obsidian vaults`.

---

## 1. Append to today's daily note

**User intent**: "Add a note to my daily that I shipped the obsidian skill" / "Log a thought to today's journal."

**Command**:
```sh
obsidian daily:append content="- Shipped the obsidian-cli skill — opened MR for review" vault="Obsidian Vault"
```

**Expected output**: silent success (or `inline` skips the leading newline).

**Follow-up**: confirm the append landed with `obsidian daily:read vault="Obsidian Vault"` and quote the trailing lines back to the user. If the user wanted multiple lines, use `\n`:

```sh
obsidian daily:append content="- Met with Alex re: pricing\n- Next step: draft proposal by Fri" vault="Obsidian Vault"
```

---

## 2. Capture a new meeting note from the conversation

**User intent**: "Create a meeting note for the standup with these attendees and agenda."

**Command** (no template):
```sh
obsidian create name="2026-05-20 Standup" content="## Attendees\n- Alex\n- Sam\n- Jordan\n\n## Agenda\n- Sprint review\n- Blockers\n\n## Notes\n" open vault="Obsidian Vault"
```

**Or, if a template exists** (verify with `obsidian templates vault="..."`):
```sh
obsidian create name="2026-05-20 Standup" template="meeting" content="Initial agenda placeholder" open vault="Obsidian Vault"
```

**Expected output**: file created, opens in Obsidian editor (because `open` flag).

**Follow-up**: tell the user the file path (default folder depends on Obsidian settings — get it with `obsidian file file="2026-05-20 Standup" vault="..."` if needed).

**Failure mode**: if the file already exists, the command errors. Either add `overwrite` (destructive — confirm with the user first) or pick a new name.

---

## 3. Search the vault and read top hits

**User intent**: "Find anything in my vault about invoice templates and summarize what I've already written."

**Step 1 — search**:
```sh
obsidian search query="invoice template" limit=10 format=json vault="Obsidian Vault"
```

**Expected output shape** (JSON array of matches):
```json
[
  {"path": "Templates/Invoice.md", "matches": 3},
  {"path": "Clients/Acme/Billing.md", "matches": 1}
]
```

**Step 2 — read top hits**:
```sh
obsidian read path="Templates/Invoice.md" vault="Obsidian Vault"
obsidian read path="Clients/Acme/Billing.md" vault="Obsidian Vault"
```

**Follow-up**: synthesize a summary of how the user currently structures invoices, citing each file by path. If the user asks for more granularity, use `obsidian search:context` instead of `search` to get matching-line snippets.

---

## 4. Triage incomplete tasks

**User intent**: "What's open in my Obsidian vault?" / "Show me my unfinished tasks."

**Command**:
```sh
obsidian tasks todo verbose format=json vault="Obsidian Vault"
```

**Expected output shape**: JSON grouped by file, each task with `line`, `text`, `status`:
```json
{
  "Projects/Acme.md": [
    {"line": 12, "text": "Draft proposal", "status": " "},
    {"line": 27, "text": "Email legal", "status": "/"}
  ],
  "Daily/2026-05-19.md": [
    {"line": 5, "text": "Schedule dentist", "status": " "}
  ]
}
```

**Follow-up**: present the tasks grouped by file, ordered by file recency or by tag if the user supplied one. To mark a specific task done:

```sh
obsidian task ref="Projects/Acme.md:12" done vault="Obsidian Vault"
```

Pre-confirm the file:line target with the user before toggling.

---

## 5. Find orphaned notes for cleanup

**User intent**: "Help me clean up — what notes in my vault aren't linked from anywhere?"

**Command**:
```sh
obsidian orphans format=json vault="Obsidian Vault"
```

**Expected output**: JSON array of file paths with no incoming links.

**Follow-up**: summarize the count and group by folder. **Do not delete anything**. Present the list and ask which (if any) the user wants to delete or move. Then route confirmed deletions through the destructive-command gate (see SKILL.md):

```sh
# Only after explicit user confirmation per file:
obsidian delete path="Inbox/abandoned-idea.md" vault="Obsidian Vault"
```

Recommend `obsidian deadends format=json vault="..."` as a complementary view (notes with no *outgoing* links — often stubs that could be expanded or merged).
