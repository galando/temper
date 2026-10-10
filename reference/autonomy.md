---
description: "Autonomous Continuation mechanics for the /temper orchestrator"
---

# Autonomous Continuation

Read by the `/temper` orchestrator (`${CLAUDE_PLUGIN_ROOT}/commands/temper.md`) **only when
`autonomy.enabled: true`** — with the block absent or false (the default), the
orchestrator never loads this file and every gate is the ordinary interactive one. The
temper CLI is `${CLAUDE_PLUGIN_ROOT}/scripts/temper`; every other path here is in the
user's project.

Opt-in, armed by the human at the **plan gate only** — never at invocation or mid-run.
The Intent gate is always interactive: no unattended run starts without a human having
accepted the intent.

**Arming** (at the plan gate, on PASS, after human review): replace "Continue to Build"
with "Stage by stage (Recommended)" (`run_mode: interactive`) / "Autonomous — run the
rest unattended" (`run_mode: autonomous`).

**While `run_mode == autonomous`, every post-plan gate:** run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate {stage}` as
usual. **PASS** → auto-select Continue, no `AskUserQuestion` (but still print the summary
box — an unattended run must leave a scroll-back-readable record). **FAIL** → loop
automatically at the same budget as interactive mode, except Build→Plan (always returns
to a human, never auto-loops); budget exhausted → park instead of asking. **At commit:**
`${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit` already checks blast radius + park-on-touch (autonomous-only) along
with every upstream gate — PASS or FAIL, **always park**, autonomy never makes the final feature commit.

**Narrowed invariant (grouped Build, design Resolution 1):** autonomy never pushes, never
merges to a remote, never re-plans unattended and never makes the final feature commit; it
always parks. It does allow the two local, CLI-made writes of grouped Build: the task
commits of a task's declared files on its `temper/{slug}/{G}` group branch (`temper task
gate`) and the local `temper integrate` merge into the feature branch. Nothing else commits.

**Groups (`build.mode: grouped`):** each group's gate (`temper group gate G`) auto-continues
on PASS, with no `AskUserQuestion`; the group panel still prints. **Change** (`temper group
reopen`) and **Stop** stay interactive-only. A parked group (a task failed its Haiku retry
and the Sonnet escalation) parks the run once no other group is ready; independent groups
finish first. An `integrate` FAIL parks the run before Review. `autonomy.max-blast-radius`
bounds each single group's declared files (the plan gate rejects a larger group; Plan
splits it), and the commit gate parks when files changed outside the union of declared
files; it is no longer compared with the feature total.

**The user is not watching.** You are operating autonomously. The user is not watching
in real time and cannot answer questions mid-task, so asking 'Want me to...?' or
'Shall I...?' will block the work. For reversible actions that follow from the approved
plan, proceed without asking; the only stop is a park. Before ending your turn, check
your last paragraph: if it is a plan, a question, or a promise about work you have not
done, do that work now with tool calls. End your turn only at a park, or when the run
is blocked on input only a human can give.

**Park:** `${CLAUDE_PLUGIN_ROOT}/scripts/temper state set run_mode interactive` (so a plain resume lands here
normally), write `.temper/autonomy-report.md` (`**Verdict:**
SHIP-PENDING-COMMIT|PARKED-NEEDS-DECISION`, `**Parked at:**`/`**Reason:**` verbatim from
`${CLAUDE_PLUGIN_ROOT}/scripts/temper gate`, `**Branch:**`, the `${CLAUDE_PLUGIN_ROOT}/scripts/temper report` ledger, "Run /temper to resume").

**Operational safety (hardcoded — see `${CLAUDE_PLUGIN_ROOT}/templates/temper.config.default`):** refuse a
dirty tree unless confirmed; `git commit -m "wip: {stage} passed"` after each PASS stage
(a crash loses at most one stage); `.temper/autonomy.lock` refuses a second concurrent run.
