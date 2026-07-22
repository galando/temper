---
name: temper-build
description: "Execute plan with TDD and quality gates"
---

<!--
  AUTO-GENERATED — do not hand-edit. Regenerate via the adapter generator script.
  Source: commands/build.md
  Plugin version: 7.0.1
  Tier: Tier 2 — Codex CLI native plugin (single-context, CLI-gated; no design/pack/eval — see adapters/codex/README.md)
  Upstream schema verified: 2026-07
-->

# Build: Execute Plan

**Goal:** Implement approved plan task by task with TDD and graduated quality gates.

## Execution

> **Full methodology:** Read `reference/build.md`

### Quick Reference

1. Load plan from `.temper/specs/{feature}/tasks.md`
2. Verify feature branch (create if on main)
3. For each task: test from intent.md scenario (RED) → implement (GREEN) → validate
4. Scenario coverage gate: every intent.md scenario must have a passing test
5. Success criteria gate: code-validated criteria must be present (WARN only)
6. **Resumes interrupted builds from checkpoint**
7. After all tasks: auto-chain → the Temper "review" stage → the Temper "check" stage
8. Report results, ask to commit

### Active Skills

- **Temper Core** — stack detection, pack resolution, quality gates
- **Context Engineering** — load hierarchical context at stage start (rules → arch → source → errors, under 2K lines/task)
- **Source-Driven Development** — before writing framework-specific code: detect installed version → fetch current docs → cite sources → surface API conflicts. Skip for plain logic or known patterns

### Deterministic Gate

Follow `agents/build.md` steps 2-3 (record RED/GREEN test evidence
via `temper evidence add --stage build --phase red|green`) as you implement each task,
then run `temper gate build --spec-path .temper/specs/{feature-slug}` before reporting
results — same reason as Plan/Review/Check: skipping this leaves `temper gate commit`
unable to see that build happened at all. Pass `--spec-path` explicitly rather than
relying on `temper state` having been initialized.

## Gate Protocol (do not skip)

Record evidence for every claim as you work, then compute — never self-assert — the
verdict:

```
scripts/temper evidence add --stage build --claim "<what you're proving>" \
  --cmd "<the exact command you ran>" --exit <code> --label PROVEN
scripts/temper gate build
```

Paths above are relative to this plugin's own installed root (wherever the
marketplace source resolved this repo on disk), not necessarily your project's working
directory — resolve `scripts/temper` to that location if your shell's cwd differs.
