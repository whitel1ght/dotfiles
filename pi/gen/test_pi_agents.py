"""Tests for pi_agents.py. A fake claude-components tree and a fake pi/agents
folder in a temp dir stand in for the real ones; the real ~/.pi is never touched."""

import json
import shutil
import tempfile
import unittest
from pathlib import Path

import pi_agents


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp()).resolve()
        self.src = self.tmp / "claude-components"
        self.local = self.tmp / "pi-agents"
        self.out = self.tmp / "agents"
        write(self.src / ".claude-plugin/marketplace.json", json.dumps({
            "name": "ecfx-components",
            "plugins": [{"name": n, "source": f"./plugins/{n}"} for n in ("shared", "backend", "ops")],
        }))
        write(self.src / "plugins/shared/agents/git-expert.md",
              '---\nname: git-expert\ndescription: "Use for Git. Reach for it when history breaks."\n'
              "model: opus\ncolor: purple\n---\n\nYou are a Git expert. Hand UI questions to `shared:ux-expert`.\n")
        write(self.src / "plugins/backend/agents/tdd-micronaut-v2.md",
              "---\nname: tdd-micronaut-v2\ndescription: >-\n  Writes tests first,\n  then code.\nmodel: sonnet\ncolor: green\n---\n"
              "Launch a subagent with the Task tool for each module.\n")
        write(self.src / "plugins/ops/agents/browser-tester.md",
              "---\nname: browser-tester\ndescription: Clicks through the app.\nmodel: opus\ncolor: red\n"
              "tools: Read, Bash, mcp__claude-in-chrome__navigate\n---\nUse the browser.\n")
        write(self.local / "worker.md", "---\nname: worker\ndescription: Does the work.\ntools: read, bash, edit, write\n---\nWork.\n")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_gen(self):
        return pi_agents.generate(self.src, self.local, self.out)


class TeamAgents(Fixture):
    def test_header_is_pi_shaped(self):
        self.run_gen()
        text = (self.out / "git-expert.md").read_text()
        front = text.split("---\n")[1]
        self.assertIn("name: git-expert\n", front)
        self.assertIn('description: "Use for Git. Reach for it when history breaks."\n', front)
        self.assertIn("tools: read, bash, grep, find, ls\n", front)
        self.assertIn("systemPromptMode: append\n", front)
        self.assertIn("advertise: true\n", front)
        self.assertNotIn("model:", front)
        self.assertNotIn("color:", front)

    def test_multiline_description_is_kept_whole(self):
        self.run_gen()
        front = (self.out / "tdd-micronaut-v2.md").read_text().split("---\n")[1]
        self.assertIn("description: >-\n  Writes tests first,\n  then code.\n", front)

    def test_editing_agents_keep_edit_and_write(self):
        self.run_gen()
        front = (self.out / "tdd-micronaut-v2.md").read_text().split("---\n")[1]
        self.assertIn("tools: read, bash, edit, write, grep, find, ls\n", front)

    def test_body_is_the_team_text_with_prefixes_dropped(self):
        self.run_gen()
        body = (self.out / "git-expert.md").read_text().split("---\n", 2)[2]
        self.assertIn("You are a Git expert. Hand UI questions to `ux-expert`.", body)

    def test_delegating_agents_get_the_pi_note(self):
        self.run_gen()
        self.assertIn("**In pi:**", (self.out / "tdd-micronaut-v2.md").read_text())
        self.assertNotIn("**In pi:**", (self.out / "git-expert.md").read_text())

    def test_agents_with_claude_memory_get_a_pi_memory_folder(self):
        write(self.src / "plugins/shared/agents/simplifier.md",
              "---\nname: simplifier\ndescription: d\nmodel: opus\ncolor: red\nmemory: user\n---\nUpdate your agent memory.\n")
        self.run_gen()
        text = (self.out / "simplifier.md").read_text()
        self.assertIn("~/.pi/agent/agent-memory/simplifier/", text)
        self.assertNotIn("memory:", text.split("---\n")[1])
        self.assertNotIn("agent-memory", (self.out / "git-expert.md").read_text())

    def test_agents_needing_claude_only_tools_are_skipped(self):
        result = self.run_gen()
        self.assertFalse((self.out / "browser-tester.md").exists())
        self.assertIn("browser-tester", result["skipped"])

    def test_marker_records_source_and_names(self):
        self.run_gen()
        marker = json.loads((self.out / pi_agents.MARKER).read_text())
        self.assertEqual(marker["team"], ["git-expert", "tdd-micronaut-v2"])
        self.assertEqual(marker["local"], ["worker"])


class LocalAgents(Fixture):
    def test_pi_only_agents_are_linked_not_copied(self):
        self.run_gen()
        link = self.out / "worker.md"
        self.assertTrue(link.is_symlink())
        self.assertEqual(link.resolve(), (self.local / "worker.md").resolve())

    def test_a_local_fork_of_a_team_agent_is_refused(self):
        write(self.local / "git-expert.md", "---\nname: git-expert\n---\nFork.\n")
        with self.assertRaises(SystemExit):
            self.run_gen()


class OutputFolder(Fixture):
    def test_rebuilt_from_scratch(self):
        self.run_gen()
        (self.src / "plugins/shared/agents/git-expert.md").unlink()
        self.run_gen()
        self.assertFalse((self.out / "git-expert.md").exists())

    def test_never_wipes_a_folder_it_did_not_create(self):
        write(self.out / "mine.md", "hand made\n")
        with self.assertRaises(SystemExit):
            self.run_gen()
        self.assertTrue((self.out / "mine.md").exists())

    def test_replaces_the_old_symlink_to_the_local_folder(self):
        self.out.symlink_to(self.local)
        self.run_gen()
        self.assertFalse(self.out.is_symlink())
        self.assertTrue((self.local / "worker.md").exists(), "the local folder must survive")
        self.assertTrue((self.out / "git-expert.md").exists())


if __name__ == "__main__":
    unittest.main()
