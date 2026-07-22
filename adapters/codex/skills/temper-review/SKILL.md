---
name: temper-review
description: "Technical code review with confidence scoring, review memory, and intent validation"
---

<!--
  AUTO-GENERATED — do not hand-edit. Regenerate via the adapter generator script.
  Source: commands/review.md
  Plugin version: 7.0.1
  Tier: Tier 2 — Codex CLI native plugin (single-context, CLI-gated; no design/pack/eval — see adapters/codex/README.md)
  Upstream schema verified: 2026-07
-->

# Review: Confidence-Scored Code Review

**Goal:** Review changes with parallel focused inline passes, confidence scoring, and intent validation.

## Execution

> **Full methodology:** Read `reference/review.md`

### Quick Reference

1. Gather changed files + active pack rules + review memory
2. Launch parallel review focused inline passes (backend/frontend/security)
3. Structured intent validation: mechanical checks (scenario/code) + deferred (metric/manual)
4. Filter by confidence threshold + review memory
5. Generate report to `.temper/reviews/`
6. Auto-fix high-priority issues (if enabled, max 2 loops)
7. Update metrics + review memory

### Active Skills

- **Context Engineering** — load hierarchical context at stage start (rules → arch → source → errors, under 2K lines/task)
- **Temper Core** — stack detection, pack resolution, quality gates

**Diff-aware: focuses on what changed, catches N+1 and performance issues**

### Deterministic Gate

This is the same gate the unified `the Temper unified pipeline` command's Review stage runs — running this
command standalone must not skip it, or `temper gate commit` sees no review evidence and
wrongly blocks (or wrongly passes) a later commit. Follow
`agents/review.md` steps 2-3 (record each open finding via `temper
evidence add --stage review --severity ...`) as you review, then run
`scripts/temper gate review` and show its PASS/FAIL to the user via
`ask the user directly and wait for their answer` (this command is not a subprocess — you own the gate here, unlike
`agents/review.md`'s "never show a gate" rule).

**Pass `--spec-path` explicitly** — a standalone command hasn't necessarily run `temper
state init`, so `temper state get spec_path` may be empty. Always call
`temper gate <stage> --spec-path .temper/specs/{feature-slug}` (the slug you already
resolved in step 1), don't rely on `temper state` having been initialized.

## Gate Protocol (do not skip)

Record evidence for every claim as you work, then compute — never self-assert — the
verdict:

```
scripts/temper evidence add --stage review --claim "<what you're proving>" \
  --cmd "<the exact command you ran>" --exit <code> --label PROVEN
scripts/temper gate review
```

Paths above are relative to this plugin's own installed root (wherever the
marketplace source resolved this repo on disk), not necessarily your project's working
directory — resolve `scripts/temper` to that location if your shell's cwd differs.
