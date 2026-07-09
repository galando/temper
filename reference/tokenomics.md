---
description: "Token optimization insights — session efficiency guidance for Temper"
---

# Token Optimization Insights

_Last updated: 2026-06-24_

These are advisory heuristics derived from session telemetry. Load on demand; they are
not required for any command to function.

## The Three Phase 3 Levers (v5.9.0) — canonical token-efficiency guidance

Model routing (Phase 2, v5.6.0) picked the right *model* per stage. Phase 3 (v5.9.0)
attacks the remaining structural waste with three independent, composable levers. Each is
config-flagged, default-on, and degrades **byte-identically** to v5.8.0 when its flag is
off. All three live under `tokens:` in `.claude/temper.config`.

1. **Cache the static instruction mass (`tokens.cache`).** A `/temper` run launches 6
   isolated Agent subprocesses that each re-read their methodology fresh at full price.
   When `tokens.cache.enabled` is true, stage agents read the **cacheable context**
   (methodology ref, orchestrator-patterns, pack-manifest, stack-pack, config) FIRST in a
   byte-stable order, then the volatile delta (build-state, spec artifacts, git diff). This
   maximizes the chance the platform returns a cache hit on re-entry; the orchestrator
   cannot force a cache, only structure reads so the prefix is stable. What the platform
   reports is recorded as `tokens.cached_input{value, source}` in observability.json. See
   `reference/orchestrator-patterns.md` → "Cacheable vs. Volatile Context" + "Cache-Stable
   Re-Entry".

2. **Adapt pipeline depth to change complexity (`tokens.adaptive-depth`).** v5.8.0 ran the
   full 6-stage pipeline on every change — a one-line fix paid for mermaid + blast radius +
   eval. When `tokens.adaptive-depth.enabled` is true, the plan stage's existing complexity
   classification (trivial|simple|medium|complex) selects a reduced pipeline per the
   Pipeline Depth table (trivial = 1 combined plan+build agent + review; simple = plan →
   build → review → check). The `floor` clamp raises the effective tier UP (`floor: medium`
   kills the trivial fast-path). The plan gate shows the chosen tier with an "Escalate to
   full pipeline" option. See `reference/orchestrator-patterns.md` → "Pipeline Depth".

3. **Make feedback loops incremental (`tokens.loops`).** A Review→Build loop to auto-fix 2
   lint findings used to re-launch a full Build agent that re-read `build.md` + tasks +
   intent. When `tokens.loops` is on, every loop resolves by a cheapest-first decision
   rule: **inline** micro-fix (no subprocess) when all findings are auto-fixable AND
   `files_touched <= inline-threshold`; else **fix-mode** minimal-context Build Agent (fix
   list + changed files + a fix-mode preamble that replaces full `build.md`) when
   `fix-mode: true`; else **full** re-launch (v5.8.0). The chosen `mode` + per-loop token
   `cost` are recorded in observability.json `loops[]`. See
   `reference/orchestrator-patterns.md` → "Loop Cost Tiers".

**Degradation contract:** with all three flags off (`cache.enabled: false` +
`adaptive-depth.enabled: false` + `loops.fix-mode: false` + `inline-threshold: 0`), a
`/temper` run is byte-identical to v5.8.0 — full pipeline, full re-launch, no cache prefix,
no `cached_input` field.

## Context Management

- Context snowballs at **turn 22** on average (31% of sessions). Use `/compact`
  proactively after turn 20-22 on long sessions to prevent unbounded growth.
- Reading files you don't end up using wastes context. Use `Grep` first to locate
  relevant files before reading them — reduces unnecessary context by ~3%.
- Split multi-file operations into parallel subagent tasks.
- Prefer `Grep`/`Read` tools over bash commands when searching files to reduce output
  tokens.

## Prompt Quality

- **6%** of prompts are under 10 words. Include specific file paths, function names, and
  expected outcomes to reduce clarification rounds.

## Model Usage

- **Enforced routing (v5.6.0):** model selection is now enforced by `models.routing` in
  `.claude/temper.config` (Deliverable 1, Phase 2). Each stage maps to a tier
  (`tier-frontier` → opus, `tier-standard` → sonnet, `tier-fast` → haiku). Do not hand-pick
  models per task — edit the routing map instead, so guidance and behavior agree.
- **Routing pointer:** see `.claude/temper.config` → `models.routing`. The fast tier
  (haiku) handles test-gen, review style/lint sweep, eval judging, and check monitoring;
  the standard tier (sonnet) handles build/fixes/exploration; the frontier tier (opus)
  handles plan/design/architecture. `review` escalates `architecture-finding` and
  `correctness-risk` findings to `tier-frontier` per `models.escalate-on`.
- **Graceful degradation:** when `models.enabled: false`, routing is off and the session
  model is inherited everywhere (byte-identical to v5.5.0).
- The historical "prefer Sonnet for editing/small fixes" advice is now realized as the
  `build: tier-standard` and `review/check/eval: tier-fast` routing entries.
