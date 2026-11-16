# Build the plan in one pass: the brief for the build session

You are the session that builds `docs/plans/two-approval-run.md` in one pass, on one branch, as one pull request. The
owner will not review it stage by stage. What stands in for that review is a set of automated checks, written before
the code, that must all be green at the end. This page is your contract. Read it whole before you touch anything.

## 1. What you build, and what "done" means

The result is Temper 9.8.5: a run that asks twice (one approval before code, one at the commit), repairs a failure
in the stage where it happened, finds a fault at the earliest moment, writes less at the front, and shows a new user
two commands and about ten config lines. The number is the owner's (section 3, decision 7): in this kit "9.8.5"
always means this result, never the tree you start from.

Done means all of these, and nothing less:

1. Every check of `docs/plans/one-go/done.md` passes.
2. The list of checks still expected to fail is empty.
3. `bash scripts/verify.sh final` ends `verify final: PASS` on a fresh work tree of the pushed head, and CI on the
   pull request is green. Only the commit of the summary (item 6) comes after that run; it changes two files
   under `docs/history`, and `quick` holds it.
4. `docs/plans/one-go/PROGRESS.md` shows every work package as done, with its commit.
5. The pull request text carries the scorecard and says plainly what was not measured.
6. The summary of what happened, `docs/history/build-9.8.5.md`, is committed, opens the pull request text and is
   your last message to the owner. It says in plain words what was built, how each item of the plan was proven,
   and whether a run with a real model was made (WP32 writes it; rows `D107` and `D109` of `done.md`).

A row that needs the owner (`done.md` note 11), a bench line that ran and missed, a cap recorded as one that
cannot be met (note 5), a check recorded as wrong, whose line stays on the list (`done.md`, "How to read a red
row", item 6), and a package whose line says `blocked` are not yours to close: each is done when the pull request
text names it under "Not done". Spend no time bending a mechanism to reach one.

## 2. Start here

Follow `docs/plans/one-go/session-mechanics.md`: the first ten minutes, the layout of this folder, the format of
PROGRESS.md, the rhythm of commits and pushes, how to use workflows on this machine, and how to go on after a restart.
If PROGRESS.md already has finished packages, you are a restarted session: go on from the first package that is not
done. Never start over.

The files of this folder:

| File | What it holds |
|---|---|
| `README.md` | this brief: the decisions, the method, the order, the eleven rules |
| `session-mechanics.md` | the first ten minutes, the gate script, `PROGRESS.md`, the rhythm, the resume rule |
| `contracts.md` | the names every package must use, each with the package that creates it |
| `done.md` | every promise of the build and the automated check that proves it |
| `pr-115-fixes.md` | the decision for each defect of pull request #115 |
| `wp/*.md` | the specs of the work packages WP00 to WP32 |
| `evidence/` | the reports and prototypes the specs cite; removed by WP32 before its final gate |

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
   otherwise. If the owner's first message allows the bench, WP32 runs the model test and may change the planner's
   default below risk H by the rule of its spec. Build task agents default to Sonnet, with a key for Haiku.
5. **A small surface.** Defaults move into code. The config template shrinks to about 10 live lines. On the first run
   after the upgrade one question offers to remove config lines that only repeat old defaults. Two listed commands,
   `/temper:temper` and `/temper:fix`; `draft`, `status`, `report`, `init` and `pack` become words of
   `/temper:temper`; the doors go.
6. **The plugin directory stays a goal.** Every rule of `scripts/validate-directory.sh` holds, no tracked file is over
   256 KiB, and the mod makes no host call outside the reviewed list of `scripts/check-mod-calls.sh`.
7. **The version of the result is 9.8.5**, the number the owner chose. `main` is 9.8.4 (`7c7a1c1`), and that is
   what users have. The base (`10e965a`) already carries 9.8.5 in its manifest, in `.claude/CLAUDE.md`, in the
   README badge and as its first CHANGELOG entry, but pull request #115 was never merged, so no user ever had
   that 9.8.5. Four things follow:
   - **No bump and no tag.** WP31 runs no bump script. It checks every place that states the version and sets
     the one that is stale at the base: `docs/index.html:35` still says 9.8.4, and no check of the base reads
     it. No other version stamp moves.
   - **One CHANGELOG entry.** No package adds a version heading. WP01 puts the heading
     `## v9.8.5: a run that asks twice` in the place of the heading of the base (`CHANGELOG.md:6`), every package
     writes its lines under it, and WP31 gives the entry its final parts and folds in what stays of pull
     request #115.
   - **One meaning.** "9.8.5" means the result. What the build starts from is "the base (`10e965a`)" or "the head
     of pull request #115". The plan and the reports under `evidence/` were written before this decision: where
     they say 9.8.5 they mean the base.
   - **Users come from 9.8.4.** Every promise about an upgrade (a saved run, an old config, the installed commit
     hook, the one time question, the one time notice, what a user must know) is first about a project of 9.8.4
     and second about one that ran the base.
8. **Scope.** Releases 0 to 7 of the plan. Its "Later" list is out, except moving code out of `scripts/temper` and
   splitting `scripts/flow.py`, which come first because nothing else fits under the file limit. Neither move may
   change behaviour. Section 9 names what else is not built.
9. **Pull request #115 is the base, not a step.** Its head `10e965a` is merged into your branch, and this kit calls
   it the base. Its defects are fixed, removed or replaced inside this build, as
   `docs/plans/one-go/pr-115-fixes.md` says for each one.

## 4. How you work

- **Tests first, for the plan itself.** Phase 2 writes the checks of `done.md` before the changes that make them
  pass. A check that cannot pass yet goes on the expected to fail list (`scripts/selftest/expected-fail.txt`), which
  the gate reads: a listed check that fails is reported and not red; a listed check that passes is red until you take
  it off the list. You never skip, disable or weaken a check to get green, and you never loosen a gate of the product.
- **One gate script.** `bash scripts/verify.sh quick` (about 3 minutes: the validators, the changed selftest case
  files, the floor and the caps, the type check) ends every package. `bash scripts/verify.sh full` (the parallel
  selftest, the end to end suite in every mode, the mod's tests, every validator) ends every phase.
- **One package at a time in the flow core.** Each package has a spec (section 5). Do what its spec says, in its
  order: the tests first, then the mechanism, then the documents of the same change.
- **Names come from one page.** `docs/plans/one-go/contracts.md` holds every name that more than one package uses: a
  file, a CLI word, a state key, a question id, an option id, a gate row, a scenario, the number of a new selftest
  case file, the number of a decision record. Where a spec names a thing differently, the page wins. A package that
  needs a new shared name adds a line to it.
- **End every package with two commits and one push.** `bash scripts/verify.sh quick` is green. Then the package
  commit: the work, its tests and its documents, with the package id in the scope of the subject. Then the progress
  commit: only `docs/plans/one-go/PROGRESS.md`, with the line of the package set to `done` and the hash of the package
  commit, which a commit cannot name by itself. Then one push for both. WP00 and WP32 say where they differ.
  Checkpoints between them are allowed and pushed, and from WP08 on the whole selftest runs in the background
  before the progress commit (`session-mechanics.md` section 6).
- **End every phase the same way:** `bash scripts/verify.sh full` green, then an independent review of the phase's
  whole diff by agents that did not write it, against the specs and the eleven rules of section 6. Fix what they
  find before the next phase.
- **From WP18 to WP24 `temper evidence resolve` refuses every call.** WP18 makes the call take only a commit the CLI
  made after Review read the code, and no such commit exists until WP24 records its repair commit. This is meant: in
  between a finding ends by the person's accept, or by a loop back and a second Review. Do not loosen the check to
  get a test green; a test that needs a resolved finding uses the helper WP18 adds.
- **CI confirms, you do not wait for it.** Open the draft pull request when WP00 is pushed. When CI is red, find the
  cause and fix it in the next commit; a job gets one rerun at most.
- **One run with a real model, when it is allowed.** Every check of `done.md` but part H uses scripted agents. WP32
  makes one real run, in this order of preference: the bench, when the owner's first message allowed it; else the
  check `approval` of `scripts/e2e/live-smoke.sh`, when that message allowed model use and a nested `claude -p`
  answers (it proves the front half only); else none, and the summary says so in plain words (row `D109`).
- **The repository's own rules hold.** `.claude/CLAUDE.md` lists the known mistakes: gate logic lives in the CLI,
  never in a prompt; what comes next lives in the flow, never in a page; a brief never points an agent at an
  orchestrator file; hooks fail open. They apply to every package.
- **Do not build Temper with Temper.** No `/temper:temper` run in this repository during the build; the run you are
  rebuilding would stop you at every gate. Work as a plain session with workflows.
- **Read the evidence, and know which source wins.** Each spec names the reports it rests on. Where two sources
  disagree the later one wins: the red team reports (`red-*.md`) over the verifier reports (`v-*.md`) over the map
  reports; the plan and this brief over all of them; `contracts.md` over a spec on a name; `done.md` over a spec on
  what must hold.
- **When a spec is wrong.** A spec was written from a reading of the code at `10e965a`, and every `file:line` in the
  kit is of that commit; phase 1 moves code, so lines shift. Find the function by name. If a mechanism cannot work as
  written, choose the smallest change that still makes the package's checks pass, and write one line about it in
  PROGRESS.md. If a check of `done.md` itself is wrong, do not edit it silently: record the reason in PROGRESS.md and
  in the pull request text.
- **Write as the repository does.** Documents are plain prose: no hyphen or dash in prose (write "test first", "read
  only", "run again"), no contraction, no markdown link (a path in a code span), lines of at most 120 characters.
  Code spans and code blocks are free. A document changes in the same commit as the behaviour it describes.
- **When you are blocked.** Only two things need the owner: the word that the bench may run, with the access it
  runs on (section 10), and anything a host refuses. Write what you need in one line in PROGRESS.md, say it once
  in your reply, and go on with every package that does not depend on it. A cap or a floor you cannot meet is
  such a line too, with the measured number: you never raise a `final`.

## 5. The order

Build the packages in the order of the second table below, from the top. It is the one order in which every
"Depends on" of every spec is already built, and the table "Packages" of PROGRESS.md lists them in it.

| Phase | Packages, in build order | Spec file |
|---|---|---|
| 0 Setup and baseline | WP00 | `wp/phase-0-and-9-setup-and-final.md` |
| 1 Speed and room | WP01, WP02, WP03 | `wp/phase-1-speed-and-room.md` |
| 2 The definition of done | WP04, WP05, WP06, WP07 | `wp/phase-2-definition-of-done.md` |
| 3 The defects of pull request #115 | WP08 | `wp/phase-3-and-6-pr115-and-repairs.md` |
| 4 The flow | WP09, WP10, WP18, WP14, WP11, WP12, WP13 | `wp/phase-4a-flow-core.md`; WP18 is in `wp/phase-4b-cards-handback-fix.md` |
| 4 The flow, second half | WP15, WP16, WP17 | `wp/phase-4b-cards-handback-fix.md` |
| 5 The checks | WP19, WP20, WP21, WP22, WP23 | `wp/phase-5-checks.md` |
| 6 Repairs | WP24, WP25 | `wp/phase-3-and-6-pr115-and-repairs.md` |
| 7 The front | WP26, WP27 | `wp/phase-7-and-8-front-and-surface.md` |
| 8 The surface | WP28, WP29, WP30, WP31 | `wp/phase-7-and-8-front-and-surface.md` |
| 9 Final verification | WP32 | `wp/phase-0-and-9-setup-and-final.md` |

Why this order: phase 1 makes every later check fast and makes room under the file limit; phase 2 writes the
definition of done; phases 3 to 8 make it pass, from the flow outward; phase 9 proves the whole. Inside phase 4 the
two holes of WP18 close and the Design change of WP14 lands before WP11 changes the default: once the Review
question is gone, the Review gate is the only look at the change, and with Design in the run the option that starts
the unattended run would sit on a question no prototype ran.

| # | Package | What it builds | Depends on | How it runs | Evidence to read first |
|---|---|---|---|---|---|
| 1 | WP00 | Setup and baseline; it creates `PROGRESS.md` | none | serial, first | `session-mechanics.md` |
| 2 | WP01 | CI split and cancel, the gate script, fixtures one view a line, older changelog entries moved | WP00 | serial | `dev-efficiency.md`, `pr-tests-ci.md`, `red-feasibility.md` |
| 3 | WP02 | Code out of `scripts/temper` into Python modules | WP01 | serial | `cli-core.md`, `dev-efficiency.md` |
| 4 | WP03 | `scripts/flow.py` split into modules | WP01, WP02 | serial; `full` ends phase 1 | `dev-efficiency.md`, `flow-questions.md`, `flow-loops.md` |
| 5 | WP04 | Ids in the protocol | WP01, WP03 | serial | `v-mod-driver.md`, `dev-efficiency.md`, `v-failure-budget.md` |
| 6 | WP05 | The floor, the caps, faithful fixtures, the run summary | WP01, WP04 | serial | `v-targets-scorecard.md`, `red-feasibility.md` |
| 7 | WP06 | Two scripted projects: slow, and broken | WP04, WP05 | its five new files may be written beside WP05; merged after WP05 | `red-bad-runs.md`, `v-targets-scorecard.md`, `pr-env.md` |
| 8 | WP07 | The acceptance scenarios and the rule checks, failing first | WP04, WP05, WP06 | its new files may be written beside WP06, and its three rule case files beside each other; merged after WP06; `full` ends phase 2 | every `v-*.md` report, `red-safety.md`, the specs of the packages its rows name |
| 9 | WP08 | The defects of pull request #115 | WP01 to WP05, WP07 | serial; `full` ends phase 3 | `v-pr115.md`, and `pr-115-fixes.md` of this folder |
| 10 | WP09 | A verdict is a verdict for every carrier | WP02, WP03, WP04, WP07, WP08 | serial | `v-mod-driver.md`, `v-auto-advance.md` |
| 11 | WP10 | One budget in the CLI | WP02, WP03, WP04, WP07, WP08, WP09 | serial | `v-failure-budget.md` |
| 12 | WP18 | Two holes: `evidence resolve` checks its commit; Review names the files it read | WP02, WP03, WP04, WP07, WP10 | serial | `v-repair-in-place.md`, `red-safety.md` |
| 13 | WP14 | Design only when asked; design concerns as questions | WP03, WP04, WP07, WP08, WP10 | serial | `v-lean-front.md`, `v-auto-advance.md` |
| 14 | WP11 | The approval runs to the commit by default | WP04, WP07, WP08, WP09, WP10, WP14, WP18 | serial | `v-auto-advance.md`, `red-safety.md` |
| 15 | WP12 | The approval is bound to what was shown | WP02, WP04, WP07, WP11 | serial | `red-safety.md`, `v-one-approval.md` |
| 16 | WP13 | The run leaves Intent by rule; the approval accepts the intent | WP05, WP07, WP11, WP12, WP14 | serial; one more `full` after it | `v-one-approval.md` |
| 17 | WP15 | The cards: approval, commit, stop | WP03, WP04, WP05, WP10 to WP14 | serial | `v-one-approval.md`, `alt-person.md` |
| 18 | WP16 | Hand back kinds as a closed list | WP04, WP09, WP10, WP11, WP15 | serial | `v-mod-driver.md` |
| 19 | WP17 | `/temper:fix` asks twice; TRIVIAL as a verdict | WP05, WP09, WP10, WP11, WP12, WP15, WP16 | serial; `full` ends phase 4 | `flow-questions.md`, `review-check-commit.md`, `red-completeness.md` |
| 20 | WP19 | Checks judged against the project | WP02, WP03, WP04, WP06, WP08, WP11, WP15 | serial | `v-checks-once-early.md`, `red-bad-runs.md`, `ux-onboarding.md` |
| 21 | WP20 | Environment check, baseline, limits | WP04, WP06, WP08, WP10, WP11, WP13, WP15, WP19 | serial | `v-checks-once-early.md`, `red-bad-runs.md`, `pr-env.md` |
| 22 | WP21 | A plan command runs once on the base; the preflight goes | WP04, WP08, WP20 | serial | `pr-env.md`, `v-pr115.md`, `red-bad-runs.md` |
| 23 | WP22 | One digest, the reuse store, the flaky recheck | WP08, WP10, WP20, WP21 | serial | `v-checks-once-early.md` |
| 24 | WP23 | The checks run when Build ends; one failure record | WP09, WP10, WP11, WP16, WP17, WP19 to WP22 | serial; `full` ends phase 5 | `v-checks-once-early.md`, `v-failure-budget.md`, `red-bad-runs.md` |
| 25 | WP24 | A finding is repaired in its stage | WP08, WP09, WP10, WP11, WP15, WP16, WP18, WP22, WP23 | serial | `v-repair-in-place.md`, `red-safety.md` |
| 26 | WP25 | `plan amend`, `plan patch`, a replan that keeps | WP08, WP10, WP11, WP12, WP15, WP21, WP23, WP24 | serial; `full` ends phase 6 | `v-failure-budget.md`, `red-safety.md` |
| 27 | WP26 | Plan writes what something reads | WP02, WP03, WP05, WP07, WP13, WP14, WP15, WP21, WP23 | serial | `v-lean-front.md`, `agents-plan-side.md` |
| 28 | WP27 | The revise agent; criteria by the CLI; models by tier and risk | WP04, WP10, WP15, WP22, WP23, WP26 | serial; `full` ends phase 7 | `v-lean-front.md`, `v-targets-scorecard.md` |
| 29 | WP28 | Two listed commands; the doors go | WP05, WP07, WP13, WP16, WP17, WP26 | serial | `ux-onboarding.md` |
| 30 | WP29 | Defaults in code; the one time config question | WP04, WP08, WP10, WP11, WP13, WP14, WP19, WP21, WP27, WP28 | serial | `ux-onboarding.md`, `red-completeness.md` |
| 31 | WP30 | Packs, skills and dormant machinery removed | WP16, WP19, WP27, WP28, WP29 | serial; `full` after it | `ux-onboarding.md`, `changelog-older.md` |
| 32 | WP31 | Words, documents, the README of at most 80 lines, decision records, the one CHANGELOG entry, the check that every place says 9.8.5 (no bump; one stale line of `docs/index.html` set by hand) | WP01 to WP30 | steps 1 to 3 serial; then its pages may be split over agents, one page each; `full` ends phase 8 | `ux-onboarding.md`, `adr-constraints.md` |
| 33 | WP32 | Final verification, the review, a real run, the pull request text, the summary of what happened | WP01 to WP31 | serial; its reviewers run two at a time | `v-targets-scorecard.md`, `red-bad-runs.md` |

**What is serial.** Every package marked serial edits the flow modules, `scripts/temper`, `scripts/go.py`, the view
or the fixtures, and nearly all of them also edit `docs/flow.md`, `CHANGELOG.md`, `scripts/e2e/scenarios.ts`,
`scripts/e2e/floor.json` and `scripts/selftest/expected-fail.txt`. Their file lists overlap, so two of them never
run at once, in any work tree. That is every package but WP06 and WP07, and the merges of those two are serial too.

**What may run side by side**, because the files are disjoint from the package in the serial lane:

- The five new files of WP06 while WP05 is built, and the new files of WP07 while WP06 is built. Each is merged only
  after the package before it: WP06 and WP07 also edit `scripts/e2e/run.ts`, `scripts/e2e/floor.json` and
  `scripts/verify.sh`.
- The new selftest case file of the next package. `contracts.md` reserves its number, so a second agent may write the
  "Tests first" of the next package in a side work tree while the current one is built. The file is merged when the
  current package is done, and each case is seen failing before the change that makes it pass.
- The pages of WP31 after its steps 1 to 3: the README, Getting Started, the other documents, the decision records
  and the CHANGELOG are separate files.
- The reviewers at the end of a phase and in WP32. They change no file but a new check.

**How to read a spec.** Each has eleven parts, in this order: Goal, Depends on, Lane, Touches, Tests first,
Mechanism, Removed, Documents in the same change, Done when, Traps, Size. "Extended later by" in a "Depends on" line
names a later package that builds on this one; it is not a dependency. "Lane" says `flow core` or `side`; the table
above is what decides whether two packages may run at once.

The evidence behind every spec is in `docs/plans/one-go/evidence/`. Read the report a spec names before you build its
package. A prototype diff a spec names is under `evidence/prototypes/`. WP32 removes that folder in the commit
before its final gate; only the commit of the summary comes after it.

## 6. The eleven rules the result must keep

Each has at least one automated check in `done.md`. The phase reviews test every diff against them.

1. Before the approval a run writes only its spec folder and Temper's own run files (under `.temper/`, and one
   detached worktree for the baseline): no project file, no branch, no commit.
2. The approval is of what was shown; a later change to the intent or the plan fails the gates until approved again.
3. Only an option the person picked starts an unattended run; a step back, a skip or an accepted finding ends it.
4. An unattended run never plans again, changes a gate's command, the intent or the approved file set, skips a check,
   accepts a finding, answers a scope drift, writes the config, pushes, opens a pull request or makes the final
   commit.
5. Every verdict is computed by the CLI from runs the CLI made or the person confirmed, and names the tree it judged.
6. A failure's class picks the next step, never a verdict. A check that was not measured is shown as not measured.
7. Tests come first, and the tests that gate the code are written and locked by an agent that did not write it.
8. A finding is resolved only by the CLI, for a commit the CLI made, after its checks passed on that tree and a reader
   that did not write the fix confirmed it.
9. Every repeat is counted in the CLI against one budget (2 per failure, 6 per run); only the person grants more.
10. The person decides only in a question dialog, and the commit question lists everything a rule decided since the
    approval.
11. Each of these holds in the CLI or the commit hook with the mod off. Where only the mod holds something (that a
    person clicked), the docs say so.

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

One pull request to `main`, opened as a draft when WP00 is pushed and kept current. Its title is
`Temper 9.8.5: a run that asks twice`. Its text opens with the summary in short (parts 1, 2 and 6 of
`docs/history/build-9.8.5.md`, which WP32 writes last). Then it has: what a user sees
change; the scorecard table (dialogs, launches, repeats and suite runs of the scripted runs, before and after); the
list of tests changed on purpose, with the reason for each; what was not measured (cost and time, unless the bench
round ran; when it ran, the scorecard of all its arms and which planner the release ships with, and why); whether
a run with a real model was made, and what it showed; what a user of 9.8.4 must know, and in one line what
differs for a project that ran the head of pull request #115; the list of decisions of section 3; what section 9
says is not built; and the items of section 10. It says once that the release removes commands and changes the
default run, which a major version would usually mark, and that the owner chose the number 9.8.5.
Pull request #116 is the plan and this kit (branch `ccr-88156f39-u643ta`). The text says that it
supersedes #115 and #116, whose commits are inside it; closing them is left to the owner.

## 9. Not built in this pass

These are in the plan or beside it and are left out on purpose. Do not build them, also when a review asks for it;
write the wish under "Found on the way" in PROGRESS.md.

- **The acceptance writer beside the first builder** (the plan's item 5f). It needs a bench arm that shows it earns
  its place. The writer stays its own agent, alone and first; WP27 pins that order with a test.
- **One front launch** for a request that leaves nothing open (the plan's "Later" list). It buys under 30 seconds and
  changes a guard table.
- **One tree per chain:** a chain of tasks built in the group's one worktree ("Later"). Its gain is unmeasured.
- **The planner on a cheaper model** (the plan's items 1c and 5e). WP27 builds the table and the keys
  (`models.plan`, `models.high.plan`), and both columns keep Opus. The change is decided by the model test of
  WP32 when the owner's first message allows the bench; else it waits.
- The rest of the plan's "Later" list, and the spec route of ADR 0017.

One item of the plan is built only if the host allows it: the classic hook that holds the write rule before the
approval when the mod is not loaded (item 3e). It is one step of WP12, and that step says when to drop it. It
holds only for the stages Intent, Plan and Design of a feature run and only for the tools that write a file: a fix
run and a shell command are outside it, and `docs/trust.md` says so.

## 10. Items for the owner

The build session does none of these. WP31 and WP32 write them into PROGRESS.md and into the pull request text.

- **The two README videos.** They show a run that asks at every stage; WP31 takes the part "See it" out until they
  are recorded again.
- **The price figures.** The README of at most 80 lines has one line on cost and time, and no figure the
  scorecard does not hold: until a bench round ran, the line says where the earlier measurements are. Figures of
  the result come from `docs/evidence/scorecard-9.8.5.json`, and only when the bench round ran.
- **The bench.** The owner's first message is where the bench is allowed: one sentence that says it may run and
  on what access (a key in the session's environment, or the session's own model access). That sentence is also
  the word that about 110 to 125 dollars and 9 to 11 hours may be spent on the two rounds and the model test
  (`docs/plans/one-go/session-mechanics.md` section 9). Without it part H of `done.md` stays open and the pull
  request text says so. The one real Maven or Gradle project of row `D97` is the owner's to order. A first
  message that allows model use is also what lets WP32 run the check `approval` of the live smoke when the bench
  cannot run (row `D109`); with no such word the summary says that no run with a real model was made.
- **Closing pull requests #115 and #116.** Both are inside this one.
- **Marking the pull request ready,** merging it and pushing the tag.
- A branch rule that names the old CI checks (WP01 renames two), and any cap or floor the session recorded as one it
  could not meet: a cap is raised only in a pull request of its own.
