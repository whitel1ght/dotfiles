"""Tests for pi_skills.py. A fake claude-components tree in a temp dir stands in
for the real clone; the real ~/.pi is never touched."""

import json
import os
import tempfile
import unittest
from pathlib import Path

import pi_skills


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp()).resolve()  # macOS: /var -> /private/var
        self.src = self.tmp / "claude-components"
        self.out = self.tmp / "skills-team"
        write(self.src / ".claude-plugin/marketplace.json", json.dumps({
            "name": "ecfx-components",
            "plugins": [{"name": n, "source": f"./plugins/{n}"} for n in ("shared", "backend", "ui-review")],
        }))
        write(self.src / "plugins/shared/skills/shipit/SKILL.md",
              "---\nname: Ship It\ndescription: Ship the branch.\nallowed-tools: Bash\n---\n"
              "# Ship it\n\n- Current branch: !`git branch --show-current`\n- Status: !`git status --short`\n\n"
              "```bash\necho '!`not a command`'\n```\n")
        write(self.src / "plugins/backend/skills/tdd-flow/SKILL.md",
              "---\nname: tdd-flow\ndescription: TDD.\n---\n"
              "Mirrors the `backend:tdd-micronaut-v2` agent. Spawn the `ui-review:ux-expert` subagent.\n"
              "Invoke `tdd-context-loader` via the Skill tool. Read `~/.claude/docs/tdd-learnings.md`.\n"
              "Run `${CLAUDE_SKILL_DIR}/run.sh` and read `${CLAUDE_PLUGIN_ROOT}/modules/x.md`.\n"
              "See https://example.com/a:b and the backend: layer.\n")
        write(self.src / "plugins/backend/skills/tdd-flow/run.sh", "#!/bin/sh\necho hi\n")
        write(self.src / "plugins/backend/skills/tdd-flow/reference.md", "Use ${CLAUDE_SKILL_DIR}/run.sh\n")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.tmp, ignore_errors=True)


class TransformTests(Fixture):
    def gen(self):
        return pi_skills.generate(self.src, self.out)

    def read(self, rel):
        return (self.out / rel).read_text()

    def test_generates_every_skill_with_supporting_files(self):
        names = self.gen()
        self.assertEqual(sorted(names), ["shipit", "tdd-flow"])
        self.assertTrue((self.out / "tdd-flow/run.sh").exists())

    def test_name_becomes_the_directory_name(self):
        self.gen()
        self.assertIn("\nname: shipit\n", self.read("shipit/SKILL.md"))
        self.assertIn("allowed-tools: Bash", self.read("shipit/SKILL.md"))

    def test_bang_commands_become_instructions_outside_code_fences(self):
        self.gen()
        text = self.read("shipit/SKILL.md")
        self.assertIn("- Current branch: run `git branch --show-current`", text)
        self.assertNotIn("!`git", text)
        self.assertIn("echo '!`not a command`'", text)

    def test_plugin_prefixes_are_dropped_only_for_known_plugins(self):
        self.gen()
        text = self.read("tdd-flow/SKILL.md")
        self.assertIn("`tdd-micronaut-v2` agent", text)
        self.assertIn("`ux-expert` subagent", text)
        self.assertIn("https://example.com/a:b", text)
        self.assertIn("the backend: layer", text)

    def test_claude_paths_and_variables_are_resolved(self):
        self.gen()
        text = self.read("tdd-flow/SKILL.md")
        self.assertIn("~/.agents/docs/tdd-learnings.md", text)
        self.assertIn(f"{self.out / 'tdd-flow'}/run.sh", text)
        self.assertIn(f"{self.src / 'plugins/backend'}/modules/x.md", text)
        self.assertNotIn("${CLAUDE_", text)
        self.assertIn(f"{self.out / 'tdd-flow'}/run.sh", self.read("tdd-flow/reference.md"))

    def test_pi_note_added_only_where_skill_delegates_or_chains_skills(self):
        self.gen()
        self.assertIn("subagent({ role, model, task", self.read("tdd-flow/SKILL.md"))
        self.assertNotIn("subagent({", self.read("shipit/SKILL.md"))
        text = self.read("tdd-flow/SKILL.md")
        self.assertTrue(text.startswith("---\n"))
        self.assertLess(text.index("name: tdd-flow"), text.index("**In pi:**"))

    def test_variables_in_front_matter_are_resolved_too(self):
        write(self.src / "plugins/shared/skills/gate/SKILL.md",
              "---\nname: gate\ndescription: d\nallowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/hooks/x.sh:*)\n---\nbody\n")
        self.gen()
        self.assertIn(f"Bash({self.src / 'plugins/shared'}/hooks/x.sh:*)", self.read("gate/SKILL.md"))

    def test_bang_inside_ordinary_inline_code_is_left_alone(self):
        write(self.src / "plugins/shared/skills/prose/SKILL.md",
              "---\nname: prose\ndescription: d\n---\nPassword `Secret123!` and `other`; branch: !`git status`\n")
        self.gen()
        text = self.read("prose/SKILL.md")
        self.assertIn("`Secret123!` and `other`", text)
        self.assertIn("branch: run `git status`", text)

    def test_pi_note_is_its_own_paragraph(self):
        write(self.src / "plugins/shared/skills/quoted/SKILL.md",
              "---\nname: quoted\ndescription: d\n---\n> Spawn a subagent here.\n")
        self.gen()
        self.assertIn("follow it.\n\n> Spawn a subagent here.", self.read("quoted/SKILL.md"))

    def test_records_source_commit_and_marks_output(self):
        self.gen()
        marker = json.loads((self.out / ".generated.json").read_text())
        self.assertEqual(marker["skills"], ["shipit", "tdd-flow"])
        self.assertIn("source", marker)

    def test_regeneration_removes_skills_that_disappeared(self):
        self.gen()
        import shutil
        shutil.rmtree(self.src / "plugins/shared/skills/shipit")
        self.assertEqual(self.gen(), ["tdd-flow"])
        self.assertFalse((self.out / "shipit").exists())

    def description(self, name):
        front = (self.out / name / "SKILL.md").read_text().split("---\n")[1]
        return next(l for l in front.splitlines() if l.startswith("description: "))[len("description: "):]

    def test_a_description_over_pis_limit_is_cut_at_a_word(self):
        long = "Reads the suite and maps it. " * 50  # ~1450 characters
        write(self.src / "plugins/shared/skills/long/SKILL.md", f"---\nname: long\ndescription: {long.strip()}\n---\nBody.\n")
        self.gen()
        d = self.description("long")
        self.assertLessEqual(len(d), 1024)
        self.assertTrue(d.endswith("…"))
        self.assertTrue(d[:-1].endswith("it."), d[-40:])  # cut after a whole sentence
        self.assertIn("Body.", (self.out / "long/SKILL.md").read_text())

    def test_a_quoted_long_description_stays_quoted(self):
        long = "Reads the suite: maps it. " * 50
        write(self.src / "plugins/shared/skills/q/SKILL.md", f'---\nname: q\ndescription: "{long.strip()}"\n---\nBody.\n')
        self.gen()
        d = json.loads(self.description("q"))
        self.assertLessEqual(len(d), 1024)
        self.assertTrue(d.endswith("…"))

    def test_a_short_description_is_untouched(self):
        self.gen()
        self.assertEqual(self.description("shipit"), "Ship the branch.")

    def test_refuses_to_wipe_a_folder_it_did_not_create(self):
        write(self.out / "mine/SKILL.md", "hand-written")
        with self.assertRaises(SystemExit):
            self.gen()
        self.assertTrue((self.out / "mine/SKILL.md").exists())



class SelectTests(Fixture):
    def setUp(self):
        super().setUp()
        write(self.src / "plugins/ops/skills/notice-qa/SKILL.md", "---\nname: notice-qa\ndescription: QA.\n---\nbody\n")
        write(self.src / "plugins/ops/skills/health-check/SKILL.md", "---\nname: Health\ndescription: H.\n---\nbody\n")
        self.select = self.tmp / "team-skills.json"

    def gen(self, select):
        self.select.write_text(json.dumps(select))
        return pi_skills.generate(self.src, self.out, select=self.select)

    def test_without_a_selection_every_plugin_is_mirrored(self):
        names = pi_skills.generate(self.src, self.out)
        self.assertEqual(sorted(names), ["health-check", "notice-qa", "shipit", "tdd-flow"])

    def test_selection_keeps_listed_plugins_and_listed_skills_only(self):
        names = self.gen({"plugins": ["shared", "backend"], "skills": ["notice-qa"]})
        self.assertEqual(sorted(names), ["notice-qa", "shipit", "tdd-flow"])
        self.assertFalse((self.out / "health-check").exists())
        marker = json.loads((self.out / pi_skills.MARKER).read_text())
        self.assertEqual(marker["skills"], ["notice-qa", "shipit", "tdd-flow"])

    def test_prefixes_of_unselected_plugins_are_still_dropped(self):
        self.gen({"plugins": ["backend"], "skills": []})
        self.assertIn("`ux-expert` subagent", (self.out / "tdd-flow/SKILL.md").read_text())

    def test_unknown_names_in_the_selection_warn_and_the_rest_is_generated(self):
        import contextlib, io
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            names = self.gen({"plugins": ["shared", "gone-plugin"], "skills": ["renamed-skill"]})
        self.assertEqual(names, ["shipit"])
        self.assertIn("gone-plugin", err.getvalue())
        self.assertIn("renamed-skill", err.getvalue())


if __name__ == "__main__":
    unittest.main()
