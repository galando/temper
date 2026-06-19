# 02 — Temper as the harness: the mapping

This chapter maps every major concept from the paper onto the concrete Temper mechanism
that implements it (as of v5.6.0). It answers: *"Does Temper actually implement the new
SDLC, and where?"*

---

## The headline: Temper is the factory's assembly line

Temper's unified command **is** the factory model in practice:

```
/temper "<intent>"
   └── ORCHESTRATOR (.claude/commands/temper.md)
         ├── Agent subprocess → PLAN     (full codebase exploration, blast radius)
         ├── Agent subprocess → DESIGN?  (complex/medium features only)
         ├── Agent subprocess → BUILD    (TDD, phase-scoped packs)
         ├── Agent subprocess → REVIEW   (confidence-scored, OCR engine)
         ├── Agent subprocess → CHECK    (stack validation pipeline)
         ├── Agent subprocess → EVAL     (LM-judge + trajectory)        ← v5.5.0
         └── commit (deterministic hooks block secrets)                 ← v5.5.0
```

Each stage runs in an **isolated Agent subprocess** — genuine context clearing, not a
self-directed "forget everything" prompt. Stage gates (`AskUserQuestion`) keep the human in
the loop; feedback loops route failures back to earlier stages.

---

## Concept-by-concept mapping

| Paper concept | Temper mechanism | Where |
|---|---|---|
| New phased SDLC | Unified `/temper` pipeline, agent-per-stage isolation | `.claude/commands/temper.md` |
| Factory model | Gates + feedback loops + context accumulation + observability | `temper.md`, `temper.config` |
| Requirements as conversation | Plan stage → `intent.md`, scenarios, blast radius, **draft evalset** | `reference/plan.md`, `templates/intent.md` |
| Design/architecture (human-centric) | `/temper:design` for complex features; **grill-me** Socratic challenge | `commands/design.md`, `skills/grill-me` |
| Implementation under constraints | `/temper:build`, TDD, task-by-task, graduated gates | `reference/build.md`, `packs/tdd` |
| **Tests** (deterministic verification) | TDD pack, `/temper:check`, coverage threshold | `packs/tdd`, `reference/check.md` |
| **Evals** (non-deterministic verification) | `/temper:eval`: LM-judge, rubric, output + trajectory | `commands/eval.md`, `reference/eval.md`, `skills/eval-judge` |
| Code review (AI first-pass) | `/temper:review`: confidence scoring, SUGGEST/WARN/BLOCK, OCR | `reference/review.md` |
| Context engineering (the real skill) | Hierarchical loading skill: static/dynamic, <2K budget, progressive disclosure | `skills/context-engineering` |
| Six context types | Instructions (`CLAUDE.md`/packs), Knowledge (source-driven skill), Memory (`.temper/*`), Examples (packs), Tools (MCP/OCR), Guardrails (packs + **hooks**) | across the plugin |
| Agent Skills / progressive disclosure | Skills = metadata at startup; reference docs loaded on demand | `.claude/skills/*`, `.claude-plugin/reference/*` |
| Static vs dynamic context | Static: `CLAUDE.md` + enabled packs; Dynamic: phase-scoped packs, on-demand references | `temper.config`, `reference/pack.md` |
| Guardrails (deterministic) | **Hooks pack**: real shell hooks block secrets/forbidden imports/uncheck-ed commits | `packs/hooks`, `scripts/hooks/*` |
| Knowledge context | **source-driven-development** skill (fetch official docs first) | `skills/source-driven-development` |
| Memory | `build-state.json`, `review-memory.json`, `metrics.json`, `learning.json`, `observability.json` | `.temper/` |
| Continuous quality flywheel | **Adaptive learning**: pattern detection → rule suggestion → noise reduction | `reference/learning.md` |
| Orchestration logic | Agent-per-stage, nested subagents w/ depth budget + parallel width | `temper.config` `agents:` |
| **Intelligent model routing** | `models:` config (stage→tier) + Model Routing Resolution | `temper.config`, `temper.md` |
| Tools | MCP code-review-graph (AST analysis), OCR external review engine | `temper.config` `tools:` |
| Configuring the harness | **config-suggestions** capability (CLAUDE.md/AGENTS.md updates after check) | `reference/config-suggestions.md` |
| **Observability** | `observability.json` v2 (measured/estimated source flags), `/temper:status` dashboard, **drift detection** | `reference/orchestrator-patterns.md`, `commands/status.md` |
| Economics (CapEx/OpEx) | `/temper:status` economics panel; context <2K budget; model routing | `commands/status.md` |
| Conductor vs orchestrator | Per-command standalone (conductor) **and** unified `/temper` (orchestrator) | both modes |
| Portability across tools | Cursor parity export (rules + commands) | `.cursor/`, `scripts/install-cursor.sh` |

---

## The six harness components — coverage

| Harness component (paper) | Temper coverage |
|---|---|
| Instructions & rule files | ✅ `CLAUDE.md`, packs, skills, sub-agent prompts |
| Tools | ✅ MCP (code-review-graph), OCR; tool-mode config |
| Sandboxes / execution | ⚠️ relies on the host harness (Claude Code) sandbox; Temper doesn't add its own |
| Orchestration logic | ✅ agent-per-stage, nested subagents, **model routing** |
| Guardrails / hooks | ✅ packs (model-interpreted) **+ deterministic shell hooks** |
| Observability | ✅ telemetry + dashboard + drift; ⚠️ token *measurement* depends on host exposure (see ch. 07) |

---

## Where Temper lands on the spectrum (v5.6.0)

| Spectrum capability | Status |
|---|---|
| Specs / structure | ✅ |
| Tests | ✅ |
| **Evals / LM-judge / trajectory** | ✅ (v5.5.0) |
| Deterministic guardrails/hooks | ✅ (v5.5.0) |
| Model routing (OpEx lever) | ✅ (v5.6.0) |
| Real observability / drift | ✅ schema + dashboard (v5.6.0); ⚠️ measurement caveat |
| Deploy / maintain / prod-agents | ❌ (Phase 3, intentionally out of scope) |

**Verdict:** Temper satisfies the paper's litmus test for agentic engineering — *both tests
and evals, gating what ships* — with deterministic guardrails and intelligent routing on
top. The remaining ❌ is the production/deployment half of the lifecycle (see ch. 07).
