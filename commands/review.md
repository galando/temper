---
description: "Technical code review with confidence scoring, review memory, and intent validation"
---

# Review: Confidence-Scored Code Review

**Goal:** Review changes with parallel subagents, confidence scoring, and intent validation.

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/reference/review.md`

### Subprocess Mode

If `$CLAUDE_PLUGIN_ROOT/scripts/temper config get stages.subprocess false` returns
`true`, don't run the methodology inline (skip the reference read and Quick Reference
below). Launch the same isolated subprocess `/temper` uses — model from `temper model
review`, prompt: *"Follow $CLAUDE_PLUGIN_ROOT/agents/review.md exactly. Spec:
.temper/specs/{feature-slug}. Standalone run — pass --spec-path
.temper/specs/{feature-slug} to every temper gate call."* Print the returned box
verbatim, then run the gate + `AskUserQuestion` per **Deterministic Gate** below (the
subprocess already recorded each open finding as evidence) — the human gate stays in
this context either way.

### Quick Reference

1. Gather changed files + active pack rules + review memory
2. Launch parallel review subagents (backend/frontend/security)
3. Structured intent validation: mechanical checks (scenario/code) + deferred (metric/manual)
4. Filter by confidence threshold + review memory
5. Generate report to `.temper/reviews/`
6. Auto-fix high-priority issues (if enabled, max 2 loops)
7. Update metrics + review memory
8. Run `$CLAUDE_PLUGIN_ROOT/scripts/temper gate review --spec-path
   .temper/specs/{feature-slug}` and show its PASS/FAIL via `AskUserQuestion` — see
   **Deterministic Gate** below

### Active Skills

- **Context Engineering** — load hierarchical context at stage start (rules → arch → source → errors, under 2K lines/task)
- **Temper Core** — stack detection, pack resolution, quality gates

**Diff-aware: focuses on what changed, catches N+1 and performance issues**

### Deterministic Gate

This is the same gate the unified `/temper` command's Review stage runs — running this
command standalone must not skip it, or `temper gate commit` sees no review evidence and
wrongly blocks (or wrongly passes) a later commit. Follow
`$CLAUDE_PLUGIN_ROOT/agents/review.md` steps 2-3 (record each open finding via `temper
evidence add --stage review --severity ...`) as you review, then run
`$CLAUDE_PLUGIN_ROOT/scripts/temper gate review` and show its PASS/FAIL to the user via
`AskUserQuestion` (this command is not a subprocess — you own the gate here, unlike
`agents/review.md`'s "never show a gate" rule).

**Pass `--spec-path` explicitly** — a standalone command hasn't necessarily run `temper
state init`, so `temper state get spec_path` may be empty. Always call
`temper gate <stage> --spec-path .temper/specs/{feature-slug}` (the slug you already
resolved in step 1), don't rely on `temper state` having been initialized.
