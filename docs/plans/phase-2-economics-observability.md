# Phase 2 — Harness Economics & Observability

**Proposed release:** v5.4.0
**Theme:** Drive down OpEx and make the harness auditable — turn the paper's economic
argument (high CapEx / low OpEx, context as a financial lever, intelligent model routing)
into measurable, enforced behavior.
**Source mandate:** _The New SDLC With Vibe Coding (Day 1)_ — *"A well-designed factory…
routes deterministic, lower-complexity tasks to smaller, faster, cheaper models."* /
*"observability… audit exactly why an agent made a specific deployment decision."*
**Status:** Planning · **Date:** 2026-06-16
**Depends on:** Phase 1 (the eval judge is the first routing consumer; eval scores are the
first real signal the observability layer trends).

---

## Why this phase

Temper already has the *structure* for economics and observability — a `models` heuristic
in `tokenomics.md`, `observability.*` flags in `temper.config`, and a `/temper:status`
dashboard. But the routing is **advisory only** and the observability is **self-estimated,
not measured** (see `implementation-gaps.md`, findings G-4 and G-7). This phase makes both
real.

**Deliverables:** (1) intelligent model routing wired into the orchestrator, (2) measured
per-stage telemetry (tokens/latency/cost), (3) drift detection, (4) an economics panel in
`/temper:status`.

---

## Deliverable 1 — Intelligent model routing

The paper's primary OpEx lever: frontier models for high-complexity work
(requirements/architecture/initial implementation); cheaper, faster models for
deterministic work (test generation, review, CI/CD monitoring, eval judging).

### 1.1 Config: stage → model tier (`.claude/temper.config`)
```yaml
models:
  enabled: true
  tiers:
    frontier: claude-opus          # planning, design, architecture, hard implementation
    standard: claude-sonnet        # build, fixes, exploration
    fast:     claude-haiku         # test-gen, review-style passes, eval judge, check monitoring
  routing:
    plan:    frontier
    design:  frontier
    build:   standard
    review:  fast      # style/lint pass; escalate correctness findings to frontier
    check:   fast
    eval:    fast      # LM-judge — the canonical "route to small model" task
  escalate-on:         # when a fast tier hits these, re-run on frontier
    - architecture-finding
    - correctness-risk
  respect-user-override: true
```

### 1.2 Orchestrator wiring (`.claude/commands/temper.md`)
- Each stage's `Agent` launch passes the `model` resolved from `models.routing.{stage}`.
  The `Agent` tool already supports a `model` parameter — this is plumbing, not new
  capability.
- **Per-finding routing in review:** cheap tier does the broad style/lint sweep; findings
  tagged `architecture` or `correctness-risk` are re-judged on the frontier tier. Reuses
  the existing confidence-scoring path in `reference/review.md`.
- If `models.enabled` is false/absent ⇒ inherit the session model everywhere (today's
  behavior; graceful degradation).

### 1.3 Acceptance criteria
- A `/temper` run records which tier ran each stage in `observability.json`.
- Disabling `models` reproduces current behavior exactly.
- User-set model overrides are never silently replaced (`respect-user-override`).

---

## Deliverable 2 — Measured telemetry (not estimated)

Today `temper.md` *estimates* tokens and writes `.temper/observability.json`; the config
flag `track-tokens` overstates this as measurement. Make it real.

### 2.1 What gets captured per stage
```json
{
  "version": 2,
  "feature": "{slug}",
  "stages": [
    {
      "stage": "build",
      "model_tier": "standard",
      "tokens": {"input": 0, "output": 0, "source": "measured|estimated"},
      "latency_ms": 0,
      "tool_calls": 0,
      "cost_usd": 0.0,
      "retries": 0,
      "eval_score": null
    }
  ],
  "totals": {"tokens": 0, "cost_usd": 0.0, "latency_ms": 0}
}
```
- Prefer **measured** values from harness-reported usage where available; fall back to
  estimation and mark `source: "estimated"` so the dashboard never lies about provenance.
- Add a small, versioned **price table** (`.claude-plugin/reference/pricing.md`) keyed by
  model tier to compute `cost_usd`. Advisory and easily updated.

### 2.2 Acceptance criteria
- `observability.json` bumps to `version: 2` with a documented schema in
  `orchestrator-patterns.md`.
- Every numeric field carries a `source` flag (measured vs estimated). No silent estimates
  presented as measurements.

---

## Deliverable 3 — Drift detection

The paper wants observability that surfaces when an agent is *"quietly drifting."*

- Maintain a rolling baseline per stage (tool-call count, retries, latency, eval score) in
  `.temper/metrics.json` (extend the existing file; it already holds histories like
  `coverage_history`).
- Flag a stage when a run deviates > N std-dev (configurable) from its baseline, or when
  eval score trends down across the last K runs.
- Drift flags are **SUGGEST-level** by default (Temper's gate vocabulary), surfaced in
  `/temper:status`, never auto-blocking.

---

## Deliverable 4 — Economics panel in `/temper:status`

Make the paper's CapEx/OpEx argument concrete for engineering leaders.

`/temper:status` (already the "observability dashboard" per its description) gains:
- **Per-stage cost/latency/tier** table for the last run and rolling averages.
- **Eval-score trend** (from Phase 1) over the last K runs.
- **Drift flags** from Deliverable 3.
- **CapEx vs OpEx summary:** one-time investment (eval sets authored, packs/hooks
  configured, context files) vs per-feature OpEx (tokens/cost per shipped feature),
  illustrating the paper's thesis that upfront structure lowers marginal cost.

### Acceptance criteria
- Panel renders from `observability.json` + `metrics.json`; absent files ⇒ "No
  observability data yet" (current graceful behavior preserved).
- No new required dependencies; pure read-and-render, consistent with existing
  `reference/status.md`.

---

## Cross-cutting
- **Config-flagged, default-on, graceful degradation** throughout.
- **Cursor parity** + lockstep `.cursor/VERSION` bump.
- Update `temper.config` (already carries `observability.*` — extend, don't replace),
  `CLAUDE.md`, `temper-core/SKILL.md`, `CHANGELOG.md`.
- Reconcile `tokenomics.md` (currently advisory "prefer Sonnet") with the new enforced
  `models` routing so guidance and behavior agree.

## Exit criteria for Phase 2
On the spectrum table in `ai-sdlc-alignment.md`: **Model routing (OpEx)** flips ⚠️ → ✅ and
**Real observability / drift** flips ⚠️ → ✅. Routing and observability stop being
documented intentions and become measured, enforced harness behavior.
