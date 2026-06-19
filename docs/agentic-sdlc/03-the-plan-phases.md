# 03 — The plan: Phase 0 → 1 → 2

The original analysis produced a phased plan to close the distance between what Temper
promised and what the paper demands. Phase 3 (production/deploy/maintain) was deliberately
deferred. This chapter records the plan as it was set out, in execution order.

> **Sequencing principle:** fix the foundation before extending it. The paper's "AI
> amplifies the culture it lands in" cuts both ways — building new capabilities on a base
> that doesn't honor its existing promises compounds the drift. So **gaps came first**.

---

## Phase 0 — Implementation gaps (do first)

An audit of whether Temper actually did what its own docs, config, and skills promised —
independent of the paper. The good news up front: the repo's own validation suites passed
and the core architecture was internally consistent. The six findings were cross-file drift
and unwired promises:

| ID | Finding | Severity |
|---|---------|----------|
| G-1 | Version stamps disagreed (`plugin.json` 5.2.1, `CLAUDE.md` 5.2.0, `.cursor/VERSION` 5.0.1, `temper.md` header v4.4.1) | High |
| G-2 | Cursor parity export 2 minors behind the plugin → stale rules for Cursor users (no generator; hand-synced) | High |
| G-3 | Phase-scoped pack loading documented in `pack.md` but **not wired** into review/build — the promised token lever wasn't applied | Medium |
| G-4 | `pack-manifest.json` cache claimed but not consumed by the stages it was meant to speed up | Medium |
| G-5 | `track-tokens` observability was **estimated, not measured** — wording implied measurement | Medium |
| G-6 | Adaptive-learning flywheel unproven in the project's own dogfooding (graceful, not broken) | Low |

**Recommended order:** G-1 + G-2 (mechanical, gate in `validate-plugin.sh`) → G-3 + G-4
(one manifest-driven, phase-filtered change closes both) → G-5 (folds into Phase 2) → G-6
(opportunistic dogfooding).

---

## Phase 1 — Close the verification gap

**Theme:** move Temper onto the *agentic engineering* end of the spectrum by adding the
verification half the paper insists on (evals) plus deterministic guardrails (hooks).

### Deliverable 1 — `/temper:eval` command + eval skill
- Eval-set format under `.temper/specs/{feature}/evals/` (labelled cases + rubric).
- Five-dimension rubric: `task_success`, `tool_use_quality`, `trajectory`, `hallucination`
  (inverted), `response_quality`.
- **Output eval** (final artifact) + **trajectory eval** (reconstruct the agent's tool-call
  sequence from `build-state.json` + `observability.json`).
- **LM-judge** on a cheaper model tier, with a **deterministic fallback** when no judge is
  available (string/regex `expected`/`must_not`, unscored semantic dims).

### Deliverable 2 — Eval gate in `/temper`
- An **Eval** stage between Check and commit (isolated subprocess, config-gated).
- On failure of a `block-on` dimension, feed back to Build via the existing feedback loop.
- Config: `eval.enabled`, `eval.block-on`, `eval.pass-threshold`, `eval.judge-model`.

### Deliverable 3 — Eval authored at plan time
- Plan stage emits a **draft `evalset.json`** beside `intent.md` (the contract written with
  the feature, not bolted on). Plan summary shows an `EVALS: N` line.

### Deliverable 4 — Deterministic hooks pack
- Real `settings.json` hooks + shell scripts that **deterministically block** secrets,
  forbidden imports, and commits that skipped check.
- One-step install; complements (doesn't replace) the model-interpreted packs.

---

## Phase 2 — Harness economics & observability

**Theme:** drive down OpEx and make the harness auditable.

### Deliverable 1 — Intelligent model routing
- `models:` config mapping **stage → tier** (frontier/standard/fast); orchestrator passes
  the resolved `model` to each stage Agent.
- Per-finding routing in review (cheap tier sweeps; `escalate-on` findings re-judged on
  frontier). Respect user overrides.

### Deliverable 2 — Measured telemetry (not estimated)
- `observability.json` **v2** with per-field `source: measured|estimated` flags; a versioned
  price table (`reference/pricing.md`) to compute `cost_usd`. Never present an estimate as
  measured.

### Deliverable 3 — Drift detection
- Rolling per-stage baselines (tool calls, retries, latency, eval score); flag deviations
  beyond a configurable std-dev. SUGGEST-level, never auto-blocking.

### Deliverable 4 — Economics panel in `/temper:status`
- Per-stage cost/latency/tier; eval-score trend; drift flags; a CapEx-vs-OpEx summary that
  makes the paper's economic argument concrete for leaders.

---

## Cross-cutting contract (every deliverable)

- **Config-flagged, default-on, graceful degradation** — Temper's established convention.
- **Cursor parity** maintained; `.cursor/VERSION` bumped in lockstep.
- Reference docs loaded on demand; thin command files.
- `validate-plugin.sh` extended to assert new files resolve and versions match.

---

## What shipped against this plan

| Plan phase | Released in | Verified |
|---|---|---|
| Phase 0 (G-1…G-6) | v5.3.0 (PR #50) | ✅ ch. 04 |
| Phase 1 (eval + hooks) | v5.5.0 (PR #55) | ✅ ch. 04 |
| Phase 2 (routing + observability) | v5.6.0 (PR #56) | ✅ ch. 04 |
| Phase 3 (deploy/maintain/prod-agents) | — | Deferred (see ch. 07) |
