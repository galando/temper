---
description: "Execute plan with TDD and quality gates"
---

# Build: Execute Plan

**Goal:** Implement approved plan task by task with TDD and graduated quality gates.

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/reference/build.md`

### Subprocess Mode

If `$CLAUDE_PLUGIN_ROOT/scripts/temper config get stages.subprocess false` returns
`true`, don't run the methodology inline (skip the reference read and Quick Reference
below). Launch the same isolated subprocess `/temper` uses — model from `temper model
build`, prompt: *"Follow $CLAUDE_PLUGIN_ROOT/agents/build.md exactly. Spec:
.temper/specs/{feature-slug}. Standalone run — pass --spec-path
.temper/specs/{feature-slug} to every temper gate call."* Print the returned box
verbatim, then run the gate + report per **Deterministic Gate** below (the subprocess
already recorded the RED/GREEN evidence and ticked `tasks.md`); auto-chain to
`/temper:review` → `/temper:check` as usual — the human gate stays in this context
either way.

### Quick Reference

1. Load plan from `.temper/specs/{feature}/tasks.md`
2. Verify feature branch (create if on main)
3. For each task: test from intent.md scenario (RED) → implement (GREEN) → validate
4. Scenario coverage gate: every intent.md scenario must have a passing test
5. Success criteria gate: code-validated criteria must be present (WARN only)
6. **Resumes interrupted builds from checkpoint**
7. After all tasks: run `temper gate build --spec-path .temper/specs/{feature-slug}` —
   see **Deterministic Gate** below
8. Auto-chain → /temper:review → /temper:check
9. Report results, ask to commit

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
