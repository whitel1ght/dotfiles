---
description: Answer a question about past work from the long-term memory in ~/wiki, with citations
argument-hint: "<question>"
disable-model-invocation: true
---

# Ask the wiki

Question: $ARGUMENTS

If the question is empty, ask for one and stop.

Spawn one subagent with the `Agent` tool: `subagent_type: "Explore"`, `model: "haiku"`, `description: "ask-wiki"`, and this prompt (fill in the question; the subagent knows nothing else; the test checks the phrase "values from step 2 of the ask procedure", so keep it in the prompt):

> Answer a question about the user's past work from the long-term memory in `~/wiki`.
> 1. Read `~/wiki/AGENTS.md` and follow its ask procedure exactly. In short: a question about a period (a week, a month) starts at the nearest review in `~/wiki/reviews/` and drills into diary or project log files only if the review does not answer it; a "why" or "what about X" question uses `qmd query "<question>" -c <project> -n <N> --files` (project is `ecfx`, `epicmax` or `personal`; try the likeliest first), then `qmd get <path>:<line> -l <L>` on the best hits. Use the values from step 2 of the ask procedure: take `<N>` (the `-n` value) and `<L>` (the `-l` value) from step 2 of the ask procedure in `~/wiki/AGENTS.md`, not from this brief. Use only `qmd`, `rg` and read-only file reads. Never write anything.
> 2. Answer in at most 200 words. Every claim cites the file it came from as `~/wiki/<path>` (add `:<line>` when you have it).
> 3. If the memory does not contain the answer, say so in one sentence and list the files you checked. Do not guess.
> Question: <the question>

Print the subagent's answer unchanged. Do nothing else.
