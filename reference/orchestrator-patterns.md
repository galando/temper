---
description: "Shared patterns for orchestrator commands (temper.md, fix.md)"
---

# Orchestrator Shared Patterns

**Used by:** `commands/temper.md`, `commands/fix.md`

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

Full methodology: Read $CLAUDE_PLUGIN_ROOT/reference/{stage}.md

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

**print-output contract:** every stage summary box (the formatted `PLAN`/`BUILD`/`REVIEW`/
`CHECK`/`EVAL` box the stage Agent returns) **prints to the main terminal in BOTH modes** —
interactive AND autonomous. The orchestrator emits the summary box before the gate decision,
so an unattended overnight run still leaves a visible, scroll-back-readable record of each
stage's result on the main terminal. Autonomy changes WHICH gate decision is taken
(AskUserQuestion vs auto-resolve), never WHETHER the summary is printed.

**Cacheable prefix delta (v5.9.0):** when `tokens.cache.enabled` is true, the "Full
methodology: Read …" line and the always-on reference reads (orchestrator-patterns,
pack-manifest, stack-pack, config) form a **cacheable context block** loaded FIRST, ahead
of the per-launch volatile delta. The cacheable block is ordered identically on every
launch so the prefix the platform caches is byte-stable across stages and across feedback
re-entries. When `tokens.cache.enabled` is false, no ordering rule is applied — reads
proceed exactly as in v5.8.0. See "Cacheable vs. Volatile Context" below.

**Model routing delta (v5.6.0):** after resolving the bracketed deltas, decide the Agent
tool `model` param per the Model Routing Resolution block below. The launch template gains
an optional `model: <tier-resolved>` param driven by `models.routing.{stage}` in
`temper.config`. When `models.enabled` is false/absent, emit NO `model` param (v5.5.0
byte-identical behavior — session model inherited).

### Cacheable vs. Volatile Context (v5.9.0)

Every read a stage Agent makes is one of two classes. The ordering rule is:
**cacheable reads first (stable prefix), volatile reads last (per-launch delta).**
Keeping the prefix byte-identical across launches maximizes the chance the platform
returns a cache hit; the orchestrator cannot force a cache, it can only structure reads
so the prefix is stable and record what the platform reports (see Observability v3
`tokens.cached_input`).

| Class       | Reads (byte-stable across launches)                         |
|-------------|-------------------------------------------------------------|
| **Cacheable** | methodology ref (`{stage}.md`), `orchestrator-patterns.md`, pack-manifest, stack-pack, `temper.config` |
| **Volatile**  | `build-state.json`, spec artifacts (`tasks.md`/`intent.md`/`plan.md`), `git diff`, `*-context.json`, feedback-loop state |

**Ordering rule:** on every stage launch AND every feedback re-entry, read the cacheable
block in the fixed order above, THEN read the volatile delta. When `tokens.cache.enabled`
is false, this rule is suspended — reads proceed in v5.8.0 order.

### Pipeline Depth (v5.9.0)

When `tokens.adaptive-depth.enabled` is true, the pipeline depth is selected by the plan
stage's existing complexity classification (trivial|simple|medium|complex — Phase 3 of
`reference/plan.md` already emits this). The `floor` clamp raises the effective tier UP:
`floor: simple` permits the trivial fast-path; `floor: medium` kills trivial; `floor:
complex` forces the full pipeline always. A floor is a clamp, NOT a toggle.

| Complexity (after floor clamp) | Stages run                                       | Design? | Eval? | Gates | Artifacts required                                   |
|--------------------------------|--------------------------------------------------|---------|-------|-------|------------------------------------------------------|
| **trivial**                    | 1 combined plan+build Agent → review             | no      | no    | 1 (final) | `intent.md` + `tasks.md` only (spine methodology) |
| **simple**                     | plan → build → review → check                    | no      | no    | 2     | `intent.md` + `tasks.md`                             |
| **medium**                     | plan → design? → build → review → check → eval   | opt     | yes   | 3     | `intent.md` + `tasks.md` + `plan.md`                 |
| **complex**                    | plan → design → build → review → check → eval    | yes     | yes   | 4     | full set: `spec.md` + `intent.md` + `plan.md` + `tasks.md` + mermaid + blast radius |

**Artifact-requirements scale:** the trivial tier runs a single combined plan+build Agent
on spine methodology only (no `design.md`, no mermaid, no blast radius, no eval). The
medium tier adds `plan.md` but may still skip design. The complex tier is the full v5.8.0
pipeline. The standalone-`/temper:plan` complexity-tiered rules in `reference/plan.md`
(lines 522+) are UNCHANGED — this table only governs the unified-`/temper` override.

**Graceful degradation:** when `tokens.adaptive-depth.enabled` is false, every complexity
runs the **complex** row — the full v5.8.0 pipeline (byte-identical). The plan gate shows
the chosen depth tier and an "Escalate to full pipeline" option so a human can override a
reduced tier upward.

---

## Model Routing Resolution (v5.6.0)

Resolve the stage tier BEFORE launching the Agent. Order is first-match-wins:

```
1. If models.enabled is false OR models block absent:
     => emit NO model param (inherit session model; v5.5.0 behavior)
2. Else if models.respect-user-override is true AND user set a model for this session/stage:
     => keep user's model; record source: "user-override" in observability.json
3. Else:
     => tier = models.routing.{stage}  (tier-frontier | tier-standard | tier-fast)
     => strip the `tier-` prefix and look up models.tiers.{tier} to get the Agent model id
        (defaults: tier-frontier -> opus, tier-standard -> sonnet, tier-fast -> haiku;
         these defaults are exactly the values in the shipped models.tiers block, so
         editing models.tiers.{tier} in temper.config changes what runs — routing honors it)
     => emit model: <mapped> on the Agent launch
```

**Review escalation (Deliverable 1.2):** the Review stage runs its broad style/lint sweep
on `tier-fast`. Findings tagged `architecture-finding` or `correctness-risk` (per
`models.escalate-on`) are re-judged on `tier-frontier`, reusing the existing
confidence-scoring path in `reference/review.md`. The escalation is recorded in
observability.json (per-stage `retries` bump or a sub-stage entry with its own tier).

---

## Observability.json v3 Schema (v5.9.0)

_(Supersedes the Observability.json v2 Schema from v5.6.0. v3 is a strict superset: the
v2 stage fields — `model_tier`, `cost_usd`, `eval_score`, `retries`, the `source`
provenance rule — are all preserved; v3 only adds `tokens.cached_input` and `loops[]`.
A v2 doc — `"version": 2` — remains a valid v3 read; v2 readers ignore the new keys.
For the v2 schema reference, see this section's history in git at the v5.6.0 tag.)_

The `.temper/observability.json` schema is versioned. v3 (Phase 3) is **additive** over
v2: it adds `tokens.cached_input` per stage (D1) and a `loops[]` array with per-loop
`mode` + `cost` (D3). v2 readers ignore the new keys gracefully (the G-5 source rule is
preserved and extended to every new numeric). v2 adds `model_tier`, `cost_usd`,
`eval_score`, `retries`, and the `source` provenance rule on EVERY numeric leaf. v1 readers
ignore unknown keys gracefully.

**Source provenance (extends G-5, v5.3.0):** every numeric value MUST carry a sibling
`source` field (`measured` | `estimated` | `user-override` | `pricing`). Do not emit a
numeric without its `source`. Consumers (e.g. `/temper:status`) surface provenance so the
dashboard never lies about how a number was obtained. This rule is extended to the new
`cached_input.value` and each `loops[].cost.value`.

```json
{
  "version": 3,
  "feature": "{slug}",
  "schema_source": "reference/orchestrator-patterns.md#observabilityjson-v3-schema",
  "stages": [
    {
      "stage": "plan|design|build|review|check|eval",
      "model_tier": "tier-frontier|tier-standard|tier-fast",
      "model_source": "routing|user-override|inherited",
      "tokens": {
        "input":  0,  "input_source":  "measured|estimated",
        "output": 0,  "output_source": "measured|estimated",
        "cached_input": { "value": 0, "source": "measured|estimated" }
      },
      "latency_ms":      { "value": 0, "source": "measured|estimated" },
      "tool_calls":      { "value": 0, "source": "measured|estimated" },
      "cost_usd":        { "value": 0.0, "source": "pricing" },
      "retries":         { "value": 0, "source": "measured" },
      "eval_score":      { "value": null, "source": "measured|estimated" },
      "ts_start": "{ISO8601}",
      "ts_end":   "{ISO8601}"
    }
  ],
  "loops": [
    {
      "loop_id": "loop-1",
      "from_stage": "review|check|eval",
      "to_stage": "build",
      "mode": "inline|fix-mode|full",
      "cost":     { "value": 0, "source": "measured|estimated" },
      "iteration": 1,
      "ts": "{ISO8601}"
    }
  ],
  "totals": {
    "tokens":   { "value": 0,   "source": "measured|estimated" },
    "cost_usd": { "value": 0.0, "source": "pricing" },
    "latency_ms": { "value": 0, "source": "measured|estimated" }
  }
}
```

**Field semantics:**
- `tokens`: prefer `measured` from harness-reported usage; fall back to `estimated` and
  flag `source` accordingly. NEVER present an estimate as measured.
- `tokens.cached_input` (v3, D1): the count of input tokens the platform reported as
  served from cache for this stage. `value > 0` with `source: "measured"` when the harness
  exposes cache-usage; `source: "estimated"` (and a flag) when only inferred. Emitted ONLY
  when `tokens.cache.enabled` is true; absent (not zero) when cache is off (v5.8.0).
- `latency_ms`, `tool_calls`: `measured` where the harness exposes them (wall-clock and
  tool-invocation counts are observable); `estimated` if only inferred.
- `cost_usd`: computed from `pricing.md[tier]` (advisory price table); `source: "pricing"`
  because the cost is derived from an external price table, not measured from a bill. When
  `cached_input > 0` is reported, `cost_usd` MAY reflect cache savings (see pricing.md cache
  multipliers) — the source stays `"pricing"`.
- `retries`: stage re-launches (feedback loops or escalations). `source: "measured"`.
- `eval_score`: pulled from `eval-context.json` for eval stage; `null` otherwise.
  `source: "measured"` when from the LM-judge, `estimated` if inferred.
- `model_source`: `routing` (tier from `models.routing`), `user-override` (respect-user-
  override kept the user's model), or `inherited` (models disabled — session model used).
- `loops[]` (v3, D3): one entry per feedback-loop iteration, recording `mode`
  (`inline` | `fix-mode` | `full` per the Loop Cost Tiers decision rule) and the per-loop
  `cost` (unit token cost of this loop iteration, with a `source` sibling per G-5). Absent
  (empty array or key omitted) when no loops fired — v2 readers ignore it.

**Pricing computation:** `cost_usd = (in_tokens/1e6)*in_price + (out_tokens/1e6)*out_price`
where `in_price`/`out_price` come from `reference/pricing.md` keyed by tier.
Round `cost_usd` to 6 decimal places when writing to observability.json. Advisory; update
pricing.md as published prices change.

---

## metrics.json Drift Baseline Schema (v5.6.0)

Extends the existing `.temper/metrics.json` (additive — existing keys unchanged).
Maintains a rolling baseline per stage and surfaces deviations as SUGGEST-level drift flags.

```json
{
  "stage_baseline": {
    "plan":  { "tool_calls": [N...], "retries": [N...], "latency_ms": [N...], "eval_score": [N...] },
    "build": { "tool_calls": [N...], "retries": [N...], "latency_ms": [N...], "eval_score": [N...] }
  },
  "drift_flags": [
    {
      "stage": "build",
      "metric": "tool_calls",
      "value": 42,
      "baseline_mean": 12.5,
      "baseline_stddev": 3.1,
      "std_devs": 5.2,
      "threshold": 2,
      "severity": "SUGGEST",
      "direction": "high",
      "ts": "{ISO8601}",
      "source": "measured"
    }
  ]
}
```

**Drift rule:** after each stage, append its metrics to `stage_baseline[stage][metric]`
(rolling window, last K runs). Compute rolling mean + stddev. If
`abs(value - mean) / stddev > drift-threshold` (from `temper.config models.drift-threshold`,
default 2), append a `drift_flags` entry at severity `SUGGEST`. Drift flags NEVER
auto-block a stage gate — they are surfaced in `/temper:status` for human review.

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
    "task_success": { "score": 0.9, "category": "artifact", "justification": "..." },
    "hallucination": { "score": 0.1, "category": "artifact", "justification": "..." }
  },
  "unscored": ["tool_use_quality"],
  "aggregate_basis": "scored|full",
  "scored_weight": 0.85,
  "recommended_actions": {
    "task_success": "Re-run (code defect)",
    "trajectory": "accept (process noise)"
  },
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

Full schema: `$CLAUDE_PLUGIN_ROOT/reference/learning.md`

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

### Cache-Stable Re-Entry (v5.9.0)

A Review→Build, Check→Build, or Eval→Build re-launch is a *re-entry*: the same stage Agent
runs again on the same methodology. When `tokens.cache.enabled` is true, the re-launch
**MUST read the same methodology file in the same order** as the first launch so the
cached prefix hits. Concretely: re-entries load the cacheable block (methodology +
orchestrator-patterns + pack-manifest + stack-pack + config) in the fixed Cacheable vs.
Volatile order, then the *volatile* delta changes (the new `*-context.json`, the new
`git diff`). When `tokens.cache.enabled` is false, re-entries read as in v5.8.0.

### Loop Cost Tiers (v5.9.0)

Every feedback loop (Review→Build, Check→Build, Eval→Build) is resolved by a strict
cost-ordering decision rule — **cheapest tier that satisfies the loop wins.** The tier
chosen is recorded as `mode` on the loop's observability entry (see Observability v3).
The circuit breaker above bounds the *count* of loops; this bounds the *unit cost*.

| Tier   | When                                                            | What runs                                                       |
|--------|-----------------------------------------------------------------|-----------------------------------------------------------------|
| inline | all findings auto-fixable AND `files_touched <= inline-threshold` | fixes applied directly in-context; **no subprocess, no methodology re-read** |
| fix-mode | NOT inline AND `tokens.loops.fix-mode: true`                  | minimal-context Build Agent: fix list + changed files + a fix-mode preamble (replaces full `build.md`) |
| full   | NOT inline AND (`fix-mode: false` OR `inline-threshold: 0`)    | full Build Agent re-launch (reads full `build.md` + tasks + intent) — v5.8.0 loop behavior |

**Decision rule (pseudocode):**

```
def loop_tier(findings, files_touched, cfg=tokens.loops):
    if all(f.auto_fixable for f in findings) \
       and files_touched <= cfg.inline_threshold:
        return "inline"            # cheapest: no subprocess
    if cfg.fix_mode:
        return "fix-mode"          # medium: lean subprocess, fix-mode preamble
    return "full"                  # full re-launch (v5.8.0)
```

**Graceful degradation:** with `fix-mode: false` and `inline-threshold: 0`, every loop
resolves to `full` — byte-identical to v5.8.0 loop behavior. Each tier is recorded in
observability.json `loops[]` with `mode` + token `cost` (per-loop unit cost), so
`/temper:status` can surface dollars saved by cheaper tiers.

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

---

## Autonomous Continuation

**This is the canonical definition of Autonomous Continuation.** `temper.md` only references
it (single-read contract) — it does not redeclare the policy. `/temper:fix` will inherit it
with a thin hook when autonomy is extended to it (out of scope here).

**Design stance:** The plan stage is always human-gated. `/temper` always runs Plan first
and stops at the plan gate. Autonomy is *armed there*, never at invocation. Autonomy governs
the post-plan stages (`design? → build → review → check → eval`) only, then **parks before
commit** and on any decision a human should own. It runs unattended until a budget ceiling,
a blast-radius trip, an unfixable BLOCK, or the commit is reached — then it parks with a
report and degrades into the existing save-state/resume path.

> **Guarantees.** Autonomy never pushes, never merges, never re-plans unattended, and always
> lets the human review the plan first.

### Graceful-degradation contract (the most important property)

With the `autonomy` block absent OR `autonomy.enabled: false`, the plan gate offers only the
existing stage-by-stage continuation ("Continue to Build (Recommended)") and **no gate ever
auto-resolves** and **no annotation is shown** — byte-identical to v5.9.0. Disabling autonomy
never affects adaptive-depth, cache, loops, or model routing. Autonomy does **not** read
`adaptive-depth.floor` and is not clamped by complexity tier.

### §2 — Plan-gate arming

There is **no invocation-time mode**. The user runs `/temper "..."` exactly as today. Plan
runs, the plan gate appears, the human reviews/edits/approves the plan. The plan gate then
offers a **continuation choice** (replacing the single "Continue to Build"):

- **"Stage by stage (Recommended)"** — stop at each gate (current behavior; v5.9.0).
- **"Autonomous — run the rest unattended"** — auto-resolve design→build→review→check→eval
  per the policy table below; park before commit and on anything needing a human.

`default-choice` config decides which continuation option is pre-highlighted. The existing
plan-gate options (Grill Me, Teach Me, walkthrough, Escalate to full pipeline, Save for
later, Other) are unchanged. Arming sets `run_mode` in `build-state.json` (`interactive` |
`autonomous`). When autonomy is off/absent, the plan gate shows "Continue to Build
(Recommended)" verbatim and arming never happens.

**Interactive gates are annotated, not duplicated:** when `autonomy.enabled` is true AND the
human chooses "Stage by stage", each subsequent gate additionally shows — as an *annotation
above the usual options* — the decision autonomy *would* take, its confidence, and whether
the park policy would have continued or stopped. The human still decides every gate. When
`autonomy.enabled` is false, no annotation appears (byte-identity).

### §3 — Auto-resolve policy table (post-plan only)

For each post-plan gate, autonomy replaces the `AskUserQuestion` call with a decision that
selects the gate's existing **Recommended** option **unless a park condition fires**.
Feedback loops, circuit breakers, loop cost tiers, observability, and save-state are reused
verbatim. In interactive mode the same decision is computed and shown as a gate annotation,
but the human still chooses.

| Gate | Auto-action (no park) | Park condition (halt + report) |
|------|----------------------|--------------------------------|
| **Plan** | — | **Always human** (the arming point; never auto-resolved) |
| **Design** | "Continue to Build" | Design surfaces an unresolved trade-off / open question (subject to the confidence rule, §4) |
| **Build** | "Continue to Review" | Build hits infeasibility → returns to the **plan gate** (human); autonomy never loops Build→Plan unattended |
| **Review** | "Fix all & continue to Check", running the Review→Build auto-fix loop bounded by `feedback.max-loops` — but applying only `auto-fix-severity` levels (§8) | A `critical`/BLOCK-class finding remains after max loops, or a non-auto-fixable critical exists |
| **Check** | On test failures, run Check→Build loop bounded by `feedback.max-loops`; else advance | Tests still failing after max loops, or same failure twice (existing circuit-breaker rule 3) |
| **Eval** | On `eval.block-on` failure, run Eval→Build loop bounded by `feedback.max-loops`; else advance | A `block-on` dimension still below `pass-threshold` after max loops |
| **Commit** | **Never auto-commit** (default) | Always parks with a SHIP-pending report (unless `stop-before-commit: false` is explicitly set) |

A tripped circuit breaker becomes a **park**, never an infinite loop. The global budget (§5)
bounds the run regardless of per-type loop counts. **No new mechanism** is introduced: the
park is the existing "Save for later" path plus one markdown report (§10).

### §4 — Self-judgment safeguards (the core risk)

Most park conditions are *LLM judgments*, not deterministic checks — and the same model that
might misbuild is the one deciding whether to stop. Three structural mitigations, none of
which adds a new mechanism:

1. **Plan is always human-reviewed (§2).** The single most dangerous autonomous judgment —
   "is this the right thing to build?" — is removed from autonomy entirely.
2. **Conservative bias (`conservative-bias: true`, default):** when a proceed/park signal is
   *uncertain*, park. Default-to-stop, not default-to-proceed.
3. **Confidence threshold:** a "continue" decision whose confidence falls below the
   **existing** `review.confidence-threshold` (default 0.7) is downgraded to a park. One
   threshold, one meaning — **no new config key**. Confidence reuses the existing review
   threshold; it is never given its own autonomy-scoped key.

### §5 — Run budget (hard ceiling)

Per-type loop limits do not bound a whole overnight run (Review + Check + Eval loops
compound). A global budget forces a park when exceeded:

```yaml
budget:
  max-total-loops: 4        # across ALL feedback types in one run
  max-stages: 12            # stage executions incl. loop re-entries
  max-wall-clock-min: 60
```

Park verdict `BUDGET-EXCEEDED`, preserving whatever stages completed. The loop count per
type still defers to `feedback.max-loops`; the global cap is `budget.max-total-loops`.
**The loop limit never gets its own autonomy-scoped key.**

### §6 — Operational safety

Autonomy edits files unattended for a long time, so tree hygiene is mandatory:

- **Clean-start (`require-clean-tree: true`):** refuse to begin autonomous continuation if
  the working tree is dirty — or auto-stash and note it in the report. Never build on top of
  unknown local changes.
- **Recoverable checkpoints (`checkpoint: wip-commit | none`):** by default, commit a `wip:`
  checkpoint after each green stage so a crash or container reclaim mid-run loses at most one
  stage, and the human can see incremental diffs.
- **Single-run lock (`lock: true`):** a `.temper/autonomy.lock` with a run-id prevents a
  concurrent `/temper` from corrupting the singleton `build-state.json`.
- **One-command abandon:** with `stop-before-commit: true` (default) the branch is never
  committed, so `git branch -D` discards the night. Documented in the report's footer; if
  `stop-before-commit: false`, the report prints the exact `git reset` to undo.

### §7 — Unattended command execution (security)

Build/Check run Bash (test runners, linters) with **no human approval** during an autonomous
run — a real surface (e.g. a malicious dependency's test script). The fix is to **reuse the
harness's existing permission system, not invent an allowlist**:

- Autonomy runs under Claude Code's configured `settings.json` allow/deny permissions. A
  command that isn't already permitted **parks** for human approval instead of running.
- The report records every command executed, so the night is auditable.
- No new mechanism — the platform already gates commands; autonomy just treats a
  denied/unpermitted command as a park signal. **There is no `autonomy.allowlist`.**

**First-run prerequisite (release notes + README):** because autonomy runs build/test
commands without prompting, the user should pre-allow the commands their build/check needs
in `settings.json` *before* the first unattended run — otherwise the run parks on the first
unpermitted command.

### §8 — Conservative fix policy under autonomy

Interactive "Fix all" includes low-severity findings. Applying those across many files
overnight is unreviewed churn. Under autonomy:

- `auto-fix-severity: [critical, high]` (default) — auto-apply only these; lower-severity
  findings are **listed in the report, not applied**.
- Loop budget per feedback type defers to `feedback.max-loops` (single source of truth); the
  global cap is `budget.max-total-loops`. **No autonomy-scoped loop-limit key is introduced.**

### §10 — Park artifact (morning handoff)

**A park is just the existing "Save for later" path plus one markdown file** — not a new
state machine. Two things happen:

1. **State is saved** exactly like "Save for later" — `build-state.json` with the parked
   `stage`/`next_stage` plus `run_mode: autonomous`. Resume is free: `/temper` lands back at
   the parked gate, interactively.
2. **One human-readable report is written** (`autonomy-report.md`, path from
   `autonomy.report`). The few machine-readable fields `/temper:status` needs go into the
   existing `observability.json` (§11) — no separate JSON file.

`autonomy-report.md` schema:

```markdown
# Autonomy Report — {feature slug}

**Verdict:** SHIP-PENDING-COMMIT | PARKED-NEEDS-DECISION | BLOCKED | BUDGET-EXCEEDED
**Parked at:** {stage} gate     **Reason:** {one-line}
**Branch:** feature/{slug}   **Checkpoints:** {N wip commits}   **Finished:** {ISO ts}

## Acceptance checklist (all must hold for SHIP-PENDING-COMMIT)
- [x] all tasks complete ({done}/{total})
- [x] review clean or auto-fixed (severity applied/deferred)
- [x] check pass, coverage {X}% ≥ {Y}%
- [x] all scenarios covered
- [x] eval aggregate {s} ≥ {pass-threshold}

## What ran
| Stage | Result | Auto-decision | Confidence | Loops |
|-------|--------|---------------|-----------|-------|
| {stage} | {result} | {continued|PARKED|fix→continued} | {conf or —} | {N or —} |

## Your next action
{Exact instruction + the file:line context that triggered any park.}

## Deferred (not applied autonomously)
- low-severity findings: {list}
- config suggestions (generated, not applied): {list}

## Audit
- commands executed: {list}
- budget used: {stages}/{max-stages} stages, {loops}/{max-total-loops} loops, {min} min
- abandon this run: `git branch -D feature/{slug}`
```

`SHIP-PENDING-COMMIT` requires the **explicit acceptance checklist above** to all hold —
otherwise the verdict is PARKED/BLOCKED. Verdict mapping: SHIP-PENDING-COMMIT ≈ SHIP,
PARKED-NEEDS-DECISION ≈ NEEDS WORK, BLOCKED ≈ BLOCK.

### §11 — Observability additions (additive over v3, G-5 source rule preserved)

Additions to `observability.json` (all ADDITIVE — v3 readers ignore them gracefully; absent
when autonomy never ran, i.e. byte-identical to v5.9.0):

- `run_mode: "interactive" | "autonomous"` (per run). `run_mode_source: "config|user-choice"`.
- `gate_decisions: []` — `{ stage, decision, auto: bool, confidence: {value, source},
  reason, ts }` per gate evaluated. `confidence.source` per G-5 (`measured` when from the
  LM-judge/confidence path, `estimated` otherwise).
- `park: { stage, reason, verdict, ts }` on park (absent when not parked).
- `budget_used: { stages: {value, source}, loops: {value, source},
  wall_clock_min: {value, source}, tokens: {value, source} }`. Every numeric carries a
  `source` sibling per the G-5 rule.

`/temper:status` gains an **Autonomous runs** panel: last run mode, park point, gates
auto-resolved vs. parked, loop/budget consumption.
