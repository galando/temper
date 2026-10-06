---
description: "Run stack-aware validation pipeline"
---

# Check: Validation Pipeline

**Goal:** Auto-detect stack and run validation levels in order.

## Execution

> **Full methodology:** Read `${CLAUDE_PLUGIN_ROOT}/reference/check.md`

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
`${CLAUDE_PLUGIN_ROOT}/scripts/temper model check` prints, with this prompt: *"Follow
${CLAUDE_PLUGIN_ROOT}/agents/check.md exactly. Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with
/scripts/temper taken off); wherever the brief or a reference page writes the
CLAUDE_PLUGIN_ROOT variable, use this folder. Spec:
.temper/specs/{feature-slug}. Standalone run: pass --spec-path
.temper/specs/{feature-slug} to every gate call."* Print the returned box
verbatim, then run the gate + `AskUserQuestion` per **Deterministic Gate** below (the
subprocess already recorded test/coverage/scenario evidence) — the human gate stays in
this context either way.

### Quick Reference

Levels (stop on failure):
0. Environment: stop when `check.environment` in temper.config is `production`, or,
   with it unset, when the project holds a `.env.production` or `.env.prod` file.
   Decide from that key and the file names only; never open a `.env` file.

1. Compile/Build
2. Unit Tests
3. Integration Tests (if configured)
4. Coverage (threshold from config)
5. Lint/Format
6. Type Check
7. Security (dependency scan)
8. Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate check --spec-path
   .temper/specs/{feature-slug}` and show its PASS/FAIL via `AskUserQuestion` — see
   **Deterministic Gate** below

### Active Skills

- **Context Engineering** — load hierarchical context at stage start (rules → arch → source → errors)
- **Temper Core** — stack detection, pack resolution, quality gates

### Deterministic Gate

This is the same gate the unified `/temper` command's Check stage runs — running this
command standalone must not skip it, or `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit` sees no check evidence and
wrongly blocks (or wrongly passes) a later commit. Follow
`${CLAUDE_PLUGIN_ROOT}/agents/check.md` steps 2-3 (record test/coverage evidence, and
trace every `intent.md` scenario to a test with `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence add
--scenario`) as you validate, then run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate check` and show its
PASS/FAIL to the user via `AskUserQuestion` (this command is not a subprocess — you own
the gate here, unlike the check brief's "never show a gate" rule).

**Pass `--spec-path` explicitly.** A standalone command hasn't necessarily run
`${CLAUDE_PLUGIN_ROOT}/scripts/temper state init`, so `${CLAUDE_PLUGIN_ROOT}/scripts/temper state get spec_path` may be empty, which silently skips the
scenario-tracing requirement (it can't find `intent.md`) instead of failing loudly.
Always call `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate check --spec-path .temper/specs/{feature-slug}`.
