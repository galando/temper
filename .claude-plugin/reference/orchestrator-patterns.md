---
description: "Shared patterns for orchestrator commands (temper.md, fix.md)"
---

# Orchestrator Shared Patterns

**Used by:** `.claude/commands/temper.md`, `.claude/commands/fix.md`

This file contains shared orchestration patterns. Both `/temper` and `/temper:fix` delegate to these patterns instead of duplicating them.

---

## $CLAUDE_PLUGIN_ROOT Resolution

All references use `$CLAUDE_PLUGIN_ROOT` to locate plugin files. Resolve it as follows:

1. If `$CLAUDE_PLUGIN_ROOT` is set and points to an existing directory → use it
2. If unset → walk up from the command file location looking for `.claude-plugin/manifest.json`
3. If still not found → fall back to `~/.claude/plugins/temper` (default install location)
4. If fallback doesn't exist → warn user: "Cannot locate Temper plugin. Set CLAUDE_PLUGIN_ROOT or reinstall."

The resolved path is used as `$CLAUDE_PLUGIN_ROOT` throughout the command.

---

## Single-Read Contract

Read this patterns file **once** at the start of the orchestrator command. Every
`→ {pattern name}` reference in `temper.md` / `fix.md` points into this
already-loaded file. **Do not re-read it** for each reference — the definitions are
already in context.

---

## Build State Schema

The orchestrator tracks progress via `.temper/build-state.json`. **Resolve the spec
path from this file before launching any agent.** Canonical shape:

```json
{
  "stage": "{stage}_complete",
  "spec": "{slug}",
  "spec_path": ".temper/specs/{slug}",
  "branch": "{feature|fix}/{slug}",
  "original_args": "{user's original description}",
  "next_stage": "{next stage}",
  "artifacts": ["intent.md", "tasks.md"],
  "updated": "{ISO timestamp}"
}
```

Per-command variations:
- **`/temper`** — stages `plan_complete | design_complete | build_complete | review_complete | check_complete`; branch `feature/{slug}`; artifacts `intent.md`, `tasks.md`.
- **`/temper:fix`** — stages `rca_complete | fix_complete | review_complete | check_complete`; branch `fix/{slug}`; artifacts `rca.md`.

### Save State Pattern

At every "Save for later" and "Continue" transition, write `build-state.json` using the
schema above with the stage-specific `stage`, `next_stage`, and `artifacts` values. Do
not re-document the full JSON at each gate — only state which `stage`/`next_stage` apply.

On **Save**: write state, then report `"Saved. Run {command} when ready to continue."`

---

## Stage Agent Launch Template

Every stage runs in an **isolated Agent subprocess** (genuine context clearing). Launch
each with this template — fill the bracketed deltas, keep the fixed scaffolding:

```
Use the Agent tool with this prompt:

"Execute {command/stage} for {item}: {spec from build-state.json}

Full methodology: Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/{stage}.md

CONTEXT: You are starting with a CLEAN context. Load these first:
{ordered list of context files for this stage}

{stage-specific instructions, e.g. enforcement notes or MCP tool priority}

CRITICAL: This agent runs in isolation. Do NOT show an AskUserQuestion gate at the
end — return the summary to the orchestrator, which owns the gate.

Return ONLY:
{stage-specific return contract}"

NESTED AGENTS (v5.1.0+):
If agents.nested is enabled in temper.config:
- Pass depth_remaining={max-depth - current_depth} to the subprocess prompt
- Add this instruction: "When spawning child agents, check depth_remaining:
  - If depth_remaining > 1: spawn Agent subprocesses (max parallel-width)
  - If depth_remaining <= 1: run helper work inline (no spawn)"
- Default depth_remaining = 4 at orchestrator (depth 0 → stage agents at depth 1 → helpers at depth 2)
```

**Fixed scaffolding** (identical for every stage, do not vary): the CLEAN-context line,
the "Full methodology: Read …" line, and the CRITICAL no-gate / return-to-orchestrator
rule. Only the bracketed deltas change per stage.

---

## Gate Options Pattern

Every stage gate uses exactly 2 explicit options plus the built-in "Other" free-text input:

```
AskUserQuestion:
  question: "What would you like to do with this {stage}?"
  options:
    - label: "{continue_label} (Recommended)"
      description: "{continue_description}"
    - label: "Save for later"
      description: "Save state and stop. Run {command} later to continue."
  multiSelect: false
```

**Users type change requests directly via the "Other" option.** AskUserQuestion always provides an "Other" free-text input. When a user selects "Other" and types a change request:
1. Make the requested change
2. **STOP** — re-show the AskUserQuestion gate with the same options
3. Do NOT interpret the change input as approval to proceed

---

## Gate Enforcement Rules

After handling a change request (via "Other" free-text input), you **MUST** re-show the AskUserQuestion gate before proceeding:

1. User selects "Other" and types their change request
2. You make the requested change
3. **STOP HERE** — re-show the AskUserQuestion gate with the same 2 options
4. Do NOT interpret the user's change input as approval to proceed to the next stage

The user must **explicitly select the "Continue" option** from the gate to proceed.

---

## Resume Validation

Before showing the saved state, validate `.temper/build-state.json`:

1. **Parseable JSON** — if malformed, show error and ask user
2. **Valid stage** — must be one of the stages defined by the command
3. **Spec directory exists** — `.temper/specs/{spec}/` must exist on disk
4. **Artifacts exist** — all files listed in `artifacts` array must exist
5. **Timestamp** — if `updated` > 30 days ago, warn user about staleness

If any check fails:
- Show what's wrong: "Saved state is invalid: {reason}"
- Ask user: "Start over / Delete saved state / Cancel?"

---

## Nested Invocation Protection

When `{command} "{new item}"` is called while `.temper/build-state.json` already exists for a different item:

```
┌─────────────────────────────────────────────────────────────┐
│ SAVED STATE FOUND                                           │
├─────────────────────────────────────────────────────────────┤
│ {Item type}: {name}                                         │
│    Stopped: After {stage}                                   │
│    Files: {N} changed                                       │
│                                                             │
│ Starting '{new item}' will overwrite this session.          │
└─────────────────────────────────────────────────────────────┘
```

Use AskUserQuestion:
```
AskUserQuestion:
  question: "A saved session exists for '{existing}'. What would you like to do?"
  options:
    - label: "Resume existing session (Recommended)"
      description: "Continue from {next_stage} stage."
    - label: "Overwrite and start new"
      description: "Delete existing session, start from scratch."
  multiSelect: false
```

---

## Agent Failure Handling

If an agent subprocess returns a failure or blocker:
1. Show the failure details to the user
2. Ask: "Retry / Save for later?" (user can type changes via "Other")
3. Do NOT silently proceed to the next stage

---

## Context Efficiency Table

Each subprocess starts genuinely clean. No theater.

| Transition | Method | Context Loaded | Size |
|-----------|--------|----------------|------|
| Stage 1 → 2 | New Agent subprocess | spec artifacts + related files | ~5-15KB |
| Stage 2 → 3 | New Agent subprocess | changed files (git diff) | ~20-50KB |
| Stage 3 → 4 | New Agent subprocess | methodology + spec context | ~5KB |
| Stage 4 → Commit | Direct (no subprocess) | Nothing | 0KB |

---

## MCP Tool-First Pattern

When MCP (Model Context Protocol) servers are available, Temper uses their tools to produce **proven** findings instead of heuristic grep-based analysis. This is progressive enhancement: everything works exactly as before when no MCP servers are installed.

### tools.mode Behavior

Configured in `.claude/temper.config` under `tools.mode`:

| Mode | Behavior |
|------|----------|
| `auto` (default) | Try MCP tool first. If unavailable, fall back to grep-based heuristic analysis. |
| `heuristic-only` | Never call MCP tools. Always use grep-based analysis. Forces `[HEURISTIC]` labels. |
| `require` | Fail if MCP tools are unavailable. Do NOT proceed with heuristic fallback. |

### Evidence Labels

Every finding in review, check, plan, and fix carries one of:

| Label | Meaning | When Applied |
|-------|---------|--------------|
| `[PROVEN]` | Output from a tool (MCP, test runner, semgrep). Mechanically verified. | MCP tool returned results, test was executed, SAST scan found issue. |
| `[HEURISTIC]` | Claude's analysis via grep/reading code. Best-effort, not mechanically verified. | MCP unavailable, grep-based detection, pattern-matching analysis. |
| `[SEMANTIC]` | Claude's interpretation or judgment. Inherently subjective. | Asserting "this assertion covers the Then clause", problem-solution alignment check. |

Labels are shown when `tools.label-findings: true` in temper.config (default: true).

### MCP Tool Registry

| MCP Tool | Server | Replaces |
|----------|--------|----------|
| `get_impact_radius_tool` | code-review-graph | grep-based blast radius (plan.md Phase 4 steps 2-3) |
| `query_graph_tool` | code-review-graph | grep-based call chain tracing (fix.md Step 2) and scenario-to-test matching (check.md Level 4.5) |
| `get_affected_flows_tool` | code-review-graph | grep-based consumer detection |
| `security_check` | semgrep | OWASP pattern-matching (review.md Step 2, check.md Level 7) |
| `semgrep_scan_with_custom_rule` | semgrep | Manual security pack rule enforcement |

### Recommended MCP Servers

| Server | Install | Purpose |
|--------|---------|---------|
| code-review-graph | `pip install code-review-graph` + configure MCP | AST-level dependency graphs, call chains, blast radius |
| semgrep | `brew install semgrep` + `claude mcp add semgrep -- semgrep --mcp` | Static analysis security scanning (SAST) |

Availability of these servers is optional. When present, findings are labeled `[PROVEN]`. When absent, the same analysis runs via grep and is labeled `[HEURISTIC]`.

---

## Context Accumulation Patterns

Each stage produces structured artifacts that accumulate in `.temper/specs/{feature}/`. Downstream stages read upstream context to make better decisions.

### Context File Schemas

**build-context.json** (written by Build stage):

```json
{
  "version": 1,
  "stage": "build",
  "timestamp": "{ISO timestamp}",
  "files_created": ["path/to/file"],
  "files_modified": ["path/to/file"],
  "test_results": {
    "total": 5,
    "passed": 5,
    "failed": 0
  },
  "deviations": {
    "unplanned_files": [],
    "skipped_tasks": [],
    "approach_changes": []
  },
  "scenarios_covered": ["scenario name"],
  "tasks_completed": 5,
  "tasks_total": 5
}
```

**review-context.json** (written by Review stage):

```json
{
  "version": 1,
  "stage": "review",
  "timestamp": "{ISO timestamp}",
  "findings_summary": {
    "critical": 0,
    "high": 0,
    "medium": 0,
    "low": 0,
    "auto_fixed": 0
  },
  "intent_verdict": "satisfied | partial | not_met",
  "security_hot_paths": [],
  "contract_changes": [],
  "scenario_coverage": {
    "total": 5,
    "strong": 3,
    "weak": 1,
    "trivial": 0,
    "uncovered": 1
  }
}
```

**check-context.json** (written by Check stage):

```json
{
  "version": 1,
  "stage": "check",
  "timestamp": "{ISO timestamp}",
  "validation_results": {
    "compile": "pass",
    "tests": "pass",
    "coverage_pct": 85,
    "lint": "pass",
    "security": "pass"
  },
  "scenario_verification": {
    "total": 5,
    "passed": 4,
    "failed": 0,
    "missing": 1
  },
  "test_failures": [
    {
      "test_name": "string",
      "error_message": "string",
      "file": "string",
      "line": 0,
      "scenario": "string"
    }
  ]
}
```

**eval-context.json** (written by Eval stage):

```json
{
  "version": 1,
  "stage": "eval",
  "timestamp": "{ISO timestamp}",
  "feature": "{feature-slug}",
  "mode": "output|trajectory",
  "judge_model": "{model id or 'deterministic-fallback'}",
  "aggregate": 0.81,
  "pass_threshold": 0.75,
  "passed": true,
  "scores": {
    "task_success": { "score": 0.9, "justification": "..." },
    "hallucination": { "score": 0.1, "justification": "..." }
  },
  "unscored": ["tool_use_quality"],
  "block_on_failed": ["task_success"],
  "results_file": "{spec_path}/evals/results/results-{ts}.json",
  "feedback_target": "build"
}
```

`block_on_failed` lists any `eval.block-on` dimensions whose score fell below `pass_threshold`
(empty when none). When non-empty AND `feedback.enabled`, the Eval gate offers the Eval→Build
Re-run loop; `feedback_target` is then `build`. Eval degrades gracefully: missing evalset or
disabled config means this file is never written and the stage is skipped.

**learning.json** (written by Review Step 8.5, read by Status and Review Step 4):

```json
{
  "version": 1,
  "last_updated": "{ISO timestamp}",
  "detected_patterns": [],
  "suppressed_patterns": [],
  "suggestion_queue": [],
  "learning_curve": {
    "reviews_sampled": [],
    "issues_per_review": [],
    "trend": "improving | stable | degrading | insufficient_data",
    "improvement_pct": 0
  }
}
```

Full schema: `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/learning.md`

### Context Loading Rules

| Stage | Reads | Writes |
|-------|-------|--------|
| Plan | Nothing (first stage) | intent.md, tasks.md, plan.md |
| Design | intent.md, plan.md | design.md |
| Build | tasks.md, intent.md, review-context.json (on feedback re-entry) | build-context.json |
| Review | intent.md, changed files (git diff), build-context.json, learning.json (noise filter) | review-context.json, learning.json (pattern detection) |
| Check | intent.md, review-context.json | check-context.json |
| Eval | evalset.json, build-state.json, observability.json, eval.md | eval-context.json, results/results-{ts}.json |
| Status | metrics.json, review-memory.json, learning.json | — |

### Context Versioning

- Each context file has a `version` field (integer)
- Downstream stages must handle older versions gracefully (ignore unknown fields)
- Version is only bumped on schema-breaking changes

### Context Cleanup

On commit (after Check passes):
- Delete `*-context.json` files from spec directory
- Keep: intent.md, tasks.md, plan.md (permanent record)
- Keep: design.md (if created, permanent record)

---

## Feedback Loop Patterns

Feedback loops allow stages to send work back to upstream stages with failure context. This transforms the pipeline from linear to cyclic.

### Feedback Registry

File: `.temper/feedback-loops.json`

```json
{
  "version": 1,
  "active_loops": [
    {
      "id": "loop-1",
      "from_stage": "review",
      "to_stage": "build",
      "reason": "auto-fixable issues found",
      "iteration": 1,
      "max_iterations": 2,
      "failure_context": {
        "issues": ["file:line — description"],
        "auto_fixable_count": 2
      },
      "started": "{ISO timestamp}"
    }
  ],
  "history": []
}
```

### Loop Types

**Review → Build (auto-fix loop):**
- Trigger: Review finds auto-fixable HIGH/CRITICAL issues
- User selects "Fix all & continue to Check"
- Fixes applied, re-review runs (1 more pass)
- Circuit breaker: max 2 loops total
- After max loops: pause for human decision

**Check → Build (test failure loop):**
- Trigger: Check finds test failures in newly written code
- Creates targeted fix task with:
  - Test name, error message, file:line
  - Original intent.md scenario that failed
- User selects "Loop back to Build"
- Build agent receives fix task + review-context.json
- Circuit breaker: max 2 loops total

**Eval → Build (block-on dimension loop):**
- Trigger: Eval stage finds an `eval.block-on` dimension below `pass_threshold`
- User selects "Re-run (loop to Build)" at the Eval gate (requires `feedback.enabled`)
- Build agent receives fix task + eval-context.json (failing dimensions + justifications)
- Circuit breaker: max `feedback.max-loops` (default 2) Eval→Build loops

**Build → Plan (revise plan loop):**
- Trigger: Build discovers plan is infeasible
- User selects "Revise plan" at build gate
- Plan agent receives revision context (what was infeasible, why)
- Plan is revised, user approves new plan
- No circuit breaker — human-driven, not automated

### Circuit Breaker Rules

1. Max 2 automated loops per feedback type per pipeline run
2. After max loops reached: show remaining issues, offer "Save for later" or "Manual fix"
3. Same issue found in 2 consecutive loops → stop immediately (fix isn't working)
4. Loop counter is stored in feedback-loops.json
5. Counter resets when pipeline starts fresh (new /temper invocation)

### Loop Context Transfer

When looping back, the downstream stage passes structured context to the upstream stage:

| Loop | Context Passed |
|------|---------------|
| Review → Build | review-context.json with fix list |
| Check → Build | check-context.json with test failures |
| Build → Plan | build-context.json with infeasibility reasons |

The receiving stage reads this context at startup (Step 1 of its methodology).
