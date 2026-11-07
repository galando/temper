---
description: "Plan a feature: starts /temper (Intent comes first), or takes up the active run"
argument-hint: "<feature-description-or-JIRA-123>"
---

# Plan

This command is a door into `/temper`: it starts a run at Plan, or takes up the run that is
active, and from there everything happens as `/temper` does it. There is one flow, and it is
`/temper:temper`. A door never has a flow of its own and never moves an active run.
With no run active, this starts a run for the feature, and its Intent stage comes first.

Invoke the Skill tool with the skill `temper:temper` and the arguments
`--enter plan $ARGUMENTS` ($ARGUMENTS is the feature to plan), and follow what it loads exactly. When
the Skill tool cannot run it, read `${CLAUDE_PLUGIN_ROOT}/commands/temper.md` and follow it
exactly with those arguments; wherever that file writes the plugin folder variable, use
`${CLAUDE_PLUGIN_ROOT}`.
