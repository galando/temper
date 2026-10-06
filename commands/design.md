---
description: "System design exploration for complex features"
argument-hint: "[--skip | --force]"
---

# Design: System Design Phase

**Goal:** Produce system design artifacts for complex/medium features.

## Execution

> **Full methodology:** Read `${CLAUDE_PLUGIN_ROOT}/reference/design.md`

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
`${CLAUDE_PLUGIN_ROOT}/scripts/temper model design` prints, with this prompt: *"Follow
${CLAUDE_PLUGIN_ROOT}/agents/design.md exactly. Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with
/scripts/temper taken off); wherever the brief or a reference page writes the
CLAUDE_PLUGIN_ROOT variable, use this folder. Spec:
.temper/specs/{feature-slug}. Standalone run: pass --spec-path
.temper/specs/{feature-slug} to every gate call."* Print the returned box
verbatim, then run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate design --spec-path
.temper/specs/{feature-slug}` and
present for approval (concerns first) — the subprocess is headless; the human gate
stays in this context either way.

### Quick Reference

1. Load intent.md + plan.md from active spec
2. Skip if complexity < medium or config disabled
3. Explore system architecture, API contracts, DB schema
4. Write design.md to spec directory — always including its Areas of Concern section
   (flagged conflicts with owners, or an explicit "None flagged — why")
5. Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate design` (checks that section exists);
   fix a FAIL before the gate
6. Present design summary for approval — flagged concerns first

### Active Skills

- **Context Engineering** — load hierarchical context at stage start (rules → arch → source → errors)
- **Temper Core** — stack detection, pack resolution, quality gates
