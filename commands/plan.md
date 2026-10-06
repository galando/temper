---
description: "Plan feature with impact analysis and blast radius"
argument-hint: "<feature-name-or-JIRA-123>"
---

# Plan a Feature

**Goal:** Transform feature request into implementation plan with impact analysis.

## Feature: $ARGUMENTS

## Execution

> **Full methodology:** Read `${CLAUDE_PLUGIN_ROOT}/reference/plan.md`

**Plugin folder:** the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that
path with /scripts/temper taken off). Wherever a reference page or a brief writes the
CLAUDE_PLUGIN_ROOT variable, use this folder.

### Subprocess Mode

If `${CLAUDE_PLUGIN_ROOT}/scripts/temper config get stages.subprocess false` returns
`true`, don't run the methodology inline (skip the reference read and Quick Reference
below). Launch the same isolated subprocess `/temper` uses, on the model that
`${CLAUDE_PLUGIN_ROOT}/scripts/temper model plan` prints, with this prompt: *"Follow
${CLAUDE_PLUGIN_ROOT}/agents/plan.md exactly. Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with
/scripts/temper taken off); wherever the brief or a reference page writes the
CLAUDE_PLUGIN_ROOT variable, use this folder. Feature:
$ARGUMENTS. Spec path: .temper/specs/{feature-slug}. Standalone run — no orchestrated
Intent stage ran: author intent.md yourself per ${CLAUDE_PLUGIN_ROOT}/reference/plan.md's standalone case,
and pass --spec-path .temper/specs/{feature-slug} to every temper gate call."* Print
the returned box verbatim, then run both gates + the approval `AskUserQuestion` per
**Deterministic Gate** below — the subprocess is headless and already recorded its
evidence; the human gate stays in this context either way.

### Quick Reference

1. Detect input (Jira/GitHub/description)
2. Explore with your own tools (a nested Explore subagent is a judgment call for large repos, not a mandatory step)
3. Re-read every `- consulted:` source the intent's `### Context Sources` records; treat every `- unavailable:` line as an explicit gap — do not re-derive context Intent already gathered
4. Cross-repo code search when a cross-repo search tool is connected (e.g. Sourcegraph MCP): blast radius outside this repo, prior art, definitions. None connected or `tools.mode: heuristic-only` → local tools. Record under `## Cross-Repo Search` in plan.md (`- used: {tool} — {query} → {finding}` / `- not available: {reason}`)
5. Assess complexity + risk (trivial/simple/medium/complex)
6. Blast radius analysis, measured not estimated (consumers, contracts, security hot paths; cross-repo rows carry `[CROSS-REPO]` + repo name)
7. Derive BDD scenarios from the blast radius (medium+ complexity) — **before architecture**. Each scenario is ONE fenced ```gherkin block holding the `Scenario:` line, Given/When/Then, `Note:` (unit|integration|mock|manual) and `Covers: AC-01, AC-02`; grouped under `#### Happy Path` / `#### Error Paths` / `#### Edge Cases`, empty groups omitted
8. Clarify if ambiguous (only where the uncertainty changes the outcome, informed by scenarios)
9. Generate exactly `intent.md` + `tasks.md` + `plan.md` — never a fourth file — to `.temper/specs/{feature}/` with file-to-scenario traceability
10. For Medium and Complex: generate mermaid diagram + ASCII art equivalent in plan.md (## Diagram section); render ASCII in terminal summary (not raw mermaid)
11. Record the tier with `${CLAUDE_PLUGIN_ROOT}/scripts/temper state set complexity <tier>`, then
    run BOTH gates with an explicit spec path and fix any FAIL, as **Deterministic Gate**
    below says: `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate intent --spec-path
    .temper/specs/{feature-slug}` (whenever intent.md exists, authored here or picked up
    as a draft) and `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate plan --spec-path
    .temper/specs/{feature-slug}`
12. Present for approval with 4 options: Continue / Walkthrough / Change / Save

### Active Skills

- **Context Engineering** — load hierarchical context at stage start (rules → arch → source → errors)
- **Temper Core** — stack detection, pack resolution, quality gates

**Scenarios drive architecture. Every file must trace to a scenario or infrastructure need.**

### Deterministic Gate

Record the tier with `${CLAUDE_PLUGIN_ROOT}/scripts/temper state set complexity <tier>`, then run
`${CLAUDE_PLUGIN_ROOT}/scripts/temper gate intent` and `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate plan`, each
with `--spec-path .temper/specs/{feature-slug}`, and fix any FAIL before presenting for
approval, for the same reason as Review/Check: skipping this
leaves `temper gate commit` unable to see that planning happened at all (it requires
an intent verdict whenever intent.md exists). The intent gate is standalone-only
here: in the orchestrated `/temper` flow the Intent stage already recorded it, which
is why the plan brief (`${CLAUDE_PLUGIN_ROOT}/agents/plan.md`) doesn't repeat it. Pass `--spec-path` explicitly rather than
relying on `temper state` having been initialized — the intent/design gates refuse to
run without a spec path.
