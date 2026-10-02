# Subagent model ranking — research notes

Why `subagents.json` lists each task type's models in the order it does. Researched
2026-10-02; redo it when OpenCode Go adds or retires models. Ranking is by quality
for the kind of work, not by price. Claude, through `claude-bridge` on the
subscription, is always the last fallback; `anthropic/*` (API billing) is never used.

## Sources

| Source | What it gave | Trust |
| --- | --- | --- |
| [Artificial Analysis](https://artificialanalysis.ai/models) | Independent runs: Intelligence Index, Terminal-Bench 2.1 and 4.0, SciCode, long-context reasoning (LCR), HLE, hallucination rate | Main source |
| [LMArena](https://lmarena.ai/leaderboard) | Blind human votes: agent, code and text arenas | Strong, but taste-based |
| [Terminal-Bench](https://www.tbench.ai/leaderboard) | Official agentic terminal leaderboard | Few open models listed |
| Vendor model cards on Hugging Face | Self-reported tables | Cross-check only; they agree with AA on TB 4.0 |
| [OpenRouter](https://openrouter.ai/api/v1/models) | Descriptions, prices | Metadata |
| Aider polyglot | — | Dropped: stops at 2025-10 |

Terminal-Bench 4.0 separates the field best: models from before August 2026 score
near 0 on it while scoring normally on 2.1, and the vendors' own cards confirm that
(DeepSeek's card: V4-Pro 12.4; MiMo's: V2.5-Pro 1.5).

## Scores (Artificial Analysis unless noted)

| Model (Go id) | Index | TB 2.1 | TB 4.0 | SciCode | LCR | HLE | Halluc.↓ | LMArena agent / code |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| claude-opus-5-5 | 57.6 | – | .60 | .67 | .85 | .61 | .59 | #2 / #1 |
| claude-sonnet-5-5 | 56.0 | – | .64 | .61 | .83 | .55 | .47 | #3 / #3 |
| grok-4.7 | 46.4 | – | .26 | .57 | .77 | .43 | .29 | #12 / #15 |
| mimo-v2.6-pro | 46.3 | – | .35 | .61 | .86 | .49 | .41 | #21 / #24 |
| qwen3.8-max | 45.4 | .89 | .39 | .52 | .80 | .43 | .29 | #23 / – (text #10) |
| glm-5.3 | 44.8 | .84 | .42 | .59 | .80 | .42 | .30 | #22 / #20 |
| kimi-k3 | 43.6 | .85 | .13 | .60 | .89 | .47 | .53 | #14 / – (text #16) |
| glm-5.3-flash | 41.8 | .84 | .33 | .52 | .80 | .40 | .28 | #33 / #25 |
| qwen3.8-flash ¹ | 39.8 | .86 | .25 | .51 | .80 | .38 | .45 | #30 / – |
| deepseek-v4.1-flash | 39.5 | – | .27 | .52 | .84 | .39 | .97 | #17 / #21 |
| mimo-v2.6-flash | 37.9 | – | .23 | .51 | .74 | .35 | .54 | #34 / – |
| deepseek-v4-pro | 36.0 | .79 | .14 | .51 | .80 | .41 | .95 | #28 / #30 |
| kimi-k2.7-code | 25.8 | .67 | .01 | .48 | .79 | .35 | .82 | – / #61 |
| claude-haiku-4-5 | 16.9 | .44 | 0 | .42 | .74 | .10 | .27 | – |

Terminal-Bench official board: GLM-5.3 41.8% (best non-Claude), Grok 4.7 37.6%.
¹ AA lists it as "Qwen3.8 Flash Next"; same release date and price as Go's `qwen3.8-flash`.

## Orders chosen

- **implement** (agentic coding): Terminal-Bench 4.0 and the agent/code arenas.
  glm-5.3 → grok-4.7 → qwen3.8-max → mimo-v2.6-pro → Sonnet.
- **review** (find real problems, invent none): index plus a low hallucination rate.
  qwen3.8-max → grok-4.7 → glm-5.3 → mimo-v2.6-pro → Sonnet.
- **reason** (hard thinking): HLE, SciCode, long context.
  mimo-v2.6-pro → grok-4.7 → kimi-k3 → qwen3.8-max → Opus.
- **explore** (many quick read-only calls): fast models, low hallucination first.
  glm-5.3-flash → qwen3.8-flash → mimo-v2.6-flash → deepseek-v4.1-flash → Sonnet.
  Not Haiku: at 17 it would be a step down from every model above it.
- **text** (no tools): glm-5.3-flash → qwen3.8-flash → mimo-v2.6-flash → Haiku.
  The local `qwen2.5-coder:14b-16k` is in no list; the parent may name it for text.

## Left out

- **deepseek-v4-pro, deepseek-v4-flash, gpt-5.6/6-luna**: answer instead of abstaining 77–97% of the time.
- **kimi-k2.7-code, minimax-m3/m2.7, mimo-v2.5(-pro), hy3, qwen3.7-plus, longcat-2.0, glm-5.2**: superseded; near 0 on TB 4.0.
- **muse-spark-1.3-contributor**: scores well (index 48 for the full model), but Go only serves it to
  workspaces that allow training on request data (Privacy settings); this one does not.
- **hy4-preview**: no independent scores yet.

All models in the lists answered a ping in 2–6s on 2026-10-02.
