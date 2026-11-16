# Temper: the run to build, and the way to it (independent plan, clean slate lens)

Written against the head of PR #115, `10e965a` (the working tree; `git log -1` confirms it). Paths are relative to
`/home/user/temper`. Sources: the 17 reader reports and `_crosscheck.md` in `.../scratchpad/understand/`, and the code.

Marks. **[code]**: I read the line at `10e965a` in this session. **[reader]**: a reader report or the cross check
says so and I did not open the line. **[doc]**: a figure from a repository evidence document, by way of the cross
check. **[est]**: my estimate, derived from [doc] figures; not measured.

---

## 1. The finding in one paragraph

Temper today is seven stages, each with its own agent, gate, question and repair-by-going-back. The evidence says
only three things in it change an outcome: asking the person the open rules before anything is built (facts met 73%
to 98%, [doc] `docs/evidence/bench-2026-11.md:146-155`), tests the builder did not choose (mutation score 93% against
79%, [doc] same file `:146-149`), and a commit that a failed check blocks. Everything else is ceremony around those
three: on a clean run 6 of 8 dialogs offer one recommended answer after a check that already passed
(`scripts/flow.py:635, 673, 749, 784, 817` [code]), the Plan agent writes about 25,000 tokens on Opus of which the
builder receives one task block ([reader] agents-plan-side section 4), and a finding is repaired by walking back
through three stages ([reader] review-check-commit 5.3). The design below keeps the three things and the four hard
commitments, and removes the rest: **four moments (Spec, Build, Verify, Commit), two decisions (approve, commit),
no stage a run can walk back to without the person.**

---

## 2. The target, in run units, against plain Claude Code

Bench tasks (small Python, the person answers at once), with the mod's driver. "Today" is the cross check's
consolidated budget (section 3 there) and evidence-bench section 5.1. "Target" columns are pass lines the bench must
show before a step is called done; the seconds and dollars in them are [est] until measured.

| Request | Unit | Plain Claude Code [doc] | Temper today [doc] | Target |
|---|---|---|---|---|
| **Clear feature** | dialogs | 0 | 8 (6 + G); live mean 13, range 8 to 26 | **2** (approve, commit) |
| | agent launches | 0 | 6 (4 + T) | **3** (spec, builder, review) |
| | seconds | 88 to 99 | 597 to 865 (one run 1,463) | **at most 300** (3 times plain) |
| | dollars | $0.43 to $0.49 | $1.08 to $3.39 | **at most $1.00** (2 times plain) |
| | stage loop backs | none | 7 of 18 runs had 2 or more Reviews | **0 by construction**; in-place repairs: median 0, at most 3 |
| | Opus passes | 0 | 1 (2 with Design) | **0** |
| **Vague feature** | dialogs | 0 (it guesses) | 8 to 13 | **3** (the open rules, approve, commit) |
| | agent launches | 0 | 6 or 7 | **5** (spec pass A, spec pass B, acceptance writer beside the builder, review) |
| | seconds | 99 to 134 | 656 to 778 | **at most 450** (4 times) plus the person's reading |
| | dollars | $0.43 to $0.56 | $1.93 to $2.88 | **at most $1.50** (3 times) |
| | facts met | 73% | 98% | **at least 95%** (the one measured win must hold) |
| **Large and risky** (risk H, 12 tasks) | dialogs | n/a | about 30 in the failed run ([doc] `CHANGELOG.md:72-74`) | **at most 4**, plus 1 for each failure the repair budget could not mend (at most 3) |
| | agent launches | n/a | worst case 53 + 6 × T = 125 ([reader] flow-loops 7.2) | **at most 14 + C** (C = chains built at once, at most 4), enforced by one counter |
| | Opus passes | n/a | 5 Plan passes in the failed run; up to 10 allowed | **1** |
| | suite runs per tree | n/a | 3 to 8 ("11,600 tests about eight times", `scripts/run_env.py:121-123` [reader]) | **1** |
| **Bug** (`/temper:fix`) | dialogs | 0 | 4 | **2** |
| | seconds, dollars | 46 to 48 s, $0.36 | 88 to 110 s, $0.45 to $0.50 (a handed back run: 290 s, $1.27) | at most 95 s, $0.55, **and no hand back** |
| Every run | seconds outside agents | n/a | 42 to 103 with the mod | at most 20 |
| Every run | model turns in the main session | all of it | 0 on a clean driven run; all of it after any hand back | 0, failures included |

Why these ratios and not parity: Temper may cost what the thing it adds would cost another way ([reader]
evidence-bench 5.2). On a clear request it adds the record, the gate and one independent review, which is CLI work
plus one short agent; on a vague one it adds one or two rules of five that plain Claude Code misses, worth two to
three plain runs.

---

## 3. The run I would build today

### 3.1 Rules of the design

1. **One route.** One sequence of steps. A step has a `when` over facts the CLI holds (`asked`, `risk`, `chains`,
   `base`); a request never chooses a route and nothing detects a request "kind". Skips only, never other stages.
2. **A question exists only where a person decides.** The guard already draws that line: the only forward moves it
   holds for the person are leaving Intent and leaving Plan (`hooks/temper-mod/core/rules.ts:491` [code]).
3. **Each check once per tree.** Every CLI check is a pure function of (tree digest, command, setup). One runner,
   one cache, one meaning of "same tree" (`scripts/run_env.py:149` is the seed [code]).
4. **A fault is mended where it was made.** The agent sees its verdict before it returns; a repair is a short pass
   on the kept work; there is no backward edge between stages after the approval.
5. **The planner writes only what a script or a builder reads.** Everything derivable is computed.
6. **One counter bounds the run.** Every repeat of any kind draws on it.

### 3.2 The route

Feature run: `spec → build → verify → commit`. Fix run: `rca → build → verify → commit` (the root cause file is the
spec). Models are the defaults I would ship; the two marked (A/B) wait for the measurement in step 0.

| # | Step, and its `when` | Who | Model | Reads | Writes | The CLI computes | The person sees and decides | When it fails |
|---|---|---|---|---|---|---|---|---|
| 0 | **Start.** Always | CLI | none | the project | `.temper/base.json` | `state init`; `temper brief`; `doctor --base`: the stack's test and coverage commands (detection exists, `scripts/check_run.py:76-144` [code]), then the suite once on HEAD **in the project folder**, in the background: exit, failing test ids, duration, whether the coverage and mutation tools start | nothing | An environment fault is asked about before any model is paid: one question with the CLI's proposed setup line. A red base is recorded, not asked: later checks subtract it |
| 1 | **Spec, pass A.** Always | agent `spec` | Sonnet, effort medium | the request text, `.temper/brief.md`, a quick look at the code | `intent.md`: problem, criteria (`Validate: test` or `manual`), scope, decisions, and a `Blocking:` line for each rule the request leaves open (the rules checklist stays the method) | nothing yet | nothing | The agent runs `temper check spec` (read only) and mends its own file before it returns |
| 1q | **The open rules.** `when: asked > 0` | driver | none | | answers into `intent.md` | the dialog, four questions to a call | **Dialog 1** (vague and large only): the open rules, each with a recommended answer. The draft criteria are in the panel above it | a typed answer is recorded as the answer; no model turn |
| 2 | **Spec, pass B.** Always. When `asked == 0` it is the same launch as pass A: the agent goes straight on | agent `spec` (a fresh launch with the answered `intent.md`, or the same agent continued where the host allows) | Sonnet, effort high (A/B); **Opus when `pre-risk` is H** | as pass A, plus the code the tasks touch | scenarios as three lines each (name, `Covers:`, test file); `tasks.md`: groups only where tasks can run at once, per task File, Depends, Test, Cases, and the group Context; `notes.md` of at most 40 lines (approach decisions, `ignore:` and `gap:` lines, design concerns as `Concern:` lines with the answer the plan assumes). **No `plan.md`** | file lists, create or modify, risk (`scripts/risk.py` [reader]), the scenario owner, the `use:` lines of the context map, each group's check (its tasks' tests plus its scenario tests) and the run's suite command (from `base.json`). The planner writes none of these | nothing | The agent runs `temper check spec` and mends in its own context. The gate adds three rows that are missing today (a group with nothing to check, an interface no task builds, a scenario no task owns: [reader] flow-loops E6) and runs each task's test command on HEAD in the project folder: a runner that cannot start is a fault, a failing test in a file no task declares is a base fault |
| 3 | **Second reader.** `when: risk == H or tasks >= 8` | agent `spec-review`, then the `spec` agent in patch mode, then one recheck | Sonnet | `intent.md`, `tasks.md`, `notes.md` | ledger rows | the gate rows of the review | nothing | One round and one recheck, never more (`scripts/flow.py:1294-1302` is the recheck that exists [reader]). A finding still open is shown in the approval |
| 4 | **Approval.** Always | driver | none | | | the panel: criteria with the answers given, tasks, files, risk, the checks that will run, `ignore:` and `gap:`, the base result, the run's budget | **Dialog 2, the one decision before code.** "Approve the intent and the plan, and build?" Approve and build (Recommended) / Approve, stop after each step / Change something / More options. At risk H the same dialog first asks each open `Concern:` (at most three) with the assumed answer recommended | A typed change, or a concern answered against the assumption, launches the `spec` agent in patch mode (Sonnet, only the tasks named), and the dialog is asked again with the difference. Never a whole new plan pass |
| 5 | **Acceptance tests.** `when: asked > 0 or risk == H` | agent `acceptance` | Sonnet | the accepted `intent.md`, the project's tests | tests under `{spec}/acceptance/`, locked | the lock | nothing | Launched **beside** the first builder, not before it (it needs only the intent, `agents/acceptance.md:15-19` [reader]). Two launches at most, then a recorded skip, as today (`scripts/flow.py:1394-1420` [code]) |
| 6 | **Build.** Always | agent `build`, one per chain (the scheduler's chains exist: `scripts/flow.py:1558-1588` [code]) | Sonnet (owner decision D2; Haiku 5.5 is the cheaper setting) | its task blocks, the group Context, the files | code and tests, **in place on the run's branch when one chain runs at a time; one worktree per agent only when two or more run at once** | per task: `task test --phase red`, `--phase green`, `task check` (the verdict, read only: `scripts/task_ops.py:669-775` is already a pure read [reader]), `task gate` (the CLI commits the declared files). At the end of the chain: `build check` = the suite with coverage, the scenario tests and the locked acceptance tests, once, on that tree | nothing; no group question, no Build question | The builder reads the verdict and mends in its own context, tests first. It returns green, or `BLOCKED` with the fact. A second attempt is a repair on the kept work, on the stronger model; there is no third |
| 7 | **Verify.** Always, started when Build passes | agent `review`; beside it the CLI's mutation run on the tests of the changed files, bounded | Sonnet, effort high | the diff, `intent.md` | findings as rows; the CLI draws the panel | one gate over both ledgers; each verdict carries the tree digest it judged; the suite is not run again (same tree) | nothing when it passes | A finding at High or above: one in-place repair (the `build` agent in fix mode with the whole finding, test first where the finding names a behaviour), `build check` on the new tree, and a recheck reviewer that reads only the difference since the reviewed tree and the finding list. Medium and Low findings and surviving mutants are carried to the commit question |
| 8 | **Commit.** Always | driver | none | | the commit, the report, the run record | `gate commit`: Build and Verify hold a PASS or the person's override **for the tree being committed** | **Dialog 3.** The numbers (tests, coverage, mutation score, open findings by severity, files, launches, repairs, seconds), then Commit (Recommended) / Commit and open a draft pull request / Repair the listed findings first / More options. A criterion validated by hand is a second question in the same dialog | Unchanged: an unattended run never makes this commit, never pushes (`scripts/flow.py:2227-2231, 887-892` [reader]) |

`pre-risk` (step 2's model switch) is a CLI fact available before the plan: the brief reaches more files than
`autonomy.max-blast-radius`, or a `park-on-touch` path (`templates/temper.config.default:145, 150` [code]).

### 3.3 The three request kinds on that route

| | Clear ("add pagination to /orders, 20 a page, cursor based") | Vague ("add refunds") | Large and risky (12 tasks, touches billing) |
|---|---|---|---|
| Facts | `asked = 0`, risk L or M, one chain | `asked = 3`, risk M, one chain | `asked > 0`, `pre-risk = H`, 3 groups, 2 to 4 chains at once |
| Launches | spec (Sonnet, one launch), build (Sonnet, in place), review (Sonnet) = **3** | spec A, spec B (Sonnet), acceptance beside build, review = **5** | spec A (Sonnet), spec B (**Opus**), spec-review, patch, recheck (Sonnet), acceptance, C builders (Sonnet, a worktree each), review; at most 3 repairs of 2 launches = **at most 14 + C** |
| Dialogs | **2**: approve, commit | **3**: the open rules, approve, commit | **3 or 4**: the open rules, approve (with the concerns), commit; plus one per failure past the budget |
| What the person reads | one panel of criteria and tasks; one panel of numbers | the same, after one dialog of real choices | the same, plus the second reader's open findings and the concerns |
| Seconds [est] | spec 70 to 100, build 120 to 135, verify 30 to 55, CLI 10 to 20: 230 to 310 | 300 to 420 | by the plan's size; the suite runs once per tree and Opus once |
| Dollars [est] | $0.60 to $0.90 | $0.90 to $1.40 | not estimated: no bench task of this shape exists yet (step 0 adds two) |

Basis of the estimates: Intent 30 to 45 s and Review 27 to 54 s on Sonnet, a Sonnet task agent 122 to 134 s, Plan on
Opus $0.75 to $1.01 for about 25,000 output tokens ([doc] cross check section 3); Opus 5.5 is twice Sonnet 5.5 per
token ([reader] platform section 8); the three files are a little over half of Plan's output and 40% to 60% of their
bytes are read by nothing ([reader] agents-plan-side section 4). **No run has measured a Sonnet planner** (cross
check gap 9); the targets stand or fall on step 0's A/B.

### 3.4 What happens when a check fails (the whole ladder)

| Rung | Where | What happens | Bound |
|---|---|---|---|
| 0 | before any model | `doctor --base` names an environment fault; one question with a proposed setup line | none needed |
| 1 | inside the agent's turn | the agent calls the read only `check`, reads the failed rows, mends, returns only green or `BLOCKED` | the agent's own turn |
| 2 | after it returned, the gate fails | one repair launch of the same brief, its prompt the failed rows (the same agent continued, where the host allows) | 1 per gate, drawn from the run's counter |
| 3 | the same failure text twice (`same_failure`, `scripts/flow.py:2573` [code]) or the counter spent | **one question**, asked by the driver: the failed rows, then Repair with my note / Amend the plan / Override with my reason / Save for later | the person |
| 4 | Build proves the plan wrong (a blocked task, a missing file) | `spec amend`: the `spec` agent in patch mode writes the changed task blocks, the person approves the difference in one question, the CLI rebuilds only the changed tasks and those that depend on them (the per task digest and the rerun set exist: `scripts/fresh_review.py:146-162`, `scripts/flow.py:1901-1926` [reader]). `temper plan patch` is its one line form today (`scripts/plan_patch.py:1-12` [code]) | always the person; never unattended |

There is no rung "go back a stage". The run counter is one number (default 3) that every repair, rerun and
amendment draws on; today only `state loop` is counted (`scripts/loop_step.py:20-32` [code]) and the shipped
`max-total-loops: 4` is read by nothing (`templates/temper.config.default:151-153` [code]; cross check claim 11).

### 3.5 The hard commitments, and where each lives in this design

| Commitment | In the design |
|---|---|
| The person approves before code is written | Dialog 2. `intent.md` and `tasks.md` are accepted in the same answer, so "no code before you approve the intent" stays literally true. The mod's write rule keeps code unwritable until that answer (`hooks/temper-mod/core/rules.ts:255-275` [code]). What changes: the intent is no longer a click of its own (decision D1) |
| Gate verdicts computed by the CLI | Unchanged, and stronger: every verdict names the tree it judged; only runs the CLI made count (9.8.5) |
| Tests first | Unchanged per task (RED before GREEN, run by the CLI). An in-place repair is test first when the finding names a behaviour; a finding with nothing to test no longer demands an invented failing test (today a loop back empties Build's ledger and the gate asks for one whatever the finding: [reader] flow-loops E12) |
| An unattended run never pushes or merges | Unchanged. The commit and every pull request stay answers of dialog 3 |
| An unattended run never plans again by itself | Restored: an amendment is always the person's. PR #115's policy breaks this today (`scripts/flow.py:1963-1972` [reader]; cross check claim 12) |
| The person decides only in the CLI's question, matched exactly | Unchanged for every deciding answer |

---

## 4. Where the present structure must change, and where it can stay

| Structure | Verdict | Why |
|---|---|---|
| **Seven stages** (`scripts/flow.py:47` [code]) | **Must become four**: spec, build, verify, commit | A stage is a gate, a question set, a brief, a reference page, a panel, a write rule and fixtures. Intent, Design and Check carry no decision of their own: the guard holds two forward moves (`rules.ts:491` [code]); `design.md` is read by no later agent ([reader] agents-plan-side 1.4); Check has had no agent since 9.8.0 (`scripts/flow.py:1359-1364` [code]); the commit gate asks for a PASS per stage, not for an order (`scripts/temper:4116-4144` [reader]). Until step 7 the seven names stay in the run state and the extra ones are passed as `auto` moves |
| **Grouped Build, a worktree per task** | **Groups and the scheduler stay; the worktree moves from the task to the agent** | The scheduler already hands a chain of tasks to one agent (`scripts/flow.py:1558-1588` [code]); in 11 of 18 measured runs one agent built the whole plan ([doc] `docs/evidence/haiku-sonnet-task-agents.md:30-47`), so the per task worktrees bought no parallel work. Must go: discard on failure (`scripts/temper:3148-3153` [code]), the merge per task, the group question (`scripts/flow.py:1758-1766` [code]), a group check the planner writes |
| **The mod's exact text matching** | **Stays where it protects a decision; everything else moves to ids** | Exact match of header, question and label for the run and step is the safety property of the four deciding answers (approve, amend, override, commit). It is the wrong key for the rest: the driver matches the label `More options` and a sentence (`hooks/temper-mod/core/driver.ts:290-291` [reader]), the policy picks an option by its display text (`scripts/flow.py:1967` [reader]), 275 test lines select by label ([reader] dev-efficiency 4.1). The session guard that holds a model to the script (`core/session.ts`, 283 lines) stays for the run without the mod and is not grown |
| **The run driver** | **Stays, and becomes the only designed path** | It already carries a clean run with no model turn ([doc] `bench-2026-11.md:437`). Must change: a failed group check or `integrate` is treated as an error and hands the run to a Sonnet session for good (`scripts/go.py:108-114`, `hooks/temper-mod/core/driver.ts:352` [code]). Any FAIL the CLI recorded is a verdict |
| **A bash CLI of 5,121 lines** | **Must go, last, and only what survives** | 2,124 of its lines are Python inside strings, a run starts 737 Python processes (about 31 s), and the file is 1,640 bytes under the 256 KiB limit (cross check rows 6, 19; `scripts/quality-check.sh:21-29` [code]). Porting 41 question sites, about 56 gate rows and 32 subcommands the product will not keep is waste, so: delete first (steps 2 to 7), port what is left (step 8). Until then one rule: `scripts/temper` only shrinks; a step that touches a subcommand moves it into a module |
| **41 question sites** (`grep -c 'self.question(' scripts/flow.py` = 41 [code]) | **At most 16** | Kept: the open rules; approval; commit; "a check failed" (one template for spec, build and verify); amend; environment; scope drift; a manual criterion (inside the commit dialog); a commit the CLI did not make; a wrong acceptance test; another run is active; resume; override reason; accept a finding; More options; pull request options. Gone: the Intent gate, the Context check, the Design gate and its hold, the group question, the three "Continue to ..." questions, the loop back reason dialog, the fresh review variants, the per stage failure variants |
| **13 agents, 11 commands** (`.claude-plugin/plugin.json` [code]) | **6 agents, 6 commands** | Agents: spec, spec-review, acceptance, build, review, rca (pipeline stays outside the run, on a red CI result only). Commands: temper, fix, intent, status, init, pack. The five stage doors go: a run entered through a door runs on the session's own model and is never driven ([reader] mod 1.1) |
| **The three artifacts** (ADR 0011) | `intent.md` and `tasks.md` stay; `plan.md` becomes `notes.md` of 40 lines; `design.md` goes | At simple tier the plan gate already passes with no `plan.md` ([reader] agents-plan-side section 4) |
| The evidence ledger, the commit hook, overrides with reasons, the spec folder in the commit, no network, hooks fail open | **Stay as they are** | They are the product |

---

## 5. PR #115: trim it, fix what survives, merge it as 9.8.5, and build on it

Not merge as it is, and not abandon. Two readers reproduced defects that CI does not reach ([reader] pr-flow section
6, pr-env section 0), and the PR turns on by default three rules that add loop backs while the one feature that
removes questions is off by default ([reader] pr-flow section 1). But about half of it is the seed of this design,
and its head is green.

| Part of the PR | Decision | Reason |
|---|---|---|
| Reuse of a passing check (`scripts/run_env.py:121-180`), failure text, no empty fix pass, the four option cap, the staged RED proof, only CLI-made runs count, `same_failure`, the read only `temper doctor`, the one runner with a `setup:` block, the SETUP wording at Check, Interfaces by shape, `temper plan patch`, the replay harness (`scripts/e2e/ab-replay.sh`) | **Keep** | Each saves work or makes a verdict honest, and steps 3 to 5 build on them |
| `autonomy.policy: decide` | **Keep the code path, fix two lines, leave it off** | It is the path step 2 turns into the default. Fix: launch the group fix agent for an armed run (the guard `not r.armed()` at `scripts/flow.py:1754` [code]); take "Loop back to Plan" out of the policy's moves so the run parks (restores "never plans again by itself") and reset `run_mode` on any step back |
| A Medium finding recommends "Loop back to Build" (`scripts/flow.py:779-787` [code]) | **Remove; High still blocks** | No evidence for Medium (cross check claim 6); each loop is two launches and four dialogs until step 5 makes a repair cheap |
| Any Design answer fails the Design gate until `tasks.md` changes (`scripts/decisions.py:53-69`, `scripts/flow.py:733-739` [code]) | **Remove the row** | It builds a second Opus Plan pass into every Design run with an answer; step 7 asks the concerns before approval |
| The environment agent and the paths that write a setup block (`agents/env.md`, `--propose --write`, `--candidate --write`) | **Remove from the PR** | Three reproduced defects; the agent's draft is refused by the mod's own write rule at Plan ([reader] agents-plan-side 1.5, pr-env section 0) |
| The preflight at the plan gate (`scripts/preflight.py`) | **Keep as it is for now** | It is replaced in step 4; fixing what is to be deleted is waste |
| The backup push allowance in the session guard | **Remove** | Nothing asks for it ([reader] pr-flow feature 13) |
| Must fix in what stays | "More options" loses four options at the Review question (`scripts/flow.py:925-947`); a failed `integrate` in a fix pass never reaches `gate build` (`scripts/flow.py:1655-1672` [code]); the commit question says "check again" and offers no such option; `agents/review.md:27` and `agents/check.md:30-33` state the old defaults | [reader] pr-flow D1, D5, D10, D6 |

Then freeze it: nothing else lands on this PR. Effort: 2 to 3 days. It depends on step 0's CI change only for
speed.

---

## 6. The migration: nine steps, each ships, each deletes

Order rule: instruments first; then the questions (cheapest, largest effect on "back and forth"); then the Plan
agent's output (largest dollar line, small change); then the checks, the repairs and Build; then the front agent
(largest and riskiest change, done when the bench can judge it); the port last, on what is left.

In the "deleted" column a line range with no mark is a reader's range whose start I checked against the function's
`def` line at `10e965a` (`ask` 574, `group_question` 1928, `context_question` 2305, `policy_move` 1144).

| # | Step | What changes | What is deleted | Effect (run units) | Depends on | How the owner knows it worked | Effort |
|---|---|---|---|---|---|---|---|
| **0** | **Instruments, and a 10 minute CI** | (a) A run record the product keeps: dialogs by kind, launches by agent and model, seconds by step, repairs, suite runs per tree; written into the report in the spec folder (local, no network). Today `state clear` deletes `usage.json` and `feedback-loops.json` (`scripts/temper:1448` [code]) and nothing counts dialogs. (b) The scripted end to end scenarios assert the floor (dialogs, launches) of `full-run`, `design`, `fix`, and of a real default fixture (`reviewed: pending`, not the `auto` the fixtures write: `scripts/e2e/project.ts:4` [reader]); CI fails when a change raises them. (c) CI: one job per case file group and per e2e mode, cancel in progress, a time limit per scenario. (d) Three measurements: Plan on Sonnet against Opus, and at two effort settings (3 tasks, 3 runs, about $50, 4 hours); `careful-ask` and the mutation control on the current model (about $15); two new bench tasks shaped like the bad runs (12 tasks; an environment fault) | The helper that runs 220 assertions twice (`scripts/selftest/temper-cases-6.sh:11` [reader]); the four hand kept lists of case files | None on a run. A change to Temper waits about 10 minutes, not 30 to 60 | nothing | `temper report --scorecard` prints the table of section 2 for any run; CI shows the floor; the A/B table exists | S: 3 to 4 days, about $65 |
| **1** | **PR #115 trimmed and merged** (section 5) | as section 5 | the environment agent, the Design hold row, the Medium recommendation, the backup push rule | Default run: no new loop backs; the reuse and honesty parts ship | 0 (c) | Version 9.8.5 on main; the replay still finds the Java run's faults; the floor did not rise | S: 2 to 3 days |
| **2** | **Two decisions on a clean run** | (a) Options get ids; the driver, the tests and the policy select by id. (b) "Approve and build (Recommended)" is the first option of the plan question and arms the run through to the commit question; "stop after each step" is the second. (c) A passed Design, group, Build, Review and Check are `auto` moves for every run (`scripts/flow.py:2441-2472` is the path [code]). (d) Intent acceptance moves into the plan approval: after the open rules are answered the CLI goes on to Plan; `intent accept` joins the approval's calls; `rules.ts:491` keeps `plan_complete` only. (e) The Context check's `ignore:` and `gap:` lines go into the approval panel. (f) A dependent group starts on its PASS (`scripts/temper:2370-2377` [code]). (g) A FAIL the CLI recorded is a verdict in `temper go`, never an error (`scripts/go.py:108-114` [code]). (h) One run counter, counting every `state redo`, `group reopen`, `group fix` and loop. (i) The commit question shows the numbers | Question sites: Intent gate (`flow.py:621-640`), Context check (`:2305-2344` and its gate row `scripts/plan_ops.py:81-101`), group (`:1928-1947`), "Continue to Review" and "Continue to Check" (`:749`, `:784`), the one option reason dialog (`:586-593`). Config: `autonomy.enabled`, `autonomy.policy`, `autonomy.budget.max-stages`, `plan.context-check`. The dead `context_choices` (`flow.py:392-396` [reader]). `reference/autonomy.md` rewritten in 20 lines | Dialogs on a clean run **8 to 2** (3 when rules are open). No hand back on a failed group check. No run without a bound | 0, 1 | The floor in CI reads 2 and 3; the `pyjokes` scenario (the replay of the failed run) ends "driver done"; bench mean dialogs falls from 13 to at most 4 on the same tasks | M: 1.5 to 2 weeks. Needs ADR 0013 and 0016 amended (D1) |
| **3** | **Plan writes only what is read** | The Plan brief and its reference page are cut to the contract: scenarios of three lines, `tasks.md`, short notes. The CLI computes the file lists, create or modify, the risk line, `Traced to:`, the `use:` lines, the cross repo default line. Plan receives the request text (today only Intent does: `scripts/flow.py:1126-1130` [code]). `effort:` is set on every agent, to the A/B's result (today 3 of 13 have one; cross check gap 1). Intent, the acceptance writer and the plan reviewer stop drawing their own boxes; the CLI draws them | `plan.md` sections Files to Create, Files to Modify, Risk Level, Patterns, Dependencies, the mermaid block, Cross-Repo Search; the Given/When/Then lines and their row (`scripts/temper:3524-3546` [reader]); the `Blocking: Context check` line (`agents/plan.md:91-92` [reader]); intent sections nothing reads (Target Users, Business Outcome); `reference/plan.md` from 428 lines to at most 150 (224 lines once cut a Plan run's cost by 41% to 48%: [doc] `docs/evidence/opus5-plan-prompt-ab.md:13-17`) | Plan output about 25,000 tokens to about 12,000 [est]: about $0.3 to $0.5 and 60 to 100 s a run; more if the A/B allows Sonnet below risk H | 0 (d) | Scorecard: Plan's output tokens, seconds and dollars; plan gate results equal on 3 tasks × 2 runs (about $15); hidden tests equal | S to M: 1 week |
| **4** | **Faults at the earliest moment, each check once per tree** | `doctor --base` at `state init`, in the project folder, before any model. The CLI owns each group's check and the suite command. Three plan gate rows added (flow-loops E6); a failure on HEAD in a file no task declares is a base fault. Every CLI check goes through the one runner, keyed by tree digest. The suite with coverage and the locked acceptance tests run at the end of Build, so the builder mends them. `setup.run` once per worktree. The task gate runs its tests outside the lock | `scripts/preflight.py`'s temp folder run and its pass by default (`:115`, `:189-193`, `:224` [code]); the planner's `**Validate:**` and `**Integration:**` lines and the rows that police them (`scripts/gate_rows.py:136-191`, `scripts/plan_rows.py:130-175` [reader]); `check ahead` and adopt (`scripts/flow.py:1375-1378` [code]); the uncached scenario reruns (`scripts/task_ops.py:704-708` [code], `scripts/temper:2504-2505, 3421-3423` [reader]); acceptance first run at Check (`scripts/check_run.py:656, 725` [code]); `plan.preflight-timeout`, `plan.preflight-skip` | Suite runs per tree 3 to 8 to **1**. The fault of both failed real runs (a check that could never pass) cannot be written. An environment fault costs seconds, not a Plan pass. No Check to Build loop for acceptance or coverage | 2 | The replay names the Java run's faults before the first agent launch; scorecard "suite runs per tree" is 1; a new e2e scenario with a broken environment asks its question at second 5 | M to L: 3 weeks |
| **5** | **Repair in place; Verify is one gate** | Verdicts carry the tree digest; the commit gate asks for verdicts of the tree committed. Review and Check are computed together and asked about once, only on failure. A finding at High or above: the fix agent with the whole finding, then a recheck of the difference only (the shape exists for a small change: `scripts/flow.py:954-965` [code]). `task check` before an attempt is spent; a failed attempt keeps its work. Build to Plan becomes `spec amend` with the person's approval of the difference. Criteria are validated by `test` or `manual` only. Mutation runs the changed files' tests and reports survivors as findings | The backward edges Review to Build and Check to Build (`scripts/flow.py:54-55` [code]) and the ledger wipes behind them (`scripts/temper:1876-1896` [reader]); the grouped run reset (`scripts/temper:1276-1279, 1297-1329` [reader]); the third attempt and discard on failure (`scripts/temper:3148-3153` [code]); the record pass and the Check agent (`scripts/flow.py:1361-1373` [code], `:197-214, 2415-2423` [reader]; `agents/check.md`, `reference/check.md`, 288 lines); the fix pass relaunch with no question (`scripts/flow.py:1655-1672` [code]); the regression proof in a bare worktree ([reader] review-check-commit 3.6) | Stage loop backs after approval: **0**. A finding costs one fix launch and one narrow recheck, no dialog, against two launches, four dialogs and $0.40 to $0.50 ([doc] `bench-2026-11.md:271-273`). A plan fault rebuilds the changed tasks, not all of them | 4 | Scorecard on the 18 run set: stage loop backs 0; launches per run down from about 9 ([reader] evidence-bench 5.2) to at most 6; the 7 of 18 "rough" runs no longer cost 39% more | L: 3 to 4 weeks. Needs ADR 0011 and 0013 amended |
| **6** | **One builder in place** | When the schedule gives one chain at a time the builder works on the run's branch; the declared files check compares with the previous task's commit. A worktree per agent when two or more run at once. The acceptance writer starts beside the first builder. One Build brief with a fix mode | The per task worktree, branch and merge for chains (`scripts/temper:2955-2972, 3214-3247` [reader]); the group gate and the merge for a plan of one group; `agents/build-task.md` and `agents/fix.md` folded into one brief; `reference/build.md` (190 lines, part of it about a Build the fix pass does not do: [reader] build-side W11) | Per task: one checkout, one cold build, one merge and one test rerun less. The acceptance writer's 30 to 45 s leave the critical path. On a compiled project this is the large one (a Build task took 25 minutes on the Java run, [doc]; not broken down) | 5 | Scorecard: worktrees made = agents running at once; Build seconds per task on the Maven fixture before and after | M: 2 weeks |
| **7** | **One front agent, four stages** | The `spec` agent of section 3.2 with its two passes and its patch mode; the design concerns asked in the approval dialog; one second reader round at risk H or 8 tasks; the model by `pre-risk`. `SEQ` becomes spec, build, verify, commit; `view.json` version 2; the mod's write rule goes from seven cases to four | `agents/intent.md`, `agents/plan.md`, `agents/design.md` (367 lines); `reference/plan.md`, `reference/design.md`; the Design stage (`scripts/flow.py:251-266, 703-741` [code]; `gate_design` at `scripts/temper:3718` [code]; `scripts/decisions.py`'s row); the full Plan relaunch for a typed change (`scripts/flow.py:1056-1059, 2318, 2327` [reader]); `plan.fresh-review-twice`, `plan.fresh-review-rounds`, `phases.design`; the five door commands | Launches before Build 3 or 4 to **1** (clear) or **2** (vague). Opus passes 1 or 2 to 0, or 1 at risk H. With steps 3 and 6 this is what brings a clear feature under $1.00 and 300 s | 0 (d), 2, 4, 5 | The bench pass lines of section 2 on the six clear and three vague tasks, 2 runs each (about $60 to $100); facts met at least 95%. **If the vague line fails, ship the two launch form (pass A and pass B as separate agents) and keep everything else** | L: 4 weeks |
| **8** | **Port what is left** | Stages, gate rows, questions and config keys as data in one Python package; one process per call; `scripts/temper` is a shim; the config template, `--help` and the reference tables are printed from the data; tests run in process | The 2,124 lines of Python inside bash; the generated fixtures for questions that no longer exist; history tags in code comments; every config key no code reads (a test fails on one) | Seconds outside agents 42 to 103 to at most 20. A wording change touches 1 file, a new question at most 3 (today 10 to 12: [reader] dev-efficiency section 5). The unit suite in under 5 minutes | 2 to 7 (delete first) | Line and byte counts in CI; the time of the unit job; `scripts/temper` under 200 lines | L: 4 to 6 weeks |

Sum: about 20 to 23 weeks of one person's work. Steps 0 to 3 (about 4 weeks) already give 2 dialogs on a clean run,
no hand back on the commonest failure, and the first cut of the largest dollar line. Releases: 9.8.5 (step 1), 9.9
(2, 3), 9.10 (4, 5, 6), 10.0 (7: the stage names and `view.json` change), 10.1 (8).

What the owner can stop after: any step. Each leaves a product with fewer parts than the one before it and no
half built route.

---

## 7. What keeps the product from growing back

1. **A budget file that CI enforces.** One checked in table: dialogs and launches of each scripted scenario,
   question sites (16), agents (6), commands (6), config keys (25), lines per brief (150), bytes of `scripts/temper`
   (may only fall), suite runs per tree (1). A change that raises a number fails CI; raising a budget takes an ADR
   that names the measured gain.
2. **The scorecard is the release note.** Every minor release runs the bench pass lines (a named budget: about $25
   for a brief change, about $100 for a stage change) and prints the table of section 2 beside the previous one.
3. **One in, one out** for questions, config keys and agents, and two tests: every key in the template is read by
   code; every section a brief asks an agent to write has a named reader (a script, a later agent or the person's
   panel).
4. **A new rule of the "known mistakes" list:** a fault met in a real run is fixed by moving a check earlier or by
   deleting the path that allowed it, not by a new question, agent or key. The changelog shows the other habit: 53
   of 326 items patch the Build mechanism alone ([reader] cross check section 5, row 5).
5. **A question must name its decision.** The question table (step 8) has a required field: what the person can
   know here that the CLI cannot. An entry without it does not load.
6. **No second route.** ADR 0017 is rejected as a route; its skips live in the `when` of the one route.

---

## 8. Risks

| # | Risk | Why it is real | What limits it |
|---|---|---|---|
| 1 | **A lighter front agent plans worse, and the bench cannot see it** | No run has measured Plan below Opus; every arm already passes nearly every hidden test, so the bench shows neither gain nor loss in correctness; its tasks are 22 to 583 lines of Python by one author ([reader] evidence-bench section 6) | Step 0 measures before step 3 and 7 change anything; pass A (asking first, the measured win) is kept as it is; Opus stays at risk H; two bench tasks shaped like the bad runs; step 7 has a named fall back |
| 2 | **Fewer stops and in-place repair weaken "what is committed is what was checked"** | Today that property rests on write bans and on wiping every later verdict after a change ([reader] review-check-commit 6.2). Tree digests replace both; a wrong cache key (state outside the tree, a flaky pass) would pass a tree that was never judged. Four ADRs (0011, 0012, 0013, 0016) and the guard's person-only list change | The commit gate compares digests itself; Review still writes no code; the fix is rechecked by a reader that did not write it; the deciding answers keep exact matching; step 5 ships only after step 4's runner has run a release in the field |
| 3 | **The migration costs more than it returns, or stalls half way** | `ask` and `core_next` are ordered special cases with history ([reader] dev-efficiency 4.1); 2,575 assertions lean on labels; the mod API is early access and tied to Claude Code versions; whether the mod can continue an agent is unknown (`hooks/temper-mod/register.tsx:505` only spawns [code]; cross check gap 3); real projects run 4 to 13 times slower than the bench, so the section 2 seconds are bench seconds | Step 0 first; delete before porting; every step ships alone and the design nowhere requires continuing an agent (it is an optimisation to try in step 7); the Maven fixture and the replay stand in for a real project until one is measured |

---

## 9. Decisions needed from the owner

| # | Decision | My answer | Unblocks |
|---|---|---|---|
| D1 | The promise becomes: "You approve once before any code (the intent and the plan together) and once at the commit. Temper stops otherwise only when a check fails and its repair budget is spent." The intent stops being a click of its own; "Stage by stage" stays as the second option | Yes | Steps 2, 7 |
| D2 | Build tasks: seconds or cents? Sonnet is about 100 s a run faster for about $0.25 ([doc] `haiku-sonnet-task-agents.md:87-91`) | Sonnet by default, Haiku a config line | The section 2 targets |
| D3 | May the planner run on Sonnet below risk H if step 0's A/B shows equal gate results, equal hidden tests and facts met at 95% or more? | Yes, on that pass line only | Steps 3, 7 |
| D4 | An unattended run never changes the plan: an amendment always asks | Yes (and correct PR #115 accordingly) | Steps 1, 5 |
| D5 | Medium findings: listed at the commit question with a one click "repair these first", not repaired by default | Yes | Steps 1, 5 |
| D6 | PR #115: trim, fix and merge as in section 5 | Yes | Step 1 |
| D7 | Remove: Design as a stage, the five door commands, the `code` and `metric` criterion types (with the record pass and the Check agent), `plan.md` as a required file, the acceptance writer when nothing was asked and risk is below H | Yes; the last one only if the scorecard shows it never failed a first build on such runs | Steps 5, 6, 7 |
| D8 | Is the public plugin directory still a goal? It sets the 256 KiB limit and the path rules, and decides whether the CLI may be a Python package behind a shim | Keep the scripted rules; do not design around a listing (the mod is held for a reviewer regardless: [reader] adr-constraints 1.5) | Step 8 |
| D9 | "With the mod off, every phase works the same" becomes "the same gates, not the same speed"; the driver is the designed path | Yes | Steps 2, 8 |
| D10 | Bench money: about $65 now, about $25 for each step that changes a brief, about $100 for step 7 | Yes | Every "how the owner knows" above |

---

## 10. What this plan assumes and did not verify

- Seconds and dollars in the Target and section 3.3 are estimates from bench figures on small Python tasks; nothing
  was run for this plan (by instruction).
- The Sonnet planner, effort settings and the value of the acceptance writer on a clear request are unmeasured
  (cross check gaps 1, 9 and row 15 of its budget).
- Lines marked [reader] were not opened by me; every [code] line was read at `10e965a`.
- I did not read the other planner's draft or the `verify` and `red` folders.
