# Build the plan in one pass: the brief for the build session

You are the session that builds `docs/plans/two-approval-run.md` in one pass, on one branch, as one pull request. The
owner will not review it stage by stage. What stands in for that review is a set of automated checks, written before
the code, that must all be green at the end. This page is your contract. Read it whole before you touch anything.

## 1. What you build, and what "done" means

The result is Temper 10.0.0: a run that asks twice (one approval before code, one at the commit), repairs a failure
in the stage where it happened, finds a fault at the earliest moment, writes less at the front, and shows a new user
two commands and about ten config lines.

Done means all of these, and nothing less:

1. Every check of `docs/plans/one-go/done.md` passes.
2. The list of checks still expected to fail is empty.
3. `bash scripts/verify.sh full` is green, and CI on the pull request is green.
4. `docs/plans/one-go/PROGRESS.md` shows every work package as done, with its commit.
5. The pull request text carries the scorecard and says plainly what was not measured.

## 2. Start here

Follow `docs/plans/one-go/session-mechanics.md`: the first ten minutes, the layout of this folder, the format of
PROGRESS.md, the rhythm of commits and pushes, how to use workflows on this machine, and how to go on after a restart.
If PROGRESS.md already has finished packages, you are a restarted session: go on from the first package that is not
done. Never start over.

## 3. The settled decisions

The owner settled these. Do not ask about them and do not reopen them.

1. **The default run asks twice.** One approval before code accepts the intent and the plan; one question at the
   commit. "Ask me at every stage" is the second option. One key, `run.default: to-commit | ask | never-unattended`;
   an existing `autonomy.enabled: false` means `ask`.
2. **What a rule may do after the approval.** It may move past a passed check, make one counted repair per failed
   check (a fix in the stage, committed by the CLI on the run's branch, with the checks run again), and add to a task
   a file the same group already owns. It may never plan again, change a gate's command, the intent or the approved
   file set, skip a check, accept a finding, answer a scope drift, write the config, push, open a pull request or make
   the final commit. A plan that touches a sensitive path (`autonomy.park-on-touch`) is risk H, is named in the
   approval, and nothing there is repaired by rule. A High or critical finding gets the one repair; a Medium one is
   listed at the commit question.
3. **Checks are judged against the project.** A missing coverage tool is "not measured", never failed and never
   passed. Coverage may not drop (changed lines where the data exists, else the total against the base). A time limit
   is three times the measured time on the base. The planted bug score is information.
4. **One route.** Design concerns are questions in front of the approval; the Design stage runs only when asked. The
   spec route of ADR 0017 is not built. The planner stays on Opus behind a config key until a bench round says
   otherwise. Build task agents default to Sonnet, with a key for Haiku.
5. **A small surface.** Defaults move into code. The config template shrinks to about 10 live lines. On the first run
   after the upgrade one question offers to remove config lines that only repeat old defaults. Two listed commands,
   `/temper:temper` and `/temper:fix`; `draft`, `status`, `report`, `init` and `pack` become words of
   `/temper:temper`; the doors go.
6. **The plugin directory stays a goal.** Every rule of `scripts/validate-directory.sh` holds, no tracked file is over
   256 KiB, and the mod makes no host call outside the reviewed list of `scripts/check-mod-calls.sh`.
7. **The version of the result is 10.0.0.**
8. **Scope.** Releases 0 to 7 of the plan. Its "Later" list is out, except moving code out of `scripts/temper` and
   splitting `scripts/flow.py`, which come first because nothing else fits under the file limit.
9. **Pull request #115 is the base, not a step.** Its head is merged into your branch. Its defects are fixed, removed
   or replaced inside this build, as `docs/plans/one-go/pr-115-fixes.md` says for each one.

## 4. How you work

- **Tests first, for the plan itself.** Phase 2 writes the checks of `done.md` before the changes that make them
  pass. A check that cannot pass yet goes on the expected to fail list, which the gate reads: a listed check that
  fails is reported and not red; a listed check that passes is red until you take it off the list. You never skip,
  disable or weaken a check to get green, and you never loosen a gate of the product.
- **One package at a time in the flow core.** Each package has a spec (section 5). Do what its spec says, in its
  order: the tests first, then the mechanism, then the documents of the same change.
- **End every package the same way:** `bash scripts/verify.sh quick` green, one commit, one push, one line in
  PROGRESS.md.
- **End every phase the same way:** `bash scripts/verify.sh full` green, then an independent review of the phase's
  whole diff by agents that did not write it, against the specs and the eleven rules of section 6. Fix what they
  find before the next phase.
- **CI confirms, you do not wait for it.** Open the draft pull request after phase 1. When CI is red, find the cause
  and fix it in the next commit; a job gets one rerun at most.
- **The repository's own rules hold.** `.claude/CLAUDE.md` lists the known mistakes: gate logic lives in the CLI,
  never in a prompt; what comes next lives in the flow, never in a page; a brief never points an agent at an
  orchestrator file; hooks fail open. They apply to every package.
- **Do not build Temper with Temper.** No `/temper:temper` run in this repository during the build; the run you are
  rebuilding would stop you at every gate. Work as a plain session with workflows.
- **When a spec is wrong.** A spec was written from a reading of the code at `10e965a`; phase 1 moves code, so lines
  shift. Find the function by name. If a mechanism cannot work as written, choose the smallest change that still
  makes the package's checks pass, and write one line about it in PROGRESS.md. If a check of `done.md` itself is
  wrong, do not edit it silently: record the reason in PROGRESS.md and in the pull request text.
- **When you are blocked.** Only two things need the owner: a credential for the bench round, and anything a host
  refuses. Write what you need in one line in PROGRESS.md, say it once in your reply, and go on with every package
  that does not depend on it.

## 5. The order

Phases run in this order. Inside a phase, packages run in the order listed unless a spec says two may run side by
side. The lane of each package is in its spec: `flow core` packages are serial; `side` packages may run in parallel
worktrees.

| Phase | Packages | Spec file |
|---|---|---|
| 0 Setup and baseline | WP00 | `wp/phase-0-and-9-setup-and-final.md` |
| 1 Speed and room | WP01, WP02, WP03 | `wp/phase-1-speed-and-room.md` |
| 2 The definition of done | WP04, WP05, WP06, WP07 | `wp/phase-2-definition-of-done.md` |
| 3 The defects of pull request #115 | WP08 | `wp/phase-3-and-6-pr115-and-repairs.md` |
| 4 The flow | WP09 to WP14 | `wp/phase-4a-flow-core.md` |
| 4 The flow, second half | WP15 to WP18 | `wp/phase-4b-cards-handback-fix.md` |
| 5 The checks | WP19 to WP23 | `wp/phase-5-checks.md` |
| 6 Repairs | WP24, WP25 | `wp/phase-3-and-6-pr115-and-repairs.md` |
| 7 The front | WP26, WP27 | `wp/phase-7-and-8-front-and-surface.md` |
| 8 The surface | WP28 to WP31 | `wp/phase-7-and-8-front-and-surface.md` |
| 9 Final verification | WP32 | `wp/phase-0-and-9-setup-and-final.md` |

Why this order: phase 1 makes every later check fast and makes room under the file limit; phase 2 writes the
definition of done; phases 3 to 8 make it pass, from the flow outward; phase 9 proves the whole.

The evidence behind every spec is in `docs/plans/one-go/evidence/`. Read the report a spec names before you build its
package. Remove that folder in the last commit of the build.

## 6. The eleven rules the result must keep

Each has at least one automated check in `done.md`. The phase reviews test every diff against them.

1. Before the approval a run writes only its spec folder and Temper's own run files (under `.temper/`, and one
   detached worktree for the baseline): no project file, no branch, no commit.
2. The approval is of what was shown; a later change to the intent or the plan fails the gates until approved again.
3. Only an option the person picked starts an unattended run; a step back, a skip or an accepted finding ends it.
4. An unattended run never plans again, changes a gate's command, the intent or the approved file set, skips a check,
   accepts a finding, writes the config, pushes, opens a pull request or makes the final commit.
5. Every verdict is computed by the CLI from runs the CLI made or the person confirmed, and names the tree it judged.
6. A failure's class picks the next step, never a verdict. A check that was not measured is shown as not measured.
7. Tests come first, and the tests that gate the code are written and locked by an agent that did not write it.
8. A finding is resolved only by the CLI, for a commit the CLI made, after its checks passed on that tree and a reader
   that did not write the fix confirmed it.
9. Every repeat is counted in the CLI against one budget (2 per failure, 6 per run); only the person grants more.
10. The person decides only in a question dialog, and the commit question lists everything a rule decided since the
    approval.
11. Each of these holds in the CLI or the commit hook with the mod off.

## 7. Models

- **You, the conductor:** the model the owner started the session on. Plan, order, merge and review yourself; hand
  the writing of a package to an agent with its spec.
- **Agents that change the flow core, the gates or the mod's guard, and every reviewer:** the same model as you. Do
  not send this work to a smaller model.
- **Agents for mechanical work** (moving code with no change of behaviour, turning test labels into ids, regenerating
  fixtures, rewriting documents to a given outline): a Sonnet class model is enough, and its work is checked by the
  gate, not by trust.
- **The product's own agents** (the briefs under `agents/`) keep the models the decisions of section 3 name.

## 8. The final pull request

One pull request to `main`, opened as a draft after phase 1 and kept current. Its text has: what a user sees change;
the scorecard table (dialogs, launches, repeats and suite runs of the scripted runs, before and after); the list of
tests changed on purpose, with the reason for each; what was not measured (cost and time, unless the bench round ran);
what a user of 9.8.5 must know; and the list of decisions of section 3. Pull requests #115 and #116 are inside it: say
so, and leave closing them to the owner.
