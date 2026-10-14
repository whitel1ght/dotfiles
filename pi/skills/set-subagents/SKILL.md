---
name: set-subagents
description: >-
  Pick which model each acp_delegate role (reviewer, researcher, planner, oracle, worker) runs on, using the ask_user_question picker over the live enabled-model pool, and write the pins to pi/billion-context.json. Use when the user says "set subagents", "set up subagent models", "which models should subagents use", after adding or removing models from the pool, or after switching provider — any time a role pin could name a model that is no longer available.
---

# set-subagents

The pins live in `~/projects/dotfiles/pi/billion-context.json` under
`.pi.subagents.agents.<role>.model`, symlinked to
`~/.config/billion-context/billion-context.json`. billion-context reads them when
`pi` starts; an explicit `model` on a launch always wins over a pin.

## 1. Read the pool

Prefer the live list: the `<subagent_models>` block in this request is the
selected ∩ available exact `provider/id` set — use those ids and nothing else.
With no block, fall back to
`jq -r '.enabledModels[]' ~/projects/dotfiles/pi/settings.json` and say that
availability is unverified.

Show the current pins:

```sh
jq -r '.pi.subagents.agents | to_entries[] | "\(.key)=\(.value.model)"' \
  ~/projects/dotfiles/pi/billion-context.json
```

Never invent, autocomplete or remember a model id. If the pool is empty, launch
nothing and ask the user to repair it.

## 2. Ask — one call

`ask_user_question`, two questions. Its limits are 1-4 questions and 2-4 options
each, and a free-text row is added automatically, so a pool bigger than four is
fine: put the likeliest candidates in the options and let the user type the rest.

- header `Read-only` — "Which model should reviewer, researcher, planner and
  oracle use?" Options: up to four pool ids, cheapest and most tool-reliable
  first.
- header `Worker` — "Which model should worker (writes code) use?" Options
  biased to the capable end of the pool.
- header `This session` — "Apply to this session too?" Options: "Yes — pass
  `model` explicitly on every launch" / "No — next session only". Pins are read
  at process start, so a running session keeps its old defaults.

If `ask_user_question` is not in the tool list (non-interactive `pi -p` removes
it), do not guess: print the pool and the current pins and stop.

## 3. Write

```sh
cd ~/projects/dotfiles
jq --arg ro "<read-only id>" --arg w "<worker id>" \
  '.pi.subagents.agents |= with_entries(if .key == "worker" then .value.model = $w else .value.model = $ro end)' \
  pi/billion-context.json > /tmp/bc.json && mv /tmp/bc.json pi/billion-context.json
```

Per-role answers: set each `.pi.subagents.agents.<role>.model` the same way.
Then `readlink ~/.config/billion-context/billion-context.json` must point into
the repo — if it does not, run `bin/plink`.

## 4. Prove it

`./bin/pi-contract --model <a pool id>` boots a real pi and asserts that every
role pin exists and is in `enabledModels`. Show `git diff pi/billion-context.json`.

## 5. Report

One short block: the pins now, what changed, and "restart `pi` for these to take
effect; this session keeps the old defaults unless I pass `model` explicitly". If
the user chose to apply it to this session, pass `model` on every `acp_delegate`
call for the rest of it.
