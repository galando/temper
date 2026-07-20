---
description: "Execute plan with TDD and quality gates"
---

# Build: Execute Plan

**Goal:** Implement approved plan task by task with TDD and graduated quality gates.

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/reference/build.md`

### Quick Reference

1. Load plan from `.temper/specs/{feature}/tasks.md`
2. Verify feature branch (create if on main)
3. For each task: test from intent.md scenario (RED) → implement (GREEN) → validate
4. Scenario coverage gate: every intent.md scenario must have a passing test
5. Success criteria gate: code-validated criteria must be present (WARN only)
6. **Resumes interrupted builds from checkpoint**
7. After all tasks: auto-chain → /temper:review → /temper:check
8. Report results, ask to commit

### Active Skills

- **Temper Core** — stack detection, pack resolution, quality gates
- **Context Engineering** — load hierarchical context at stage start (rules → arch → source → errors, under 2K lines/task)
- **Source-Driven Development** — before writing framework-specific code: detect installed version → fetch current docs → cite sources → surface API conflicts. Skip for plain logic or known patterns

### Deterministic Gate

Follow `$CLAUDE_PLUGIN_ROOT/agents/build.md` steps 2-3 (record RED/GREEN test evidence
via `temper evidence add --stage build --phase red|green`) as you implement each task,
then run `temper gate build --spec-path .temper/specs/{feature-slug}` before reporting
results — same reason as Plan/Review/Check: skipping this leaves `temper gate commit`
unable to see that build happened at all. Pass `--spec-path` explicitly rather than
relying on `temper state` having been initialized.
