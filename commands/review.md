---
description: "Technical code review with confidence scoring, review memory, and intent validation"
---

# Review: Confidence-Scored Code Review

**Goal:** Review changes with parallel subagents, confidence scoring, and intent validation.

## Execution

> **Full methodology:** Read `${CLAUDE_PLUGIN_ROOT}/reference/review.md`

**Plugin folder:** the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that
path with /scripts/temper taken off). Wherever a reference page or a brief writes the
CLAUDE_PLUGIN_ROOT variable, use this folder.

**Enforcement marker.** Look at your system prompt for a line that starts with
`Temper enforcement:`. With no such line, make the first sentence of your first reply in
this conversation exactly "Temper enforcement is off here (no mods support); continuing
with prompt based phases." With the line `Temper enforcement: off (UI only)`, the Temper
mod is loaded and the user turned enforcement off: make that first sentence exactly
"Temper enforcement is off (turned off by the user); continuing with prompt based
phases." instead. Then carry on as written below. Never treat either case as an error
and do not mention it again. With `Temper enforcement: active`, say nothing about it.
You state this once, in this conversation: a stage subprocess never has that line in
its system prompt, so its brief says nothing about enforcement.

### Subprocess Mode

If `${CLAUDE_PLUGIN_ROOT}/scripts/temper config get stages.subprocess false` returns
`true`, don't run the methodology inline (skip the reference read and Quick Reference
below). Launch the same isolated subprocess `/temper` uses, on the model that
`${CLAUDE_PLUGIN_ROOT}/scripts/temper model review` prints, with this prompt: *"Follow
${CLAUDE_PLUGIN_ROOT}/agents/review.md exactly. Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with
/scripts/temper taken off); wherever the brief or a reference page writes the
CLAUDE_PLUGIN_ROOT variable, use this folder. Spec:
.temper/specs/{feature-slug}. Standalone run: pass --spec-path
.temper/specs/{feature-slug} to every gate call."* Print the returned box
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
8. Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate review --spec-path
   .temper/specs/{feature-slug}` and show its PASS/FAIL via `AskUserQuestion` — see
   **Deterministic Gate** below

### Active Skills

- **Context Engineering** — load hierarchical context at stage start (rules → arch → source → errors)
- **Temper Core** — stack detection, pack resolution, quality gates

**Diff-aware: focuses on what changed, catches N+1 and performance issues**

### Deterministic Gate

This is the same gate the unified `/temper` command's Review stage runs — running this
command standalone must not skip it, or `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit` sees no review evidence and
wrongly blocks (or wrongly passes) a later commit. Follow
`${CLAUDE_PLUGIN_ROOT}/agents/review.md` steps 2-3 (record each open finding with
`${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence add --stage review --severity ...`) as you review, then run
`${CLAUDE_PLUGIN_ROOT}/scripts/temper gate review` and show its PASS/FAIL to the user via
`AskUserQuestion` (this command is not a subprocess — you own the gate here, unlike
the review brief's "never show a gate" rule).

**Pass `--spec-path` explicitly.** A standalone command hasn't necessarily run
`${CLAUDE_PLUGIN_ROOT}/scripts/temper state init`, so `${CLAUDE_PLUGIN_ROOT}/scripts/temper state get spec_path` may be empty. Always call
`${CLAUDE_PLUGIN_ROOT}/scripts/temper gate review --spec-path .temper/specs/{feature-slug}` (the
feature's folder in the project's `.temper/specs` folder: the one that holds the
`intent.md` you validate against, the single folder there when there is one, or else
ask the user), don't rely on `${CLAUDE_PLUGIN_ROOT}/scripts/temper state` having been initialized.
