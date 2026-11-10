#!/usr/bin/env python3
"""Build pi's copy of the team skills from a claude-components clone.

Claude Code loads claude-components as a plugin marketplace. pi reads the same
SKILL.md format, so instead of hand-kept forks this script generates pi's set:
every plugins/*/skills/<name>/ folder is copied whole into the output folder,
and its markdown gets the few Claude-only constructs rewritten:

  name: Ship It            ->  name: shipit      (pi commands use the folder name)
  - Branch: !`git …`       ->  - Branch: run `git …`   (pi does not run !`…`)
  `backend:tdd-micronaut`  ->  `tdd-micronaut`   (pi agents are not namespaced)
  ~/.claude/docs/          ->  ~/.agents/docs/
  ${CLAUDE_SKILL_DIR}      ->  the generated skill folder
  ${CLAUDE_PLUGIN_ROOT}    ->  the plugin folder in the clone
  description: <1395 chars> ->  cut to 1024 (pi's limit) after a sentence, with …

Skills that delegate or chain skills get a short "In pi" note on how to do that
in pi. The output folder is owned by this script: it is rebuilt from scratch on
every run and carries a .generated.json marker; a folder without the marker is
never wiped.

  pi_skills.py [--src ~/projects/claude-components] [--out ~/.pi/agent/skills-team]
               [--select pi/team-skills.json]

--select limits the copy to the plugins Claude Code enables plus single skills pi
uses from the others: every mirrored description sits in every pi session's prompt.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

MARKER = ".generated.json"

PI_NOTE = (
    "> **In pi:** this skill comes from claude-components and is written for Claude Code. "
    "Where it says to launch a subagent (the Agent or Task tool, or a plugin agent such as "
    "`backend:x`), call `subagent({ role, model, task, cwd, label })`: `role` is the agent's name "
    "without the plugin prefix (a file in `~/.pi/agent/agents/`) and `model` comes from the "
    "`<subagent_models>` list. Where it says to invoke a skill via the Skill tool, read that "
    "skill's SKILL.md and follow it.\n\n"
)

DELEGATES = re.compile(r"\bsubagents?\b|\bAgent tool\b|\bTask tool\b|\bvia the Skill tool\b", re.IGNORECASE)
# Claude runs !`cmd` only at the start of a token; `Secret!` and `x` is ordinary prose.
BANG = re.compile(r"(?<![\w`])!`([^`\n]+)`")
FENCE = re.compile(r"^\s*(```|~~~)")


def plugin_names(src: Path) -> list[str]:
    market = json.loads((src / ".claude-plugin/marketplace.json").read_text())
    return [p["name"] for p in market["plugins"]]


def outside_fences(text: str, fn) -> str:
    """Apply fn to every line that is not inside a fenced code block."""
    out, fenced = [], False
    for line in text.splitlines(keepends=True):
        if FENCE.match(line):
            fenced = not fenced
            out.append(line)
        else:
            out.append(line if fenced else fn(line))
    return "".join(out)


def resolve_vars(text: str, *, skill_out: Path, plugin_src: Path) -> str:
    text = text.replace("${CLAUDE_SKILL_DIR}", str(skill_out))
    return text.replace("${CLAUDE_PLUGIN_ROOT}", str(plugin_src))


def transform_text(text: str, *, skill_out: Path, plugin_src: Path, plugins: list[str]) -> str:
    prefix = re.compile(r"(?<![\w/.:-])(?:" + "|".join(map(re.escape, plugins)) + r"):([a-z0-9][a-z0-9-]*[a-z0-9])")

    def line_fn(line: str) -> str:
        line = BANG.sub(r"run `\1`", line)
        return prefix.sub(r"\1", line)

    text = outside_fences(text, line_fn)
    text = text.replace("~/.claude/docs/", "~/.agents/docs/")
    return resolve_vars(text, skill_out=skill_out, plugin_src=plugin_src)


DESC_MAX = 1024  # the Agent Skills limit; pi warns past it, Claude Code does not


def shorten(text: str) -> str:
    """Cut to DESC_MAX with an ellipsis: after the last sentence that fits, else the last word."""
    if len(text) <= DESC_MAX:
        return text
    head = text[: DESC_MAX - 1]
    cut = max(head.rfind(". "), head.rfind("; "))
    cut = cut + 1 if cut > DESC_MAX // 2 else head.rfind(" ")
    return head[:cut].rstrip() + "…"


def fit_description(front: str) -> str:
    def fix(m: re.Match) -> str:
        value = m.group(1)
        if value.startswith('"'):
            try:
                return "description: " + json.dumps(shorten(json.loads(value)), ensure_ascii=False)
            except ValueError:
                return m.group(0)
        if value[:1] in ("|", ">", "'"):
            return m.group(0)
        return "description: " + shorten(value)
    return re.sub(r"(?m)^description: (.+)$", fix, front, count=1)


def transform_skill_md(text: str, *, name: str, skill_out: Path, plugin_src: Path, plugins: list[str]) -> str:
    match = re.match(r"---\n(.*?)\n---\n", text, re.DOTALL)
    if not match:
        raise ValueError("SKILL.md has no front matter")
    front = re.sub(r"(?m)^name:.*$", f"name: {name}", match.group(1), count=1)
    front = fit_description(resolve_vars(front, skill_out=skill_out, plugin_src=plugin_src))
    body = transform_text(text[match.end():], skill_out=skill_out, plugin_src=plugin_src, plugins=plugins)
    if DELEGATES.search(text[match.end():]):
        body = "\n" + PI_NOTE + body
    return f"---\n{front}\n---\n{body}"


def source_commit(src: Path) -> str:
    try:
        return subprocess.run(["git", "-C", str(src), "rev-parse", "--short", "HEAD"],
                              capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def load_select(path: Path | None, src: Path) -> tuple[set[str], set[str]] | None:
    """The plugins mirrored whole and the single skills kept from the others; None mirrors all.
    A name the clone no longer has is warned about, so an upstream rename is seen, not lost."""
    if path is None:
        return None
    sel = json.loads(path.expanduser().read_text())
    plugins, skills = set(sel.get("plugins", [])), set(sel.get("skills", []))
    have_plugins = {p.name for p in src.glob("plugins/*") if p.is_dir()}
    have_skills = {p.parent.name for p in src.glob("plugins/*/skills/*/SKILL.md")}
    for kind, names, have in (("plugin", plugins, have_plugins), ("skill", skills, have_skills)):
        for n in sorted(names - have):
            print(f"pi_skills: {path.name} names {kind} {n}, which {src} does not have", file=sys.stderr)
    return plugins, skills


def generate(src: Path, out: Path, select: Path | None = None) -> list[str]:
    src, out = src.expanduser().resolve(), out.expanduser()
    if out.exists() and any(out.iterdir()) and not (out / MARKER).exists():
        sys.exit(f"pi_skills: {out} has files this script did not create; refusing to wipe it")
    plugins = plugin_names(src)
    chosen = load_select(select, src)
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    names = []
    for skill_md in sorted(src.glob("plugins/*/skills/*/SKILL.md")):
        skill_src = skill_md.parent
        plugin_src = skill_src.parent.parent
        name = skill_src.name
        if chosen and plugin_src.name not in chosen[0] and name not in chosen[1]:
            continue
        skill_out = out / name
        if skill_out.exists():
            sys.exit(f"pi_skills: two plugins define a skill named {name}")
        shutil.copytree(skill_src, skill_out)
        for md in skill_out.rglob("*.md"):
            text = md.read_text()
            if md == skill_out / "SKILL.md":
                text = transform_skill_md(text, name=name, skill_out=skill_out, plugin_src=plugin_src, plugins=plugins)
            else:
                text = transform_text(text, skill_out=skill_out, plugin_src=plugin_src, plugins=plugins)
            md.write_text(text)
        names.append(name)
    names.sort()
    (out / MARKER).write_text(json.dumps({"source": str(src), "commit": source_commit(src), "skills": names}, indent=2) + "\n")
    return names


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate pi skills from claude-components.")
    parser.add_argument("--src", default="~/projects/claude-components")
    parser.add_argument("--out", default="~/.pi/agent/skills-team")
    parser.add_argument("--select", help="JSON {plugins: [...], skills: [...]}; without it every plugin is mirrored")
    args = parser.parse_args()
    names = generate(Path(args.src), Path(args.out), Path(args.select) if args.select else None)
    print(f"pi_skills: {len(names)} skills from {Path(args.src).expanduser()} -> {Path(args.out).expanduser()}")


if __name__ == "__main__":
    main()
