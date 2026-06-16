# Temper & The New SDLC — Alignment Plan

**Source:** _The New SDLC With Vibe Coding (Day 1)_ — Osmani, Saboo, Kartakis (May 2026)
**Temper version at time of writing:** 5.2.1
**Status:** Planning
**Date:** 2026-06-16

---

## TL;DR

The paper's thesis is that software engineering is shifting **from writing code to
expressing intent**, and that the discipline separating "vibe coding" from "agentic
engineering" is **how much structure, verification, and human judgment surrounds the
model** — what the paper calls the **harness**. The developer's real output becomes the
*system that builds software* (the **factory model**).

Temper is already a working implementation of large parts of that thesis: a phased SDLC
(`plan → design → build → review → check`) run as isolated agent subprocesses, with
quality gates, blast-radius analysis, hierarchical context engineering, scoped rule packs,
feedback loops, and an adaptive-learning flywheel. **Where Temper falls short of the paper
is the verification half of the spectrum and the harness plumbing**: no eval/LM-judge
layer, no deterministic lifecycle hooks, no intelligent model routing, shallow
observability, and no production/deployment phase.

This document (1) maps the paper's framework onto Temper as it exists today, (2) names the
gaps honestly, and (3) lays out a phased plan to make Temper a reference harness for the
new SDLC.

---

## Part 1 — The paper's framework in one page

| Concept | What the paper says |
|---|---|
| **Spectrum** | Vibe coding → structured AI-assisted → **agentic engineering**. The differentiator is *not* whether you use AI — it's the structure, verification, and judgment around the output. |
| **Verification** | The single biggest differentiator. **Tests** verify deterministic behavior; **evals** (labelled datasets, rubrics, LM judges, trajectory checks) verify non-deterministic behavior. *"Without both, the practice is always vibe coding."* |
| **Context engineering** | The real skill. Six context types — instructions, knowledge, memory, examples, tools, guardrails — split into **static** (always loaded) vs **dynamic** (loaded on demand). **Agent Skills** = progressive disclosure of procedural knowledge. |
| **Factory model** | The developer's output is the *system that builds software*: specs + context, agents, tests + quality gates, feedback loops, guardrails. |
| **Harness** | `Agent = Model + Harness`. Harness = instructions/rule files, tools, sandboxes, **orchestration logic**, **guardrails/hooks**, **observability**. *"Most agent failures are configuration failures."* |
| **Harness across SDLC** | Configure (requirements/arch) → Run (implementation) → Feedback loop (test/QA) → Observe (review/deploy/maintain). |
| **Developer roles** | **Conductor** (hands-on, real-time) vs **Orchestrator** (async, multi-agent delegation). Skills: specification, decomposition, evaluation, system design. |
| **The 80% problem** | AI nails ~80%; the last 20% (edge cases, integration, subtle correctness) needs human judgment. Errors are now *conceptual*, not syntactic — code "looks right." |
| **Economics** | Vibe = low CapEx / **high OpEx** (token burn, maintenance tax, security remediation). Agentic = high CapEx / **low OpEx**. Context engineering is a **financial lever**; **intelligent model routing** drives down OpEx. |
| **Where to start** | Individuals: AGENTS.md, skills, write tests+evals first, review every shipped line. Leaders: context engineering as a first-class practice, *set the bar at the eval not the demo*, reshape review for AI code, separate prototyping from production. |

Durable principles: **Structure scales, vibes don't. AI amplifies your engineering
culture. The human role is evolving, not diminishing. Generation is solved — verification,
judgment, and direction are the new craft.**

---

## Part 2 — How Temper already enables the new SDLC

| Paper concept | Temper mechanism (today) | Where |
|---|---|---|
| The new phased SDLC | Unified `/temper`: `plan → design? → build → review → check → commit`, each stage an **isolated Agent subprocess** with clean context | `.claude/commands/temper.md` |
| Factory model (system that builds software) | Stage gates + feedback loops + context accumulation + observability config — the orchestrator *is* the assembly line | `temper.md`, `temper.config` |
| Requirements as conversation | `intent.md` / `spec.md` templates; plan stage generates intent, scenarios, blast radius | `templates/`, `reference/plan.md` |
| Design/architecture (human-centric) | `/temper:design` for complex/medium features; `grill-me` Socratic challenge at plan/design gates | `commands/design.md`, `skills/grill-me` |
| Implementation under constraints | `/temper:build` with TDD discipline, task-by-task, graduated gates | `reference/build.md`, `packs/tdd` |
| Tests (deterministic verification) | TDD pack, `/temper:check` validation pipeline, coverage threshold (80%) | `packs/tdd`, `reference/check.md` |
| Code review (AI first-pass) | `/temper:review` with **confidence scoring (0–1)**, SUGGEST/WARN/BLOCK gates, OCR external engine, review memory | `reference/review.md`, `temper.config` |
| Context engineering (the real skill) | Dedicated **context-engineering skill**: hierarchical loading, static vs dynamic, <2K-line budget, progressive disclosure | `skills/context-engineering/SKILL.md` |
| Agent Skills / progressive disclosure | Skills surfaced as lightweight metadata, loaded on task match; reference docs loaded on demand | `.claude/skills/*`, `reference/*` |
| Guardrails / rule files | Scoped **packs** (quality, tdd, security, git, performance, api-design, architecture-depth) with `phases:` targeting | `.claude/packs/`, `temper.config` |
| Knowledge context | **source-driven-development** skill (fetch official docs before writing framework code) | `skills/source-driven-development` |
| Memory | `build-state.json`, `review-memory.json`, `metrics.json`, adaptive `learning.json` | `.temper/` |
| Continuous quality flywheel | **Adaptive learning**: pattern detection → rule suggestion (3+ accepts) → noise reduction (5+ dismissals) | `reference/learning.md` |
| Orchestration logic | Agent-per-stage isolation, **nested subagents** with depth budget + parallel width | `temper.config` (`agents:`), v5.1.0 |
| Tools | MCP integration (code-review-graph for AST-level analysis), OCR review CLI | `temper.config` (`tools:`) |
| Configuring the harness | **config-suggestions** capability: proposes CLAUDE.md/AGENTS.md updates after check | `reference/config-suggestions.md` |
| Conductor vs orchestrator | Per-command standalone use (conductor) **and** unified `/temper` async delegation (orchestrator) | both modes supported |
| Portability across tools | Cursor parity export (rules + commands under `.cursor/`) | `.cursor/`, `scripts/install-cursor.sh` |
| Economics — context as lever | <2K budget, progressive loading, dedup, lean memory (v4.7 perf work) | `skills/context-engineering`, `reference/tokenomics.md` |

**Bottom line:** Temper already covers the *configure → run → feedback* arc of the harness
and the entire left side of the spectrum (specs, structure, tests, review, context
discipline). It is a credible "agentic engineering" harness today.

---

## Part 3 — Gaps: where Temper does NOT yet answer the paper

Ranked by how central the paper considers them.

### G1 — Evals, LM-judge, and trajectory evaluation (the biggest gap)
The paper is emphatic: *"Without both [tests and evals], the practice is always vibe
coding."* Leaders should *"set the bar at the eval, not the demo."* It calls out **output
evaluation** vs **trajectory evaluation** (did the agent take the right steps / use the
right tools), and scoring via **labelled datasets, rubrics, and LM judges**.

Temper has **tests** (TDD, check, coverage) but **no eval layer at all**. The word "eval"
in the codebase refers to adaptive-learning statistics, not eval suites. There is no
rubric, no LM-judge, no eval-coverage gate, no trajectory scoring of an agent's run.

### G2 — Deterministic guardrails / lifecycle hooks
The paper defines hooks as **deterministic code that runs at lifecycle points** (e.g.,
*block a commit if the agent tries to push a hard-coded password*). Temper's guardrails
are **model-interpreted packs and gates** — strong, but advisory and non-deterministic.
There are no real `settings.json` hooks (PreToolUse/PostToolUse/pre-commit) that enforce
constraints the agent "should never forget but often does."

### G3 — Intelligent model routing
The paper presents routing as a primary **OpEx lever**: frontier models for
requirements/architecture/initial implementation; cheaper/faster models for test
generation, review, and CI/CD monitoring. Temper only has an **advisory** "prefer Sonnet"
heuristic in `tokenomics.md`. The orchestrator does not route per stage, even though the
`Agent` tool supports a `model` override.

### G4 — Observability depth (cost, latency, drift)
`temper.config` has `observability.track-tokens/latency/tool-calls` and `/temper:status`
shows a dashboard — but values are **estimated**, there are no real cost/latency traces,
no **agent drift** detection, and no trend of eval scores over time. The paper wants the
observability layer to *"audit exactly why an agent made a specific deployment decision."*

### G5 — Production / deployment / maintenance phase
Temper's lifecycle stops at **commit**. The paper extends the SDLC to **deployment**
(AI-aware pipelines, health monitoring, auto-rollback, deployment-risk prediction) and
**maintenance/evolution** (framework migrations, deprecated-API updates). Temper has
`/temper:fix` (RCA) but no deploy/observe-in-production loop.

### G6 — Production-agent lifecycle ("the agent is the product")
The paper's "Vibe Coding Production-ready Agents" section describes a
build→evaluate→deploy→observe→refine loop for shipping *agents themselves* (à la Google
Agents CLI / ADK). Temper builds *software*; it has no first-class path for building,
evaluating, and deploying *agents* as products (eval sets, A2A/MCP wiring, agent runtime).

### G7 — Spec/eval as the explicit contract
Temper has `intent.md` and scenarios, but the paper frames **tests + evals as the contract
with the AI**, written *before* code. Today the contract is mostly intent + TDD; closing
G1 should make "spec + eval suite" the formal, gating contract.

---

## Part 4 — The plan

Three phases, mapped to proposed releases. Each item is independently shippable and follows
Temper's own conventions (capability flags default-on, graceful degradation, pack-based
extension, reference docs loaded on demand).

### Phase 1 — Close the verification gap (proposed v5.3.0)
**Theme: make Temper land on the *agentic* end of the spectrum.**

1. **`/temper:eval` command + eval skill (G1, G7).**
   - Eval set format under `.temper/specs/{feature}/evals/` (labelled cases + rubric).
   - **LM-judge** scoring with explicit rubrics: task success, tool-use quality,
     trajectory compliance, hallucination, response quality (the paper's five dimensions).
   - **Output eval** (final artifact) + **trajectory eval** (reconstruct the agent's
     tool-call sequence from `build-state.json` / stage telemetry and score it).
   - New gate in `/temper`: **eval-coverage gate** — mirror the coverage threshold but for
     evals; configurable `eval.block-on` like `review.block-on`.
   - Plan stage emits a draft eval set alongside `intent.md` so the **eval is written
     before the code** (the contract).

2. **Deterministic hooks pack (G2).**
   - Ship a `hooks` pack + `settings.json` hook templates (PreToolUse/PostToolUse,
     pre-commit) that **deterministically block** secrets, hard-coded credentials,
     `.env` writes, and forbidden imports — the things the model "often forgets."
   - Wire into `update-config` skill so adoption is one command.
   - Hooks complement (don't replace) the model-interpreted packs.

3. **Config & docs.**
   - `temper.config`: add `eval:` block and `capabilities.evals: true` (default-on,
     graceful degradation).
   - `reference/eval.md`; update `temper-core` SKILL and `CLAUDE.md` command table.

### Phase 2 — Harness economics & observability (proposed v5.4.0)
**Theme: drive down OpEx and make the harness auditable.**

4. **Intelligent model routing (G3).**
   - `models:` block in `temper.config` mapping **stage → model tier**:
     plan/design/architecture → frontier (Opus); build/test-gen/review/check → faster
     tier (Sonnet/Haiku). The orchestrator passes `model` to each stage `Agent`.
   - Per-finding routing in review (cheap model for style/lint, frontier for
     correctness/architecture). Respect user overrides; document as an OpEx lever.

5. **Real observability (G4).**
   - Capture actual per-stage token/latency/tool-call telemetry into `metrics.json`
     (not estimates); add **cost** using a small price table.
   - **Drift detection**: flag when a stage's tool-call count, retries, or eval score
     deviates from its rolling baseline.
   - `/temper:status` gains a cost/latency/drift panel and an **eval-score trend**.

6. **Economics surfacing.**
   - `/temper:status` shows a CapEx-vs-OpEx style summary (upfront context/eval
     investment vs per-feature token cost), making the paper's economic argument concrete
     to engineering leaders.

### Phase 3 — Extend the lifecycle (proposed v6.0.0)
**Theme: cover deploy/maintain and production agents.**

7. **Deploy + maintenance stages (G5).**
   - Optional `/temper:deploy` (phase-gated, default-off): deployment-risk scoring from
     blast radius + change scope, health-check hook points, rollback checklist.
   - `/temper:fix` extended toward maintenance/evolution playbooks (framework migration,
     deprecated-API sweeps) — the paper's "too risky to touch" debt.

8. **Production-agent lifecycle (G6) — exploratory.**
   - A `temper:agent` track (or companion pack) for building *agents as products*:
     scaffold → eval set → MCP/A2A wiring → runtime deploy → observe. Reuses the Phase-1
     eval engine. Evaluate whether to integrate with an existing agent runtime rather than
     reinvent.

### Cross-cutting
- Keep every new capability behind a **config flag, default-on, graceful degradation** —
  Temper's established contract.
- Maintain **Cursor parity** for any new rules/commands (portability is a paper principle).
- Add an **`AGENTS.md` quickstart** alongside the existing CLAUDE.md guidance so Temper
  matches the paper's "start with ten lines" advice for non-Claude agents.

---

## Part 5 — Positioning

After Phase 1, Temper can credibly claim to be **an agentic-engineering harness, not a
vibe-coding tool** — because it will satisfy the paper's own litmus test: *both tests and
evals, with rubrics, gating what ships.* Phases 2–3 turn it into a full **factory**: the
system the developer builds so that agents can build software under structure,
verification, and judgment.

| Spectrum position | Temper today (5.2.1) | After Phase 1 | After Phases 2–3 |
|---|---|---|---|
| Specs / structure | ✅ | ✅ | ✅ |
| Tests | ✅ | ✅ | ✅ |
| **Evals / LM-judge / trajectory** | ❌ | ✅ | ✅ |
| Deterministic guardrails/hooks | ⚠️ advisory | ✅ | ✅ |
| Model routing (OpEx) | ⚠️ advisory | ⚠️ | ✅ |
| Real observability / drift | ⚠️ estimated | ⚠️ | ✅ |
| Deploy / maintain / prod-agents | ❌ | ❌ | ✅ |

**Generation is solved. Temper's job is the rest — verification, judgment, and direction —
and this plan closes the distance to that mandate.**
