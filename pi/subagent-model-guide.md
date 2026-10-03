# Subagent model guide

<!-- Generated from pi/subagent-models.json by `npm run generate-guide` in pi/extensions/subagents. Do not edit. -->

Evidence date: 2026-10-03

Quality, speed and cost labels are operational guidance for picking a subagent model, not benchmark results or
prices. Sources and scores are in [subagents-research.md](subagents-research.md). Models are listed best first;
`claude-bridge/*` is Anthropic via Claude Bridge (the subscription), never the `anthropic/*` API-billed provider.

## text

### Budget

Low-cost models only (no Claude fallback); enough for pasted-text transforms.

| # | Model | Provider | Quality | Speed | Cost |
| --- | --- | --- | --- | --- | --- |
| 1 | `opencode-go/glm-5.3-flash` (GLM 5.3 Flash) | opencode-go | good | fast | low |
| 2 | `opencode-go/qwen3.8-flash` (Qwen 3.8 Flash) | opencode-go | good | fast | low |
| 3 | `openai/gpt-5.4-mini` (GPT-5.4 Mini) | openai | good | fast | low |

### Balanced

Existing ranking: fast open models first, Claude Haiku as the final fallback.

| # | Model | Provider | Quality | Speed | Cost |
| --- | --- | --- | --- | --- | --- |
| 1 | `opencode-go/glm-5.3-flash` (GLM 5.3 Flash) | opencode-go | good | fast | low |
| 2 | `opencode-go/qwen3.8-flash` (Qwen 3.8 Flash) | opencode-go | good | fast | low |
| 3 | `opencode-go/mimo-v2.6-flash` (MiMo V2.6 Flash) | opencode-go | good | fast | low |
| 4 | `claude-bridge/claude-haiku-4-5` (Claude Haiku 4.5) | Anthropic via Claude Bridge | good | fast | subscription |

### Premium

Stronger models for nuanced rewriting where tone or accuracy matters.

| # | Model | Provider | Quality | Speed | Cost |
| --- | --- | --- | --- | --- | --- |
| 1 | `claude-bridge/claude-sonnet-5-5` (Claude Sonnet 5.5) | Anthropic via Claude Bridge | very strong | medium | subscription |
| 2 | `openai/gpt-5.4` (GPT-5.4) | openai | very strong | medium | high |

## explore

### Budget

Low-cost flash models only, with no Claude fallback; fine for read-only search and summaries.

| # | Model | Provider | Quality | Speed | Cost |
| --- | --- | --- | --- | --- | --- |
| 1 | `opencode-go/mimo-v2.6-flash` (MiMo V2.6 Flash) | opencode-go | good | fast | low |
| 2 | `opencode-go/deepseek-v4.1-flash` (DeepSeek V4.1 Flash) | opencode-go | good | fast | low |
| 3 | `opencode-go/glm-5.3-flash` (GLM 5.3 Flash) | opencode-go | good | fast | low |
| 4 | `opencode-go/qwen3.8-flash` (Qwen 3.8 Flash) | opencode-go | good | fast | low |

### Balanced

Existing ranking: flash models first, Claude Sonnet as the final fallback.

| # | Model | Provider | Quality | Speed | Cost |
| --- | --- | --- | --- | --- | --- |
| 1 | `opencode-go/glm-5.3-flash` (GLM 5.3 Flash) | opencode-go | good | fast | low |
| 2 | `opencode-go/qwen3.8-flash` (Qwen 3.8 Flash) | opencode-go | good | fast | low |
| 3 | `opencode-go/mimo-v2.6-flash` (MiMo V2.6 Flash) | opencode-go | good | fast | low |
| 4 | `opencode-go/deepseek-v4.1-flash` (DeepSeek V4.1 Flash) | opencode-go | good | fast | low |
| 5 | `claude-bridge/claude-sonnet-5-5` (Claude Sonnet 5.5) | Anthropic via Claude Bridge | very strong | medium | subscription |

### Premium

Stronger models for large or subtle codebases.

| # | Model | Provider | Quality | Speed | Cost |
| --- | --- | --- | --- | --- | --- |
| 1 | `claude-bridge/claude-sonnet-5-5` (Claude Sonnet 5.5) | Anthropic via Claude Bridge | very strong | medium | subscription |
| 2 | `openai/gpt-5.4` (GPT-5.4) | openai | very strong | medium | high |

## implement

### Budget

GPT-5.4 Mini first for small, well-specified edits; medium-cost coding models follow.

| # | Model | Provider | Quality | Speed | Cost |
| --- | --- | --- | --- | --- | --- |
| 1 | `openai/gpt-5.4-mini` (GPT-5.4 Mini) | openai | good | fast | low |
| 2 | `opencode-go/glm-5.3` (GLM 5.3) | opencode-go | strong | medium | medium |
| 3 | `opencode-go/mimo-v2.6-pro` (MiMo V2.6 Pro) | opencode-go | strong | medium | medium |

### Balanced

Existing ranking: open coding models first, Claude Sonnet as the final fallback.

| # | Model | Provider | Quality | Speed | Cost |
| --- | --- | --- | --- | --- | --- |
| 1 | `opencode-go/glm-5.3` (GLM 5.3) | opencode-go | strong | medium | medium |
| 2 | `opencode-go/grok-4.7` (Grok 4.7) | opencode-go | strong | medium | medium |
| 3 | `opencode-go/qwen3.8-max` (Qwen 3.8 Max) | opencode-go | strong | medium | medium |
| 4 | `opencode-go/mimo-v2.6-pro` (MiMo V2.6 Pro) | opencode-go | strong | medium | medium |
| 5 | `claude-bridge/claude-sonnet-5-5` (Claude Sonnet 5.5) | Anthropic via Claude Bridge | very strong | medium | subscription |

### Premium

Terminal-heavy or risky changes where a first-try success matters.

| # | Model | Provider | Quality | Speed | Cost |
| --- | --- | --- | --- | --- | --- |
| 1 | `openai/gpt-5.3-codex` (GPT-5.3 Codex) | openai | very strong | medium | high |
| 2 | `claude-bridge/claude-opus-5-5` (Claude Opus 5.5) | Anthropic via Claude Bridge | top | slow | subscription |

## review

### Budget

Lower-cost first pass: GPT-5.4 Mini screens routine diffs, medium-cost models follow. Escalate risky changes to balanced.

| # | Model | Provider | Quality | Speed | Cost |
| --- | --- | --- | --- | --- | --- |
| 1 | `openai/gpt-5.4-mini` (GPT-5.4 Mini) | openai | good | fast | low |
| 2 | `opencode-go/glm-5.3` (GLM 5.3) | opencode-go | strong | medium | medium |
| 3 | `opencode-go/mimo-v2.6-pro` (MiMo V2.6 Pro) | opencode-go | strong | medium | medium |

### Balanced

Existing ranking: strongest open reviewers first, Claude Sonnet as the final fallback.

| # | Model | Provider | Quality | Speed | Cost |
| --- | --- | --- | --- | --- | --- |
| 1 | `opencode-go/qwen3.8-max` (Qwen 3.8 Max) | opencode-go | strong | medium | medium |
| 2 | `opencode-go/grok-4.7` (Grok 4.7) | opencode-go | strong | medium | medium |
| 3 | `opencode-go/glm-5.3` (GLM 5.3) | opencode-go | strong | medium | medium |
| 4 | `opencode-go/mimo-v2.6-pro` (MiMo V2.6 Pro) | opencode-go | strong | medium | medium |
| 5 | `claude-bridge/claude-sonnet-5-5` (Claude Sonnet 5.5) | Anthropic via Claude Bridge | very strong | medium | subscription |

### Premium

High-stakes changes where a missed bug is expensive.

| # | Model | Provider | Quality | Speed | Cost |
| --- | --- | --- | --- | --- | --- |
| 1 | `openai/gpt-5.4` (GPT-5.4) | openai | very strong | medium | high |
| 2 | `claude-bridge/claude-opus-5-5` (Claude Opus 5.5) | Anthropic via Claude Bridge | top | slow | subscription |

## reason

### Budget

Lower-cost first look for exploratory analysis: GPT-5.4 Mini leads, medium-cost reasoners follow. Not for hard root causes; use balanced.

| # | Model | Provider | Quality | Speed | Cost |
| --- | --- | --- | --- | --- | --- |
| 1 | `openai/gpt-5.4-mini` (GPT-5.4 Mini) | openai | good | fast | low |
| 2 | `opencode-go/mimo-v2.6-pro` (MiMo V2.6 Pro) | opencode-go | strong | medium | medium |
| 3 | `opencode-go/kimi-k3` (Kimi K3) | opencode-go | strong | medium | medium |

### Balanced

Existing ranking: strongest open reasoners first, Claude Opus as the final fallback.

| # | Model | Provider | Quality | Speed | Cost |
| --- | --- | --- | --- | --- | --- |
| 1 | `opencode-go/mimo-v2.6-pro` (MiMo V2.6 Pro) | opencode-go | strong | medium | medium |
| 2 | `opencode-go/grok-4.7` (Grok 4.7) | opencode-go | strong | medium | medium |
| 3 | `opencode-go/kimi-k3` (Kimi K3) | opencode-go | strong | medium | medium |
| 4 | `opencode-go/qwen3.8-max` (Qwen 3.8 Max) | opencode-go | strong | medium | medium |
| 5 | `claude-bridge/claude-opus-5-5` (Claude Opus 5.5) | Anthropic via Claude Bridge | top | slow | subscription |

### Premium

Expensive-if-wrong decisions and tricky root causes.

| # | Model | Provider | Quality | Speed | Cost |
| --- | --- | --- | --- | --- | --- |
| 1 | `claude-bridge/claude-opus-5-5` (Claude Opus 5.5) | Anthropic via Claude Bridge | top | slow | subscription |
| 2 | `openai/gpt-5.4` (GPT-5.4) | openai | very strong | medium | high |

## Model reference

| Model | Provider | Quality | Speed | Cost | Strengths | Avoid for |
| --- | --- | --- | --- | --- | --- | --- |
| `claude-bridge/claude-haiku-4-5` (Claude Haiku 4.5) | Anthropic via Claude Bridge | good | fast | subscription | reliable fallback | hard reasoning |
| `claude-bridge/claude-opus-5-5` (Claude Opus 5.5) | Anthropic via Claude Bridge | top | slow | subscription | hardest problems | routine work |
| `claude-bridge/claude-sonnet-5-5` (Claude Sonnet 5.5) | Anthropic via Claude Bridge | very strong | medium | subscription | reliable all-rounder | bulk trivial work |
| `openai/gpt-5.3-codex` (GPT-5.3 Codex) | openai | very strong | medium | high | terminal and coding agents | plain text work |
| `openai/gpt-5.4` (GPT-5.4) | openai | very strong | medium | high | broad review and reasoning | bulk trivial work |
| `openai/gpt-5.4-mini` (GPT-5.4 Mini) | openai | good | fast | low | cheap agent work | hard reasoning; high-stakes review |
| `opencode-go/deepseek-v4.1-flash` (DeepSeek V4.1 Flash) | opencode-go | good | fast | low | fast code reading | complex edits |
| `opencode-go/glm-5.3` (GLM 5.3) | opencode-go | strong | medium | medium | coding; agentic tool use | trivial text work |
| `opencode-go/glm-5.3-flash` (GLM 5.3 Flash) | opencode-go | good | fast | low | quick and cheap; good tool use | hard reasoning |
| `opencode-go/grok-4.7` (Grok 4.7) | opencode-go | strong | medium | medium | broad coding ability | trivial text work |
| `opencode-go/kimi-k3` (Kimi K3) | opencode-go | strong | medium | medium | long-horizon reasoning | trivial text work |
| `opencode-go/mimo-v2.6-flash` (MiMo V2.6 Flash) | opencode-go | good | fast | low | fast; cheap | complex edits |
| `opencode-go/mimo-v2.6-pro` (MiMo V2.6 Pro) | opencode-go | strong | medium | medium | deep reasoning | trivial text work |
| `opencode-go/qwen3.8-flash` (Qwen 3.8 Flash) | opencode-go | good | fast | low | fast; long context | hard reasoning |
| `opencode-go/qwen3.8-max` (Qwen 3.8 Max) | opencode-go | strong | medium | medium | careful analysis | trivial text work |

Best for:

- `claude-bridge/claude-haiku-4-5`: text, exploration
- `claude-bridge/claude-opus-5-5`: reasoning, review
- `claude-bridge/claude-sonnet-5-5`: exploration, implementation, review
- `openai/gpt-5.3-codex`: terminal-heavy implementation
- `openai/gpt-5.4`: review, reasoning
- `openai/gpt-5.4-mini`: text, implementation, light review, agent work
- `opencode-go/deepseek-v4.1-flash`: exploration
- `opencode-go/glm-5.3`: implementation, review
- `opencode-go/glm-5.3-flash`: text, exploration
- `opencode-go/grok-4.7`: implementation, review, reasoning
- `opencode-go/kimi-k3`: reasoning
- `opencode-go/mimo-v2.6-flash`: text, exploration
- `opencode-go/mimo-v2.6-pro`: reasoning, review, implementation
- `opencode-go/qwen3.8-flash`: text, exploration
- `opencode-go/qwen3.8-max`: review, implementation, reasoning

## Changing the policy

Edit `pi/subagent-models.json` (move a line to change priority), then run `npm run generate-guide` and `npm run check-models`.
