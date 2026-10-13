# ADR-0012: The CLI decides, the dialog asks, the mod shows

**Status:** Accepted
**Date:** 2026-10-13
**Supersedes:** the mod's own run state and its bar buttons (docs/mods-plan.md, sections 3.3 and 3.8)

## Context

The flow audit of PR #97 ran three rounds and found 27, 20 and 8 issues. The last round found two
serious bugs that the fixes of the round before had made. Almost every finding sat on one of three seams:

1. **Two sources of truth.** The CLI keeps the run (`build-state.json`, `gates.json`, `overrides.json`,
   `feedback-loops.json`). The mod kept its own event log, folded it into a second run state, and
   reconciled the two on every refresh. Design was part of Plan in the mod, Fix was Check in the CLI,
   Done came before `check_complete`, the CLI moved on by verdicts while the mod's record stayed behind,
   and an armed run looped back with no record at all. Each mapping needed its own repair.
2. **Decide, then mirror.** A mod runs no process, so a bar button could not run the CLI. A press wrote
   a decision, asked Claude to run the CLI, and the guard matched Claude's call to the decision. Every
   step could fail, and each failure needed its own machinery: pending moves, "press 1 to finish it",
   cooldowns, locks, voided steps back, looped decision lists, fingerprints.
3. **Two ways to decide.** Bar keys in full mode, the `Temper gate` dialog in every other setup, and
   typed `/temper:temper` words. Each gate existed twice, and the pages branched on the mode.

## Decision

1. **The CLI is the only run state.** The mod reads where the run is (`next_stage`), the verdicts, the
   skips, the loops and the groups from the `.temper` files, and keeps no run state of its own. There is
   no fold, no reconcile, no "looks reset", no Fix phase and no Design-in-Plan mapping: the mod's stages
   are the CLI's (intent, plan, design, build, review, check, commit).
2. **The CLI marks each step.** `state init` writes a `run_id` and `step: 0`. Every change of
   `next_stage` (`state advance`, `state loop`, a `state set next_stage` to another stage) adds one to
   `step`. A `state set next_stage` to the stage the run is already at changes nothing.
3. **Going back clears what is redone.** `state loop <from> <to>`, and a `state set next_stage` to an
   earlier stage, remove the verdicts of `<to>` and every later stage from `gates.json`, and move their
   skips from `overrides.json` to `.temper/archive/overrides-redone.json`. A skip of a stage no longer
   outlives the loop that redoes it, and every verdict in `gates.json` belongs to the current pass.
4. **The dialog is the one way to decide.** Every gate is an `AskUserQuestion` dialog with the header
   `Temper gate` (or `Temper resume` for Start over), in every setup: no mod, and the mod in every mode.
   Claude asks, the person clicks, and Claude runs the CLI in the same turn. The bar draws no decision
   buttons, the pane has no Fix or Accept buttons, and the typed decision words of `/temper:temper`
   lead to the same dialog.
5. **A decision belongs to one step.** The mod reads the person's answer from the dialog's result (only
   the result counts) and keeps it in its own store, stamped with the CLI's `run_id` and `step`. A move
   (approve, skip, step back, arm, save for later, keep the agent's commits, override and commit) counts
   only while the CLI is at that run and step, and the latest move at a step replaces the earlier ones.
   An accepted finding counts at its step for that finding. A Scope drift answer counts for the run and
   its path, and Allow once is used by one write. Start over counts until the next `state init`.
6. **The guard has three jobs**, and `core/bash.ts` is frozen (no new shell parsing):
   - a CLI call that only the person may cause needs the matching move at the current step: leaving
     Intent or Plan, a skip, a step back, accepting a finding, arming autonomy, keeping an agent's
     commits, clearing the run during a run. Every other advance follows the stage's own verdict (PASS,
     or a skip of the person), and an armed run loops back to Build by itself after a failed Review or
     Check;
   - Claude never writes Temper's own files (the run state, the config during a run, the git hooks, the
     plugin data folder that holds the decisions), and, while a run is active (the Commit stage
     included, and a `/temper:fix` run too), a commit never goes around the native hook: `--no-verify`,
     a changed hooks path, a git alias that runs a shell, a git command that runs a command of its own,
     git plumbing that makes or moves a commit, and a commit the hook does not check (a merge,
     cherry-pick, revert, am, pull, commit-tree, or a commit of named paths);
   - each stage allows its own writes (Intent: intent.md; Plan and Design: the spec files and decision
     records; Build: the files of the plan the person approved, tests and the person's Scope drift
     answers; Review and Check: the spec folder; Commit: anything). Save for later lifts no rule.

   The commit gate is the CLI's alone: the native pre-commit hook runs `temper gate commit`.
7. **The mod shows the run.** uiMode sets only how much is drawn. Full: the bar with the stage timeline,
   each verdict and skip, the stage's detail (groups and tasks in Build, findings in Review, the failed
   checks in Check, a "waiting for you" line at a gate) and the pane. Minimal: the stage timeline.
   Off: nothing. Every drawing is a plain function of the CLI's files.
8. **The standalone stage commands are doors.** `/temper:plan`, `/temper:build`, `/temper:check` and the
   other stage commands start or resume `/temper` at their stage instead of keeping their own copy of
   the gates (the orchestrator's section "Entering at a stage"). A door never moves a run: with a run
   active it takes it up where the CLI says; with none, a later door starts a run for the spec and asks
   each earlier gate in turn. ADR-0005's stage hook marks only `/temper:intent` now, since a door may end
   at any gate.

## Consequences

- A decision cannot outlive its step, so stale decisions, earlier runs, steps back that wait, voided
  steps and "decisions with enforcement off are never spent" need no code.
- A bar key press can no longer race with Claude's own turn: the person decides only when Claude asks.
- One press of a bar key is now one click in a dialog. A gate Claude forgets to ask is caught by the
  guard: the move is refused, and the refusal tells Claude to ask the `Temper gate` question.
- The orchestrator pages have one path for every setup, and a run with the mod reads the same as a run
  without it.
- A run state written before this change has no `run_id`: the CLI adds one (and `step`) on its next state
  call (ADR-0004's write through migration). A decision made before that call is asked again.
- The in-agent commit check is gone. The guarantee rests on the native hook, which `temper init`
  installs and which the guard keeps Claude from skipping.
- Later, not now: per task Build (`build.mode: per-task`) stays as the way back from grouped Build. Retire
  it once grouped Build has proven itself in real runs; that is its own decision.
