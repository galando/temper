# Pull request #115: what is fixed, what goes, what stays

This is the document the owner asked for. It answers three questions: is pull request #115 worth fixing, where is the
list of fixes, and what is the benefit. It then gives one decision for each of its 16 defects (M1 to M16) and its 4
changed defaults (F1 to F4), says what happens to its 29 smaller points (U1 to U29), and ends with what the pull
request gave and what stays of it.

The ids are those of `docs/plans/one-go/evidence/v-pr115.md`, the report that reproduced the defects. Every
`file:line` is of the head of the pull request, `10e965a`. The work itself is package WP08 of the one pass build; its
spec is `docs/plans/one-go/wp/phase-3-and-6-pr115-and-repairs.md`. The brief of the build is
`docs/plans/one-go/README.md`: its section 3 holds the settled decisions this page rests on (decision 9 is this
pull request), and its section 5 the order in which the packages named below are built. The ids of questions and
options and the names of scenarios are those of `docs/plans/one-go/contracts.md`.

## 1. The answer in brief

**Is it worth fixing? Yes, and it is cheap.** Pull request #115 is 16 commits, 64 files and 4,662 added lines. Four of
its parts are sound and the whole rebuild stands on them: the one command runner, the declared setup block, the store
that reuses a passed check, and the rule that only a run the CLI made counts. Its 16 defects are small: each fix is
under about 20 lines of product code and one test. Throwing the pull request away would mean writing those four parts
again by hand, with the 11 selftest files that cover them.

**It is not merged on its own.** The one pass build starts its branch from the head of #115. The defects are fixed or
removed inside the one pull request, as its third phase, before any new behaviour is built on them. The head of
#115 calls itself 9.8.5 in its manifest, but it was never merged: no user has it, users have 9.8.4. The result of
the build keeps the number 9.8.5 (the brief, section 3, decision 7), so this page says "the head of #115" or "the
base" for the pull request and never calls it by that number.

**What you get.** Seven dead ends on the path of a user who changes no config are gone (M1, M2, M7, M9, M10, M15,
M16). A run asks no more than 9.8.4 did and recommends no loop that 9.8.4 did not. An unattended run never plans again
by itself, which four of the project's own documents promise and the head breaks. Nothing reaches your config without
you reading it, and nothing is pushed during a run.

**The decisions in numbers.**

| Decision | Means | Count |
|---|---|---|
| FIX NOW | WP08 makes the smallest fix, with a test that fails at the head | 9: M1, M2, M7, M8, M9, M10, M11, M14, F1 |
| REMOVE | The feature goes | 2: M12 (the backup push), M13 (the environment agent) |
| REPLACED BY | A later package of this build rebuilds the area; WP08 only makes it safe until then | 8: M3 to M6 (WP11), M15, M16, F4 (WP21), F2 (WP14) |
| KEPT | The new default stays as shipped | 1: F3 |

## 2. Each defect and its decision

"Default path: yes" means a user with the shipped config who takes the recommended answer everywhere can reach it.
Each test is a selftest case in `scripts/selftest/` (the file is named), a test of the mod in `tests/mod/`, or a
scripted run in `scripts/e2e/`. The token in brackets is the row of `docs/plans/one-go/done.md` that must pass.

### 2.1 The 16 defects

| Id | What goes wrong for a user | Where | Default path | Decision | The fix, or what "safe" is | Its test |
|---|---|---|---|---|---|---|
| M1 | After a loop back to Build, a fix that breaks the Integration suite strands the run for good. `integrate` can never pass again, also after the code is repaired, and the fix agent is launched again with no question and no count | `scripts/temper:3316-3327, 3387-3397, 3430`; `scripts/flow.py:1658-1671` | yes | FIX NOW | The integration record remembers that the groups were merged. A later `integrate` then only runs the suite again and never tries the merge of a branch that is gone. A failed rerun is recorded and the Build question is asked, which stops at the second identical failure. The fix agent is told what failed | `temper-cases-25.sh`, case `m1 integrate`; scenario `fix-breaks-suite` in three modes (`D41`) |
| M2 | A passed Review with an open Medium finding shows a "More options" that holds only itself and one other option. Accept a finding, Grill Me, Teach Me and Save for later cannot be reached | `scripts/flow.py:925-930, 943-947` | yes | FIX NOW | Teach Me gives way to the small change at every passed Review with an open finding, and a More question that exists is never built again from the visible options | `temper-cases-25.sh:46-48` rewritten; a case over every fixture view (`D42`) |
| M3 | In an unattended run under the policy, the agent that should fix a failed group check is never launched | `scripts/flow.py:1754` | no (policy on) | REPLACED BY WP11 | Safe: one condition, so the fix agent is launched. WP11 turns the policy into the default run and rebuilds its rules | `temper-cases-28.sh` (`D43`) |
| M4 | Under the policy one failed group check ends in a step back to Plan with nobody asked: the whole Build is thrown away and the planner runs again. Four documents say this never happens | `scripts/flow.py:1966-1972, 2003-2005` | no (policy on) | REPLACED BY WP11 | Safe: the rule never takes an option that goes back. It stops and asks. This is the rule the owner settled: an unattended run never plans again | `temper-cases-28.sh` (`D44`) |
| M5 | After that step back the run stays unattended whatever you answer, and a passed Design is skipped | `scripts/flow.py:673, 2441-2462`; `scripts/temper:1269-1295` | no (policy on) | REPLACED BY WP11 | Safe: every step back to Intent, Plan or Design turns the run back to asking at each stage | `temper-cases-28.sh` (`D32b`) |
| M6 | The policy loops back to Build, up to twice, for a criterion only you can confirm. Without the policy the same state is one click | `scripts/flow.py:1173-1180` | no (policy on) | REPLACED BY WP11 | Safe: the run stops there, and the next question is the confirmation | `temper-cases-28.sh` (`D46`) |
| M7 | On a project where the CLI finds no test command, Check can no longer pass: the Check agent's brief still records a claimed test run, and a claimed run no longer counts. The same fault breaks a small change made at Check | `agents/check.md:30-31`; `reference/check.md:8`; `scripts/runs.py:30-33`; `scripts/flow.py:966-971` | yes | FIX NOW | The brief records the run with `temper evidence run`, which the CLI makes itself. A small change at Check is checked by the CLI, with no agent | `temper-cases-31.sh`; `temper-cases-11.sh` (`D47a`, `D47b`) |
| M8 | A user who uncomments the documented `build.grouped` block loses it without a word, because the template has an empty `build:` key further down and the reader replaces a repeated key. The same rule drops `park-on-touch` when a second `autonomy:` block is added | `templates/temper.config.default:155, 158`; `scripts/config_yaml.py:27-30` | no (one config edit) | FIX NOW | The two empty keys become comments, and the reader merges a repeated key | `temper-cases-23.sh` (`D48a`, `D48b`) |
| M9 | A code bug that prints "Connection refused" is judged an environment fault. No attempt is spent and the only answers are "Check it again" and "Save for later", every time | `scripts/flow.py:1857-1870`; `scripts/task_ops.py:761-767` | yes | FIX NOW | A third answer, "It is the code: send the task back to its agent", spends the attempt. The same reason twice no longer recommends "Check it again". WP21 later narrows the rule itself to three sure signs | `temper-cases-24.sh` (`D49`) |
| M10 | An environment fault at Check recommends the same repair every round; following the recommendation never ends | `scripts/flow.py:837-851` | yes | FIX NOW | The second identical fault recommends "Save for later", as the other questions already do | `temper-cases-26.sh` (`D50`) |
| M11 | When only the commit gate's own row fails, the question says "then check again" and no option does it | `scripts/flow.py:2245-2277` | no (unattended run) | FIX NOW | "Check again" is the first option. WP11 adds the answer for a person who meant the change | `temper-cases-8.sh` (`D51`) |
| M12 | With the mod on, the session may push during a run to any remote from any source, as long as the branch is named `temper-backup/`. Nothing in the product uses it | `hooks/temper-mod/core/session.ts:123-134, 154` | yes (the guard) | REMOVE | The code that goes: `BACKUP_DEST` and `backupPush` (`session.ts:120-134`), its call (`:154`), its two allowed test lines, the paragraph at `docs/flow.md:259-260`. Every push during a run is refused again | `tests/mod/session.test.ts` (`D52`) |
| M13 | A setup block is one shell line that then runs before every command of every gate. It can reach your config without you seeing it: in the agent path you click before the draft exists; the check passes a block that fakes the tool; and the call that writes it is not yours alone | `scripts/flow.py:1200-1204, 1220-1225`; `scripts/preflight.py:227-243`; `scripts/doctor.py:457-483` | yes | REMOVE | The environment agent goes. WP08 removes its option, its launch and its dispatch (`scripts/flow.py:1200-1227, 2377-2379`); WP21 deletes its brief `agents/env.md`, its manifest line and `doctor --candidate`. Fixed now: `doctor` with `--write` is a call only your answer can cause, and the question shows every line of the block. No cheap check catches a faked tool: your reading of the block is the control | `tests/mod/v975.test.ts`; `temper-cases-27.sh` (`D53a`, `D53b`) |
| M14 | Three new files decide gate rows and the mod guards none of them: the store of reused passes, `.temper/preflight.json` and `.temper/decisions.json` | `hooks/temper-mod/core/rules.ts:108-122` | yes (the guard) | FIX NOW | The three files, and `.temper/setup-tried.json`, join the guarded list. WP22 and WP23 keep the rule for each file they add | `tests/mod/guard.test.ts` (`D54`) |
| M15 | A plan command that takes over 300 s fails the plan gate as an "environment fault", and the remedy on offer cannot make a command faster | `scripts/preflight.py:31, 80-81` | yes | REPLACED BY WP21 | Safe: a time out is "not checked". The row passes and names the three ways on: more time, another command, a skip with a reason. WP21 removes the preflight; a slow command then gets its own question, `plan.command` | `temper-cases-22.sh` (`D55`: never an environment fault, never an agent. The final form, a question with the three ways on as options, is row `D99`, which passes after WP21) |
| M16 | A failed preflight is stored and returned again after you repaired the environment. No option checks again | `scripts/preflight.py:165-171`; `scripts/flow.py:693-701` | yes | REPLACED BY WP21 | Safe: only a pass is stored, and the failed plan question gets "Check again". WP21 keeps the rule in its own form | `temper-cases-22.sh`; `temper-cases-27.sh` (`D56a`, `D56b`; the final form is row `D99`) |

### 2.2 The 4 changed defaults

| Id | The new default of #115 | What it costs a user who changes nothing | Where | Decision | What changes | Its test |
|---|---|---|---|---|---|---|
| F1 | A passed Review with an open Medium finding recommends "Loop back to Build" | Each loop is a fix agent, a second whole Review and Check again, 4 dialogs. 9.8.4 recommended "Continue to Check" | `scripts/flow.py:779-788, 1141, 1167` | FIX NOW | A Medium finding recommends "Continue to Check" and is listed where you commit. A High or critical one still gets the repair; WP24 makes that repair cheap | `temper-cases-25.sh`, `temper-cases-28.sh` (`D57a`) |
| F2 | Any answered Design question fails the Design gate until `tasks.md` changes, and planning again is recommended | Plan and Design again, both on Opus, also when the answer is the rule the plan already has | `scripts/decisions.py:40-69`; `scripts/flow.py:733-739` | REPLACED BY WP14 | Safe: the row passes with a note. The answers still go to every Build task. WP14 makes Design concerns questions in front of the approval | `temper-cases-25.sh:21` rewritten (`D57b`) |
| F3 | A High finding fails Review (`review.block-on` is `critical, high`) | A High finding stops the run at Review | `scripts/temper:3814`; `templates/temper.config.default:31` | KEPT | Nothing. It is the one accuracy gain the replay of #115 shows: 9.8.4 committed the High defect. The key stays yours | holds at the head (`D57c`) |
| F4 | The plan gate runs every Validate, every task Test, the Integration line and every scenario Test once, 300 s each, with no limit on the total, inside the Plan agent's own call | Many extra runs before the plan question; a task's Test cannot pass on code that is not written yet | `scripts/preflight.py:44-61, 189-210` | REPLACED BY WP21 | Safe: only the Integration line and the group Validates run, under one total limit. WP21 moves the run out of the gate and out of the agent's turn | `temper-cases-22.sh` (`D57d`, a token of its own; the final form is row `D99`) |

### 2.3 Two tests the pull request lacked

CI was green on #115 because no test walked these paths. WP08 adds both.

- One scripted run with the policy on, a failed group check and a High finding: scenario `policy-run` in
  `scripts/e2e/scenarios.ts`.
- One selftest for the store of reused passes, in `scripts/selftest/temper-cases-23.sh`.

## 3. The 29 smaller points

The build takes 24, keeps one as shipped and names it to you, and drops four. WP08 writes each line below into
`docs/plans/one-go/PROGRESS.md`; the package named closes it, and WP32 reads the list at the end: a line still open
goes into the text of the pull request. Where the spec of a named package does not carry the
point in its own words, the point is still that package's.

| Id | What | Decision |
|---|---|---|
| U1 | A plan patch keeps the marks of a failed fix, so the next failure still blames the command | WP25 |
| U2 | A patched command skips the plan's checks; a Validate patched to `true` passes; the patch is not shown as a change of the approved plan | WP25 (the static rows on the result, the record, the commit card) and WP21 (the patched command runs once on the current code) |
| U3 | `evidence void` is read in one place only | Dropped. WP30 removes claimed runs, so every run that counts is one the CLI made; a wrong kept pass is met by the counted "run it anyway" of WP22 (the option `run-anyway`) |
| U4 | The store of reused passes has no test; its key has no tool versions | WP08 (the test) and WP22 (the key, and a record of every reuse) |
| U5 | `temper go` reports a failed group check or `integrate` as an error, so the mod hands the run back | WP09 |
| U6 | After one stop the run asks at every stage for good | WP11 |
| U7 | The policy stops where the question recommends a retry | WP11, with the budget of WP10 |
| U8 | An unattended run cannot end in a pull request | WP11 |
| U9 | Every group failure question has five options, so "Save for later" is behind "More options" | Dropped as its own item. WP10 and WP25 rebuild that question; the four option rule stays |
| U10 | The preflight runs under the temp folder, Build inside the project | WP21 |
| U11 | Any failure no pattern names passes as "needs new code" | WP21 (a command is judged by its exit code) |
| U12 | A gate call that is ended leaves its worktree and its running command | WP21 (the plan gate runs no command) |
| U13 | The proposed setup line `. .venv/bin/activate` fails in every worktree (`scripts/doctor.py:354-356`) | WP20 |
| U14 | The environment agent's normal "no draft" result is a failed call | Gone with the agent (M13) |
| U15 | A failed preflight row goes whole into the question (26,010 characters measured) | WP21 |
| U16 | The wrong reason on a red Maven base | WP21 |
| U17 | The proposal treats any mention of a variable as "the code reads it" | Dropped. The block is shown whole and you decide (M13) |
| U18 | Secrets are masked by name only; `3.10` reaches a command as `3.1` | WP29 (the config reader keeps such a value as text) and WP20 (what is shown of a block) |
| U19 | Three run files are not in the exclude list and outlive the run | WP08 |
| U20 | Documents that disagree with the code | WP08 for the lines of its own fixes; WP18 for `agents/review.md:27`; WP31 for the rest |
| U21 | No end to end test runs the policy, a failing preflight, a setup block or a plan patch; the shared selftest fixture counts claimed runs | WP08 (the policy run), WP07 (the scripted promises), WP30 (the fixture, when claimed runs go) |
| U22 | The mod counts a typed answer of at most 100 characters; the CLI takes 2,000 | WP16 |
| U23 | The Interfaces check is looser on purpose: `client.send(msg)` now matches any `send(msg)` | Kept as shipped. WP32 names it in the text of the pull request, so the choice is yours |
| U24 | The plan digest has three copies that must agree | WP25 |
| U25 | The policy's tests run without `park-on-touch` | WP08 (it follows from M8) |
| U26 | At Check the setup offer reads the Plan stage's stored faults | WP21 |
| U27 | The preflight skip row is written outside the CLI's lock | WP21 (the code goes) |
| U28 | A generated copy of test helpers with its own rule | WP01 |
| U29 | Housekeeping of the pull request page | Dropped. #115 is not merged on its own; the text of the one pull request is WP32's |

## 4. What pull request #115 gave, and what stays of it

**Stays, and the build stands on it.**

- **The runner.** One function runs every command of every gate, with one meaning for its exit codes (`run_cmd`,
  `scripts/run_env.py:183-205`). WP19 to WP23 all call it.
- **The setup block.** The project's one declared environment (`setup:` in `.claude/temper.config`, read at
  `scripts/run_env.py:76-118`). From WP08 on it reaches the config only by your answer, with every line shown.
- **The failure text.** A failed check names its first failing lines in the question and in the stop report
  (`fail_text`, `scripts/flow.py:1951-1955`). WP23 puts the same lines into one failure record.
- **The reuse store.** A check that passed on a tree does not run again on the same tree
  (`scripts/run_env.py:121-180`). Guarded from WP08 on, tested, and given a sounder key by WP22.
- **Runs the CLI made.** A test run counts at a gate only when the CLI ran it or you confirmed it
  (`scripts/runs.py:30-33`). WP30 removes the old mode that also counted a claimed run.
- **`plan patch`.** Your change of one command line, with every passed task kept (`scripts/plan_patch.py`). WP25
  completes it and adds the narrow amendment by rule beside it.
- **The Maven rows.** The two plan gate rows that stopped the measured Java run before Build
  (`scripts/gate_rows.py:150-212`). Unchanged.
- **High blocks Review** (F3), the `temper doctor` report, `temper evidence void`, and the rule that a question holds
  four options at most.

**Goes.**

- The backup push of the mod (M12), in WP08.
- The environment agent (M13): its offer in WP08, its brief and its code in WP21.
- The preflight that runs each command of the plan inside the plan gate, with its lists of text patterns (F4, M15,
  M16): cut down in WP08, removed in WP21. A command the plan wrote then runs once on the current code, started by the
  CLI after the planner returned.
- The policy as a config key (`autonomy.policy: decide`), with its defects M3 to M6: made safe in WP08; WP11 turns its
  sound half into the default run, which asks twice.
- The Medium loop (F1) and the Design hold (F2) as recommendations: flipped in WP08.

**Changes its form.**

- The environment fault at a task gate (M9): from text patterns to three sure signs, in WP21.
- A repair of a finding: from a loop back through Build to a fix in the stage, in WP24.

**In the CHANGELOG.** The build adds no version heading. It replaces the entry of the base, whose heading at
`CHANGELOG.md:6` is `## v9.8.5: a run that checks its own environment first, and asks less`, by one entry,
`## v9.8.5: a run that asks twice`. WP01 changes the heading, every package writes its lines under it, and WP31
gives the entry its final parts. What that entry keeps of pull request #115 is the list "Stays" above and the two
lines of "Changes its form", told as what a user of 9.8.4 gets. What is under "Goes" is not told there as a
removal: no user ever had it, so nothing was taken from anyone. It stands only in the one closing line the entry
has for a project that ran the head of #115.
