# Temper: the smallest plan that works

Independent plan, written from the `understand` reports and the code at `10e965a` (the head of PR #115). Paths are
relative to `/home/user/temper`. Every code line cited here I read at that head. Dollar and second figures come from
`docs/evidence/` through `_crosscheck.md`; I did not open those documents again and ran nothing.

Sizes: S is a day or less, M is 2 to 4 days, each plus one CI round of about 30 minutes.

---

## 1. Thesis

Temper already holds a run of two decisions. It is switched off. The armed run with `autonomy.policy: decide` asks
3 questions where the default asks 8, and it is the option that is not recommended (`scripts/flow.py:673-675`), behind
a commented config line (`templates/temper.config.default:146`), with three defects that defeat it. So the plan builds
nothing: it cuts PR #115 to the half that saves work, makes the short run the default, halves what Plan writes, runs
each check once, caps every repeat with the key that is already shipped, and puts a ceiling in CI so the counts
cannot rise again.

What this plan does not do is make the run short. The seconds are in Plan (143 to 246 s) and the Build agents (244 to
259 s). Only a merge of the front agents or a rebuilt Build would cut those, and both are refused in section 6.

---

## 2. The target, in run units

The run: the reference run of `_crosscheck.md` section 3. Shipped config, the recommended answer everywhere, the mod's
driver, tier medium, risk below H, 2 groups, 2 task agents, small Python task.

| Unit | Plain Claude Code | Temper today | After the eight | Which PR |
|---|---|---|---|---|
| Questions on a clean run | 0 | 8 (6 + G), plus 0 to 2 Blocking dialogs; live mean 13 | **2** (approve the plan, commit), plus the Blocking dialogs; 3 if the owner declines PR 4; one more when Design runs | 3, 4 |
| Questions that decide nothing | 0 | 6 of 8 | 0 | 3, 4 |
| Agent launches, clean run | 1 session | 6 (4 + T) | 6. No launch is removed | none |
| Launches for one failed group check | none | Plan on Opus again and every task again (policy), or a hand back to a model session | 1 Sonnet fix agent | 3, 8 |
| Stage loop backs, clean run | 0 | 0, but an open Medium finding recommends one, and any Design answer recommends one to Plan | 0, and neither is recommended | 1, 3 |
| Repeats of any kind, worst case | none | no bound (131, 40, 52 and 72 in four incidents) | 4 a run, then one question | 8 |
| Seconds, machine time | 88 to 99 | 597 to 865 | about 540 to 800; no stop between the plan approval and the commit question | 5, 7 |
| Dollars | $0.43 to $0.49 | $1.93 to $2.50 | $1.80 to $2.35; $1.35 to $1.85 if the Sonnet A/B of PR 6 holds | 5, 6 |
| Ratio to plain, cost and time | 1 | 4.5 and 6.7 (vague feature) | about 3 to 4, and about 6 | |

Honest limits of this table:

- The second and dollar gains are inferred from one Plan sample and the price table, not measured. PR 5 and PR 6 each
  carry the bench round that confirms or kills their line.
- On a real project the larger gain is elsewhere and has no number: one measured run "ran the same 11,600 tests about
  eight times", and both failed real runs spent hours in repeats. PR 7 and PR 8 address those; the toy benchmark
  cannot show it.
- The reports' target for a clear request (cost at most 2 times plain, time at most 3) is **not reached**. Plan alone
  is longer than two plain runs. The README already says to skip Temper for "a change whose rules are already written
  down" (`README.md:56-57`). I keep that answer instead of building a second route.

---

## 3. PR #115: cut it on its own branch, then merge it once

Two readers reviewed it and both say it is not ready. CI is green at `10e965a`, but no end to end scenario runs what it
adds. Its 14 CI runs took about 546 minutes, so splitting it into many pull requests is the expensive choice.

The rule for the cut: **what only saves work stays; what adds a loop, a question, an agent or a writer of the
person's config goes or is switched off.** Cutting removes most of the defects without repairing them.

| Keep, as it is | Evidence |
|---|---|
| The one runner and the `setup:` block; the reuse of a passing check | `scripts/run_env.py:149-205`; `scripts/task_ops.py:464, 488` |
| Failure text; no fix pass with no fault to fix; four options a question | `scripts/flow.py:1659-1664` |
| Runs the CLI saw count, claimed runs do not; the staged RED proof | `scripts/runs.py:30-56` |
| `plan patch` (repairs a command without a second Plan); plain `temper doctor`; SETUP wording at Check; the Maven rows | `scripts/plan_patch.py`; `scripts/gate_rows.py:158-191` |
| The policy code, still off | `scripts/flow.py:1144-1181` |

| Cut | Where | What goes with it |
|---|---|---|
| An open Medium finding recommends "Loop back to Build" | `scripts/flow.py:779-784` | The regression that makes four options of the Review question unreachable (pr-flow D1); a default loop of 2 launches and $0.40 to $0.50 |
| The Design gate row that fails on any Design answer | `scripts/temper:3735-3736`; `scripts/flow.py:733-739` | A recommended second Plan and Design pass, about 300 s of Opus (D9). The decisions still reach every Build task prompt |
| `integrate` runs the suite again after new commits | `scripts/temper:3316-3324` | The new way into the fix pass that relaunches with no question (D5) |
| The environment agent, `doctor --candidate`, `--propose --write` and their two questions | `agents/env.md`; `scripts/flow.py:1184-1225`; `.claude-plugin/plugin.json` | One agent type; a setup block that fakes a tool and is written into the person's config (pr-env 5.2, 5.3); 5.4, 5.8, 5.9, 5.13 |
| The backup push allowance | `hooks/temper-mod/core/session.ts:120-134` | Nothing asks for it, and it allows any remote (D11) |
| ENV at a task gate on text patterns | `scripts/task_ops.py:761-767`; `scripts/preflight.py:34-35` | Keep ENV only for the runner's own exit 125 (the setup line failed). A code bug that prints "Connection refused" spends an attempt again, as on main (D8, 5.1) |
| The preflight as a failing row of the plan gate | `scripts/temper:3600-3601`; `scripts/preflight.py:115, 224` | Off unless `plan.preflight: on`. It runs up to 300 s a command inside the Opus turn (`agents/plan.md:59-61`), passes any failure no pattern names, and tests another place than Build runs in (5.5, 5.6, 5.10, 5.11) |

| Fix, because it cannot be cut | Where | Size |
|---|---|---|
| The Check brief still records claims, which the new default never counts | `agents/check.md:30-33`; `reference/check.md:8` | 2 edits |
| The empty `build:` and `evidence:` keys discard the documented `build.grouped` block | `templates/temper.config.default:155-160` | delete 2 lines |
| The commit question says "check again" and offers no option that does | `scripts/flow.py:2269-2277` | S |
| SETUP at Check repeats its recommendation before the "same failure" rule | `scripts/flow.py:837-863` | reorder |
| A plan patch keeps `fix_empty` | `scripts/plan_patch.py:123-124` | 2 lines |

The three policy defects (D2, D3, D4) are not fixed here: the policy stays commented out until PR 3 repairs it and
turns it on.

---

## 4. The eight pull requests

### PR 1. 9.8.5, cut to what saves work (this is PR #115)

- **Depends on:** nothing.
- **Files:** the three tables of section 3; `CHANGELOG.md`; the selftest cases of what is cut (21 to 24, 27, parts of
  28 to 31); `docs/decisions/0018` amended (preflight opt in, no agent).
- **Effect against 9.8.4:** questions on a clean run unchanged. Kept: one suite run less for a one group plan, one
  launch less when a fix pass has nothing to fix, a failed command repaired by a patch in place of Plan again.
  Avoided against the PR as it stands: one recommended loop per open Medium finding, one Opus Plan and Design pass
  per Design answer, one agent type, 3 question kinds, about 600 lines.
- **Proof:** CI green; `bash scripts/e2e/ab-replay.sh` still prints 8 questions and 7 launches for 9.8.5 against 8 and
  10 for 9.8.4; `git diff --shortstat origin/main` is visibly below the present +4,662; `scripts/temper` is not
  larger than today (260,504 bytes; the limit is 262,144, `scripts/quality-check.sh:21-27`).
- **Size:** M. Mostly deletions.

### PR 2. The record and the ceiling

Placed second so that every later PR proves itself by lowering a number in its own diff.

- **Depends on:** PR 1.
- **Files:** `scripts/temper` (`_archive_ledger` already writes `usage`, the launches with model and milliseconds,
  into the committed ledger, `:1377-1378, 1399-1400`; add the loops file, which `state clear` deletes at `:1448`, and
  a count of questions asked); `scripts/flow.py` (that count, written where the flow writes `view.json`);
  `scripts/selftest/budget.json` (new, about 15 numbers); `scripts/quality-check.sh` (compare); `scripts/e2e/run.ts`
  (the clean run's questions, launches and CLI calls against the same file); `CONTRIBUTING.md`, `.claude/CLAUDE.md`.
- **The ceilings, at today's values:** question sites in `flow.py` 41 and 12, option sites 89, agents 13, commands 11,
  config template lines 171, `reference/plan.md` 428 lines, `commands/temper.md` 215 lines, clean run questions 7,
  launches 6, CLI calls 46.
- **The one new thing here** is the question count. No file holds it: `usage.json` has launches only, and the mod's
  record is not the CLI's.
- **Effect:** none on a run. Every committed run then states its questions, launches, loop backs and agent seconds,
  with no network call.
- **Proof:** a scratch branch that adds one question fails CI; a finished run's ledger shows the four numbers.
- **Size:** S to M.

### PR 3. One approval, then the run goes to the commit

- **Depends on:** PR 1 (the policy code), PR 2 (the ceiling it lowers).
- **Files and changes:**
  - `scripts/flow.py:673-675, 726-730`: the arming option becomes the first, recommended one; "Stage by stage"
    stays second and sets `run_mode interactive`. The call is still the person's (`hooks/temper-mod/core/rules.ts:493`),
    so the guard is untouched.
  - `scripts/flow.py:296-298`; `templates/temper.config.default:146`: the policy default becomes `decide`.
  - `scripts/flow.py:1754`: launch the group fix agent in an armed run (D2).
  - `scripts/flow.py:1963-1972`: the policy never takes a step back to Plan; it parks. This restores "never plans
    again by itself", which four documents state and the PR's code breaks.
  - `scripts/flow.py:1166-1168`: the policy loops for the findings `review.block-on` names (`open_findings`,
    `:419-421`), not for every Medium one. The others are listed in the commit question.
  - `scripts/flow.py:1173-1180`: a criterion only the person can confirm parks; it does not loop (D3).
  - `scripts/temper:1269-1281`: a step back to Intent, Plan or Design sets the run interactive (D4).
    `scripts/temper:4520`: the answer to a parked question arms the run again, so one failure costs one question.
  - `scripts/plan_ops.py:92-101`; `scripts/flow.py:2338`: in mode `auto`, a `pending` map with no `ignore` or `gap`
    entry passes with no question. That is the rule the template states at `:104` and no code follows. The end to end
    fixtures stop writing `reviewed: auto` themselves (`scripts/e2e/project.ts:4`, `scripts/e2e/pyjokes.ts:119`).
  - `scripts/flow.py:2242-2244`: the parked commit question also offers the pull request options.
  - Text: `templates/temper.config.default:132-148`; `reference/autonomy.md`; `docs/flow.md:224-235`;
    `.claude/CLAUDE.md`. Tests: `scripts/selftest/temper-cases-28.sh`, `temper-cases-8.sh`, `view-fixtures.ts`, one
    end to end scenario that takes a policy run through a failed group.
- **Effect:** questions 8 to 3 on the reference run (the 3 was measured by two readers with the Context check off).
  A dependent group no longer waits for a click. A failed group costs one Sonnet launch, not an Opus Plan and every
  task. An open Medium finding costs no loop.
- **Proof:** the end to end clean run counts 3; the ceiling in `budget.json` goes from 7 to 3 in this diff; the new
  scenario launches `temper:temper-build` and never `temper:temper-plan`.
- **Size:** M. Dev-efficiency measured ten files for one changed option.

### PR 4. The intent is accepted by rule (the owner's call)

- **Depends on:** nothing in code; after PR 3 for the fixtures.
- **Files:** `scripts/flow.py:633-637`: a passed Intent gate returns an `auto` action with the calls of
  `leave_intent()`, and the Plan question shows the intent's summary. The guard already lets the CLI's own action
  carry a person only call (`hooks/temper-mod/core/rules.ts:459-461`), so `rules.ts:491` does not change. Also
  `README.md:3`, `.claude-plugin/plugin.json` (the promise line), `docs/decisions/0013` amended,
  `reference/autonomy.md:17-19`, the mod test's table, view fixtures.
- **Effect:** questions 3 to 2. The branch clash question (`scripts/flow.py:625-632`) and every Blocking question
  stay.
- **Cost:** a wrong intent is seen after one Plan pass, not before it. The promise changes from "before you approve
  the intent" to "before you approve the plan, which shows the intent". No code is written earlier than today.
- **Proof:** the end to end clean run counts 2; ceiling 3 to 2.
- **Size:** S.

### PR 5. Plan writes half as much

- **Depends on:** PR 1. Independent of PR 3 and PR 4.
- **Files:** `agents/plan.md`, `reference/plan.md`, `templates/plan.md`; `scripts/temper` only where a gate row asks
  for a section that goes (the `## Cross-Repo Search` row, `:2142-2149`). The Blast Radius section and its row
  (`:3560-3566`) stay.
- **What goes** (agents-plan-side section 4; one sample, so the shares are indicative):
  - from plan.md: Files to Create and Files to Modify (the panel reads the tasks' file lines), Risk Level
    (`scripts/risk.py` computes it), Patterns, Dependencies, the second diagram, the Cross-Repo line when no tool is
    connected;
  - scenario step lines: at most one line each. No script reads them and the builder gets only the name and the
    `Test:` command;
  - the `Blocking: Context check` line Plan adds to intent.md (`agents/plan.md:91-92`), which nothing reads;
  - from `reference/plan.md` (428 lines, read at every Plan launch): the fresh review's bookkeeping, the approval
    dialog, the stale Design rule, the summary box lines. Target 230 lines. It was 224 when shrinking it from 1,086
    cut a Plan run's cost by 41% to 48% with equal gate results.
- **Effect:** Plan output about 25,000 tokens to about 17,000 to 19,000; about $0.12 to $0.16 and 35 to 60 s a Plan
  pass, and the same again for every revision; about 3,000 input tokens less a launch.
- **Proof:** four anchor tasks, two runs ($10.10 and 1 hour on the last such round): median Plan output at most
  19,000 tokens, gate results and hidden tests equal. Ceilings: `reference/plan.md` 428 to 230.
- **Size:** S to M.

### PR 6. Plan on Sonnet, if the A/B holds

- **Depends on:** PR 5, so the test measures the brief that ships.
- **Files:** `agents/plan.md:4` (`model: opus` to `sonnet`); `docs/evidence/` (the result). Design stays on Opus, and
  Design is what a risk H plan gets (`scripts/flow.py:251-266`), so a risky plan keeps an Opus reader.
  `models.plan: opus` restores it for anyone (`scripts/cli_ctx.py:57-60`).
- **The test:** `bench/compare_models.py`, three tasks, three runs, two arms: $48.68 and 4.2 hours last time.
- **Rule:** merge only if hidden tests and facts met are not worse and steps back to Plan are not more. Otherwise
  close it and keep the evidence file.
- **Effect if it holds:** Plan $0.75 to $1.13 becomes about $0.35 to $0.55 (Sonnet 5.5 is half of Opus 5.5 per
  token), about a fifth of the run. Seconds: not known.
- **Size:** S, plus the bench.

### PR 7. Each check once per tree, and before Review

- **Depends on:** PR 1 (the reuse store).
- **Files and changes:**
  - Scenario tests go through `run_cached` (`scripts/run_env.py:149-180`), keyed by command, setup block and clean
    tree as today: the task gate (`scripts/task_ops.py:706-708`), the group gate (`scripts/temper:2504-2505`),
    integrate (`scripts/temper:3421-3423`), and Check's suite, acceptance and scenario commands
    (`scripts/check_run.py:671, 693, 720`).
  - `integrate` runs the locked acceptance tests (`acc_run`, `scripts/check_run.py:656`, whose only caller today is
    Check at `:725`) and the Build gate fails on them. A failure is mended by Build's fix pass, before Review.
  - Mutant runs set `PYTHONDONTWRITEBYTECODE=1` (`scripts/check_run.py:386`): a reader got 50%, 75% and 80% on one
    unchanged tree against a threshold of 70, and 75% twelve times of twelve with the variable set.
  - The coverage row passes with its hint when the CLI found no coverage tool (`scripts/temper:3910-3913`), as the
    mutation row already does for "not measured" (`:3929-3930`). Maven, Gradle and Rust have no coverage command
    (`scripts/check_run.py:139-144`), so a first run there fails Check today with correct code.
- **Effect:** a scenario test runs once per tree, not 3 or 4 times. An acceptance failure costs one fix launch inside
  Build, not a Check to Build loop with a second Review and a second Check. No Check failure by chance, and none for
  a missing tool.
- **Proof:** a selftest case where the second run on one tree prints "reused, not run again" for a scenario command;
  an end to end scenario with a failing acceptance test launches Review once; twelve mutation runs give one score.
- **Size:** M.

### PR 8. A failure costs one repair, never a spiral

- **Depends on:** PR 1 and PR 3.
- **Files and changes:**
  - `scripts/go.py:108-109` and `hooks/temper-mod/core/driver.ts:261`: a `group gate` or `integrate` that exits 1
    with a FAIL line is a verdict, not an error. Today it is an error, and the driver hands the run to a model session
    for good (`driver.ts:352`). Measured hand backs cost $0.02 to $0.91.
  - `scripts/flow.py:1655-1672`: a failed `integrate` records the Build gate's FAIL, so the question and the "same
    failure twice" rule apply. Today the fix pass is launched again with no question.
  - `scripts/loop_step.py:20-32`; `scripts/temper:1455-1492`: `state redo`, `group reopen` and `group fix` count
    against one run limit, `autonomy.budget.max-total-loops`. It ships as 4 (`templates/temper.config.default:152`)
    and no script reads it. When it is spent the run parks with the failure text.
  - `scripts/flow.py:588-593`: a recommended step back writes its own reason, as the policy already does (`:1161`).
    One dialog less per loop.
  - Delete `max-stages` and the `autonomy.enabled` text (`templates/temper.config.default:133-136, 144, 153`).
- **Effect:** repeats per run from unbounded to 4. A failed group check under the driver: 0 hand backs, was 1.
- **Proof:** a selftest case where the fifth repeat parks; the end to end failed group scenario ends in driver mode
  with no hand back; `budget.json` gains "repeats at most 4".
- **Size:** M.

---

## 5. Order and what blocks what

| # | Pull request | Needs | Owner decision first | Size |
|---|---|---|---|---|
| 1 | #115 cut and merged | none | the cut list | M |
| 2 | Record and ceiling | 1 | none | S to M |
| 3 | One approval | 1, 2 | yes | M |
| 4 | Intent by rule | 3 (fixtures) | yes | S |
| 5 | Plan writes half | 1 | scenario step lines | S to M |
| 6 | Plan on Sonnet | 5 | the bench spend | S + $49 |
| 7 | Checks once, before Review | 1 | none | M |
| 8 | One repair, one cap | 1, 3 | none | M |

5 and 7 can run beside 3. About 17 to 20 working days and about $60 of bench in all. Any of 4, 6, 7 and 8 can be
dropped and the rest still stands.

---

## 6. What I leave out, and why

| Left out | Why it is not worth it here |
|---|---|
| One front agent for Intent, Plan and Design | The only way to the clear request target. It changes two person only moves in the guard, three briefs, the gates and every fixture, and nothing measures it. Temper's one measured gain is Intent on vague requests (facts met 73% to 98%), which this would put at risk first |
| Repair inside Review or Check, continuing the agent that made the fault | A new mechanism. Whether the mod can continue an agent without a model turn is not known (`_crosscheck.md` gap 3). The cut and PR 3, 7 and 8 remove most loops; each one left costs two launches and no dialog |
| Build in one tree, warm worktrees, keeping work after a failure | 53 of 326 changelog items already patch this mechanism. No number splits a 25 minute Build task on a real project into checkout, cold build and model |
| A baseline environment run, a rebuilt preflight, an agent that finds the setup | No evidence document has a line on any of them. Two real runs failed on this class, so I bound the damage (fix agent, plan patch, cap of 4) instead of predicting it. This is the weakest point of the plan; see decision 2 |
| A plan amendment that keeps passed tasks | Large. PR 3 already stops the unattended second Plan, and `plan patch` covers the command case |
| The acceptance writer beside the first group (30 to 45 s) | The tests must be locked before a builder can see them; the saving is 5% of a run. First candidate if a ninth is allowed |
| Effort levels on the Opus agents | Not measured, and two platform documents disagree on the default. It can ride as a third arm of PR 6's test for about $25 |
| Refactoring `scripts/temper` and `flow.py`, generated fixtures, faster CI | A cost of developing Temper, not of a run. These eight touch known lines |
| A run without the mod | It pays $0.28 to $0.97 for a model in the main session. The driver is the answer; say so in the README |
| Review memory, OCR, confidence scores, Grill Me, Teach Me, Pipeline | None is on the clean run's path |
| A coverage threshold relative to the project's own level | Needs a stored baseline. PR 7 removes only the missing tool case |

---

## 7. What keeps it from growing back

1. **The ceiling file in CI** (PR 2). Counts of questions, options, agents, commands, config lines and brief lines,
   and the clean run's questions, launches and CLI calls. Raising one needs an edit of `budget.json` in the same
   diff, where a reviewer sees it.
2. **The record in every commit** (PR 2). Questions, launches, loop backs and agent seconds of each real run, in the
   repository that ran it. Today these are deleted when the run ends (`scripts/temper:1448`).
3. **One rule in `CONTRIBUTING.md` and the "Known mistakes" list:** nothing new is on by default without a line in
   `docs/evidence/`. PR #115 added about 1,170 lines of runtime code, 6 config keys, 4 questions and an agent with no
   such line.
4. **The 256 KiB limit.** `scripts/temper` is 1,640 bytes under it, so every PR here that touches it must remove
   more than it adds.

---

## 8. Decisions I need from the owner

1. **The cut list of PR #115** (section 3), above all: the environment agent goes, and an open Medium finding no
   longer recommends a loop.
2. **The preflight: off by default, or pay for a real one.** Off leaves environment faults to be found at the first
   group check, where the damage is now bounded. The alternative is one baseline suite run at the start of a run,
   which is a new mechanism and a ninth pull request.
3. **"Approve and run" as the recommended answer**, the policy on by default. The run still never commits, pushes or
   plans again by itself.
4. **The intent accepted by rule** (PR 4). It changes the first sentence of the README.
5. **Medium findings are listed at the commit question**, and only the `review.block-on` severities loop.
6. **Scenario step lines cut to one line.** The product's description names BDD scenarios.
7. **About $60 and 5 hours of bench** for PR 5 and PR 6.
8. **The commit stays a click.** I assumed yes; the target of 2 questions counts it.
9. **Clear requests.** Accept that Temper stays about 4 times plain there and the README sends them away, or order
   the front agent merge as a separate project after these eight.
10. **Is the plugin directory still a goal?** It sets the 256 KiB limit that shapes every change to `scripts/temper`.

---

## 9. What I did not verify

- The size of each cut in PR 1 in lines. "About 600" is my estimate from pr-env section 4.1.
- That removing `integrate`'s rerun leaves the fix pass's `after` calls sound in every state. I read
  `scripts/temper:3316-3324` and `scripts/flow.py:1655-1672`, not every caller.
- That re-arming after a park (`scripts/temper:4520`) is small. If it is not, a run that fails once asks its stage
  questions from there on, and the target of "one question per failure" does not hold.
- The split of Plan's output. It rests on one sample from 9.6.0.
