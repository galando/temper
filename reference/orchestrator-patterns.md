---
description: "Shared patterns for orchestrator commands (temper.md, fix.md)"
---

# Orchestrator Shared Patterns

**Used by:** the `/temper` and `/temper:fix` orchestrators
(`${CLAUDE_PLUGIN_ROOT}/commands/temper.md`, `${CLAUDE_PLUGIN_ROOT}/commands/fix.md`). Read
once at the start — every `→ pattern` reference in either file points here.

Scope: shared, judgment-adjacent bookkeeping only (state schema, gate UX,
resume/invocation safety, hand-off formats). Mechanism with one correct output (model
resolution, gate logic) lives in the temper CLI (`${CLAUDE_PLUGIN_ROOT}/scripts/temper`)
and in the `model:` frontmatter of each stage brief.

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

## Build State Schema

`.temper/build-state.json`, owned by `${CLAUDE_PLUGIN_ROOT}/scripts/temper state` — never hand-write it. Resolve the
spec path from `${CLAUDE_PLUGIN_ROOT}/scripts/temper state get spec_path` before launching any agent.
When the CLI exits 3, it refused because the project's `.temper` folder is, or holds, a
symlink: stop, show its one-line reason, and wait for the user. Never remove, replace or
follow the link yourself.

```json
{ "stage": "{stage}_complete", "spec": "{slug}", "spec_path": ".temper/specs/{slug}",
  "branch": "{feature|fix}/{slug}", "command": "temper|fix", "next_stage": "{next}",
  "run_mode": "interactive|autonomous", "artifacts": ["intent.md", "tasks.md"],
  "updated": "{ISO timestamp}" }
```

Stage sequences: `/temper` — `intent_complete | plan_complete | design_complete |
build_complete | review_complete | check_complete`, branch `feature/{slug}`.
`/temper:fix` — `rca_complete | fix_complete | review_complete | check_complete`,
branch `fix/{slug}`.

**Save/Continue:** `${CLAUDE_PLUGIN_ROOT}/scripts/temper state advance {stage}_complete {next_stage}` at every
transition. On Save, report "Saved. Run {command} when ready to continue."

## Gate Options + Enforcement

Every gate: 2 explicit options plus the built-in "Other" free-text.

```
AskUserQuestion:
  question: "What would you like to do with this {stage}?"
  options:
    - label: "{continue_label} (Recommended)"
    - label: "Save for later"
      description: "Save state and stop. Run {command} later to continue."
```

A change typed via "Other" is **never** approval to proceed: make the edit, then **STOP**
and re-show the same gate. The user must explicitly pick "Continue" — never infer
approval from a change request.

## Resume Validation

Before honoring saved state, check: parseable JSON; `stage` is one the command defines;
`.temper/specs/{spec}/` exists on disk; the artifacts the **completed** stages should
have produced exist — `artifacts[]` lists the full run's expected set, so check it
stage-aware: at `intent_complete` only `intent.md` is owed (Plan hasn't written
`tasks.md`/`plan.md` yet); from `plan_complete` onward, every file in `artifacts[]`;
`updated` < 30 days old (warn if older). Any check fails → show what's wrong, ask
"Start over / Delete saved state / Cancel?"

## Nested Invocation Protection

`{command} "{new item}"` called while state exists for a **different** item:

```
AskUserQuestion:
  question: "A saved session exists for '{existing}'. What would you like to do?"
  options:
    - label: "Resume existing session (Recommended)"
      description: "Continue from {next_stage} stage."
    - label: "Overwrite and start new"
      description: "Delete the saved run state, start from scratch."
```

On "Overwrite and start new", run `${CLAUDE_PLUGIN_ROOT}/scripts/temper state clear`, then
start the new item from its first stage.

## Agent Failure Handling

An agent subprocess returns a failure/blocker → show the details, ask "Retry / Save for
later?" (changes via "Other"). Never silently proceed to the next stage.

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

- **Review → Build:** auto-fixable HIGH/CRITICAL found → "Fix all & continue to Check" →
  fixes applied, re-review runs. Context: `review-context.json`'s fix list.
- **Check → Build:** test failures → a targeted fix task (test name, error, file:line,
  the `intent.md` scenario it maps to) → "Loop back to Build". Context:
  `check-context.json`'s `test_failures[]`.
- **Build → Plan:** Build judges the plan infeasible → "Loop back to Plan", Plan gets the
  infeasibility context and re-approves. Human-driven only — no circuit breaker, max 1
  per run. Context: `build-context.json`'s infeasibility reason.

**Circuit breaker + evidence clearing:** full mechanics (budget, auto-clear) live in
`${CLAUDE_PLUGIN_ROOT}/commands/temper.md` → "Feedback Loops" — not restated here. A loop is
always a normal stage re-launch that reads the relevant `review-context.json` or
`check-context.json` at startup.
