---
description: "Execute plan with TDD and quality gates"
---

# Build: Execute Plan

**Goal:** Implement the approved plan in groups of small TDD tasks, with one human gate per group.

## Execution

> **The loop:** Read `${CLAUDE_PLUGIN_ROOT}/reference/build-groups.md` and run it. The method
> each task agent follows is `${CLAUDE_PLUGIN_ROOT}/agents/build-task.md`; the TDD methodology
> behind it is `${CLAUDE_PLUGIN_ROOT}/reference/build.md`.

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

### Before the loop

The loop needs the run state: when `${CLAUDE_PLUGIN_ROOT}/scripts/temper state get spec_path`
prints nothing, run `${CLAUDE_PLUGIN_ROOT}/scripts/temper state init {feature-slug}` first (the
spec folder `.temper/specs/{feature-slug}` holds the approved `tasks.md`). Verify the feature
branch (create it if on main). The task agents run in their own context whatever
`stages.subprocess` says; the human gates stay in this context.

### After the loop

Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate build` (the loop's step 8), report the group
panel, then auto-chain → `/temper:review` → `/temper:check` and ask to commit.

### Active Skills

- **Temper Core** — stack detection, pack resolution, quality gates
- **Context Engineering** — load hierarchical context at stage start (rules → arch → source → errors)
- **Source-Driven Development** — before writing framework-specific code: detect installed version → fetch current docs → cite sources → surface API conflicts. Skip for plain logic or known patterns

### Deterministic Gate

`${CLAUDE_PLUGIN_ROOT}/scripts/temper gate build` passes only with each task's RED then GREEN run
(recorded by the CLI's `temper task test`), no unchecked task in `tasks.md`, every group-gate
feedback answered, and `temper integrate` PASS. Run it before reporting results: without it
`${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit` cannot see that Build happened.
