---
description: "Show quality metrics dashboard"
---

# Status: Quality Metrics Dashboard

**Goal:** Display accumulated quality metrics, trends, and learning loop suggestions.

## Execution

### Step 0: Initialize (if `.temper/` is missing)

Create `.temper/specs/`, `.temper/reviews/`, `metrics.json` (schema below), and
`review-memory.json: { "patterns": {} }`. Report "Initialized .temper/ directory for
quality tracking."

### Step 1: Read Metrics + Build Hotspots

Read `metrics.json`, `review-memory.json`, `.temper/specs/` for active specs. Scan
`.temper/reviews/*.md` to build a file-frequency map: `issues_per_file = findings at
file / reviews touching file`; top 5 by density = hotspots. No `metrics.json` → "No
metrics yet. Run /temper:review or /temper:check to start tracking."

### Step 1.5: External Tool Availability

- **code-review-graph / semgrep:** probe with a trivial tool call (e.g.
  `get_impact_radius_tool` on the current file, or `security_check`); tool responds →
  available, errors/missing → unavailable.
- **ocr:** `command -v ocr` → not-installed if missing; else `ocr --version` then probe
  `ocr review --preview --from HEAD~1 --to HEAD` → ready, or not-configured if the probe
  fails (LLM not set up).
- Read `tools.mode` (`auto`/`heuristic-only`/`require`) and report accordingly.
- Evidence ratio: `proven / (proven + heuristic + semantic) * 100` from
  `metrics.json.evidence`.

### Step 1.7: Learning State

Read `.temper/learning.json` if present (absent → "not initialized", graceful). Extract
`detected_patterns` counts by status, `suppressed_patterns` count,
`suggestion_queue` pending items, `learning_curve` (trend, improvement_pct). Malformed →
warn and skip the learning section, don't crash.

### Step 2: Display Dashboard

```
+-------------------------------------------------------+
| Temper Status — {project}           Period: 30 days   |
|                                                        |
| REVIEWS: {total} | issues {N} | auto-fixed {N} ({%})   |
|   acceptance rate {%}                                  |
| QUALITY TREND: coverage {old}%->{new}% {up/down}        |
|   avg issues/review {old}->{new}   blocked commits {N}  |
| HOTSPOTS: 1. {file} — {N} issues / {R} reviews  ...     |
| TOP PATTERNS: 1. {pattern} ({count}x) {auto-rule?} ...  |
| REVIEW MEMORY: suppressed {N}   promoted to rules {N}   |
| ACTIVE SPECS: {spec} ({status}, {X}/{Y} tasks)          |
| VERIFICATION: live scenarios {enabled/prompt/disabled}  |
|   last run {date} ({X}/{Y})   mutations {N} caught/missed |
| EXTERNAL TOOLS: code-review-graph/semgrep/ocr status,    |
|   ocr accept rate (if any), evidence ratio {X}% PROVEN   |
| ADAPTIVE LEARNING: {N} patterns ({M} active, {D} degraded)|
|   suppressed {N}, promoted {N}, pending {N}, curve {trend}|
|   (absent -> "Adaptive learning: not yet initialized")   |
| GATE LEDGER: Plan/Build/Review/Check {PASS/FAIL}          |
|   overrides {N}, evidence {N} PROVEN/{N} HEURISTIC/{N} SEMANTIC |
|   (gates.json absent -> "No gate data yet — run /temper") |
| AUTONOMOUS RUNS: mode, park point + reason, loop budget   |
|   (no autonomy-report.md -> print nothing for this panel) |
+-------------------------------------------------------+
```

Populate every panel from real files, never a hardcoded example; empty/absent inputs
degrade to the notices above, not an error.

### Step 2.5: Gate Ledger Panel (v7 — replaces the v6.x Economics panel)

Render from `.temper/gates.json`, `.temper/overrides.json`, `.temper/evidence/*.json` —
the same ledger `temper gate` computes verdicts from. Deliberately not the v6.x cost/
latency/token dashboard (those were unbacked estimates): per-stage verdict + requirement
detail (`temper report`), override count + reason per stage, and the PROVEN/HEURISTIC/
SEMANTIC evidence-label mix as a rough proxy for how much of the run was mechanically
verified. No `gates.json` → "No gate data yet. Run /temper to populate it." — never error.

### Step 2.6: Autonomous Runs Panel (purely additive)

From `.temper/autonomy-report.md` (if present) + `.temper/feedback-loops.json`: run mode
(from `build-state.json` if a run is active), park point + reason (parsed from the
report), loop budget used (sum `iteration` across `active_loops[]` + `history[]` vs.
`autonomy.budget.max-total-loops`). No report → print nothing for this panel.

### Step 3: Learning Loop + Adaptive Suggestion Prompts

If a pattern's shown-count >= 3 with no auto-rule yet: `AskUserQuestion` — "Yes, add as
BLOCK rule" (active pack's Mandatory Rules) / "Yes, add as WARN rule" (Quality Rules) /
"No, keep as advisory" (mark `no-promote` in review memory).

If `learning.json.suggestion_queue` has a `pending` item: `AskUserQuestion` — "Yes,
promote to rule" (move the template from `.temper/learning/suggestions/{id}.md` into
`.claude/packs/adaptive-learning/rules.md`, mark `accepted` + pattern `promoted`) / "No,
dismiss" (mark `rejected`) / "Skip for now" (leave pending).

### Metrics Schema

```json
{ "version": 1, "project": "", "reviews": { "total": 0,
  "issues_by_severity": { "critical": 0, "high": 0, "medium": 0, "low": 0 },
  "issues_by_category": { "security": 0, "performance": 0, "quality": 0, "logic": 0, "architecture": 0, "test_gap": 0 },
  "auto_fixed": 0, "suppressed": 0, "acceptance_rate": 0.0 },
  "coverage_history": [], "test_count_history": [], "patterns": {},
  "plans": { "created": 0, "completed": 0, "in_progress": 0, "abandoned": 0 },
  "fixes": { "total": 0, "rca_used": 0 },
  "baseline": { "date": null, "coverage": null, "violations": null },
  "scenarios": { "total_verified": 0, "total_passed": 0, "total_failed": 0, "total_missing": 0,
    "mutations_caught": 0, "mutations_missed": 0 },
  "evidence": { "proven": 0, "heuristic": 0, "semantic": 0 } }
```

### Formulas

| Metric | Formula |
|---|---|
| Acceptance rate | `accepted_findings / total_shown_findings` |
| Auto-fix rate | `auto_fixed / total_issues` |
| Coverage trend | `coverage_history[-1] - coverage_history[-7]` |
| Issues/review | `sum(issues_found) / reviews.total` |
| Debt ratio | `(violations_current - violations_baseline) / violations_baseline` |
| Pattern frequency | `patterns[key].total_shown / reviews.total` |
| Standards compliance | `(files_total - files_with_violations) / files_total * 100` |

Show trend arrows (📉/📈/➡️) next to coverage and issues/review — the user reads the
dashboard, there's no separate alerting system.

### Learning Loop Lifecycle

Pattern detected in a review → shown → user's response tracked as accepted or dismissed
in `patterns[key]`. Accepted >= 3 (at >= 70% acceptance rate, no existing auto-rule) →
prompt for promotion at `/temper:status` (user picks BLOCK/WARN/no-promote). Dismissed
>= 5 → auto-suppress in `/temper:review`, moved to `suppressed_patterns[]`.
