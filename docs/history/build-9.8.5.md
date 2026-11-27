---
description: "The one pass build of Temper 9.8.5 from the unmerged pull request #115: what changed and what is left"
nav_exclude: true
---

# The build of Temper 9.8.5

For the owner. 9.8.5 is the result; the build started from the unmerged pull request #115 (`10e965a`); users have
9.8.4 (`7c7a1c1`). The audit after the build, and the outcome of each finding: `docs/history/audit-9.8.5.md`.

## In five lines

1. A feature run asks twice: one approval of intent and plan before any code, and one question at the commit.
2. Between them a passed check moves on, a failed one gets one repair in its stage; repeats: 2 a failure, 6 a run.
3. A bug run (`/temper:fix`) asks twice too: the root cause with its fix, and the commit. Two commands are listed.
4. Tools, services and the suite are checked once before the change, and every verdict names the tree it judged.
5. Defaults live in code, the config template has 21 lines, and stack packs, three skills and unread machinery are gone.

## The numbers, before and after

| The number | Before | After | Where it comes from |
|---|---|---|---|
| Dialogs of a clean feature run (`default-run`, all three modes) | 8 (first count at `fbc75ec`; the file does not exist at `10e965a`) | 2 | a scripted run |
| Dialogs of a clean bug run (`fix`) | 4 (first count at `fbc75ec`; the file does not exist at `10e965a`) | 2 | a scripted run |
| Dialogs of a run with one repaired High finding (`repair-finding`) | not measured (a scenario new in this build; the file does not exist at `10e965a`) | 2 | a scripted run |
| The bound on repeats | 2 a kind of loop back (`loops.max-per-type` in the config template of `10e965a`) | 2 for one failure, 6 for one run, then the person decides (`scripts/defaults.py`) | a scripted run (`budget-stop`) |
| Agent launches of a clean feature run | 6 (first count at `fbc75ec`; the file does not exist at `10e965a`) | 6 | a scripted run |
| Whole suite runs on the slow scripted project (`slow-first-run`) | not measured (a scenario new in this build; the file does not exist at `10e965a`) | 2, under a bound of 3 | a scripted run |
| Questions in the replay of the measured bad run | 9.8.4: 10; pull request #115: 9 | 3 | the replay |
| Agent launches in the replay | 9.8.4: 10; pull request #115: 7 | 7 | the replay |
| Agent minutes in the replay (an estimate) | 9.8.4: 191; pull request #115: 92 | 92 | the replay |
| The High defect in the commit of the replay | 9.8.4: yes; pull request #115: no | no | the replay |
| Cost a run in dollars, mean of 18 runs | pull request #115: 2.44; plain Claude Code: 0.39 | 1.30 | the bench |
| Seconds a run, mean of 18 runs | pull request #115: 545; plain Claude Code: 71 | 358 | the bench |
| Cost and time against plain Claude Code, by kind of task | not measured as a ratio | a bug 1.681 and 3.226 times; a clear feature 4.007 and 5.916; a vague one 3.63 and 5.011 | the bench |
| Share of hidden tests passed | pull request #115: 0.906; plain Claude Code: 0.948 | 1.0 | the bench |

Scripted counts: `scripts/e2e/floor.json`, which does not exist at `10e965a`; its first version (`fbc75ec`) counted
pull request #115. The replay: `docs/evidence/ab-replay-9.8.5.md`. The bench: `docs/evidence/scorecard-9.8.5.json`.

## The plan, item by item

Every item of releases 0 to 7 of `docs/plans/two-approval-run.md`. The state is read from the progress file of the
build and from `python3 -B scripts/check_done.py --final`: of the 109 promises of the definition of done, 94 hold
by their check, 15 need a person or a model, and none fails.

| Item | In a few words | State | The check that proves it, or the reason |
|---|---|---|---|
| 0a | CI in shards, old runs cancelled, smaller files | built and proven | A selftest reads the CI workflow: a newer push cancels the older run, six shards cover every case file once, and one gate job ends it. The wall times are read off the pull request (part 7) |
| 0b | The defects of pull request #115 fixed; one line kept per finished run | built and proven | One case for each of the 16 defects of pull request #115 and each of its four flipped defaults shows it gone; a case checks that a finished run leaves its line and that clearing the state keeps it. The 29 smaller points are a list for the owner |
| 1a | CI in about 10 minutes | built and proven | The same reading of the workflow as 0a. Whether the median stays under 12 minutes is read off the pull request (part 7) |
| 1b | A scorecard in `bench/` and two scripted projects, slow and broken | built and proven | The slow project passes Check on correct code with no config edit; the broken one names every fault before Build; the scorecard has its own test on made up runs. Real runs: the bench (part 8) |
| 1c | The before round and the model test | built and not proven | Both ran: 36 runs of pull request #115 and plain Claude Code, 18 with the planner on Sonnet. Their checks need a model, so no check in the tree runs them again; the planner stays on Opus |
| 1d | Coverage judged against the project | built and proven | The slow project at 55% before and after passes, and a drop fails with a row that names it; a coverage that was not measured is shown as not measured and never passes a gate |
| 1e | Defaults in code, a short template, the one time question | built and proven | Cases run the templates of 9.8.4 and of pull request #115 with no error, check that every key has a reader, ask the one time question once with a copy kept, and read `autonomy.enabled: false` as ask |
| 1f | An id for each question and option | built and proven | A case checks that every dialog the CLI writes carries ids beside it, never inside; the mod still reads a view of pull request #115, which has no ids |
| 1g | Counts and size limits compared in CI | built and proven | CI compares the scripted counts and the size limits exactly; on 2026-11-27 the owner raised three targets to the measure of the release: distinct gate rows 81 (from 55), option labels 83 (71), question ids 38 (35) |
| 2a | A verdict marked the same for every carrier | built and proven | A scripted run with a failed `integrate`, under the mod's run driver, reaches its question with no hand back to the conversation |
| 2b | One budget of repeats | built and proven | A scripted run launches no third agent for one failure; cases refuse a third repeat of one failure and a seventh of one run, and write nothing |
| 2c | Design runs only when asked | built and proven | A scripted default run launches no Design agent at any tier or risk, and the approval offers it |
| 2d | The Context check only when the map flags something | built and proven | A clean feature run asks 2 dialogs in all three modes; a flagged map is shown whole in the approval and still costs 2 |
| 2e | The approval runs to the commit | built and proven | Cases: no question follows a passed check before the commit, Ask me at every stage keeps every gate's question, only the person's option starts the run, and such a run never plans again, pushes or makes the final commit. That a person and not the model clicked only the mod holds |
| 2f | The approval bound to what was shown | built and proven | Before the approval a scripted run leaves no project file, branch or commit; a case changes a criterion after the question was built and the approving calls are refused |
| 2g | The run leaves Intent by rule; the approval accepts the intent | built and proven | A clean run asks 2 dialogs with no Intent question; a vague run asks one more for every four rules it left open |
| 2h | Two holes closed | built and proven | A case resolves a finding with a note in the place of a commit and is refused; a Review that names fewer files than the change fails its row |
| 3a | The cards on the approval, the commit and a stop | built and proven | Cases compare the cards in the view and in the CLI's text, the same with and without the mod. Nobody timed a reader |
| 3b | Hand backs a closed list of 7 kinds | built and proven | The count of kinds is compared exactly; a mod test ends each former cause as a question or a saved stop; a failed group check hands nothing back; the mod's three live defects are gone |
| 3c | `/temper:fix` asks twice | built and proven | A scripted bug run asks the root cause question and then the commit, with Review started beside the checks |
| 3d | TRIVIAL a verdict the CLI records | built and proven | After a trivial exit a case makes a commit larger than the size bound and the hook refuses it |
| 3e | A classic hook holds the write rule without the mod | built and proven | A scripted run with the mod off writes nothing but its spec folder before the approval, and `docs/trust.md` says the hook covers only Intent, Plan and Design of a feature run and file writing tools |
| 4a | The acceptance tests run when Build ends | built and proven | A scripted run with a wrong acceptance test gets the triage first, and no fix agent changes code for it; a case changes a locked test and the Build gate fails |
| 4b | A finding repaired in its stage | built and proven | A scripted run repairs one High finding with no dialog: one Review, one fix agent, one narrow recheck, and the commit card lists the repair. A real fix agent may not mend the finding; then the run asks |
| 4c | What is never repaired by rule | built and proven | For each of the eight cases a run that goes on by itself stops at a question and opens no repair |
| 4d | The plan row for a group with no Validate | built and proven | Cases: the plan gate fails such a group, `plan patch` adds the line, and an amendment by rule adds only a file the group owns |
| 5a | At the simple tier Plan writes `tasks.md` only | built and proven | The plan gate passes with `tasks.md` alone, and a simple tier with two groups, four production files or risk H fails |
| 5b | Plan writes only what something reads | built and proven | A case finds the cut sections gone from the briefs and templates. That every section left has a reader is not checked |
| 5c | A narrow revise agent | built and proven | A scripted revision launches the narrow agent with the note and the task blocks, not a full planner pass |
| 5d | Design folded into Plan | built and proven | Design concerns are questions at the approval; at risk H the run to the commit is offered only after a clean fresh review round |
| 5e | The planner's model by tier and risk | built and proven | A case reads the model table: build task agents on Sonnet, the planner on Opus behind a key. The cheaper planner itself was decided by the model test, which kept Opus |
| 5f | The acceptance writer beside the first builder | not built | Left out by the brief of the build: it needs a bench arm of its own |
| 5g | The CLI records `code` and `metric` criteria | built and proven | A scripted run passes such criteria with no record pass and no Check agent |
| 6a | An environment check before the first agent | built and proven | On the broken scripted project the tool version and the service are named in the first question, before any agent. Only one stack, Maven, is scripted |
| 6b | A baseline of the suite when the run starts | built and proven | The slow project hits no limit and passes; coverage is judged against the code before the change. A real slow build was not measured |
| 6c | A command of the plan runs once before the change | built and proven | Cases count every run of the plan's commands: none at the plan gate, each at most once after the planner; one past its limit asks with a longer limit on offer |
| 6d | One digest, and every verdict names its tree | built and proven | A scripted run records fail then pass as flaky and shows it at the commit; cases refuse to run a failed check again unchanged and find a tree in every verdict |
| 6e | One failure record | built and proven | A case records an environment failure; its gate stays failed until a run of the CLI passes on a new tree or the person skips with a reason |
| 6f | A plan amendment in place of a replan | built and proven | Cases: an amendment only adds a file its group owns, the approved record is never overwritten, a replan keeps built tasks, a changed plan fails the gates |
| 7a | Two listed commands | built and proven | The manifest lists `/temper:temper` and `/temper:fix`, no door file is left, and the five words are rows of the command page |
| 7b | Default packs security and tdd | built and proven | A case finds no stack pack, two skills, and security and tdd as the default packs |
| 7c | Dormant machinery removed | built and proven | A case finds no text on OCR, bands, review memory or metrics writes; a claimed test run counts at no gate |
| 7d | At most 12 words, one word for a stage | built and proven | A case counts 12 words, each with its line in Getting Started, and finds armed and parked in no fixture view or page. A text built only in a state no fixture holds is not read |
| 7e | Getting Started one page; a one time notice | built and proven | One assertion for each of the 12 places where documents and code disagreed; a project that ran 9.8.4 is told once in one line. That the page is right needs a reviewer |

## What changes for someone who used 9.8.4

- `/temper:intent`, `/temper:status`, `/temper:init` and `/temper:pack` are words of `/temper:temper` now (`draft`,
  `status`, `init`, `pack`, and `report`); the stage commands went; `/temper:temper` and `/temper:fix` stay.
- The old config still works, and `autonomy.enabled: false` reads as ask. One time question: remove the lines that
  only repeat old defaults; Remove them keeps a copy, `.claude/temper.config.before-9.8.5`.
- The first run tells once, in one line: `Temper 9.8.5 asks twice: before any code is written, and at the commit.` A
  saved run goes on (all five saved states checked reach the commit question); the installed commit hook still blocks.
- A project that ran pull request #115: `autonomy.policy: decide`, the preflight and the environment agent are gone;
  the default run, a plan command run once before the change and one run of the suite take their place.

## What went differently from the plan

- No package was built twice. The builder of the checks at the end of Build left four parts out, built by a separate
  agent at that phase's review; two edits of `.claude/CLAUDE.md` left by builders were made by the leading session.
- Specs that were wrong: question ids inside a dialog were refused by the host, so they sit beside it; the scripted
  flaky test could never pass as written; where the repair spec and the rule on repeats disagreed, the rule won.
- Checks recorded as wrong: several tests could never pass and two could not fail; each was fixed with its expected
  value unchanged. The counters of option labels and gate rows were blind to some forms; made honest, they showed
  pull request #115 already above two targets. Two commits wrote scripted counts one commit late (`b3abf56`, `16587ac`).
- Not met as planned: the bench's cost and time lines for every kind of task, which the owner accepted as measured,
  and three size limits, which the owner raised to the measure of the release (part 3, item 1g).
- The adversarial review found 43 issues (35 High), then 15 in its fixes (11 High); all fixed but the late counts above.
- Dropped: four of the 29 smaller points of pull request #115, and the older live smoke checks were not run.

## What is not done, and what is yours to do

- Not done: the list "What is still open" of `docs/history/audit-9.8.5.md`: the findings the owner left to the next
  release, the `state clear` guard, U23 (a check of interfaces that matches any `send(msg)`, kept as shipped), the
  median CI time under 12 minutes, no real Maven or Gradle project measured, no reader timed the sample cards, and
  the older live smoke checks.
- Yours: record the two README videos again; order a real Maven or Gradle bench if wanted; mark the pull request
  ready, merge, tag; close pull requests #115 and #116; make a branch rule require the CI check "Gate"; walk
  `docs/mods-testing.md`; bring the older live smoke checks up if wanted; decide what stays of `docs/plans/one-go`.

## The build in numbers

Counted from `3f186d4`, the second merge of the setup package (WP00, the baseline): it brought in the plan and the
build's working papers, so neither pull request #115 nor those papers count as work of the build.

- Days: from 2026-11-16 13:54 to 2026-11-22 01:22 UTC, 5 days and 11 hours.
- Packages: 33 done, 0 blocked.
- Commits: 434 (`git rev-list --count 3f186d4..HEAD`), 110 of them merges.
- Lines: 544 files changed, 65214 added, 46554 removed; without `docs/plans`, 492 files, 63902 added, 31011 removed.
- Tests: at the baseline the selftest passed 2879, the end to end suite 69 mode lines, the mod's suite 1774 tests;
  at the final verification (3089 seconds) the selftest passed 3561, every scripted scenario in every mode agreed
  with its recorded counts (150 runs), and the mod's suite passed 2003 tests.
- CI: 113 runs of the checks on this pull request up to the last push before this summary, many of them stopped by a
  newer push; the last five that passed took 22 min 40 s to 24 min 41 s, a median of 23 min 52 s.

## Was it run for real

Yes: the bench ran. Round (b), 9.8.5 with its default config, made 18 runs with a real model; all 18 ended done at
the commit, and 213 of 213 hidden tests passed. A bug run asked 2 dialogs and launched 3 agents (root cause, fix,
Review); the feature runs asked a median of 5 to 6.5 dialogs, and their launches included 52 fresh reviews of the
plan. The older live smoke checks (start, fresh, cost) were written for pull request #115 and were not run.
