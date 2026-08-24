---
description: "Plan feature with impact analysis and blast radius"
argument-hint: "<feature-name-or-JIRA-123>"
---

# Plan a Feature

**Goal:** Transform feature request into implementation plan with impact analysis.

## Feature: $ARGUMENTS

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/reference/plan.md`

### Subprocess Mode

If `$CLAUDE_PLUGIN_ROOT/scripts/temper config get stages.subprocess false` returns
`true`, don't run the methodology inline (skip the reference read and Quick Reference
below). Launch the same isolated subprocess `/temper` uses — model from `temper model
plan`, prompt: *"Follow $CLAUDE_PLUGIN_ROOT/agents/plan.md exactly. Feature:
$ARGUMENTS. Spec path: .temper/specs/{feature-slug}. Standalone run — no orchestrated
Intent stage ran: author intent.md yourself per reference/plan.md's standalone case,
and pass --spec-path .temper/specs/{feature-slug} to every temper gate call."* Print
the returned box verbatim, then run both gates + the approval `AskUserQuestion` per
**Deterministic Gate** below — the subprocess is headless and already recorded its
evidence; the human gate stays in this context either way.

### Quick Reference

1. Detect input (Jira/GitHub/description)
2. Explore with your own tools (a nested Explore subagent is a judgment call for large repos, not a mandatory step)
3. Research external docs if needed
4. Assess complexity + risk (trivial/simple/medium/complex)
5. Blast radius analysis, measured not estimated (consumers, contracts, security hot paths)
6. Derive BDD scenarios from the blast radius (medium+ complexity) — **before architecture**
7. Clarify if ambiguous (max 2-3 questions, informed by scenarios)
8. Generate exactly `intent.md` + `tasks.md` + `plan.md` — never a fourth file — to `.temper/specs/{feature}/` with file-to-scenario traceability
9. For Medium and Complex: generate mermaid diagram + ASCII art equivalent in plan.md (## Diagram section); render ASCII in terminal summary (not raw mermaid)
10. Record `temper state set complexity <tier>`, then run BOTH gates with an explicit
    spec path and fix any FAIL — see **Deterministic Gate** below:
    `temper gate intent --spec-path .temper/specs/{feature-slug}` (whenever intent.md
    exists — authored here or picked up as a draft) and
    `temper gate plan --spec-path .temper/specs/{feature-slug}`
11. Present for approval with 4 options: Continue / Walkthrough / Change / Save

### Active Skills

- **Context Engineering** — load hierarchical context at stage start (rules → arch → source → errors, under 2K lines/task)
- **Temper Core** — stack detection, pack resolution, quality gates

**Scenarios drive architecture. Every file must trace to a scenario or infrastructure need.**

### Deterministic Gate

Record `temper state set complexity <tier>`, then run `temper gate intent` and
`temper gate plan`, each with `--spec-path .temper/specs/{feature-slug}`, and fix any
FAIL before presenting for approval — same reason as Review/Check: skipping this
leaves `temper gate commit` unable to see that planning happened at all (it requires
an intent verdict whenever intent.md exists). The intent gate is standalone-only
here: in the orchestrated `/temper` flow the Intent stage already recorded it, which
is why `agents/plan.md` doesn't repeat it. Pass `--spec-path` explicitly rather than
relying on `temper state` having been initialized — the intent/design gates refuse to
run without a spec path.
