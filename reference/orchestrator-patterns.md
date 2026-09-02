---
description: "Shared patterns for orchestrator commands (temper.md, fix.md)"
---

# Orchestrator Shared Patterns

**Used by:** `commands/temper.md`, `commands/fix.md`. Read once at the start — every
`→ pattern` reference in either file points here.

Scope: shared, judgment-adjacent bookkeeping only (state schema, gate UX,
resume/invocation safety, hand-off formats). Mechanism with one correct output (model
resolution, gate logic) lives in `scripts/temper` and `agents/*.md` frontmatter.

## $CLAUDE_PLUGIN_ROOT Resolution

Set and valid → use it. Unset → walk up from the command file for `.claude-plugin/`.
Still not found → `~/.claude/plugins/temper` (default install). That doesn't exist
either → warn "Cannot locate Temper plugin. Set CLAUDE_PLUGIN_ROOT or reinstall."
`$TEMPER` means `$CLAUDE_PLUGIN_ROOT/scripts/temper` throughout `temper.md`/`fix.md`.

## Build State Schema

`.temper/build-state.json`, owned by `$TEMPER state` — never hand-write it. Resolve the
spec path from `$TEMPER state get spec_path` before launching any agent.

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

**Save/Continue:** `$TEMPER state advance {stage}_complete {next_stage}` at every
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
      description: "Delete existing session (temper state clear), start from scratch."
```

## Agent Failure Handling

An agent subprocess returns a failure/blocker → show the details, ask "Retry / Save for
later?" (changes via "Other"). Never silently proceed to the next stage.

## Context Efficiency

| Transition | Context loaded | Size |
|---|---|---|
| Stage N → N+1 (plan→build) | spec artifacts + related files | ~5-15KB |
| Build → Review/Check | changed files (`git diff`) | ~20-50KB |
| Check/Fix → Commit | nothing (direct, no subprocess) | 0KB |

`/temper:fix` uses `fix/{bug-slug}` branches, `rca.md` in place of `intent.md`/`plan.md`.

## MCP Tool-First Pattern

`tools.mode`: `auto` (default — try MCP, fall back to grep-based heuristic) /
`heuristic-only` (never call MCP, forces `[HEURISTIC]`) / `require` (fail if MCP
unavailable, no fallback). Every finding's `temper evidence add --label`:

| Label | Meaning |
|---|---|
| `PROVEN` | Mechanically verified — a real command/tool ran with a real exit code and artifact. `temper evidence add` re-checks this itself; a missing artifact or unexplained nonzero exit auto-downgrades to HEURISTIC. |
| `HEURISTIC` | Grep/reading-based analysis, best-effort, not mechanically verified. |
| `SEMANTIC` | Claude's judgment/interpretation — inherently subjective. |
| `OCR` | External engine (open-code-review) finding — informational, same trust tier as HEURISTIC. |

Recommended servers: `code-review-graph` (`pip install code-review-graph`) for AST-level
dependency graphs and blast radius; `semgrep` (`brew install semgrep`,
`claude mcp add semgrep -- semgrep --mcp`) for SAST. Both optional — absence just means
the same analysis runs via grep, labeled `HEURISTIC` instead of `PROVEN`.

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
pattern acceptance/dismissal, promotion, and suppression). See `reference/review.md` →
"Metrics + Memory".

| Stage | Reads | Writes |
|---|---|---|
| Intent | nothing (first stage) | intent.md (Problem/criteria/constraints — no scenarios) |
| Plan | intent.md (accepted) | intent.md (adds Scenarios), tasks.md, plan.md |
| Design | intent.md, plan.md | design.md |
| Build | tasks.md, intent.md, review/check-context.json (on re-entry) | build-context.json |
| Review | intent.md, `git diff`, build-context.json, review-memory.json | review-context.json, review-memory.json |
| Check | intent.md, review-context.json | check-context.json |
| Status | metrics.json, review-memory.json, gates.json, evidence/ | — |

**Cleanup:** `$TEMPER state clear` (on commit) removes `*-context.json`, `gates.json`,
`overrides.json`, the evidence ledger. `intent.md`/`tasks.md`/`plan.md`/`design.md` under
`.temper/specs/` are kept — they're the permanent record.

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
`commands/temper.md` → "Feedback Loops" — not restated here. A loop is always a normal stage re-launch that reads the
relevant `*-context.json` at startup.
