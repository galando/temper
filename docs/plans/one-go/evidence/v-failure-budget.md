# Verification: one failure record, one budget, one ladder; the plan amendment; the static plan rows (draft 3f, 3g, 3c)

Verdict: **feasible with changes.** Read at the head of PR #115 (`10e965a`, the working tree of `/home/user/temper`);
every line number below is of that commit. Nothing was written or run in `/home/user/temper`. One experiment ran in a
clone (`.../scratchpad/work-v-failure-budget/repo`, section 5). No selftest, e2e or bench run.

Marks: **[code]** read at the cited line. **[ran]** run in the clone. **[counted]** counted with grep.
**[reader]** taken from a report, not repeated.

## 0. The answer in brief

- Today a failure is written in 12 kinds of record across 7 files, none with a class or a tree hash, and the next step
  is picked at 33 separate sites (26 questions, 7 rules with no question) with 11 separate "do not repeat" limits.
- A single record and a single counter are small: the CLI already knows, at 8 call sites, that a check failed, with
  the exit code and who ran it. Four of the five classes can be told by structure. Environment faults that exit 1
  cannot: they need the 7 existing text patterns or the baseline run of draft 3b.
- The counter must be enforced inside the CLI calls, as `state loop` is, and must not count the person's own changes.
- "The same check never runs twice on the same tree" is wrong as worded: three re-runs on an unchanged tree are
  legitimate (after an environment repair, with a longer time limit, for a missing tool).
- `plan patch` already patches a task's Test line. The amendment is new work for File and Depends lines: it must run
  the static plan rows, move four stored values (not two) and reopen the changed tasks. It does not replace every
  Build to Plan loop, and the draft does not say who writes it.
- Of the four static rows, three are new and one exists since 9.8.4 and needs an extension. All four faults pass
  every static plan row at the head [ran]. A 55 line prototype flags all four [ran]. A Validate with no path in it
  (a whole suite) cannot be judged statically.
- Small and first: the rows, the counter, the plan patch repairs (about 4 to 5 days). A rewrite: the ladder in place
  of `flow.py`'s question logic (8 to 12 days), and only after the protocol carries ids (draft 1e).

## 1. Where a failure is recorded and where a next step is recommended today

### 1.1 The records (12 kinds, 7 files)

| # | Store | What it holds | Written at | Read at | Survives a step back? |
|---|---|---|---|---|---|
| 1 | `.temper/gates.json` | per stage: verdict, `requirements[] {name, pass, detail}` | `temper gate <stage>` (plan rows: `scripts/temper:3494-3605`) | `flow.py:581-582` (`failed_rows`), `output_ops.py:62-68` | No: `_redo_from` removes the verdicts of the stage and every later one (`scripts/temper:1041-1092`) |
| 2 | `.temper/evidence/<stage>.json` | run rows: `cmd`, `exit_code`, `phase`, `executed_by`, output tail, `fail_lines`, `reused` | `task_ops.py:449-455` (task test), `:463-470` (group Validate), `:483-487` (Integration), `scenario_ops.py:142-145`, `check_run.py:700-703` | `runs.py:30-56`, `loop_step.py:83-121`, `output_ops.py:49-57, 70-77` | No: `_clear_evidence_downstream` (`scripts/temper:1876-1896`) |
| 3 | `groups.json`, group | `gate {verdict, reason, timeout_s, ran, fail_lines}`, `fails` | `scripts/temper:2518-2536` | `flow.py:1978-1991`, `loop_step.py:35-53` | No after a loop to Intent, Plan or Design: `_groups_reset` archives the file (`scripts/temper:1297-1329`) |
| 4 | `groups.json`, group | `fix`, `fix_tries`, `fix_empty` | `group_fix.py:68-69, 82-83` | `flow.py:1986, 1989, 1996` | As row 3. Not reset by `group reopen` (`scripts/temper:2771-2776`) or `plan patch` (`plan_patch.py:123-124`) |
| 5 | `groups.json`, group | `status: parked`, `parked_reason`, `parked_foreign` | `scripts/temper:3161-3168, 3235-3236` | `flow.py:2067-2129` | As row 3 |
| 6 | `groups.json`, task | `attempts[] {n, model, outcome, reason, output}`, `attempts_prior`, `reopened[]` | `scripts/temper:3155-3160, 2763-2769` | `tasks_md.py:209-210`, `flow.py:2117` | As row 3 |
| 7 | `groups.json`, task | `blocked {needs, owners, reason}`, `env_fault {reason}`, `covered {cmd, tail}` | `task_blocked.py:56`, `scripts/temper:3129`, `:3122` | `flow.py:2093-2112, 1857-1870, 1832-1855` | As row 3 |
| 8 | `groups.json` | `integration {verdict, reason, head, foreign}` | `scripts/temper:3292-3298` | `flow.py:1646, 1655-1672, 1236-1246, 1772-1830` | As row 3 |
| 9 | `state.json` | `redo {stage, reason, ts}`: one slot, overwritten | `scripts/temper:1480` | `flow.py:755-756, 855-856` | Removed by the next `state loop` (`loop_step.py:76-80`) |
| 10 | `feedback-loops.json` | `active_loops[] {from, to, reason, iteration, findings[<=20]}` | `loop_step.py:56-123` | `flow.py:308-312, 1248-1277` | Yes, for the run; deleted by `state clear` [reader: crosscheck gap 5] |
| 11 | `.temper/preflight.json`; Check ledger rows `setup fault: ...` | `env_faults[] {cmd, why, files}`; the claim text | `preflight.py`; `check_run.py:700-703, 728-731` | `flow.py:1189-1191, 1211-1214, 1229-1234` | preflight.json yes; the row no |
| 12 | acceptance lock; `state.json` marks | `triage`, `reopened {launches}`; `env_agent`, `record_pass`, fresh review `rounds/extra/grant`, `parked` | `check_run.py:625-647`; `flow.py:1200, 1224, 2415-2420`; `fresh_review.py:91-100` | `flow.py:1487-1511, 2241-2244` | Yes |

None of the twelve has a class field. The class is implied by where the record sits (`env_fault`, the claim prefix
`setup fault:`, the preflight's four names at `preflight.py:33`). None has a tree hash. The only tree hash in the
product is the key of the store of passed runs (`run_env.py:133-141`), which keeps passes only: "a failure always
runs again" (`run_env.py:121-123`).

Two consequences that matter for the draft:

- A loop back deletes the records that explain it (rows 1 and 2), which is why `loop_step.step` copies up to 20 items
  into the loop record by three ad hoc collectors (`loop_step.py:35-53, 83-121`).
- A Build to Plan loop archives `groups.json`, so `fails`, `fix_tries`, `fix_empty`, `attempts_prior` and `blocked`
  start from zero in the Build that follows (`scripts/temper:1276-1279, 1328-1329`). The run forgets what it tried.

### 1.2 The sites that pick the next step after a failure (33)

Questions inside `ask()` (17):

| # | Situation | Recommended | Where |
|---|---|---|---|
| 1 | a walked stage's check failed | Run the stage | `flow.py:609-614` |
| 2 | Plan FAIL, fresh review rows | Run the fresh review again, or Revise the plan | `flow.py:690-692, 1044-1065` |
| 3 | Plan FAIL, preflight environment fault | Add the proposed setup block, or Let an agent find the setup | `flow.py:693-699, 1183-1205` |
| 4 | Plan FAIL, other rows | none | `flow.py:700-701` |
| 5 | Design FAIL, `tasks agree with decisions` | Loop back to Plan | `flow.py:733-739` |
| 6 | Design FAIL, other | none | `flow.py:740-741` |
| 7 | Build or Fix FAIL | Run again; Save for later when the text matches the last redo | `flow.py:753-765` |
| 8 | Review PASS, open finding at medium or above | Loop back to Build | `flow.py:779-784` |
| 9 | Review FAIL | Loop back to Build; Run Review again when it did not finish | `flow.py:794-798` |
| 10 | Check FAIL, a criterion validated by hand | Confirmed | `flow.py:826-836` |
| 11 | Check FAIL, setup fault | Repair the environment, or Add the proposed block | `flow.py:837-851` |
| 12 | Check FAIL, a measurement nobody took | Run Check again; Save for later when the text matches | `flow.py:852-863` |
| 13 | Check FAIL, locked acceptance tests only | by the triage: Correct the test, or Loop back | `flow.py:864-873, 1487-1511` |
| 14 | Check FAIL, other | Loop back to Build | `flow.py:874-875` |
| 15 | the Review of a small change failed | Loop back to the work stage | `flow.py:976-989` |
| 16 | Pipeline red or not final | Apply the fix and push; Run Pipeline again; End the run | `flow.py:1017-1037` |
| 17 | Commit gate FAIL | Add to plan; Loop back to Fix; Override | `flow.py:2246-2275` |

Questions inside Build (9):

| # | Situation | Recommended | Where |
|---|---|---|---|
| 18 | tasks with no groups | Run Plan again | `flow.py:1621-1633` |
| 19 | a covered task | Accept it as done | `flow.py:1832-1855` |
| 20 | a task failed on the environment | Check it again | `flow.py:1857-1870` |
| 21 | foreign commits at integrate | Take the commits out; Merge the groups | `flow.py:1772-1830` |
| 22 | group check FAIL | one of six: twice the time, fix the merged work, run the tasks again, Loop back to Plan, Save for later, Change the group's command | `flow.py:1978-2046` |
| 23 | group parked on an agent's commits | Take the commits out and run the task again | `flow.py:2084-2092` |
| 24 | group parked on a blocked task | Loop back to Plan | `flow.py:2093-2112` |
| 25 | group parked after three attempts | Run the task again; Loop back to Plan the second time | `flow.py:2113-2128` |
| 26 | a manual task | Confirm (an armed run parks) | `flow.py:1871-1899` |

Rules with no question (7):

| # | Rule | Where |
|---|---|---|
| 27 | the policy at Review and Check | `flow.py:1144-1181` |
| 28 | the policy at a failed group check: it takes the option whose label ends in `(Recommended)` | `flow.py:1963-1972` |
| 29 | the armed run's parks | `flow.py:1973-1977, 2074-2077, 1795-1809, 2227-2231, 2441-2467` |
| 30 | a fix pass with nothing that names a fault runs `integrate` and `gate build` again; a failed `integrate` relaunches the fix agent with no question and no count | `flow.py:1653-1672` |
| 31 | the record pass; the acceptance writer again; the acceptance triage | `flow.py:2415-2423, 1404-1410, 1465-1485` |
| 32 | a failed task gate: retry, escalate, park | `scripts/temper:3145-3183`; the model by attempt `tasks_md.py:209-210` |
| 33 | `temper go` stops when the same calls would run twice | `go.py:98-103` |

`grep -c Recommended scripts/flow.py` gives 60 [counted].

### 1.3 The limits on repeats (11, by 5 techniques)

| Limit | Technique | Where |
|---|---|---|
| a step back, per pair | a counted budget, enforced in the call | `loop_step.py:20-32, 68-71` |
| the same Build or Check failure after a redo | text compare, numbers masked; moves the recommendation only | `flow.py:756, 856, 2573-2577` |
| a group check | three counters (`fails`, `fix_tries`, `fix_empty`) and `timeout_s`; move the recommendation only | `flow.py:1982-1991` |
| a task | 3 attempts, enforced; `group reopen` sets it to zero | `scripts/temper:3161, 2763-2766` |
| a parked group | the `reopened` mark; moves the recommendation only | `flow.py:2117` |
| fresh review rounds | a cap plus one earned round per replan | `fresh_review.py:91-100` |
| acceptance writer | two fixed constants | `check_run.py:625-626` |
| environment agent | a one shot mark | `flow.py:1200, 1224` |
| record pass | a one shot mark per round | `flow.py:2415-2420` |
| Pipeline fix rounds | `loops.max-per-type` reused | `flow.py:1017` |
| `temper go` | 60 steps, same calls twice | `go.py:28, 98-103` |

Only three of the eleven refuse a call (the step back, the task attempts, the acceptance writer). The others change
which option carries `(Recommended)`. Under the policy and under draft 2a the recommended option is what runs, so a
limit that only moves the recommendation is the real bound, and each was added after a loop was seen: 131 times
(`flow.py:1985`), 40 (`flow.py:754`), 52 (`flow.py:854`), 72 (`flow.py:2575`).

Not counted anywhere [code]: `state redo` (`scripts/temper:1455-1492` holds no counter), `group reopen`
(`scripts/temper:2603-2776`), `group fix` (`group_fix.py:69` counts and nothing reads it as a limit), the doubled
time limit (`flow.py:1993-1995`), the fix pass after a failed `integrate` (`flow.py:1653-1672`), `state set
next_stage <earlier>` (`scripts/temper:913-935`). `autonomy.budget.max-total-loops` and `max-stages` appear only in
`templates/temper.config.default:151-153`, `.claude/temper.config`, `reference/status.md`, one old plan and the
selftest's fixture [counted]: no script reads them.

## 2. One record: format, where it is written and read, and how a class is told

### 2.1 The format

One file, `.temper/failures.json`, a list. It must be a file of its own: every existing store is deleted or archived
by a step back (1.1). It should go into the committed ledger at `state archive` and not be deleted at `state clear`,
which is what makes "how often does this loop fire" answerable (crosscheck gap 5).

```
{ "id": "F3", "ts": "...", "stage": "build",
  "scope": "task:4 | group:G1 | integrate | gate:<stage> | preflight | review",
  "check": "task-test | validate | scenario | integration | interfaces | suite | coverage | mutation | acceptance | row:<name> | finding",
  "cmd": "...", "exit": 1, "ran_by": "cli | person | agent-claim",
  "tree": "<git tree hash, or the digest of the task's declared files>", "setup": "<digest of the setup block>", "limit_s": 600,
  "key": "sha256(check, cmd, tree, setup)",
  "class": "environment | command | plan | code | measurement", "class_by": "exit | structure | baseline | pattern | agent | person",
  "why": "<= 300 characters", "fail_lines": [...], "row": "evidence/build.json#412",
  "n": 2, "step": "what the ladder did", "resolved": null }
```

`tree`, `cmd` and `setup` are exactly what `run_env.result_key` hashes today (`run_env.py:133-141`), so the key costs
nothing new on a clean, committed tree (a group worktree at its gate, the project after integrate, Check). A task
attempt's worktree is dirty by design, and `result_key` returns None for it (`run_env.py:135-138`); there the tree
must be the digest of the declared files, which `task_ops.py:448` already computes for a RED run (`red_hashes`).

### 2.2 Where it is written (8 sites, all in the CLI, all already holding the exit code)

1. a failed task gate: `scripts/temper:3145-3183` (the verdict's reason comes from `task_ops.py:669-775`)
2. a failed group gate: `_group_gate_record`, `scripts/temper:2518-2536`
3. a failed integrate: `_integ_record`, `scripts/temper:3292-3298`
4. a failed stage gate: the writer of `gates.json` (one record per failed row)
5. the Check run: `check_run.py:693-731`
6. the preflight: `preflight.py:211-222`
7. a group fix that changed nothing: `group_fix.py:79-86`
8. `task blocked`: `task_blocked.py:56`

### 2.3 Where it is read

- one function in `flow.py` that maps a record to a step (the ladder), in place of the rules of 1.2
- what a step back carries (`loop_step.py:35-53, 83-121`) and the three prompt builders (`flow.py:1236-1246`
  `fault_lines`, `:1248-1277` `feedback_lines`, `:2048-2065` `group_fix_work`)
- `output_ops.py`, `view.json`, the report

### 2.4 Each existing rule mapped to a class

| Existing rule | Class | The signal it uses today |
|---|---|---|
| ENV verdict at a task gate (`task_ops.py:758-767`) | environment | text patterns (`preflight.env_fault`) |
| preflight environment fault (`preflight.py:82-103`) | environment | exit 125, 124, 127, plus 7 patterns |
| SETUP at Check (`check_run.py:177-183`; `flow.py:837-851`) | environment | a marker line or the same patterns |
| preflight command fault (`preflight.py:36-37, 108-112`) | command | 5 patterns and one regex |
| group check timed out (`flow.py:1990-1995`) | command | exit 124 |
| a fix that changed nothing (`flow.py:1989, 2023`) | command, or environment | an empty diff |
| the two Maven rows (`gate_rows.py:136-212`) | command | static |
| a blocked task (`flow.py:2093-2112`) | plan | the CLI checked the path is outside the declared files (`task_blocked.py:53-55`) |
| tasks with no groups (`flow.py:1621-1633`) | plan | the parsed plan |
| a covered task (`task_ops.py:744-747`) | plan (work already done) | exit 0 of a RED run |
| group parked again after a rerun (`flow.py:2113-2128`) | plan, presumed | a count |
| group check failed after a fix (`flow.py:2000-2005`) | plan, presumed | a count |
| a group with no Validate (`scripts/temper:2481-2482`) | plan | the parsed plan |
| an undeclared change (`task_ops.py:737-740`); a merge conflict (`scripts/temper:3225-3243`) | plan | git |
| Design answer not in the tasks (`decisions.py:53-69`) | plan | a hash |
| group check failed, every task passed (`flow.py:1983, 1996-1999`) | code | task states and `gate.ran` |
| task attempts 1 to 3 | code | a count |
| Build gate FAIL (`flow.py:753-765`) | code, or measurement (the RED and GREEN counts) | none |
| Review findings (`flow.py:779-798`) | code | the severity field |
| Check FAIL, other (`flow.py:874-875`); integrate suite FAIL | code | the exit code |
| locked acceptance tests fail (`flow.py:1465-1511`) | code, or plan (the test is wrong) | an agent's verdict |
| a measurement nobody took (`flow.py:880-885`) | measurement | a regex over the gate's own detail text |
| a criterion with no CLI row (`flow.py:197-214`); a claimed run (`runs.py:30-33`) | measurement | `executed_by` |
| Review, fresh review or acceptance writer did not finish | measurement | a missing row |
| foreign commits (`flow.py:1772-1830, 2084-2092`); a changed locked test (`flow.py:1499-1501`) | none of the five | a rule was broken; the person or a restore |
| a manual task, a criterion confirmed by hand (`flow.py:826-836, 1871-1899`) | none of the five | the person's input, not a failure |

The last two rows do not fit the five classes. They stay questions of their own, or the draft names a sixth class.

### 2.5 Which classes can be told by exit code and by who ran what, with no text pattern

| Class | Structural signals that exist | What is left to patterns |
|---|---|---|
| environment | exit 125: the setup line failed (`run_env.py:102-107`); exit 127: the program could not start (`run_env.py:203-204`); exit 124 on the base tree | An environment fault that exits 1: wrong JDK, connection refused, a dependency not cached (`preflight.py:34-35, 91-103`). Not decidable from the exit code. With the baseline of draft 3b it becomes structural: the same command fails on the base tree |
| command | exit 124 at a group gate; a fix agent that changed nothing; pytest exit 4 or 5 at a scenario test (`scenario_ops.py:118-120`) | the 5 command patterns of the preflight |
| plan | all of it: the blocked record, an undeclared change, a merge conflict, no Validate, a missing interface, no groups, a RED that passes | nothing |
| measurement | all of it, if the gate that knows a value is absent says so: `executed_by`, a missing row, value None against value below the threshold | nothing. Today `flow.py:880-885` reads it back with a regex over the gate's own detail text; the gate should write the class |
| code | the residual: a non zero exit of a command the CLI ran, on a tree that differs from the base, none of the above; a finding's severity; a mutation score | nothing new |

So four classes are structural now. The hard split is code against not code when the exit is 1. Two existing
structural facts settle most of it: the command failed on the base tree too (the preflight's run, `preflight.py:186-208`),
or a fix agent changed nothing (`group_fix.py:79-86`). Environment against command then matters little: both lead to a
step that keeps every built task (a setup repair, a line patch). The 7 environment patterns stay as `class_by: pattern`
with a way out ("it is the code", the missing option of pr-flow D8). No new pattern list is needed.

## 3. One counter

- **What it counts:** every repeat taken because a check failed: `state loop`, `state redo` of a stage whose verdict
  is FAIL, `group reopen` (one per call), `group fix`, a group gate run again with more time, `task retry` of a
  covered task, the fix pass after a failed integrate, a plan patch or amendment, `acceptance reopen`, "Check it
  again" after an environment repair, a Pipeline fix round.
- **What it does not count:** a task's attempts 1 to 3 (they stay the inner bound, `scripts/temper:3161`; what is
  counted is the `group reopen` that sets them back to zero); the person's own changes at a passed gate ("Change
  something" `flow.py:746-748`, the group's "Change" `flow.py:1928-1949`, a small change). Counting those would make
  the budget refuse the person's edits.
- **Two levels.** Per failure key: a failed check is not run again on an unchanged key unless its class is
  environment or measurement, then at most twice. Per run: one total.
- **Default:** not determined by data: no installed copy keeps a run's loops (`scripts/temper:1448` deletes them)
  and no evidence document counts repeats per run. By construction: the ladder (section 6.3) has at most 2 steps per
  class before it asks, so 2 per failure key and 6 per run fits a run with three distinct failures. The shipped dead
  value 4 was meant for step backs only.
- **At the limit:** the call is refused with `BLOCKED`, as `state loop` does now (`loop_step.py:68-71`). An
  interactive run gets one question that names the failure record, with Save for later recommended and one person
  only option that grants more. An armed run parks with the record in its report (`flow.py:1153-1155` is the shape).
- **Where enforced:** in `cmd_state_loop`, `cmd_state_redo`, `_group_reopen_body`, `group fix`, `group gate
  --timeout-s`, `plan patch`. Not in the options: the guard treats `state redo`, `group fix` and a plain `group
  reopen` as not the person's (`hooks/temper-mod/core/rules.ts:475-497`), and the policy takes the recommended option's
  calls (`flow.py:1963-1972`).
- **Keys it replaces:** `loops.max-per-type` (`templates/temper.config.default:119`; `loop_step.py:26`),
  `fix.max-loops` (template `:48-51`; `loop_step.py:27-28`), `autonomy.budget.max-total-loops` and `max-stages`
  (template `:151-153`, dead). `feedback.enabled` (template `:115-116`; `flow.py:319-320`) becomes a budget of 0.
  The fixed Build to Plan 1 (`loop_step.py:24-25`) becomes a ladder rule. `plan.fresh-review-rounds` can stay: its
  earned rounds come one per loop back or replan (`fresh_review.py:91-100`), so a bound on those bounds it.
  Net: 4 keys become 1, plus one made redundant.

## 4. The plan amendment

### 4.1 What `plan patch` does today [code]

- Targets: a group's Validate, a task's Test, the Integration line (`plan_patch.py:86-93`). So a task's Test line is
  already covered. Only the group form is offered by a question (`flow.py:2021-2027` is the one caller).
- One backticked command, at most 400 characters (`plan_patch.py:22, 96-98`). It replaces an existing line and fails
  when there is none (`plan_patch.py:70-77`), so it cannot add the Validate a group lacks.
- Refuses before the plan is approved (`:102-103`) and when tasks.md already differs from the approved digest
  (`:109-111`).
- Moves `plan_hash` in `state.json` and in `groups.json` (`:116-122`); clears the patched group's gate or the
  integration verdict (`:123-126`). For a task target it clears nothing: a passed task whose Test line changed stays
  passed.
- Does not move `approved_files` or `evidence/approved-tasks.json`, which `state advance plan_complete` writes with
  the hash (`scripts/temper:1136-1161`).
- Runs no plan gate row and no preflight (pr-flow D13); keeps `fix_empty` and `fix_tries` (D12; `plan_patch.py:123-124`).
- Records one plan ledger row with label PERSON, whoever called (`plan_patch.py:134-136`). Only the mod makes it the
  person's (`rules.ts:481`).
- Spends no loop (`plan_patch.py:8-11`). The policy never takes it: it needs a typed answer (`flow.py:1968`).

### 4.2 What the extension to a task's files needs

1. **A diff, not more flags.** `temper plan amend` compares a changed tasks.md with the approved copy at the level of
   the digest's fields. The comparison exists: `tasks_change_summary` (`flow.py:155-181`) names "Task 1 gains X",
   "new Task 7", "Task 3 has a new Test command" from `evidence/approved-tasks.json`. One mechanism then serves the
   CLI's own mechanical change, the person's typed change and an agent's draft.
2. **Validation.** Run `plan_rows.py` and `gate_rows.py plan-rows` on the amended plan and refuse on a failed row.
   Both are pure and take about a second (section 5 ran them alone). This also closes D13.
3. **Scope.** Every declared file is in `state.approved_files` or the person adds it in this answer; intent.md is not
   touched; the groups and their Depends are the same; no passed task is removed. Nothing in the CLI holds a change
   to `approved_files` today except the commit gate's blast radius row (`scripts/temper:4181-4187`), so this check is
   new code. `state set approved_files` and `plan_hash` are refused by design (`scripts/temper:843-846`); the amend
   call becomes the second writer.
4. **Four values move, not two:** `state.plan_hash`, `groups.plan_hash`, `state.approved_files`,
   `evidence/approved-tasks.json`. The Design step already does this for tasks Design changed
   (`scripts/temper:1185-1210`); that is the model.
5. **Which built tasks stay valid.** A task is kept when its core fields (files, depends, test: the fields of
   `_plan_digest`, `scripts/temper:2163-2174`) are unchanged and it is not in the reopen closure of a changed task (a
   task that depends on it and shares a file: `reopen_set`, `flow.py:1901-1926`). The digest of
   `fresh_review.task_hashes` (`fresh_review.py:146-162`) cannot be used: it hashes the block's text, and the CLI
   ticks the checkbox inside the block. Changed tasks go through the existing `_group_reopen_body`
   (`scripts/temper:2603-2776`): attempts to `attempts_prior`, `blocked` cleared, the group's gate and the
   integration verdict cleared. It must run after the hash moved, because it starts with `_plan_fresh`
   (`scripts/temper:2639`). `fails`, `fix_tries` and `fix_empty` of the group are reset.
6. **Order.** A task that gains a file a passed task wrote must depend on that task, or the reopen's restore of
   "the content the file had when the task started" can undo the passed task's work. The `file ownership` row
   (`plan_rows.py:99-123`) forces the order when step 2 runs.
7. **No running task is touched:** "A running task is never reopened" (`task_cover.py:31`). In the blocked case the
   task's gate has already failed and parked the group (`scripts/temper:3147-3149`).
8. **Scenario owners need no step:** `owners()` is computed from the plan at each gate (`scenario_ops.py:74-98`), and
   the group gate runs every scenario owned inside the group (`scenario_ops.py:103-109`).
9. **Counted:** one step of the budget, class plan.
10. **The guard.** `plan patch` is person only (`rules.ts:481`); `plan amend` joins it. If an armed run may amend
    inside the approved files (draft decision 3), the call comes as the CLI's own action, which the guard lets
    through (`rules.ts:460-461`), so the scope rule of step 3 is the only hold and must be in the CLI.

### 4.3 Who writes the amendment (the draft does not say)

| Case | Author | Model cost |
|---|---|---|
| a blocked task whose file is declared by a task that passed or precedes it | the CLI: add the file, add the Depends. The record has `needs` and `owners` (`task_blocked.py:55-56`) | none |
| a blocked task whose file no task declares | the CLI proposes; the file is outside the approved set, so the person is asked | none |
| a blocked task whose file belongs to a later task ("Plan moves the change or the test", `flow.py:2106`) | judgment: the person, or an agent | one launch |
| a wrong command line | the person types it (today), or the baseline names it | none |
| a group parked twice with no blocked record, a group check that fails after a fix | not known what to change: an agent has to diagnose | one launch |

For the last three the amendment needs the revise mode of draft 4d (the failure record and the affected task blocks
to a cheaper model). Whether a cheaper model writes a sound amendment: not determined.

### 4.4 When a full replan is still right

- the fault is in the intent (a criterion or scenario is wrong; the acceptance tests are locked against it)
- the structure changes: a new or removed group, a task that moves to another group, a change of group Depends (a
  group's worktree base is fixed at `group start`, `scripts/temper:2419`)
- tasks with no groups (`flow.py:1621-1633`): reachable only when the `grouped plan` row was overridden
- an amendment that fails the static rows, or amended tasks that fail again with class plan
- an armed run and a change outside the approved files: ask
- the person asks for it

Of the five ways into Build to Plan (`flow-loops` L3 a to e): the amendment replaces (d) a blocked task and the
command cases of (c); it does not replace (a); (b) needs no plan change (accept the task); (e) is the person's choice.

## 5. The static rows

### 5.1 The four faults at the head [ran]

In the clone at `10e965a` I ran the two pure row scripts (not the CLI's gate) on a plan that holds all four faults:
G1 with no Validate and an Interfaces entry in `src/api.py` that no task declares and the project lacks; Task 1
traced to a scenario "ghost" the intent lacks; G2's Validate naming `tests/test_c.py`, a new file that Task 3 of G3
writes, where G3 depends on G2.

- `plan_rows.py`: 14 rows, all PASS, among them `group validate order`.
- `gate_rows.py plan-rows`: `scenario test commands`, `maven group verify`, `request routes kept`, `maven filtered
  verify`, all PASS.
- The preflight was not run. By its code it would pass G2's command as `needs new code` (`preflight.py:111-115`: a
  declared file that is not on the base).

A prototype (`.../work-v-failure-budget/static_rows_proto.py`, 55 lines, using the CLI's own parsers) fails all four:

```
FAIL group validate command | G1: no **Validate:** command
FAIL interfaces built | G1: Interfaces file src/api.py is declared by no task and is not in the project
FAIL scenarios traced | Task 1: Traced to "ghost", which intent.md does not have; scenario "first": no task is traced to it
FAIL group validate order (new files) | G2's Validate names tests/test_c.py, a new file Task 3 of G3 writes: it is not on G2's worktree
```

### 5.2 Each fault

| Fault | From tasks.md and the repository alone? | Today | What the row is |
|---|---|---|---|
| a group with no Validate | **Yes**, tasks.md alone (`tasks_md.py:83`) | No row. First seen at the group gate (`scripts/temper:2481-2482`); `plan patch` cannot add the line (`plan_patch.py:70-77`) | two lines in `plan_rows.py` beside `integration command` (`:195`) |
| an interface no task builds | **At the level of the file, yes:** the path is declared by a task, or the literal is at HEAD already. Whether the task will write the literal: no; that stays `ifcheck` at integrate (`task_ops.py:516-522`) | No row | about ten lines; it needs `git show HEAD:path` or a file read |
| a Traced to name the intent lacks | **Not from tasks.md and the repository alone: it needs intent.md.** The plan gate already reads both files in one row (`gate_rows.py:105-133`), so yes at the plan gate | No row. Such a scenario is owed by nobody and first runs at integrate (`scenario_ops.py:74-98, 134-145`) | about six lines with `scenario_ops.traced` and `acceptance.scenario_blocks`. The form `Traced to: Infrastructure: ...` (`templates/tasks.md:52`) must stay allowed; `traced()` already returns nothing for it (`scenario_ops.py:32`). Add the sibling: a scenario no task is traced to |
| a group check that runs another group's tests | **Partly.** The row exists since 9.8.4: `group validate order` (`plan_rows.py:130-175`), for files that exist now (`:171`). A new file named exactly in the command: yes, by dropping that condition for an exact match. **A Validate with no path** (`pytest -q`, `mvn verify`, `npm test`): no. `run_paths` returns nothing and the group is skipped (`plan_rows.py:164-165`); what a runner collects is not in tasks.md | Exists, with the two gaps | an extension of the existing row, about eight lines |

### 5.3 What these rows do and do not buy

- The Plan agent runs the gate itself before it returns (`agents/plan.md:59-61`), so a new row is repaired inside
  Plan's own turn. That is the one working case of repair inside a stage.
- The three new faults were built by a reader for an experiment (`flow-loops` E6). No report shows one in a measured
  run. The Build to Plan loops in the evidence came from a Validate that could never pass (both failed real runs,
  crosscheck section 5 row 4) and from a blocked task, whose cause (what a test imports) is not static
  (`task_blocked.py:5-9`). So 3c alone does not reach "zero loop backs to Plan from a fault knowable before Build";
  the baseline (3b) and the amendment (3g) carry that.

## 6. What is small enough to do first, and what is a rewrite

### 6.1 Small, each independent of the others

| # | Change | Files | Days |
|---|---|---|---|
| S1 | The static rows: three new, one extended | `scripts/plan_rows.py`, `scripts/gate_rows.py`, `scripts/selftest/temper-cases-20.sh`, `agents/plan.md`, `docs/flow.md` | 0.5 to 1 |
| S2 | One counter in the CLI for `state loop`, `state redo`, `group reopen`, `group fix`, the gate rerun and the fix pass after a failed integrate; the dead keys go | `scripts/loop_step.py`, `scripts/temper`, `scripts/group_fix.py`, `scripts/flow.py` (`can_loop`, the offers, `:1653-1672`), the config template, `.claude/temper.config`, `reference/status.md`, `docs/flow.md`, selftest cases 1, 2, 8, 12, 17, 18 and `test-temper.sh` | 2 |
| S3 | `plan patch` repairs: reset `fix_empty` and `fix_tries`, run the static rows on the patched plan, insert a missing Validate line | `scripts/plan_patch.py`, `scripts/selftest/temper-cases-29.sh` | 0.5 |
| S4 | The blocked record goes with the loop (`loop_step.group_failures` reads groups, not tasks: `loop_step.py:35-53`) | `scripts/loop_step.py`, one case | 0.25 |
| S5 | Keep a failed run by its key too and say "the same command failed on this same tree at ...": the two text compares and `fix_empty` become one structural test | `scripts/run_env.py`, `scripts/flow.py:756, 856`, cases 8 and 26 | 1 |

`scripts/temper` is 1,640 bytes under the 256 KiB limit [reader: crosscheck gap 16], so S2's code belongs in
`loop_step.py`, with one line per call site in the CLI.

### 6.2 Medium

| # | Change | Files | Days |
|---|---|---|---|
| M1 | `failures.json`, written at the 8 sites of 2.2 with a class by structure; read by the prompts and the loop record | new `scripts/failure.py`, `scripts/temper`, `scripts/task_ops.py`, `scripts/check_run.py`, `scripts/preflight.py`, `scripts/group_fix.py`, `scripts/task_blocked.py`, `scripts/loop_step.py`, `scripts/flow.py`, `scripts/output_ops.py`, the run file list, a new case file | 3 to 4 |
| M2 | `plan amend` (4.2) with the question that offers it | `scripts/plan_patch.py`, `scripts/temper` (`cmd_plan`, reopen), `scripts/flow.py` (`parked`, `group_failed`), `hooks/temper-mod/core/rules.ts` and its tests, `scripts/check-mod-calls.sh`, cases 20 and 29, one e2e scenario, `scripts/selftest/view-fixtures.ts`, docs, one decision record | 4 to 6 |

### 6.3 The rewrite

The ladder in place of the question logic. A table of class by attempt by scope can hold what the 33 sites hold:

| Class | First step | Second step | Then |
|---|---|---|---|
| environment | the setup repair (the proposed block, then the environment agent); no attempt spent | "it is the code" or ask | ask |
| command | a time-out: twice the time, once; else a line patch | ask | ask |
| plan | an amendment (by the CLI when the record names the file and its owner) | ask; a full replan is the person's | ask |
| code | task: the next attempt, then the stronger model; group: one fix on the merged tree; Review or Check: one repair in place (draft 3e) | ask | ask |
| measurement | the CLI measures or records it itself; "run again" once the tool is there | ask | ask |

That is at most 15 cells against 33 sites. What makes it a rewrite:

- `ask()` is `flow.py:574-877`, the Build questions are `flow.py:1621-2129`, the policy is `flow.py:1144-1181`: about
  900 lines hold the rules of 1.2.
- The label text is the interface. The policy picks the option whose label ends in `(Recommended)`
  (`flow.py:1967`); the Check question does the same (`flow.py:867-869`); 142 lines in 16 selftest files and 10 lines
  in 3 e2e files match the text [counted]. Until the protocol carries an id and a `recommended` field (draft 1e),
  every relabel breaks tests and the view fixtures.
- The mod counts an answer only on an exact match (CLAUDE.md), and `scripts/selftest/view-fixtures.ts` must be
  regenerated when the view changes.

So: 1e first; then introduce `ladder(record)` and move one site at a time to it, the group check first (it is already
a ladder of six options over four counters, `flow.py:1978-2046`). About 8 to 12 days, 25 to 35 files, most of them
tests and documents.

### 6.4 "The same check never runs twice on the same tree"

Needs rewording. On an unchanged tree these re-runs are right today:

- after an environment repair: "Repair the environment and run again" (`flow.py:841-843`), "Check it again" for a
  task (`flow.py:1867-1868`)
- with a longer limit (`flow.py:1993-1995`)
- for a tool that was missing ("Run Check again", `flow.py:857-858`)

And one is wrong today and already stopped by hand: the group check after a fix that changed nothing
(`group_fix.py:79-86`). The rule that holds: **a failed check is not run again on the same tree, command, setup block
and time limit, unless its class is environment or measurement, and then at most twice.** A flaky test needs the
person's "run it anyway", counted. The key exists for clean trees only (2.1).

## 7. The smallest change that delivers it, in order

1. S1: the rows (`plan_rows.py`, `gate_rows.py`).
2. S3 and S4: the `plan patch` repairs and the blocked record in the loop.
3. S2: the counter, enforced in the calls; the dead keys deleted; the fix pass after a failed integrate spends it.
4. M1: `failures.json` with the class by structure; S5 folds into it (the key of a failed run).
5. M2: `plan amend`, first for the mechanical blocked case and the missing Validate, offered in `parked()` and
   `group_failed()` before "Loop back to Plan".
6. After draft 1e: the ladder, one site at a time.

Steps 1 to 3 need no decision from the owner and no change to an ADR. Step 5 needs draft decision 3 settled.

## 8. Risks

1. A wrong class sends the run down the wrong rung. The costly direction is "code" read as "environment" (pr-flow
   D8: a wrong implementation whose test prints "Connection refused" waits forever). Every rung needs "it is the
   code" as a way out, and the per key limit of 2.
2. A budget that counts the person's own changes, or has no way to grant more, turns into a dead end. The changelog
   holds many dead end repairs [reader: changelog-recent section 5.1].
3. `plan amend` and the reopen's restore: a task that gains a file a passed task wrote can undo that work unless the
   order is forced (4.2 step 6). This needs its own selftest cases.
4. The amendment lets the approved plan change with no Plan pass. Without the mod any caller can run it and is
   recorded as the person (`plan_patch.py:134-136`); the scope rule must be in the CLI.
5. Keeping failed runs by key freezes a flaky failure until the tree changes.
6. `scripts/temper` has 1,640 bytes left under the directory's limit: new logic must go to the Python files.
7. A new record file must be added to the run file list, which already misses `preflight.json` and `decisions.json`
   (draft WP0).
8. The ladder before draft 1e means editing about 150 label matches twice.

## 9. Not determined

- The right default of the counter. No data exists; 2 per failure and 6 per run is by construction.
- Whether the three new static faults ever occurred in a real run.
- Whether a cheaper model writes a sound amendment for the cases that need judgment.
- How the mod's driver treats a refused call (`BLOCKED`, exit 1): `go.py:108-114` makes any failed call that is not
  a gate an `error`, which the driver hands back [reader: crosscheck section 2 row 10]. The budget's refusal should
  be a verdict the flow reads before it offers the call, so the refusal is never reached on the driven path. I did
  not read the driver.
- Whether a Validate that runs the whole suite should be refused by rule (the Plan brief says a group's Validate
  runs the tests that group can break, `agents/plan.md:104`). That is a policy choice, not a computation.
