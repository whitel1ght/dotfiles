#!/usr/bin/env python3
"""Build pi's agents folder from claude-components plus the pi-only agents.

Claude Code loads the team's agents from claude-components (plugins/*/agents).
pi reads agent files with its own header, so instead of hand-kept forks this
script writes ~/.pi/agent/agents/:

  - every team agent: pi's standard header (name and description from the team
    file, read-only tools unless it is in EDITORS, the delegation settings pi-sub
    expects) above the team body, rewritten like the skills (pi_skills.py:
    `backend:x` -> `x`, !`cmd` -> run `cmd`, plus the "In pi" note for agents
    that launch subagents). Agents whose `tools:` name Claude-only MCP tools
    (the claude-in-chrome browser) are skipped, since pi cannot run them.
  - every pi-only agent in dotfiles/pi/agents, linked, so edits show at once.
    A pi-only file named like a team agent is refused: forks are what this
    replaces.

The folder is owned by this script (a .generated.json marker; a folder without
it is never wiped) and rebuilt on every run. plink runs it.

  pi_agents.py [--src ~/projects/claude-components] [--local dotfiles/pi/agents] [--out ~/.pi/agent/agents]
"""

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

from pi_skills import DELEGATES, PI_NOTE, plugin_names, source_commit, transform_text

MARKER = ".generated.json"
READ_ONLY = "read, bash, grep, find, ls"
EDITING = "read, bash, edit, write, grep, find, ls"
# Team agents that write code themselves; the rest advise and the parent edits.
EDITORS = {"tdd-micronaut-v2"}
PI_KEYS = (
    'acceptance: { level: "none", reason: "Parent verifies results and requests review explicitly" }\n'
    "systemPromptMode: append\n"
    "inheritProjectContext: true\n"
    "inheritGlobalContext: true\n"
    "inheritSkills: true\n"
    "advertise: true\n"
)
FRONT = re.compile(r"---\n(.*?)\n---\n?", re.DOTALL)
# Claude keeps an agent's `memory:` folder for it; pi has no such feature, so
# the agent is told where its notes live.
MEMORY_NOTE = (
    "> **In pi:** your agent memory is the folder `~/.pi/agent/agent-memory/{name}/`. Read what "
    "is there before you start, and write concise notes there when you learn something that "
    "would otherwise have to be rediscovered.\n"
)


def field(front: str, key: str) -> str | None:
    """The `key:` entry with its indented continuation lines, verbatim."""
    lines = front.splitlines()
    for i, line in enumerate(lines):
        if line.startswith(f"{key}:"):
            block = [line]
            for more in lines[i + 1:]:
                if more.startswith((" ", "\t")) or not more.strip():
                    block.append(more)
                else:
                    break
            return "\n".join(block).rstrip() + "\n"
    return None


def convert(text: str, *, name: str, agent_out: Path, plugin_src: Path, plugins: list[str]) -> str:
    match = FRONT.match(text)
    if not match:
        raise ValueError(f"{name}: no front matter")
    front, body = match.group(1), text[match.end():]
    description = field(front, "description") or f"description: {name}\n"
    tools = EDITING if name in EDITORS else READ_ONLY
    new_body = transform_text(body, skill_out=agent_out, plugin_src=plugin_src, plugins=plugins)
    if DELEGATES.search(body):
        new_body = "\n" + PI_NOTE + new_body.lstrip("\n")
    if field(front, "memory"):
        new_body = new_body.rstrip("\n") + "\n\n" + MEMORY_NOTE.format(name=name)
    return f"---\nname: {name}\n{description}tools: {tools}\n{PI_KEYS}---\n{new_body}"


def generate(src: Path, local: Path, out: Path) -> dict:
    src, local, out = src.expanduser().resolve(), local.expanduser().absolute(), out.expanduser()
    if out.is_symlink():
        out.unlink()  # the old setup linked this folder straight to dotfiles/pi/agents
    elif out.exists() and any(out.iterdir()) and not (out / MARKER).exists():
        sys.exit(f"pi_agents: {out} has files this script did not create; refusing to wipe it")
    plugins = plugin_names(src)
    team_files = {}
    for path in sorted(src.glob("plugins/*/agents/*.md")):
        if path.stem in team_files:
            sys.exit(f"pi_agents: two plugins define an agent named {path.stem}")
        team_files[path.stem] = path
    local_files = sorted(local.glob("*.md")) if local.is_dir() else []
    forks = sorted(p.stem for p in local_files if p.stem in team_files)
    if forks:
        sys.exit(f"pi_agents: {local} has forks of team agents: {', '.join(forks)}. "
                 "Change them in claude-components instead.")

    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    team, skipped = [], []
    for name, path in sorted(team_files.items()):
        text = path.read_text()
        match = FRONT.match(text)
        tools = field(match.group(1), "tools") if match else None
        if tools and "mcp__" in tools:
            skipped.append(name)
            continue
        (out / f"{name}.md").write_text(
            convert(text, name=name, agent_out=out, plugin_src=path.parent.parent, plugins=plugins))
        team.append(name)
    for path in local_files:
        (out / path.name).symlink_to(path)
    result = {"source": str(src), "commit": source_commit(src), "team": team,
              "local": [p.stem for p in local_files], "skipped": skipped}
    (out / MARKER).write_text(json.dumps(result, indent=2) + "\n")
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate pi's agents folder.")
    parser.add_argument("--src", default="~/projects/claude-components")
    parser.add_argument("--local", default=str(Path(__file__).resolve().parent.parent / "agents"))
    parser.add_argument("--out", default="~/.pi/agent/agents")
    args = parser.parse_args()
    r = generate(Path(args.src), Path(args.local), Path(args.out))
    skipped = f", skipped {', '.join(r['skipped'])} (Claude-only tools)" if r["skipped"] else ""
    print(f"pi_agents: {len(r['team'])} team + {len(r['local'])} pi-only agents -> {args.out}{skipped}")


if __name__ == "__main__":
    main()
