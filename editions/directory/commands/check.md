---
description: "Validate the changes: starts /temper, or takes up the active run, at Check"
argument-hint: "[<feature-slug>]"
---

# Check

This command is a door into `/temper`: it starts a run at Check, or takes up the run that is
active, and from there everything happens as `/temper` does it. There is one flow, and it is
`/temper:temper`. A door never has a flow of its own and never moves an active run.

Invoke the Skill tool with the skill `temper:temper` and the arguments
`--enter check $ARGUMENTS` ($ARGUMENTS is the spec folder's name), and follow what it loads exactly. When
the Skill tool cannot run it, read `${CLAUDE_PLUGIN_ROOT}/commands/temper.md` and follow it
exactly with those arguments; wherever that file writes the plugin folder variable, use
`${CLAUDE_PLUGIN_ROOT}`.
