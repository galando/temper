---
description: "System design exploration for complex features"
argument-hint: "[--skip | --force]"
---

# Design: System Design Phase

**Goal:** Produce system design artifacts for complex/medium features.

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/reference/design.md`

### Subprocess Mode

If `$CLAUDE_PLUGIN_ROOT/scripts/temper config get stages.subprocess false` returns
`true`, don't run the methodology inline (skip the reference read and Quick Reference
below). Launch the same isolated subprocess `/temper` uses — model from `temper model
design`, prompt: *"Follow $CLAUDE_PLUGIN_ROOT/agents/design.md exactly. Spec:
.temper/specs/{feature-slug}. Standalone run — pass --spec-path
.temper/specs/{feature-slug} to every temper gate call."* Print the returned box
verbatim, then run `temper gate design --spec-path .temper/specs/{feature-slug}` and
present for approval (concerns first) — the subprocess is headless; the human gate
stays in this context either way.

### Quick Reference

1. Load intent.md + plan.md from active spec
2. Skip if complexity < medium or config disabled
3. Explore system architecture, API contracts, DB schema
4. Write design.md to spec directory — always including its Areas of Concern section
   (flagged conflicts with owners, or an explicit "None flagged — why")
5. Run `$CLAUDE_PLUGIN_ROOT/scripts/temper gate design` (checks that section exists);
   fix a FAIL before the gate
6. Present design summary for approval — flagged concerns first

### Active Skills

- **Context Engineering** — load hierarchical context at stage start (rules → arch → source → errors)
- **Temper Core** — stack detection, pack resolution, quality gates
