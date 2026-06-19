---
description: "Token optimization insights — session efficiency guidance for Temper"
---

# Token Optimization Insights

_Last updated: 2026-05-12_

These are advisory heuristics derived from session telemetry. Load on demand; they are
not required for any command to function.

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
