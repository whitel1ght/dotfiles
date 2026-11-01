#!/usr/bin/env python3
"""VENV_DIR placement test for inbox_lookup.

Run directly -- `python3 plugins/ops/skills/inbox-lookup/test_inbox_lookup.py`. No pytest: not
installed here, and this mirrors lib/test_jira_metrics.py's self-contained-script convention.

VENV_DIR used to be `SKILL_DIR / ".venv"` -- inside the skill's own directory. SKILL_DIR is a
plugin install path that a version bump replaces wholesale (see docs/INSTALL.md, "Getting
updates"): every bump silently threw away the ~150 MB Playwright virtualenv and forced a full
rebuild on the next login, and a fresh clone (or repo sync) of the checkout would pick it up too.
This pins VENV_DIR outside SKILL_DIR, in the per-user cache location the rest of the skill's
per-machine state already uses (see SESSION_CACHE in inbox_lookup.py).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import inbox_lookup as il  # noqa: E402

FAILURES = []


def check(name, condition, detail=""):
    if condition:
        print(f"  ok   {name}")
    else:
        print(f"  FAIL {name} {detail}")
        FAILURES.append(name)


def main():
    print("VENV_DIR placement")
    check("VENV_DIR is not inside SKILL_DIR (the plugin install path)",
          il.SKILL_DIR not in il.VENV_DIR.parents,
          f"-> SKILL_DIR={il.SKILL_DIR} VENV_DIR={il.VENV_DIR}")
    check("VENV_DIR is under the user's home directory",
          Path.home() in il.VENV_DIR.parents,
          f"-> {il.VENV_DIR}")
    check("LOGIN_SCRIPT is still inside SKILL_DIR (it is code the skill ships, not state)",
          il.SKILL_DIR in il.LOGIN_SCRIPT.parents,
          f"-> SKILL_DIR={il.SKILL_DIR} LOGIN_SCRIPT={il.LOGIN_SCRIPT}")

    print()
    if FAILURES:
        print(f"{len(FAILURES)} failure(s): {', '.join(FAILURES)}")
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
