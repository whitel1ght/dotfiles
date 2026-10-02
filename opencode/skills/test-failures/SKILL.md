---
name: test-failures
description: >-
  Analyze Gradle test reports and summarize failures concisely. Use when tests fail, user asks about test results or failures, after ./gradlew test commands with failures, or when user invokes /test-failures. Invoke with /test-failures <project-name>.
---


# Test Failure Analyzer

Summarize Gradle JUnit XML failures. The heavy report-reading work is delegated to the `backend:test-report-analyzer` agent (its system prompt already encodes the full extraction strategy and output format), so this skill only orchestrates: resolve path → fast-exit if nothing to analyze → spawn agent → relay output.

## 1. Resolve project path

`$ARGUMENTS` holds the user's argument. Normalize it: strip a leading `:`, replace `:` with `/`, replace spaces with `_` (e.g., `:data import:web` → `data/import_web`). Build the report path:

```
{repo-root}/projects/{normalized}/build/test-results/test/
```

If `$ARGUMENTS` is empty, ask the user which project to analyze (you may suggest projects that have a `build/test-results/test/` directory).

## 2. Verify and triage (single early-exit pass)

```bash
ls {report_path}/TEST-*.xml 2>/dev/null > /tmp/_xmls && \
  grep -l 'failures="[1-9]\|errors="[1-9]' $(cat /tmp/_xmls) 2>/dev/null
```

- **No XMLs at all** → respond: `No test results found for {project_name}. Run ./gradlew :{project_name}:test first.` Stop.
- **XMLs exist, no failures matched** → sum `tests="N"` across files and respond: `All {total} tests passed in {project_name}.` Stop.
- **Failures matched** → keep that file list for step 4.

Both no-result and all-pass cases must skip spawning the agent.

## 3. Stale-results check (compressed)

```bash
stat -f "%m" {report_path}/TEST-*.xml | sort -rn | head -1
```

If the newest mtime is more than ~1 hour old, prepend to the final output:
> **Note:** Test results from {timestamp} may be stale.

## 4. Spawn the analyzer

Use the **Agent tool** with `subagent_type: backend:test-report-analyzer`, `model: sonnet`. The agent's system prompt is the source of truth for the multi-pass strategy, grouping rules, output format, and constraints — do **not** restate them, and do **not** fall back to `general-purpose` (it has none of that context and will dump raw stack traces).

If `backend:test-report-analyzer` is unavailable, stop and tell the user the agent is missing — the `backend` plugin is not installed, or the session predates it (agents bind at session launch).

Pass only:

- The full report directory path
- The list of XML files identified in step 2 as having failures

Example minimal prompt:
> Analyze test failures in `{report_path}`. Files with failures: `{file list}`. Follow your standard extraction strategy and return the markdown summary.

## 5. Relay output

The agent returns formatted markdown — pass it through verbatim (with the stale-results warning prepended if applicable).

## Examples

- `/test-failures data_import_web`
- `/test-failures :core_rest`
- `/test-failures` — prompts for a project
