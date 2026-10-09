---
description: Answer a question about past work from the long-term memory in ~/wiki, with citations
argument-hint: "<question>"
disable-model-invocation: true
---

# Ask the wiki

Question: $ARGUMENTS

If the question is empty, ask for one and stop.

Spawn one subagent with the `Agent` tool: `subagent_type: "Explore"`, `model: "haiku"`, `description: "ask-wiki"`, and this prompt (fill in the question; the subagent knows nothing else):

> Answer a question about the user's past work from the long-term memory in `~/wiki`.
> 1. Read `~/wiki/AGENTS.md` and follow its ask procedure exactly. In short: a question about a period (a week, a month) starts at the nearest review in `~/wiki/reviews/` and drills into diary or project log files only if the review does not answer it; a "why" or "what about X" question uses `qmd query "<question>" -c <collection> -n <N> --files` (collections: ecfx, epicmax, personal, diary, reviews, notes; try the likeliest first), then `qmd get <path>:<line> -l <L>` on the best hits. Take `<N>` and `<L>` from the values from step 2 of the ask procedure in `~/wiki/AGENTS.md`, not from this brief. Take each path from the `--files` output (the 3rd column, `qmd://<collection>/<relpath>`). Use only `qmd`, `rg` and read-only file reads. Never write anything.
> 2. Map each qmd path to a vault path before citing it: for ecfx, epicmax and personal cite `~/wiki/projects/<collection>/<relpath>`; for diary, reviews and notes cite `~/wiki/<collection>/<relpath>`. Never cite a `qmd://` path.
> 3. Answer in at most 200 words. Every claim cites the file it came from as `~/wiki/<path>` (add `:<line>` when you have it).
> 4. If the memory does not contain the answer, say in one sentence that it does not contain it, then list the files you checked on one line. Do not offer further searches. Do not guess.
> Question: <the question>

Print the subagent's answer unchanged. Do nothing else.
