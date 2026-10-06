---
description: "Execute plan with TDD and quality gates"
---

# Build: Execute Plan

**Goal:** Implement approved plan task by task with TDD and graduated quality gates.

## Execution

> **Full methodology:** Read `${CLAUDE_PLUGIN_ROOT}/reference/build.md`

**Plugin folder:** the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that
path with /scripts/temper taken off). Wherever a reference page or a brief writes the
CLAUDE_PLUGIN_ROOT variable, use this folder.

### Subprocess Mode

If `${CLAUDE_PLUGIN_ROOT}/scripts/temper config get stages.subprocess false` returns
`true`, don't run the methodology inline (skip the reference read and Quick Reference
below). Launch the same isolated subprocess `/temper` uses, on the model that
`${CLAUDE_PLUGIN_ROOT}/scripts/temper model build` prints, with this prompt: *"Follow
${CLAUDE_PLUGIN_ROOT}/agents/build.md exactly. Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with
/scripts/temper taken off); wherever the brief or a reference page writes the
CLAUDE_PLUGIN_ROOT variable, use this folder. Spec:
.temper/specs/{feature-slug}. Standalone run: pass --spec-path
.temper/specs/{feature-slug} to every temper gate call."* Print the returned box
verbatim, then run the gate + report per **Deterministic Gate** below (the subprocess
already recorded the RED/GREEN evidence and ticked `tasks.md`); auto-chain to
`/temper:review` → `/temper:check` as usual — the human gate stays in this context
either way.

### Quick Reference

1. Load plan from `.temper/specs/{feature}/tasks.md`
2. Verify feature branch (create if on main)
3. For each task: cross-repo code search first when a search tool is connected (definitions, prior art; record `"code_search"` in build-context.json — `{"tool": "{name}", "queries": N}` or `{"available": false, "reason": "{why}"}`), then test from intent.md scenario (RED) → implement (GREEN) → validate
4. Commit per GREEN scenario: `git add {paths touched}` then a SEPARATE
   `git commit -m "feat({slug}): {scenario} [AC-NN]"` — never `git add -A`, never
   `--no-verify`; an infrastructure-only task makes no commit
5. Scenario coverage gate: every intent.md scenario must have a passing test
6. Success criteria gate: code-validated criteria must be present (WARN only)
7. **Resumes interrupted builds from checkpoint** (disk state in tasks.md is the source of truth; with a `Checkpoint: task {N}` launch, answer every pending feedback item via `--phase feedback-resolved` first, then run only task N)
8. After all tasks: run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate build --spec-path
   .temper/specs/{feature-slug}`, as **Deterministic Gate** below says
9. Auto-chain → /temper:review → /temper:check
10. Report results, ask to commit

### Active Skills

- **Temper Core** — stack detection, pack resolution, quality gates
- **Context Engineering** — load hierarchical context at stage start (rules → arch → source → errors)
- **Source-Driven Development** — before writing framework-specific code: detect installed version → fetch current docs → cite sources → surface API conflicts. Skip for plain logic or known patterns

### Deterministic Gate

Follow `${CLAUDE_PLUGIN_ROOT}/agents/build.md` steps 2-3 (record RED/GREEN test evidence
with `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence add --stage build --phase red|green`) as you implement
each task, then run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate build --spec-path
.temper/specs/{feature-slug}` before reporting results, for the same reason as
Plan/Review/Check: skipping this leaves `temper gate commit` unable to see that build
happened at all. Pass `--spec-path` explicitly rather than
relying on `temper state` having been initialized.
