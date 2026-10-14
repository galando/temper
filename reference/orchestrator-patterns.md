---
description: "Shared patterns of a run: the plugin folder, the run files, evidence labels, stage hand off files"
---

# Shared patterns of a run

**Read by** the stage briefs and the reference pages that point here, and by people. What comes
next in a run, every gate question and every move are computed by the temper CLI
(`${CLAUDE_PLUGIN_ROOT}/scripts/temper next --json`, described in `${CLAUDE_PLUGIN_ROOT}/docs/flow.md`);
nothing on this page decides a step.

## The plugin folder

The plugin folder is the folder Temper is installed in: the folder that holds
`${CLAUDE_PLUGIN_ROOT}/scripts/temper` (that path with /scripts/temper taken off).

- **In a Temper command, stage brief or skill**, Claude Code writes the plugin's
  absolute folder in place of the CLAUDE_PLUGIN_ROOT variable when it loads the text, so
  the command text already holds the real path.
- **In the Bash tool** the CLAUDE_PLUGIN_ROOT variable is not set. A command run in Bash
  uses the absolute path, written out in full, exactly as the command text shows it.
- **In a reference page** like this one, or in a brief read with the Read tool, the
  variable is not filled in. There it means the same folder: the one the command, or the
  `Plugin folder:` line of a stage's launch prompt, names.

Only if the folder is unknown, stop and say: "Cannot locate Temper plugin. Reinstall
it." Never search the disk for the plugin folder and never guess another one. The temper
CLI is always called by its full path, `${CLAUDE_PLUGIN_ROOT}/scripts/temper`. Every
path that does not start with the plugin folder (`.temper/`, the spec files,
`.claude/temper.config`) is in the user's project, the current directory.

## The run files

`.temper/build-state.json` is owned by `${CLAUDE_PLUGIN_ROOT}/scripts/temper state`; never hand write it.
When the CLI exits 3, a path it keeps run state in (the `.temper` folder, its evidence, specs or archive
folder, a state or evidence file, or the active run's spec folder or its `gate-ledger.json`) is a symlink:
stop, show its one line reason, and wait for the person. Never remove, replace or follow the link yourself.

```json
{ "stage": "{stage}_complete", "spec": "{slug}", "spec_path": ".temper/specs/{slug}",
  "branch": "{feature|fix}/{slug}", "command": "temper|fix", "next_stage": "{next}",
  "run_mode": "interactive|autonomous", "run_id": "{16 hex}", "step": 0,
  "feature": "{as the person typed it}", "enter": "{a door's stage}", "base_sha": "{sha}",
  "approved_files": ["{the plan's files when the person approved it}"], "parked": "{stage}",
  "redo": {"stage": "build", "reason": "{what to mend}"}, "started": "{ISO}", "updated": "{ISO}" }
```

Stage sequences: `/temper` is intent, plan, design (medium or complex), build, review, check, commit,
on branch `feature/{slug}`; `/temper:fix` is rca, fix, review, check, commit, on branch `fix/{slug}`.
Every change of `next_stage` counts one `step`; a step back clears the verdicts of the stages it redoes.
A run moves forward only by `state advance` (a forward `state set next_stage`, and a `state loop` to a
later stage, are refused), and entering Commit clears any earlier commit verdict, so the commit gate
runs for the run itself. `base_sha` is recorded when the run leaves Plan: HEAD, or, for a door into
Review or Check, where the feature started (before the commit that added its `intent.md`, else where
the branch left main or master), so the work the door reviews is in the diff.

The other run files are the CLI's too: `.temper/gates.json` (each stage's verdict and rows),
`.temper/overrides.json` (the person's skips), `.temper/feedback-loops.json` (the loop budget),
`.temper/usage.json` (whole flow usage rows `{stage, model, tokens, ms, task, group, ts}`, from
`temper usage add` after each stage launch and from `temper task gate --tokens --ms` for each task
agent, so each launch is counted once), in Build `.temper/groups.json` (each group's worktree,
status and gate verdict; each task's status, attempts and commit; the integration verdict), and
`.temper/view.json`, the view the mod draws (`${CLAUDE_PLUGIN_ROOT}/docs/flow.md`).

## Context Efficiency

| Transition | Context loaded | Size |
|---|---|---|
| Stage N → N+1 (plan→build) | spec artifacts + related files | ~5-15KB |
| Build → Review/Check | changed files (`git diff` vs `base_sha` when recorded, + uncommitted paths) | ~20-50KB |
| Check/Fix → Commit | nothing (direct, no subprocess) | 0KB |

`/temper:fix` uses `fix/{bug-slug}` branches, `rca.md` in place of `intent.md`/`plan.md`.

## MCP Tool-First Pattern

`tools.mode`: `auto` (default — try MCP, fall back to grep-based heuristic) /
`heuristic-only` (never call MCP, forces `[HEURISTIC]`) / `require` (fail if MCP
unavailable, no fallback). Every finding's `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence add --label`:

| Label | Meaning |
|---|---|
| `PROVEN` | Mechanically verified: a real command or tool ran with a real exit code and artifact. `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence add` re-checks this itself; a missing artifact or unexplained nonzero exit auto-downgrades to HEURISTIC. |
| `HEURISTIC` | Grep/reading-based analysis, best-effort, not mechanically verified. |
| `SEMANTIC` | Claude's judgment/interpretation — inherently subjective. |
| `OCR` | External engine (open-code-review) finding — informational, same trust tier as HEURISTIC. |

Recommended servers: code-review-graph for AST-level dependency graphs and blast radius
(install it as its own page says: https://github.com/tirth8205/code-review-graph), and
Semgrep for SAST (install it and add it as an MCP server as its own page says:
https://github.com/semgrep/semgrep). Name the tool and give its page; never print an
install command for it. Both are optional: without them the same analysis runs via
grep, labeled `HEURISTIC` instead of `PROVEN`.

## Context Accumulation

Each stage writes structured artifacts to `.temper/specs/{feature}/` that downstream
stages read — richer than the flat evidence ledger: deviations, coverage detail,
justifications a gate doesn't need but a re-launched agent does.

```json
// build-context.json (Build, on a Review/Check feedback re-entry or Build->Plan loop)
{ "version": 1, "stage": "build", "timestamp": "", "files_created": [], "files_modified": [],
  "test_results": { "total": 0, "passed": 0, "failed": 0 },
  "deviations": { "unplanned_files": [], "skipped_tasks": [], "approach_changes": [] },
  "scenarios_covered": [], "tasks_completed": 0, "tasks_total": 0 }

// review-context.json (Review, read by Build on a loop-back)
{ "version": 1, "stage": "review", "timestamp": "",
  "findings_summary": { "critical": 0, "high": 0, "medium": 0, "low": 0, "auto_fixed": 0 },
  "intent_verdict": "satisfied|partial|not_met", "security_hot_paths": [], "contract_changes": [],
  "scenario_coverage": { "total": 0, "strong": 0, "weak": 0, "trivial": 0, "uncovered": 0 } }

// check-context.json (Check, read by Build on a loop-back)
{ "version": 1, "stage": "check", "timestamp": "",
  "validation_results": { "compile": "pass", "tests": "pass", "coverage_pct": 0, "lint": "pass", "security": "pass" },
  "scenario_verification": { "total": 0, "passed": 0, "failed": 0, "missing": 0 },
  "test_failures": [ { "test_name": "", "error_message": "", "file": "", "line": 0, "scenario": "" } ] }
```

`review-memory.json` (Review writes, Status + Review read — the single finding memory:
pattern acceptance/dismissal, promotion, and suppression). See
`${CLAUDE_PLUGIN_ROOT}/reference/review.md` → "Metrics + Memory".

| Stage | Reads | Writes |
|---|---|---|
| Intent | nothing (first stage) | intent.md (Problem/criteria/constraints — no scenarios) |
| Plan | intent.md (accepted) | intent.md (adds Scenarios), tasks.md, plan.md |
| Design | intent.md, plan.md | design.md |
| Build | tasks.md, intent.md, review/check-context.json (on re-entry) | build-context.json |
| Review | intent.md, `git diff`, build-context.json, review-memory.json | review-context.json, review-memory.json |
| Check | intent.md, review-context.json | check-context.json |
| Status | metrics.json, review-memory.json, gates.json, evidence/ | — |

**Cleanup:** `${CLAUDE_PLUGIN_ROOT}/scripts/temper state clear` (on commit) removes the run state (`build-state.json`,
the loop counters, `gates.json`, `overrides.json`) and the evidence ledger. Nothing under
`.temper/specs/` is touched: `intent.md`/`tasks.md`/`plan.md`/`design.md` are the
permanent record. Build deletes a `review-context.json` or `check-context.json` itself
once it has acted on it (see `${CLAUDE_PLUGIN_ROOT}/reference/build.md`).

## Feedback Loop Patterns

The pipeline is cyclic, not strictly linear — a gate FAIL can send work back upstream
with failure context.

- **Review → Build:** open findings at or above the block level → "Loop back to Build" →
  the Build fix pass, then Review again. Context: `review-context.json`'s fix list.
- **Check → Build:** test failures → a targeted fix task (test name, error, file:line,
  the `intent.md` scenario it maps to) → "Loop back to Build". Context:
  `check-context.json`'s `test_failures[]`.
- **Build → Plan:** Build judges the plan infeasible → "Loop back to Plan", Plan gets the
  infeasibility context and re-approves. Human-driven only — no circuit breaker, max 1
  per run. Context: `build-context.json`'s infeasibility reason.

**Budget and clearing:** `temper state loop` enforces the budget (`loops.max-per-type`) and clears
the evidence, the verdicts and the skips of the stages it redoes. A loop is a normal stage launch that
reads the relevant `review-context.json` or `check-context.json` at startup.
