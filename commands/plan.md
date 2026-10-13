---
description: "Plan a feature: starts /temper, or takes up the active run, at Plan"
argument-hint: "<feature-description-or-JIRA-123>"
---

# Plan

This command is a door into `/temper`: it starts a run at Plan, or takes up the run that is
active, and from there everything happens as `/temper` does it. There is one flow, and it is
`${CLAUDE_PLUGIN_ROOT}/commands/temper.md`.

Read `${CLAUDE_PLUGIN_ROOT}/commands/temper.md` now and follow it exactly, entering at **Plan**
as its section "Entering at a stage" says, with `$ARGUMENTS` as the feature to plan. That file was not filled
in when you read it: wherever it writes the CLAUDE_PLUGIN_ROOT variable, use the folder that holds
${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off), and wherever it
writes the ARGUMENTS variable, use `$ARGUMENTS`. Its first instruction (the enforcement line)
applies here too.
