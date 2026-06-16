# Phase 1 — Close the Verification Gap

**Proposed release:** v5.3.0
**Theme:** Move Temper from the *structured AI-assisted* band onto the *agentic engineering*
end of the spectrum by adding the verification half the paper insists on — **evals** — plus
the **deterministic guardrails** the paper calls hooks.
**Source mandate:** _The New SDLC With Vibe Coding (Day 1)_ — *"Without both [tests and
evals], the practice is always vibe coding."* / *"Set the bar at the eval, not the demo."*
**Status:** Planning · **Date:** 2026-06-16

---

## Why this phase first

Temper today has the deterministic side of verification (TDD pack, `/temper:check`,
coverage gate) but **no eval layer at all**. The paper makes evals the single biggest
differentiator between vibe coding and agentic engineering. Until Temper can score
non-deterministic behavior against rubrics and gate on it, its own marketing claim
("agentic engineering harness") is unmet. This phase closes that gap and adds the
deterministic hooks that make guardrails enforceable rather than advisory.

**Deliverables:** (1) `/temper:eval` command + eval skill, (2) eval-coverage gate in
`/temper`, (3) eval-set authored at plan time (the contract), (4) deterministic hooks pack.

---

## Deliverable 1 — `/temper:eval` command + eval skill

### 1.1 Eval-set format
Stored per feature so evals are versioned with the spec (the paper's "context as code").

```
.temper/specs/{feature}/evals/
├── evalset.json        # cases + rubric + thresholds
├── results/            # one results-{timestamp}.json per run
└── README.md           # human notes on what "correct" means here
```

`evalset.json` schema:
```json
{
  "version": 1,
  "feature": "{slug}",
  "rubric": {
    "dimensions": [
      {"id": "task_success",       "weight": 0.35, "scale": "0-1"},
      {"id": "tool_use_quality",   "weight": 0.15, "scale": "0-1"},
      {"id": "trajectory",         "weight": 0.20, "scale": "0-1"},
      {"id": "hallucination",      "weight": 0.15, "scale": "0-1", "invert": true},
      {"id": "response_quality",   "weight": 0.15, "scale": "0-1"}
    ],
    "pass_threshold": 0.75
  },
  "cases": [
    {
      "id": "case-001",
      "input": "…",
      "expected": "…",
      "labels": ["edge-case", "error-path"],
      "must_not": ["fabricated-import", "skipped-validation"]
    }
  ]
}
```
The five rubric dimensions are taken directly from the paper (task success, tool-use
quality, trajectory compliance, hallucination, response quality).

### 1.2 Two evaluation modes (paper: output eval vs trajectory eval)
- **Output eval** — score the final artifact (code/response) against each case's
  `expected` + `must_not`, judged by an LM-judge against the rubric.
- **Trajectory eval** — reconstruct the agent's tool-call sequence from
  `.temper/build-state.json` + stage telemetry (`.temper/observability.json`) and score
  whether it took the right steps, used the right tools, and didn't skip verification.

### 1.3 LM-judge
- A judge prompt that takes (case, output, trajectory, rubric) → per-dimension scores +
  a one-line justification per dimension, written to `results/results-{ts}.json`.
- Judge runs on a **cheaper model tier** (forward reference to Phase 2 model routing) —
  judging is the canonical "route to a smaller model" task from the paper.
- Deterministic fallback: if no LM available, run `expected`/`must_not` string + regex
  checks only and mark dimensions needing a judge as `unscored` (graceful degradation,
  matching Temper's existing default-on/degrade convention).

### 1.4 Command surface
- `/temper:eval` — run the eval set for the active feature, print a score table.
- `/temper:eval --create` — scaffold `evalset.json` from `intent.md` scenarios.
- Standalone (conductor) and subprocess (orchestrator) modes, mirroring how
  `reference/build.md` already documents the two modes.

### 1.5 Files to add
| File | Purpose |
|---|---|
| `.claude/commands/eval.md` | Command entry (thin, defers to reference) |
| `.claude-plugin/reference/eval.md` | Full methodology (loaded on demand) |
| `.claude/skills/eval-judge/SKILL.md` | LM-judge skill (rubric scoring, progressive disclosure) |
| `templates/evalset.json` | Starter eval set |
| `.cursor/commands/temper-eval.md` + `.cursor/rules/temper-ref-eval.mdc` | **Cursor parity** (portability is a paper principle) |

---

## Deliverable 2 — Eval-coverage gate in `/temper`

Mirror the existing `review.block-on` / `check.coverage-threshold` pattern.

### 2.1 New `/temper` stage
Insert an **Eval** stage between Check and commit (default-on, config-gated):
```
plan → design? → build → review → check → eval → commit
```
- Runs as an isolated Agent subprocess (same architecture as every other stage in
  `.claude/commands/temper.md`).
- Returns score table + `eval-context.json`; on failure, feeds back to **Build** through
  the existing feedback-loop machinery (`feedback.max-loops`), exactly like Review→Build
  and Check→Build today.

### 2.2 Config additions (`.claude/temper.config`)
```yaml
eval:
  enabled: true            # default-on; absent = enabled (graceful degradation)
  block-on: [task_success] # gate the commit if these dimensions fail
  pass-threshold: 0.75
  judge-model: tier-fast   # resolved by Phase 2 model routing; ignored if unset

capabilities:
  evals: true              # surfaces the Eval gate option in /temper
```

### 2.3 Acceptance criteria
- `/temper` shows an Eval gate (AskUserQuestion) with Continue / Re-run / View results /
  Save-for-later, consistent with existing gates.
- Missing `eval` config or missing `evalset.json` ⇒ stage is skipped with a one-line
  notice, **no errors** (matches the project's graceful-degradation contract).
- `eval-context.json` schema documented in `reference/orchestrator-patterns.md` alongside
  the existing `build/review/check-context.json` schemas.

---

## Deliverable 3 — Eval authored at plan time (the contract)

The paper: *write the tests and evals before generating the code… together they are the
contract with the AI.*

- Extend `reference/plan.md` so the plan stage emits a **draft `evalset.json`** next to
  `intent.md`, derived from the scenarios it already generates.
- Plan summary box gains an `EVALS` line (count of draft cases) beside the existing
  `Scenarios` line.
- This makes "spec + tests + evals" the gating contract rather than intent + TDD alone.

---

## Deliverable 4 — Deterministic hooks pack

The paper defines hooks as **deterministic code at lifecycle points** (e.g. *block a
commit if the agent tries to push a hard-coded password*). Temper's guardrails today are
model-interpreted packs — strong but non-deterministic.

### 4.1 What ships
| Artifact | Purpose |
|---|---|
| `.claude/packs/hooks/rules.md` | Documents the hook contract + catalog |
| `.claude/packs/hooks/settings.hooks.json` | Copy-paste `settings.json` hook block |
| `scripts/hooks/block-secrets.sh` | PreToolUse/pre-commit: block hard-coded secrets, `.env` writes, key material |
| `scripts/hooks/block-forbidden-imports.sh` | PostToolUse: deny imports flagged in active packs |
| `scripts/hooks/verify-tests-ran.sh` | Pre-commit: refuse commit if `/temper:check` not green |

### 4.2 Adoption
- Wire into the `update-config` skill so `/temper:pack enable hooks` installs the
  `settings.json` block in one step.
- Hooks **complement** packs: packs advise during generation; hooks enforce
  deterministically at lifecycle boundaries. Both stay independently toggleable.

### 4.3 Acceptance criteria
- With the hooks pack enabled, a commit containing a hard-coded secret is **blocked by
  the hook, not by model judgment** (demonstrable, deterministic).
- Hooks degrade safely: absent scripts ⇒ no-op, never break a session.

---

## Cross-cutting (applies to every deliverable)
- **Config-flagged, default-on, graceful degradation** — Temper's established contract.
- **Cursor parity** for new commands/rules; bump `.cursor/VERSION` in lockstep (see the
  version-drift finding in `implementation-gaps.md`).
- **Reference docs loaded on demand**, thin command files — match existing structure.
- Update `.claude/CLAUDE.md` command table, `temper-core/SKILL.md` capability table, and
  `CHANGELOG.md`.
- Extend `scripts/validate-plugin.sh` to assert the new command/reference/skill files
  resolve (the repo already gates on this — 13 checks today).

## Exit criteria for Phase 1
On the spectrum table in `ai-sdlc-alignment.md`, the **Evals / LM-judge / trajectory** row
flips from ❌ to ✅ and **Deterministic guardrails/hooks** flips from ⚠️ to ✅. Temper can
then honestly claim it satisfies the paper's litmus test: *both tests and evals, gating
what ships.*
