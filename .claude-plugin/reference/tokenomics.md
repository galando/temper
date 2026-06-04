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

- Prefer **Sonnet** for editing, small fixes, and exploration tasks — up to ~5x cheaper
  on those sessions than Opus.
