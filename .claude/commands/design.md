---
description: "System design exploration for complex features"
argument-hint: "[--skip | --force]"
---

# Design: System Design Phase

**Goal:** Produce system design artifacts for complex/medium features.

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/design.md`

### Quick Reference

1. Load intent.md + plan.md from active spec
2. Skip if complexity < medium or config disabled
3. Explore system architecture, API contracts, DB schema
4. Write design.md to spec directory
5. Present design summary for approval

### Active Skills

- **Context Engineering** — load hierarchical context at stage start (rules → arch → source → errors, under 2K lines/task)
- **Temper Core** — stack detection, pack resolution, quality gates
