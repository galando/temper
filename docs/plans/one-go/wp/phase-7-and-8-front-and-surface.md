# Phases 7 and 8, the front and the surface: the specs of WP26 to WP31

This file holds WP26 and WP27 (phase 7, the front: what Plan writes, the revise agent, criteria by the CLI, models)
and WP28, WP29, WP30 and WP31 (phase 8, the surface: commands, config, removals, words, documents, version 9.8.5).

Every `file:line` is of the head `10e965a`. WP02 and WP03 move code out of `scripts/temper` and split
`scripts/flow.py`, so find a cited function by its name first and by its line second.

In this file "9.8.5" is the result of the build. The state the build starts from carries the same number
(`.claude-plugin/plugin.json:5`) and is called "the base" or `10e965a`: it is the head of pull request #115, which
was never merged, so no user had it. Users have 9.8.4 (`7c7a1c1`), and every promise to an existing project is
made to a project of 9.8.4 first and to one of the base second.

The brief is `docs/plans/one-go/README.md`, and every shared name below is the one `docs/plans/one-go/contracts.md`
fixes: the new case files are `scripts/selftest/temper-cases-70.sh` to `temper-cases-75.sh`, one a package in the
order of this file (the runner of WP01 finds a case file by its name, so no `source` line is added), and the
decision records have the numbers of its section 11. The packages are built in the order of this file, after WP25.
Each ends as the brief's section 4 says: `bash scripts/verify.sh quick` green, then the package commit, then the
small progress commit that sets its line of `docs/plans/one-go/PROGRESS.md`, in one push. A package that names
`CHANGELOG.md` writes its lines under the one heading of the result, `## v9.8.5: a run that asks twice`, and
adds no version heading; WP31 sorts those lines into the final parts of the entry.

A check leaves `scripts/selftest/expected-fail.txt` in the package commit that makes it pass. A check that passed
earlier is simply not on the list (`docs/plans/one-go/done.md`, note 7). If one still fails for a reason that
belongs to a later package, do not weaken it: name that package on its line of the list and in
`docs/plans/one-go/PROGRESS.md`.

## WP26 Plan writes what something reads; `tasks.md` only at the simple tier

- **Goal:** The planner writes only what a script, a gate row or a later agent reads. At the simple tier that is
  `tasks.md` and the scenarios; above it a short `plan.md` as well. On the one real plan in git the cut is 50% to 56%
  of the bytes Plan writes into files (`docs/plans/one-go/evidence/v-lean-front.md`, part 1.6). No gate, builder or
  commit step may need a part that is no longer written.
- **Depends on:** WP02, WP03, WP05, WP07, WP13, WP14, WP15, WP21, WP23.
- **Lane:** `flow core`.
- **Touches:** `agents/plan.md`, `agents/intent.md`, `agents/acceptance.md`, `agents/plan-review.md`,
  `agents/check.md`, `reference/plan.md`, `reference/review.md`, `reference/build.md`, `reference/check.md`,
  `templates/intent.md`, `templates/example-intent.md`, `templates/plan.md`, `templates/tasks.md`, `scripts/temper`
  (`gate_plan`, `_cross_repo_recorded`, the `spec deviations` help line) or the module WP02 moved them to,
  `scripts/plan_ops.py`, `scripts/scenario_ops.py`, `scripts/spec_ops.py`, `scripts/intent_draft_rows.py`,
  `scripts/panel.py`, the flow modules that hold `plan_files` and `record_steps` (`context_choices` went with WP13),
  `scripts/card.py` (WP15: where it lists files), `scripts/selftest/case-helpers.sh`,
  `scripts/selftest/make-view-fixtures.sh`, both view fixture files, `scripts/selftest/temper-cases-1.sh`, `-2.sh`,
  `-11.sh`, `-14.sh`, `-16.sh`, `temper-cases-70.sh` (new), `scripts/e2e/project.ts`, `scripts/e2e/pyjokes.ts`,
  `scripts/e2e/replay.ts`, `scripts/e2e/scenarios.ts`, `scripts/caps.json`, `scripts/e2e/floor.json`,
  `docs/flow.md`, `docs/methodology.md`, `docs/ai-native-sdlc.md`, `docs/plans/one-go/changed-tests.md`,
  `scripts/selftest/expected-fail.txt`, `CHANGELOG.md`.
- **Tests first:** `scripts/selftest/temper-cases-70.sh` (new; the hand list of
  `scripts/selftest/test-temper.sh:235-246` went with WP01, so no `source` line is added). Build each state with
  `fresh`, `gpass`, `nx` and `vw` of `scripts/selftest/case-helpers.sh`.
  1. `w26 simple tier is tasks.md only`: a spec folder with an accepted `intent.md` (scenarios in the new shape of
     mechanism step 2), a `tasks.md` of one group and two production files, no `plan.md`, tier `simple`.
     `temper gate plan` is PASS, no row is named `cross-repo search recorded`, `blast radius documented` or
     `criteria -> scenarios`, and `temper next --json` asks the approval. The PASS holds at the head already (a
     verifier ran it: 25 rows); the three absent names are what fails first.
  2. `w26 no tier needs plan.md`: the same folder with tier `medium` and two groups passes the plan gate.
  3. `w26 an untraced scenario is owed by the task that writes its test file`: `tasks.md` has no `Traced to:` line;
     a scenario's `Test:` is `python3 -m unittest unit.test_a`; Task 2 declares `unit/test_a.py`. `temper task show 2`
     prints the scenario under `SCENARIO TESTS` (`scripts/task_ops.py:385-389`) and `temper task show 1` does not.
  4. `w26 an old plan still reads`: the fixture plan of `scripts/selftest/case-helpers.sh:106`, which has
     `**Traced to:** Scenario: "alpha"`, gives the same owner as at the head.
  5. `w26 deviations are a file of their own`: with one deviation in `build-context.json`, `temper spec deviations`
     exits 0 with and without a `plan.md`, writes `deviations.md` in the spec folder, and leaves `plan.md` and
     `tasks.md` byte equal.
  6. `w26 the intent row is gone`: a draft intent with a `Target Users` bullet that has no arrow gets no row named
     `target users action chain` from `temper gate intent`.
  7. `w26 the context row passes with no map`: a `plan.md` with no `## Context Map` gives the row
     `context map reviewed` with `pass` true.
  8. `w26 the tier is bounded`: tier `simple` with two groups, or with four production files, or with risk H in the
     run state, fails the plan gate on the row `tier recorded`, and the detail names the bound that was crossed and
     the call `temper state set complexity medium`.
  9. `w26 the templates pass their own gate`: the block between the markers of `templates/tasks.md` still passes
     `temper gate plan` (the existing check is `scripts/selftest/temper-cases-5.sh:1192`), and it holds no
     `Traced to`.
  10. `w26 no page asks for a cut part`: `git grep` over `agents`, `reference` and `templates` finds none of
      `Cross-Repo Search`, `Files to Create`, `Files to Modify`, `Patterns to Follow`, `Risk Level:`,
      `Scenario Coverage Checklist`, `Target Users`, `Business Outcome`, `Traced to`, `Given/When/Then`,
      `Approach Decisions`, `## Diagram`, and `templates/plan.md` holds no `mermaid`.
  11. `scripts/e2e/project.ts`: write `PLAN_MD` and `TASKS_MD` (`:4-5`) in the new shape. The scenario
      `default-run` must end at the commit in the three modes with the same dialogs and launches as before. No
      count of `scripts/e2e/floor.json` moves: the floor holds no count of gate rows
      (`docs/plans/one-go/contracts.md` section 12), and the rows that go are counted by `gate_rows` of
      `scripts/caps.json`.
  12. Rewrite in the same change the tests that state the old behaviour on purpose, and list each in
      `docs/plans/one-go/changed-tests.md`: `temper-cases-2.sh` (the cross repo row), `-14.sh` (the blast radius
      row), `-11.sh` (the Context Map row with no map), `-1.sh` (`criteria -> scenarios`), `-16.sh` and
      `case-helpers.sh` (`Traced to`).
  13. From `scripts/selftest/expected-fail.txt`: `D27a` and `D27b` of `scripts/selftest/temper-cases-46.sh` (row
      `D27`) pass and leave the list here.
- **Mechanism:** no prototype diff exists for this package; the verifier's experiment (a plan gate with no
  `plan.md`) is in `docs/plans/one-go/evidence/v-lean-front.md`, part 1.3.
  1. **What Intent writes.** Kept, each with its reader: the header lines Status, Author, Created, Ticket and
     Complexity (`scripts/temper:2077-2083`, `scripts/intent_draft_rows.py:156-167`, `scripts/temper:3569-3578`);
     Problem; Success Criteria with `Why:` and `Validate:`; Constraints; `Scope and Non-goals`; Open Questions;
     Assumptions; Rules covered; the `**States:**` line; Decisions; Context Sources. Cut from
     `templates/intent.md`, `templates/example-intent.md` and `agents/intent.md`:
     - the `**Reviewer:**` line (`templates/intent.md:7`; no row needs it, `scripts/intent_draft_rows.py:158-160`);
     - `### Business Outcome` (`templates/intent.md:45-49`; no row, no reader);
     - `### Target Users` (`templates/intent.md:51-56`), its row (step 5) and the second of the two "mandatory
       probes" (`agents/intent.md:67-68, 89-91`);
     - `## Scenario Coverage Checklist` (`templates/intent.md:107-109`) and the one line that told Build to fill it
       (`reference/build.md:91`);
     - the box the agent draws (`agents/intent.md:162-187`), unless WP13 or WP15 already removed it. The agent
       returns the spec path and its status word; the person reads the criteria on the card of WP15.
  2. **What Plan writes into `intent.md`.** Per scenario one fenced `gherkin` block of four lines:

     ```gherkin
     Scenario: a locked account gets 423
       Then the response is 423 and carries the unlock time
       Covers: AC-02
       Test: npm test -- test/auth/lockout.test.ts -t "423"
     ```

     `Given`, `When`, further `Then` lines and `Note:` go: `acceptance.scenario_blocks` reads only the name,
     `Covers:` and `Test:` (`scripts/acceptance.py:91-112`). The one `Then` line stays because three pages judge a
     test against it. Change those pages to say so: Review step 3c judges a test against the scenario's `Then`
     line and the Cases of the task that owns it (`reference/review.md:149-154`); the Check agent finds the test
     by the `Test:` line (`agents/check.md:42-44`, `reference/check.md:64`); Build's fix pass writes one test per
     scenario from its `Then` line (`reference/build.md:39-41`). Rewrite step 6 of `agents/plan.md` (`:42-48`)
     and the example of `reference/plan.md:236-247`. The line
     `- Blocking: Context check: ...` is no longer written (`agents/plan.md:91-92`): WP13 took it out of the brief
     and deleted its parser (`context_choices`, `scripts/flow.py:392-396`). Confirm that neither is left.
  3. **`tasks.md`.** Unchanged but for `**Traced to:**`, which is no longer written
     (`templates/tasks.md:26, 36, 52`, `reference/build.md:112`). Its one reader is `scenario_ops.traced`
     (`scripts/scenario_ops.py:30-36`).
     In `scenario_ops.owners` (`:74-99`) the file rule only adds owners to a scenario some task already traces
     (`if b["name"] in tracing`, `:86`). Seed instead: for every block with a `Test:` command, every task whose
     declared files meet `cmd_files(cmd)` traces it, whether or not a `Traced to:` line names it. Keep `traced()`
     for plans that have the line. A scenario no task traces is owed at `integrate`, as today (`:133-155`).
  4. **`plan.md`.** Not written at the simple tier (`reference/plan.md:37-40` and `agents/plan.md:19-20, 86-88`
     ask for three files at every tier today). Above it the file holds only:
     - `## Context Map`: the brief asks for `ignore:` and `gap:` lines; a `use:` line is allowed and counted, never
       asked for (the card of WP15 counts the sources, and a line costs 100 bytes);
     - `## Blast Radius`: only what the change reaches outside the declared files; a `[CROSS-REPO]` row keeps its
       meaning for `risk.cross_repo` (`scripts/risk.py:59-65`).

     `## Approach Decisions` and `## Diagram` are cut at every tier. Their one reader was the plan panel
     (`scripts/panel.py:120-121` listed the headings, `scripts/panel.py:144-158` printed the `text` block), and
     WP15 removed that panel. Cut both from `templates/plan.md` (`:14-31` and `:33-46`), from `reference/plan.md`
     (`:283-304`, and the clause on the diagram at `:411`) and from the paragraph of `agents/plan.md:121-127`
     that WP15 rewrote. Delete `ascii_diagram` of `scripts/panel.py` if WP15 left it: it has no caller.

     Cut from `templates/plan.md`: Architecture (`:10-12`), the mermaid block (`:35-40`), Files to Create and Files
     to Modify (`:52-62`), Patterns to Follow, Dependencies and Risk Level (`:64-74`). Cut from `agents/plan.md`:
     step 5 and the two gotchas on `## Cross-Repo Search` (`:34-41, 114-115`), the mermaid sentence (`:124-125`),
     the sentence that the gate needs a Blast Radius (`:57-58, 111-113`), and "exactly three files" (`:86-88`),
     which becomes "`tasks.md`, and `plan.md` above the simple tier; never another file". The route rule of
     `:83-85` reads `plan.md` and `tasks.md` (`scripts/gate_rows.py:301-305`): tell the planner to keep a route in
     a task block when there is no `plan.md`.
  5. **Rows.** In `gate_plan`: delete `criteria -> scenarios` (`scripts/temper:3507-3514`; the row counts one
     scenario per criterion whatever its Validate type, and `criteria -> validation` already fails a `scenario`
     criterion that nothing covers, `scripts/acceptance.py:392-394`); delete `cross-repo search recorded`
     (`:3548-3559`) with `_cross_repo_recorded` (`:2126-2151`); delete `blast radius documented` (`:3561-3568`).
     In `scripts/intent_draft_rows.py` delete `target users action chain` (`:112-118` and its name at `:28`). In
     `plan_ops.gate_row` (`scripts/plan_ops.py:81-101`) a `plan.md` with no map passes with the detail
     `no map: nothing flagged` (the two returns at `:84-87` go); WP13 changed the `reviewed` rule of this
     function, keep its change.
  6. **The simple tier is bounded by the CLI.** In the row `tier recorded` (`scripts/temper:3569-3578`): a run
     recorded as `simple` fails the row when `tasks.md` has more than one group, declares more than 3 production
     files (`risk.is_production`, the L band of `scripts/risk.py:75`), or the run's risk is H. The detail names
     the bound and the call that records `medium`. The planner runs the gate before it returns
     (`agents/plan.md:59-61`), so it meets the row itself. Say the bound in `reference/plan.md:37-40`.
  7. **The files of a plan.** `plan_files` (`scripts/flow.py:2538-2559`) unions the two file tables of `plan.md`
     with the `**File:**` lines. Keep reading the tables (a plan approved by 9.8.4 or by the base has them) and say
     in the docstring that new plans have none. `scripts/drift.py:60` needs no change. The plan panel went with
     WP15, and with it the file list of `scripts/panel.py:108-112` and the `SEARCH` field of `:118-119, 132`:
     confirm that `scripts/card.py` took no `SEARCH` row over, and drop it there if it did.
  8. **Deviations.** `spec_ops.deviations` (`scripts/spec_ops.py:70-101`) writes `## Deviations` into `plan.md`
     and exits 1 with no `plan.md` (`:91-94`), at the commit (`scripts/flow.py:2143`). Write the same rows to
     `deviations.md` in the spec folder instead, replacing an earlier file, and never touch `plan.md`. One file
     works at every tier and leaves the approved files as the approval of WP12 saw them. The commit of the run's
     record takes the whole spec folder, so the file is in it.
  9. **Pages that name `plan.md` as a source.** The acceptance writer learns entry points from the
     `**Interfaces:**` and `**File:**` lines of `tasks.md` (`agents/acceptance.md:16`); the fresh reviewer reads
     `plan.md` "when the plan has one" (`agents/plan-review.md:24`). The later door's folder rule
     (`commands/temper.md:199-203`) is removed by WP28; until then it reads "the folder that holds `tasks.md`".
  10. **Counts.** Regenerate the fixtures with `scripts/selftest/make-view-fixtures.sh` (its plan has three
      `Traced to` lines). Run `python3 scripts/check_caps.py` and write the new `now` of `gate_rows` and of
      `prompt_bytes`. `gate_rows` is the one key for every row name (`docs/plans/one-go/contracts.md` sections 12
      and 14): this package takes four names out of it, three of the CLI (32 less 3 by the count of the head) and
      one of `scripts/intent_draft_rows.py`. The floor holds no count of gate rows.
- **Removed:** the gate rows `criteria -> scenarios`, `cross-repo search recorded`, `blast radius documented` and
  `target users action chain`; `_cross_repo_recorded`; `context_choices` (gone since WP13); the sections named in
  steps 1, 2 and 4 from the three templates and the briefs; the `Traced to:` field; the `## Deviations` section of
  `plan.md`.
- **Documents in the same change:** `reference/plan.md` (the artifact list at `:26`, the tiers at `:37-40`, the
  scenario format, the grouped format); `docs/flow.md` (`spec deviations`); `docs/methodology.md` and
  `docs/ai-native-sdlc.md` where they state the three artifact rule; `templates/example-intent.md`;
  `CHANGELOG.md`; `docs/plans/one-go/changed-tests.md`. The line of the package in
  `docs/plans/one-go/PROGRESS.md` is the progress commit that follows (`docs/plans/one-go/README.md` section 4).
- **Done when:**
  - `bash scripts/verify.sh quick` is green.
  - `TEMPER_CASES_ONLY="1 2 5 11 14 16 70" bash scripts/selftest/test-temper.sh` ends `FAIL: 0`.
  - `python3 scripts/check_caps.py` exits 0 with `gate_rows` four lower than before this package (at the head the
    CLI held 32 of the names; 3 of them go here, and one row of `scripts/intent_draft_rows.py`); `D27a` and `D27b`
    are off the list.
  - `bun scripts/e2e/run.ts all default-run full-run --floor scripts/e2e/floor.json` exits 0.
- **Traps:**
  - Line `scripts/temper:3560` declares `complexity` for the blast radius row and for the tier row under it.
    Delete lines 3561 to 3568 only.
  - `agents/plan.md` is read by a model on Opus at $20 per million output tokens: the cut is worth what the
    planner stops writing, not the bytes of the brief. Do not spend time on wording the brief shorter.
  - `scripts/gate_rows.py:331-332` prints the Context Map row only when `plan.md` exists. That stays; step 5 is
    for a `plan.md` with no map.
  - The acceptance lock refuses tests that name no listed state (`scripts/check_run.py:495-508`): the
    `**States:**` line is kept for that reason, do not cut it with the other header lines.
  - `scripts/e2e/replay.ts` drives 9.8.4 too and holds four `Traced to` lines: its plan text must keep reading on
    both sides, so leave its fixture as it is and only confirm the replay's last line.
  - `case-helpers-5.sh` is made from `temper-cases-5.sh` by `scripts/selftest/make-helpers-5.sh`, and a case of
    `temper-cases-31.sh` fails when the two differ: edit the case file and regenerate.
  - The view fixtures are close to the 256 KiB limit; WP01 made room. Regenerating must not add a view.
- **Size:** M.

## WP27 A narrow revise agent; `code` and `metric` criteria by the CLI; models by tier and risk

- **Goal:** A change to an existing plan is made by a small agent on Sonnet that gets the reason and the affected
  task blocks, not by a second full planner pass. A criterion validated by `code` or `metric` is proven by a
  command the CLI runs, so a default run launches no record pass and no Check agent. Each agent's model comes
  from one table in code, by tier and risk, with config keys over it. The acceptance tests are still written by
  an agent of their own.
- **Depends on:** WP04, WP10, WP15, WP22, WP23, WP26.
- **Lane:** `flow core`.
- **Touches:** `agents/plan-revise.md` (new), `.claude-plugin/plugin.json`, `agents/build-task.md`, `agents/check.md`,
  `agents/intent.md`, `agents/acceptance.md`, `agents/plan.md`, `reference/plan.md`, `reference/build.md`,
  `reference/check.md`, `templates/intent.md`, `scripts/cli_ctx.py`, `scripts/temper` (`_resolve_model`,
  `_resolve_task_model`, `_resolve_task_escalation_model`, `cmd_model`, `cmd_risk`), `scripts/risk.py`,
  `scripts/acceptance.py`, `scripts/intent_draft_rows.py`, `scripts/scenario_ops.py`, `scripts/check_run.py`,
  `scripts/card.py`, the flow modules that hold `Flow.agent`, `stage_work`, `missing_records`, `criteria`,
  `task_model` and the Check question, both view fixture files, `tests/mod/session.test.ts`,
  `scripts/selftest/temper-cases-71.sh` (new), `scripts/e2e/scenarios.ts`, `scripts/e2e/accept.ts`,
  `scripts/e2e/floor.json`, `scripts/caps.json`, `scripts/selftest/expected-fail.txt`, `docs/flow.md`,
  `docs/grouped-build.md`, `docs/commands.md`, `docs/decisions/0022-the-acceptance-tests-keep-their-own-writer.md`
  (new), `CHANGELOG.md`.
- **Tests first:** `scripts/selftest/temper-cases-71.sh` (new).
  1. `w27 a note gets the revise agent`: a run at Plan whose `tasks.md` exists, with a person's note recorded as
     the page records a typed change (`commands/temper.md:154-160`: an `evidence add` of kind `input`, then
     `temper state redo plan --reason`). `temper next --json` names one agent of type
     `temper:temper-plan-revise` on `sonnet`; its prompt holds the note whole, a line `Affected tasks:`, no
     `Project brief:` line; the action's `calls` hold no `brief`.
  2. `w27 a finding is passed whole`: an open fresh finding of 600 characters is in the prompt whole (the head
     cuts it at 200, `scripts/flow.py:1334`), and `Affected tasks:` holds the number its claim names as `Task 3`.
  3. `w27 a first plan and a changed intent get the planner`: with no `tasks.md` the agent is
     `temper:temper-plan`; after a loop back to Intent that passes Plan again it is `temper:temper-plan` too.
  4. `w27 the second failure falls back`: after two revise launches for one reason with the plan gate still FAIL,
     the next launch before the approval is `temper:temper-plan` with the same items. After the approval the
     same state is the budget question of WP10 (`run.budget`), never a launch.
  5. `w27 a code criterion is run by the CLI`: an intent whose criterion `AC-02` has a Validate line of type
     `code` with the command `grep -q "POST /api/reset" src/routes.txt` in backticks, and a tree where the text
     is there.
     After `temper integrate` the build ledger has a row with `criterion` `AC-02`, `executed_by` `cli` and exit
     0; the row `criteria validated` passes; no action of `temper next` names an agent whose prompt holds
     `Record only`. With the text missing: the row has exit 1, the Build gate fails with the criterion and the
     command in its detail, and still no agent is named for it.
  6. `w27 a metric criterion`: a Validate line of type `metric` with the command
     `test "$(wc -c < out.txt)" -lt 2000` in backticks is recorded the same way at `integrate` and by
     `temper check run`, and with such a criterion the Check action has no agent.
  7. `w27 no command means the person confirms`: an accepted intent whose `code` criterion has prose and no
     command launches no agent; the criterion is in the list the person confirms where `manual` ones are. A
     draft intent with the same line fails the intent gate on the row `criteria validate`, and the detail says
     to write the command in backticks or to use `manual`.
  8. `w27 the model table`: `temper model --all --source` prints `opus` for plan and rca, `sonnet` for every
     other agent and for `task`, each with the source `table`. With `models.plan: sonnet` the plan line says
     `sonnet` from `config`. With `models.high.plan: opus` as well and risk H in the state it says `opus`. With
     `models.task: haiku` the task line says `haiku`; with the old key `build.grouped.task-model` it says the
     same. The `model:` line of every `agents/*.md` equals the table's standard value for that agent.
  9. `w27 a sensitive path makes risk H`: one declared production file `src/auth/login.ts` gives
     `RISK: H (1 production file; sensitive path src/auth/login.ts)` from `temper risk`; with
     `autonomy.park-on-touch: []` the same plan is L.
  10. `w27 the acceptance writer is alone and first`: at the start of Build `temper next --json` names exactly
      one agent, `temper:temper-acceptance`, and no task agent until the lock or the recorded skip exists. No
      file of `agents` but `agents/acceptance.md` holds `acceptance start` or `acceptance lock`.
  11. `tests/mod/session.test.ts`: a launch of `temper:temper-plan-revise` that the view names is allowed on the
      model the view names; the same launch with another prompt is refused as any other is.
  12. `scripts/e2e/accept.ts`: WP07 wrote `revise-narrow` and `criteria-by-cli` failing first. Make them pass
      and take their lines off `scripts/selftest/expected-fail.txt` in this commit, with the line of `D28` of
      `scripts/selftest/temper-cases-46.sh` (the builders on Sonnet, the planner on Opus behind a key).
- **Mechanism:** no prototype diff exists for this package; the mechanism of the revise agent is
  `docs/plans/one-go/evidence/v-lean-front.md`, part 4; of the criteria,
  `docs/plans/one-go/evidence/red-bad-runs.md`, finding M9.
  1. **The brief.** `agents/plan-revise.md`, frontmatter `name: temper-plan-revise`, `model: sonnet`, and a
     `**Gotchas**` section (`scripts/validate-plugin.sh:103-111` fails a brief without them). List it in
     `.claude-plugin/plugin.json:38-52`. It says, in under 6 KB and with no pointer to `reference/plan.md`: read
     `tasks.md` and the scenarios of `intent.md`; change only the task blocks the prompt names and the scenarios
     those tasks own; never a Success Criterion; the grouped format in ten lines (the field names of
     `templates/tasks.md`), the two byte budgets (`scripts/temper:107-108`), and that `temper gate plan` names
     each failed row with what it wants; run the gate and fix what it names; return `PLAN REVISED {spec path}`
     and one line per finding as `agents/plan.md:131-132` gives them. It draws no panel and names none: it says
     that the CLI draws the card (`temper card`), the form `scripts/validate-panels.py` accepts since WP15.
  2. **The prompt, a closed list of lines the CLI writes.** `Follow <plugin>/agents/plan-revise.md exactly.`;
     `Spec path:`; `Reason:` with one of `fresh findings`, `the person's note`, `the context answer`,
     `a decision against the plan`, `a failed plan row`, `a loop back from <stage>`; then every item whole, one
     a line (`Finding #<id> [<severity>]: <claim>`, `Person's note: <text>`, `Left open: <text>`,
     `Row <name>: <detail>`); `Affected tasks: 3, 4`; the Decisions line of `decisions_line`; the plugin line.
     The task numbers come from a `Task N` in an item (`agents/plan-review.md:77` makes a finding name one), the
     tasks of a group an item names, or the tasks that declare a file an item names. When none can be read the
     line is `Affected tasks: not named`. No `Project brief:` line, and no `brief` call in the action.
  3. **Where it is chosen.** `stage_work` for the stage plan (`scripts/flow.py:1316-1385`). Today every revision
     ends there as a full pass: open fresh findings (`:1330-1334`), a note (`:1133`), a loop back (`:1349-1354`).
     Choose the revise agent when `tasks.md` exists, at least one item exists, no loop back passes through Intent
     (`through`, `:1340-1348`), and fewer than two revise launches were made for this reason. Choose the planner
     otherwise. Its `after` calls are those of the planner: the usage row, `risk` (step 9), `baseline plan` (WP21)
     and `gate plan`. The `panel plan` call went with WP15.
  4. **The fall back.** Count each revise launch through the budget call of WP10 under the key
     `plan-revise:<reason>`. The first failed plan gate after a revise gets one more revise, with the failed
     rows added as items. After the second, before the approval, the next launch is the planner with the same
     items; after the approval the flow asks the budget question (`run.budget`), because a rule never plans again
     there (rule 4 of `docs/plans/one-go/README.md` section 6).
  5. **A criterion command.** In `acceptance.parse_criteria` (`scripts/acceptance.py:168-169`) add `vcmd`: the
     first backticked span of the Validate details when the type is `code` or `metric`. In the intent gate the
     row `criteria validate` (`scripts/intent_draft_rows.py:77-105`) also fails such a criterion with no `vcmd`.
     `templates/intent.md:26`, `reference/plan.md:261-262` and the gotcha at `agents/intent.md:155` show the
     form: a command that exits 0 when the criterion holds. A metric that can only be read after release is
     `manual`, and the brief says so.
  6. **The CLI runs it, twice.** In `scenario_ops.integrate` (`scripts/scenario_ops.py:133-155`), after the
     scenario commands: each criterion with a `vcmd` that is not deferred runs through the same runner and adds
     a row like the scenario rows, with `"phase": "criterion"`, `"criterion": "<id>"`, `"scenario": null` and
     `"executed_by": "cli"`. The CLI's Check run (`scripts/check_run.py`, where it runs the scenario commands)
     does the same into the check ledger. Use the runner and the reuse store WP22 and WP23 left, so a command
     that passed on an unchanged tree is not run again.
  7. **The gates read only that row.** `acceptance.build_report` (`scripts/acceptance.py:292-302`): a `code` or
     `metric` criterion with a `vcmd` passes only from a row of `cli_rows` (`:267`) that exited 0; a failed row
     is `FAIL: <cmd> exit N`; no row is `FAIL: its command has no row run by the CLI`; one with no `vcmd` is
     `CONFIRM`, as `manual` is (`:299-300`). In the Check branch (`:403-410`) accept a row only when
     `executed_by` is `cli` or `person`.
  8. **The two launches go.** Delete `Run.missing_records` (`scripts/flow.py:197-214`), the record pass
     (`:2415-2423`) and the state key `record_pass`. In `stage_work` delete the criteria branch of Check
     (`:1361-1373`): with `cli_check()` true the action is always `check run` and the gate, with no agent. The
     list the person confirms (`self.criteria("manual")`, `scripts/flow.py:824-836`) also takes `code` and
     `metric` criteria that have no `vcmd`. Rewrite `agents/check.md:9-10`, `reference/build.md:102-104` and
     `agents/acceptance.md:25`. Add the criterion commands to the `commands` rows of the approval card
     (`scripts/card.py`): the approval is of every command a gate will run.
  9. **Risk.** `risk.compute` (`scripts/risk.py:72-108`): a declared file that matches a pattern of
     `autonomy.park-on-touch` makes the level H with the reason `sensitive path <file>`. WP11 built this already,
     on the one Python matcher `scripts/sensitive.py` that it made of `_glob_touch_match` (`scripts/temper:4008`),
     and made `cmd_risk` (`scripts/temper:4625-4639`) pass the patterns: do not build it twice, test 9 holds it.
     New here: the CLI runs `temper risk` in the `after` calls of the planner and of the revise agent,
     before `gate plan` (the `panel plan` call went with WP15); take the instruction to run it out of
     `agents/plan.md:129`. `--raise` stays the planner's call.
  10. **The model table.** In `scripts/cli_ctx.py`, in place of `TASK_DEFAULT`, `ESCALATION_DEFAULT` and
      `RISK_TASK_MODEL` (`:22-24`), one table of two columns, `standard` and `high`:

      | Agent | standard | high |
      |---|---|---|
      | `plan`, `design`, `rca` | `opus` | `opus` |
      | `intent`, `plan-revise`, `plan-review`, `acceptance`, `build`, `review`, `check`, `fix`, `pipeline` | `sonnet` | `sonnet` |
      | `task`, `task-escalation` | `sonnet` | `sonnet` |

      The class is `high` when the run's tier is `complex` or its risk is H (`risky_run`, `:46-54`, becomes the
      class). `resolve` (`:57-79`) takes, in this order: `models.high.<agent>` when the class is `high`;
      `models.<agent>`; for `task` and `task-escalation` the old keys `build.grouped.task-model` and
      `build.grouped.escalation-model`; the table. The source it prints is `config` or `table`. The two columns
      are equal today on purpose: the planner stays on Opus until a bench round says otherwise (decision 4 of
      `docs/plans/one-go/README.md` section 3), and the `high` column is what lets that round, or a person, set
      a cheaper planner below risk H and keep Opus at risk H (`models.plan: sonnet` with `models.high.plan: opus`;
      in the table, `sonnet` in the `standard` column and `opus` in the `high` column). This package keeps
      `opus` in both columns. After it the table has one writer: the bench block of WP32, which may change the
      planner's default below risk H by the rule of its model test, in one small commit with its test. No other
      package changes a default of the table.
  11. **One resolver.** `_resolve_model`, `_resolve_task_model` and `_resolve_task_escalation_model`
      (`scripts/temper:567-589`) call `python3 cli_ctx.py models` (`scripts/cli_ctx.py:4`) and hold no default of
      their own. `fresh_work` (`scripts/flow.py:1284-1287`) and `acceptance_work` (`:1411-1414`) take their
      model from the same call. `agents/build-task.md:4` becomes `model: sonnet`.
  12. **The acceptance writer.** No change of order or of agent: `acceptance_work`
      (`scripts/flow.py:1394-1420`) launches `temper:temper-acceptance` alone before any group. Running it
      beside the first builder is not built: it needs a bench arm, and the first builders would lose the line
      that points them at the locked tests (`acceptance_line`, `:1436-1441`). Test 10 pins the order.
  13. **Counts.** Regenerate the fixtures. `agent_briefs` in `scripts/caps.json` moves by one for the new brief.
      The floor of `default-run` keeps its launches: a clean run has no revision. `agents/check.md` stays while
      `stage_work` can still launch it (a stack with no test command the CLI finds, or a step back with a note).
      If WP19 and WP20 left no such launch, delete the brief, its line in the manifest and its row of the table
      here, and `agent_briefs` ends one lower. If the `final` of `agent_briefs` in `scripts/caps.json` is below
      what this leaves, write that in `PROGRESS.md` as a blocker for the owner: do not delete a brief that is
      still launched to meet a number.
- **Removed:** the record pass and `missing_records`; the Check agent launch for criteria; the 200 character cut
  of a finding; the three model constants of `scripts/cli_ctx.py:22-24` and the copies of them in
  `scripts/temper:573-589`; Haiku as the default of the task agents; the line that told the planner to run
  `temper risk`.
- **Documents in the same change:** `docs/flow.md` (the revise agent as an action, the criterion rows);
  `docs/grouped-build.md` (the builders run on Sonnet; `models.task: haiku` for cents, with the two measured
  figures of `docs/evidence/haiku-sonnet-task-agents.md`); `docs/commands.md` (`temper model`);
  `reference/plan.md` (Validate types); the decision record
  `docs/decisions/0022-the-acceptance-tests-keep-their-own-writer.md`: "The tests that gate the code are written
  by an agent that does not write it; `code` and `metric` criteria are commands the CLI runs";
  `CHANGELOG.md`. The line of the package in `docs/plans/one-go/PROGRESS.md` is the progress commit that follows.
- **Done when:**
  - `bash scripts/verify.sh quick` is green and `python3 scripts/check_done.py` shows `revise-narrow` and
    `criteria-by-cli` as `ok`.
  - `scripts/temper model --all --source` in a clone prints the table of step 10.
  - `claude plugin test .`, `tsc -p tsconfig.mod.json` and `bash scripts/check-mod-calls.sh` pass.
  - `git grep -n "Record only" scripts` prints nothing.
  - `bash scripts/verify.sh full` is green: this package ends phase 7.
- **Traps:**
  - `agents/build-task.md` is 6,043 bytes and `TASK_BRIEF_MAX_BYTES` is 6,144 (`scripts/temper:106`, checked at
    `scripts/selftest/temper-cases-5.sh:1170-1172`). The new `model:` line frees 10 bytes; add nothing else.
  - The first planner launch of a run has no risk and no final tier yet, so its class is `standard`. The `high`
    column therefore decides later launches and every agent after the plan. Say this next to the keys in
    `docs/commands.md`; do not invent a risk guess before planning.
  - The mod's option `reviewerModel` sets the model of the two reviewers in a `turn.step` hook
    (`hooks/temper-mod/register.tsx:659, 678-680`) and `phaseModels` reaches only the main loop. The table does
    not see either; leave both.
  - The view fixtures and several scripted scenarios hold `claude-haiku-5-5` as the task model. Regenerate the
    fixtures; in `scripts/e2e` search for the model name and for `Model:` in expected prompts.
  - A criterion command is written by the Intent agent and run by the CLI. It is covered by the approval only
    because the card shows it and WP12 binds the intent; do not run one from an intent that is not accepted.
  - `scenario_ops.integrate` appends rows to the ledger file it rewrites whole (`:137-155`): add the criterion
    rows inside the same read and write, not in a second pass that could lose the first.
  - A revise launch after the approval happens only on an option the person picked. If a test shows `next`
    returning the revise agent as an `auto` step of an unattended run, the choice of step 3 is wrong.
- **Size:** L.

## WP28 Two listed commands; the words of `/temper:temper`; the doors removed

- **Goal:** A session lists two Temper commands, `/temper:temper` and `/temper:fix`. What the other nine did is
  either a first word of `/temper:temper` (`draft`, `status`, `report`, `init`, `pack`) or gone (the five doors).
  A first word is taken as a word only in its documented form, so a request that starts with "status" starts a
  run.
- **Depends on:** WP05, WP07, WP13, WP16, WP17, WP26 (it cut the Target Users section that the draft page no
  longer asks about).
- **Lane:** `flow core` (it removes the door code from the CLI and the flow and regenerates the fixtures).
- **Touches:** `commands/temper.md`, `commands/intent.md`, `commands/plan.md`, `commands/design.md`,
  `commands/build.md`, `commands/review.md`, `commands/check.md`, `commands/status.md`, `commands/init.md`,
  `commands/pack.md` (the last nine deleted), `reference/draft.md` (new), `reference/pack.md`,
  `reference/status.md` (deleted), `.claude-plugin/plugin.json`, `scripts/validate-docs.sh`, `scripts/temper`
  (`cmd_state_init`, the `enter` and `built_before` keys, `_earlier_build`), `scripts/earlier_build.py`
  (deleted), the flow modules that hold `walked` and the readers of `built_before`,
  `scripts/guards/stage-marker.sh`, `hooks/hooks.json`, `hooks/temper-mod/core/commands.ts`,
  `hooks/temper-mod/core/session.ts`, `hooks/temper-mod/register.tsx`, `tests/mod/session.test.ts`,
  `tests/mod/dialog.test.ts` and the mod test that covers `parseArgs`, both view fixture files,
  `scripts/selftest/temper-cases-8.sh`, `-9.sh`, the cases of the stage marker, `temper-cases-72.sh` (new),
  `scripts/caps.json`, `docs/commands.md`, `docs/flow.md`, `README.md` (the Commands table and one hook line),
  `.claude/CLAUDE.md`, `scripts/selftest/expected-fail.txt`, `docs/plans/one-go/changed-tests.md`, `CHANGELOG.md`.
- **Tests first:** `scripts/selftest/temper-cases-72.sh` (new). WP07 holds the surface checks of row `D29` in
  `scripts/selftest/temper-cases-46.sh` (`D29a` to `D29c`): take each one this package makes pass off the expected
  to fail list, and name WP31 on the line of each that still fails on a retired word.
  1. `w28 two listed commands`: the `commands` of `.claude-plugin/plugin.json` are exactly
     `./commands/temper.md` and `./commands/fix.md`, and `git ls-files commands` prints those two files.
  2. `w28 the words have their pages`: the Arguments table of `commands/temper.md` has a row for each of
     `status`, `report`, `draft`, `init`, `pack` and `help`; `reference/draft.md` and `reference/pack.md` exist;
     `reference/status.md` does not.
  3. `w28 no page names a command that is gone`: a `git grep -nE` for `/temper:` followed by one of
     `intent`, `plan`, `design`, `build`, `review`, `check`, `status`, `init`, `pack` and a word end, over
     `commands`, `agents`, `reference`, `templates`, `packs`, `skills`, `scripts/guards`, `hooks/hooks.json`
     and `README.md`, prints nothing.
  4. `w28 no door`: `temper state init demo --enter build` exits 1 with one line that says the doors are gone
     and that `/temper:temper` takes up the active run; `temper --help` holds no `--enter`.
  5. `w28 the draft word owes its gate`: given a hook input whose `prompt` is `/temper:temper draft an idea`,
     `scripts/guards/stage-marker.sh` writes `.temper/pending-stage.json` for the stage intent; for the prompts
     `/temper:temper add a thing` and `/temper:intent x` it writes nothing.
  6. Mod tests. `requestOf('status')` is null and `requestOf('status badge on the order page')` is the text.
     `requestOf('draft a refund flow')`, `requestOf('init')`, `requestOf('pack')` and
     `requestOf('pack enable guardrails')` are null; `requestOf('pack the response with gzip')` is the text.
     `parseArgs('status')` gives the word and `parseArgs('status badge')` gives null. A run word typed as
     `/temper:temper status badge on the order page` reaches the driver as a request.
  7. Search `scripts/e2e` and `tests/mod` for `--enter` and for the nine command names. At the head no scripted
     scenario enters through a door; `tests/mod/dialog.test.ts:398` runs the command `temper:plan`: move that
     case to `temper:fix`, the one other command left, and list it in `docs/plans/one-go/changed-tests.md`.
  8. `bash scripts/validate-docs.sh` and `bash scripts/validate-plugin.sh` pass with the rows of mechanism
     step 7.
- **Mechanism:**
  1. **Each command file.**

     | File | After | What stands in its place |
     |---|---|---|
     | `commands/temper.md` | kept, listed | its Arguments table (`:30-44`) gains the three new words; the part "Entering at a stage" (`:190-206`) goes |
     | `commands/fix.md` | kept, listed | nothing changes here |
     | `commands/intent.md` | deleted | the word `draft <idea>`, which reads `reference/draft.md` |
     | `commands/plan.md`, `design.md`, `build.md`, `review.md`, `check.md` | deleted | nothing: `/temper:temper "<feature>"` starts a run, and with no words it takes up the active one |
     | `commands/status.md` | deleted | the word `status` (`commands/temper.md:37`): `temper status` and the `say` of `temper next --json` |
     | `commands/init.md` | deleted | the word `init`: the three setup calls, each once, and what each printed |
     | `commands/pack.md` | deleted | the word `pack`, which reads `reference/pack.md` |
     | (never a file) | kept | the word `report` (`commands/temper.md:38`) |

  2. **`draft`.** Move the body of `commands/intent.md` to `reference/draft.md` as the page the word reads: the
     interview in the main session, the draft `intent.md` with `Status: draft`, `temper gate intent` at the end,
     no run started. Take out the question for a reviewer (`commands/intent.md:46-47`; the Intent brief says
     never to ask it) and the Target Users probe (WP26 cut the section). A later `/temper:temper "<feature>"`
     finds the folder by its `intent.md` (`commands/temper.md:55-59`), so a draft needs no door.
  3. **`init`.** The row says: run `temper config init`, `temper init` and `temper guards install`, each once,
     and show what each printed, as the Start part does for `setup` (`commands/temper.md:50-54`). The 116 lines
     of `commands/init.md` on hook managers (`:59-174`) go to `docs/commands.md` in short: the installer prints
     the line to paste itself. `temper guards uninstall` is named there too.
  4. **`pack`.** Merge the steps of `commands/pack.md` that `reference/pack.md` lacks into that page and delete
     the command. The word alone shows the packs and how to change `packs:`; `pack enable guardrails` and
     `pack disable guardrails` print the hooks with `scripts/guardrails-snippet.py`. The launcher packs and
     `scripts/pack-discover.py` stay: the plan names no removal for them, and a validator and two selftests hold
     the script (`scripts/validate-plugin.sh:310-317`, `scripts/selftest/temper-cases-1.sh:410-469`).
  5. **The form of a word.** One rule, in `commands/temper.md` and in the mod:
     - alone, and nothing after it: `status`, `report`, `timeline`, `help`, `init`, `pack`, `mode`,
       `enforcement`, `pane`, and the wish words `approve`, `next`, `back`, `override`, `accept`, `drift`, `pr`;
     - with text after it: `draft <idea>`, `discuss <text>`, `chose <label>`, and `pack enable guardrails` or
       `pack disable guardrails`;
     - anything else is a request.

     In `hooks/temper-mod/core/session.ts:232-238` replace `NOT_A_REQUEST` and `requestOf` by that rule. In
     `hooks/temper-mod/core/commands.ts:15-19` `parseArgs` gives a word only when nothing follows it (no
     handler reads `rest`), and `HELP` (`:22-31`) lists `draft`, `init` and `pack` and says that any other text
     is a request. `drives` (`hooks/temper-mod/register.tsx:611-619`) then starts a run for
     "status badge on the order page" and none for `draft an idea`, which goes on to the page.
  6. **The hook pair follows the word.** `scripts/guards/stage-marker.sh:126` matches `/temper:intent*`: match
     `/temper:temper draft *` and `/temper draft *` instead, and rewrite its header (`:5-19`), the description
     of `hooks/hooks.json:2`, the comment at `scripts/temper:4315` and the last line of the README's hook
     bullet (`README.md:78`). The guarantee of ADR 0005 is unchanged: a session that captured a draft owes the
     intent gate.
  7. **The manifest and the validators.** `.claude-plugin/plugin.json:25-37` keeps two entries.
     `scripts/validate-docs.sh` rule 1 fails a command file the manifest does not list (`:45-48, 59-62`), so the
     nine files are deleted, never left unlisted, and no word gets a file under `commands`. In its table of
     rows (`:222-258`) delete the rows of `:233-235` and `:242-247`, and add four: `commands/temper.md` must hold
     `reference/draft.md` and `reference/pack.md`, and must not hold `## Entering at a stage` or `--enter`.
     `scripts/caps.json`: `listed_commands` is 2.
  8. **The door code.** Delete `--enter` from `cmd_state_init` (`scripts/temper:699-706`) and refuse the flag
     with the line of test 4 (today an unknown flag is skipped by `*) shift ;;`). Delete the tier lookup for a
     door (`:948`), the writes and reads of `built_before` (`:1283-1284, 3704-3705, 4297-4300`),
     `_earlier_build` (`:3607-3631`) and `scripts/earlier_build.py`. Keep the line that refuses
     `state set enter` and `state set built_before` (`:857`): a refused key costs nothing. In the flow delete
     `walked` (`scripts/flow.py:1110-1116`) and its three callers (`:600, 2400, 2431`), and the two readers of
     `built_before` (`:1402, 1656-1657`). The door case of the Intent question that WP13 kept goes with them, and
     so do the two callers added since the head: the condition "no door walked Intent" of `intent_by_rule` (WP13)
     and the door branch of the baseline (WP20 step 16). `baseline start --env-only` then has no caller in the
     flow; the flag stays a word of the CLI (`docs/plans/one-go/contracts.md` section 2).
     In `hooks/temper-mod/register.tsx:724-725` the comment on a door goes; the line still drops the request
     for `/temper:fix`. Leave `enter` and `built_before` in the mod's `GUARD_KEYS`
     (`hooks/temper-mod/core/rules.ts:335`; `tests/mod/audit-round4.test.ts:240` holds them): a saved state may
     carry the keys, and a guard list does not shrink without a decision record.
  9. **Fixtures and counts.** Regenerate the fixtures; write the new `now` of `question_sites`, `option_sites`,
     `option_labels`, `prompt_bytes` and `cli_bytes` in `scripts/caps.json`, and of `readme_lines` when the
     page's line count moved (its Commands table loses two rows).
- **Removed:** nine command files and `reference/status.md`; the five doors with `state init --enter`, the state
  keys `enter` and `built_before`, `walked`, `_earlier_build` and `scripts/earlier_build.py`; the part "Entering
  at a stage"; the rule that any first word in a list is a word whatever follows it.
- **Documents in the same change:** `docs/commands.md`: the parts for the nine commands
  (`:188-211, 265-579, 630-859`) become one part per listed command, one part "Words of `/temper:temper`" and
  the CLI calls;
  `docs/flow.md` (no `enter`); the Commands table of `README.md:64-71`; the command table and the two known
  mistakes on doors in `.claude/CLAUDE.md`; `docs/plans/one-go/changed-tests.md`; `CHANGELOG.md` (with one line
  for what is lost: a planned folder with no run is started from its intent, and its plan is written again).
- **Done when:**
  - `bash scripts/verify.sh quick` is green.
  - `bash scripts/validate-docs.sh`, `bash scripts/validate-plugin.sh` and `bash scripts/validate-directory.sh`
    exit 0.
  - `claude plugin test .`, `tsc -p tsconfig.mod.json` and `bash scripts/check-mod-calls.sh` pass.
  - `python3 scripts/check_caps.py` exits 0 with `listed_commands` at 2.
  - `git grep -n "built_before\|--enter" scripts hooks commands` prints only the two refusals of step 8 and the
    guard list of the mod.
- **Traps:**
  - A row of `scripts/validate-docs.sh` whose page is missing fails for both signs (`:259-263`): delete the rows
    of a deleted page in the same commit as the page.
  - `scripts/validate-plugin.sh:154-155` needs `commands/temper.md`, and `:31` needs the key `commands`.
  - With the mod loaded, a word the mod does not know becomes the request of a new run
    (`hooks/temper-mod/register.tsx:742-754`). Change the mod and the page in one commit, or `draft an idea`
    starts a feature run named "draft an idea".
  - `temper-cases-8.sh` and `-9.sh` hold 13 uses of `--enter` that state the door behaviour on purpose. Delete
    those cases and list them; do not turn them into cases of something else.
  - A run that 9.8.4 or the base saved after it came through a door has `enter` in its state. The key is ignored
    from here: a stage before the door with no verdict runs its agent. It is not an error. Say it in the
    `CHANGELOG.md` line of this package; carrying it into what a project of 9.8.4 reads is left to WP31.
  - The words `discuss` and `chose` carried the hand back of the driver at the head. WP16 owns their meaning: it
    removed the hand back words `next` and `discuss` and made the note `step KIND OPTION`. This package only
    moves the words WP16 left into the rule of step 5; it brings none back.
  - `README.md` must keep its Install heading, the heading "What the mod reads and writes" and the line
    `Intent, Plan, Build, Review, Check` before any diagram (`scripts/validate-directory.sh:73-81`).
- **Size:** L.

## WP29 Defaults in code; a template of 10 live lines; the one time question; every key has a reader

- **Goal:** A new project gets a config of 10 live lines, and every other default lives in one table in the
  CLI. A project with an older config, first of all one of 9.8.4, is asked once whether the lines that only
  repeat old defaults may go, so that the new defaults reach it. Every key the template or a page names is read
  by code, and no agent is told to read the config.
- **Depends on:** WP04, WP08, WP10, WP11, WP13, WP14, WP19, WP21, WP27, WP28.
- **Lane:** `flow core` (one new question, a new line in agent prompts, the fixtures).
- **Touches:** `templates/temper.config.default`, `.claude/temper.config`, `scripts/defaults.py` (new),
  `scripts/config_yaml.py`, `scripts/config_tidy.py` (new), `scripts/check_config_keys.py` (new), `scripts/temper`
  (`_cfg_get` and its callers, `cmd_config`, a new `cmd_packs`), `scripts/cli_ctx.py`, the flow modules that hold
  `Run.cfg`, `Flow.agent` and the order of questions, `scripts/flow_base.py` (the registries of WP04),
  `scripts/stops.json`, `hooks/temper-mod/core/rules.ts`, `tests/mod/audit.test.ts` (person only calls),
  `agents/rca.md`, `agents/fix.md`, `reference/plan.md`, `reference/build.md`, `reference/review.md`,
  `reference/check.md`, `reference/design.md`, `reference/fix.md`, `reference/pack.md`,
  `reference/orchestrator-patterns.md`, `scripts/quality-check.sh`, `scripts/selftest/test-temper.sh`,
  `scripts/selftest/case-helpers.sh`, `scripts/selftest/temper-cases-73.sh` (new), both view fixture files,
  `scripts/selftest/expected-fail.txt`, `scripts/caps.json`, `docs/commands.md`, `docs/packs.md`, `docs/flow.md`,
  `docs/enterprise.md`, `docs/recommended-setup.md`, `docs/decisions/0023-two-commands-and-defaults-in-code.md` (new),
  `CHANGELOG.md`.
- **Tests first:** `scripts/selftest/temper-cases-73.sh` (new).
  1. `w29 the template has 10 live lines`: `templates/temper.config.default` has exactly the 10 key lines of
     mechanism step 1 that are not comments, at most 25 lines in all, and `temper config init` in an empty
     project writes it byte equal.
  2. `w29 a default comes from the table`: in a project with an empty config, `temper config get` prints the
     table's value for `review.block-on`, `packs`, `run.default` and `autonomy.park-on-touch`, and
     `temper config show` prints every key of the table with the source `default`.
  3. `w29 every key has a reader`: `python3 scripts/check_config_keys.py` exits 0 (mechanism step 4). Give it one
     failing input of each kind in a throwaway copy: a key in the table that no file reads, a key read in code
     that the table lacks, a key in the template that the table lacks, a page that names a key that is gone.
  4. `w29 no agent is sent to the config`: `git grep -nF ".claude/temper.config" -- agents reference` prints
     only lines of `reference/pack.md`. A page may still name a call of `temper config get`.
  5. `w29 the CLI names the pack files`: with the default config, the prompt of the plan agent in
     `temper next --json` holds one `Packs:` line with the full paths of `packs/security/rules.md` and
     `packs/tdd/rules.md` of the plugin; the Intent agent's prompt holds none; a project file
     `.claude/packs/security/rules.md` takes the place of the plugin's; a pack whose `phases:` leaves the stage
     out is not listed.
  6. `w29 an old config is asked once`: a project whose config is the 9.8.4 template
     (`git show 7c7a1c1:templates/temper.config.default`, what users have), at the start of a run: the first
     `temper next --json` is the question `config.tidy`, its text names the count of lines and the copy, and its
     two options carry the calls `config tidy --apply` and `config tidy --keep`. The same for the template of
     the base (`git show 10e965a:templates/temper.config.default`, 171 lines against 147), which already says
     `block-on: [critical, high]`. The cases read both texts from `scripts/selftest/saved-old.json` (WP07 stored
     them under the keys `7c7a1c1` and `10e965a`), so they need no old commit when they run.
  7. `w29 yes gives the new defaults`: after `temper config tidy --apply` the file is the new template, the copy
     `.claude/temper.config.before-9.8.5` is byte equal to the old file, and `temper next --json` is no longer
     that question. Run it on the 9.8.4 template and on the template of the base.
  8. `w29 yes keeps what the person changed`: an old config with `coverage-threshold: 60`,
     `block-on: [critical]`, `enabled: false` under `autonomy` and `max-parallel: 7`. After `--apply`:
     `check.coverage-threshold` is 60 and `build.grouped.max-parallel` is 7 from `config`; `review.block-on`
     is the new default (the old value was the 9.8.4 default); `run.default` is `ask` from `config`; no line
     names `autonomy.enabled`.
  9. `w29 no keeps the file`: after `temper config tidy --keep` the file is the old one plus the key
     `upgrade.asked`, the question is not asked again, and the old values still rule
     (`check.coverage-threshold` is 80).
  10. `w29 never in the middle of a run`: with a run past Intent, `temper config tidy --apply` exits 1 and
      changes nothing; with a fix run active the question is not asked.
  11. `w29 a repeated block is merged`: the case WP08 wrote for M8 still passes (an appended `upgrade:` block
      must not drop another block).
  12. `tests/mod`: in the audit table of person only calls, `config tidy` counts only as the picked option of
      the `Temper gate` question the view holds; the same call from the model is refused. Add the fixture view
      of the question in the same change.
  13. `scripts/selftest/temper-cases-46.sh`: the cases of WP07 that read the 9.8.4 template and the template of
      the base as the project's config (the tokens of rows `D61` and `D62`), `D63b` (the one time question never
      flips an existing `autonomy.enabled: false`, as test 8 has it) and `D71` pass here; take them off
      the expected to fail list. `default-run` still asks two dialogs: a fresh project is never asked.
- **Mechanism:**
  1. **The template.** These lines, and nothing else that is not a comment:

     ```yaml
     # Temper configuration. Only your choices live here; every other setting has its default in the CLI.
     # `temper config show` prints each key, its value and where the value comes from.
     run:
       default: to-commit          # to-commit | ask (a question at every stage) | never-unattended
     packs: [security, tdd]        # the rules the agents follow; more in docs/packs.md
     review:
       block-on: [critical, high]  # finding levels that stop a run
     autonomy:
       park-on-touch: ["**/auth/**", "**/payment/**", "**/billing/**"]  # sensitive paths
     models:
       plan: opus                  # the planner
       task: sonnet                # the builders; haiku costs less and takes longer
     # Your project's own commands and environment, when what the CLI detects is wrong:
     # check:
     #   commands:
     #     test: npm test
     #     coverage: npx c8 npm test
     # setup:
     #   run: nvm use
     #   services:
     #     postgres: 127.0.0.1:5432
     ```

     The 10 live lines are `run`, `default`, `packs`, `review`, `block-on`, `autonomy`, `park-on-touch`,
     `models`, `plan` and `task`. The comment on `park-on-touch` says "sensitive paths: named at the approval,
     never repaired by rule" if it fits in 120 columns.
  2. **One table.** `scripts/defaults.py` holds `KEYS`: for each dot path its default, the literal a reader is
     found by, and one line of meaning; `OLD`: for each dot path the values that an earlier template shipped as
     live lines, with the version that retired them (9.8.5; fill it from the template of 9.8.4 first, then from
     the template of the base); `GONE`: each key that is no longer read, with its
     replacement or an empty string. `config_yaml.get` (`scripts/config_yaml.py:60-72`) takes the default from
     `KEYS` when the caller gives none, and reads a renamed key under its old name when the new one is absent.
     `_cfg_get` (`scripts/temper:523`) and `Run.cfg` (`scripts/flow.py:220-222`) call it with no default; take
     the default words out of their callers (`scripts/temper:574-4938` holds about 30, the flow about 20). The
     table then states a default once. `temper config show` prints `key`, `value` and the source (`config`,
     `default`, or `old name <key>`), then one line `not read: <key>` for each key of the file that is in
     neither `KEYS` nor `GONE`. An unknown key is never an error.
  3. **Every key and what becomes of it.** A key an earlier package already took out is checked here, not
     removed twice.

     | Key at the head | After | Its replacement, or its reader |
     |---|---|---|
     | `run.default` (WP11) | live line | read by the flow |
     | `packs` | live line, default `[security, tdd]` | read by the CLI (step 5); the old default of five packs is in `OLD` |
     | `review.block-on` | live line | `scripts/temper:3814`, `scripts/flow.py:420`; `[critical]` is in `OLD` |
     | `autonomy.park-on-touch` | live line | `scripts/temper:4204`, `scripts/sensitive.py` and `scripts/risk.py` (WP11), the card |
     | `models.plan`, `models.task` | live lines | the table of WP27; `models.<agent>` and `models.high.<agent>` stay readable |
     | `check.commands.test`, `.coverage` | comment example | `scripts/flow.py:1554`, `scripts/temper:4938` |
     | `setup.run`, `.env`, `.services`, `.tools` | comment example | `scripts/run_env.py:79` |
     | `build.grouped.task-model`, `.escalation-model` | read as old names | `models.task`, `models.task-escalation` |
     | `build.grouped.max-parallel`, `.max-groups`, `.keep-days`, `build.red-before-code` | in the table, not in the template | `scripts/temper:1451, 2207, 3115`, `scripts/flow.py:1678, 1692` |
     | `autonomy.max-blast-radius` | in the table, not in the template | `scripts/temper:3587, 4192` |
     | `budget.per-failure`, `budget.per-run` (WP10) | in the table, not in the template | `scripts/budget.py` |
     | `upgrade.asked` (new here) | in the table, not in the template | the question of step 6; written by `config tidy --keep` |
     | `plan.fresh-review`, `-twice`, `-rounds` | in the table, not in the template | `scripts/flow.py:248-249`, `scripts/temper:3599, 4574` |
     | `phases.pipeline` | in the table, not in the template | `scripts/flow.py:233, 2215` |
     | `protect.paths`, `format.cmd` | in the table, not in the template | `scripts/guards/block-protected-paths.sh:50`, `scripts/guards/run-formatter.sh:53` |
     | `check.coverage-threshold` | read when set (WP19); `80` is in `OLD` | the rule `threshold` of WP19 |
     | `plan.context-check` | as WP13 left it; `auto` is in `OLD` | the flagged map is on the approval card |
     | `feedback.enabled` | gone (WP10 removed its reader); in `GONE` | the one budget of WP10 |
     | `autonomy.enabled` | read as `run.default: ask` when `false` (WP11) | `run.default` |
     | `autonomy.policy` | gone | `run.default` |
     | `autonomy.budget.max-total-loops`, `.max-stages` | gone (never read) | the one budget of WP10 |
     | `loops.max-per-type`, `fix.max-loops` | gone | the one budget of WP10 |
     | `phases.design` | gone | Design runs only when asked (WP14) |
     | `plan.preflight-timeout`, `plan.preflight-skip` | gone | the plan's commands run once on the base (WP21) |
     | `check.mutation-threshold` | gone | the planted bug score is information (WP19) |
     | `stack` | gone | the CLI detects the stack (`scripts/check_run.py:76-144`) |
     | `tools.mode` | gone | none: an agent uses a connected tool when there is one |
     | `tools.ocr.mode`, `bands.*`, `evidence.claimed-runs` | gone with WP30: a key that code still reads here stays in `KEYS`, and WP30 adds it to `GONE` when it removes the reader | none |
     | `check.environment` | gone | none: no script reads it; it guarded the Check agent's live step (`reference/check.md:42`), and that page keeps its rule from file names |

     Keys that only pages named and nothing reads go from those pages: `tools.label-findings`,
     `check.live-scenarios`, `review.confidence-threshold`, `review.auto-fix`, `check.debt-tracking`,
     `tools.ocr.timeout`, `tools.ocr.replace-defect-subagent`, `plan.default-depth`, `branch.pattern`,
     `branch.commit-style`, `eval.*` (`docs/getting-started.md:229-239`, `docs/recommended-setup.md:13, 94`,
     `docs/enterprise.md:99-100, 161, 176`, `reference/review.md`, `reference/check.md`).
  4. **The reader test.** `scripts/check_config_keys.py`, Python 3 and git only, called from
     `scripts/quality-check.sh`. It fails when: a key of `KEYS` has no reader (its literal is in no file of
     `scripts` but `defaults.py`); a key read through `_cfg_get`, `cfg(`, `.on(` or `config_yaml.get(` is in
     neither `KEYS` nor the old names of `GONE`; a key line of the template, live or comment, is not in `KEYS`; a
     dotted key under one of the template's top names appears in `agents`, `reference`, `commands`, `templates`,
     `README.md` or `docs` (history, plans, evidence and decisions left out) and is not in `KEYS`; a brief or a
     reference page other than `reference/pack.md` holds `temper.config`.
  5. **Packs by the CLI.** No code reads `packs:` today; an agent is told to read the config and resolve the
     files (`reference/plan.md:180-183`, `reference/build.md:12-16`, `reference/review.md:28-33`,
     `reference/check.md:99-104`, `reference/design.md:12-15`, `agents/rca.md:23-25`, `agents/fix.md:16`). Add
     `temper packs --stage <stage>`: for each name of `packs`, the project's `.claude/packs/<name>/rules.md` when
     it exists, else the plugin's, kept when the file's `phases:` is `all` or holds the stage (Plan also takes
     the packs of `build`, as `reference/plan.md:182-183` says). `Flow.agent` (`scripts/flow.py:1119-1136`) adds
     one line `Packs: <path>, <path>` for plan, design, build, review, check, rca and fix. The seven pages say
     "read the pack files your prompt lists" and lose the sentence on the config. The CLI reads nothing in the
     home folder, as the pack scan already does on purpose (`scripts/selftest/temper-cases-1.sh:410-451`), so a
     pack under `~/.claude/packs` is no longer found: say so in `docs/packs.md` and in the CHANGELOG.
  6. **The question.** Id `config.tidy`, header `Temper gate`, asked by the flow before any other question or
     launch when all of these hold: the run is a `/temper:temper` run at Intent with no agent launched yet; the
     config holds at least one line of `OLD` or one key of `GONE`; the config has no `upgrade.asked` at or above
     the version that retired that line. Text: "Your config holds N lines that only repeat old defaults or are
     no longer read. Remove them so the new defaults apply? A copy is kept." followed by at most eight of the
     lines, each with what changes, then "and M more". The four that change a run are always among the eight:
     the coverage threshold, `phases.design`, the five packs, `block-on: [critical]`. Options:
     "Remove them (Recommended)", id `tidy-config`, with the call `temper config tidy --apply`, and
     "Keep my file", id `keep-config`, with `temper config tidy --keep`.
  7. **What the two calls do.** `scripts/config_tidy.py`. `--apply` reads the file's leaves, drops each leaf
     whose value is in `OLD` for its key and each key of `GONE` with no replacement, moves a renamed key to its
     new name, turns `autonomy.enabled: false` into `run.default: ask`, copies the old file to
     `.claude/temper.config.before-<version>`, and writes the new template with the kept leaves in place of or
     after its lines. `--keep` appends `upgrade:` with `asked: "<version>"`. Both print what they did, and both
     exit 1 when the run is past Intent, is a fix run or is unattended. An explicit opt out is never flipped:
     `enabled: false` becomes `ask`, never the new default, and the question says so on that line.
  8. **Only the person.** Add `config tidy` to the person only calls of the mod
     (`hooks/temper-mod/core/rules.ts:476-497`) with its fixture view and its row in the audit test, and add
     the question to `scripts/stops.json` as a stop that must stay. With the mod off the rule is the CLI's
     refusal of step 7 and the page's rule that an option is the person's.
  9. **The fixtures of the tests.** The config the selftest writes (`scripts/selftest/test-temper.sh:58-79`)
     holds old lines (`block-on: [critical]`, `coverage-threshold: 80`, `enabled: false`, the two budget keys).
     Write it as the new template plus the keys a case needs, or every case that walks a run from its start
     gets one more question. The projects of `scripts/e2e` get their config from `config init`, so they are
     never asked; the floor of two dialogs proves it.
  10. **This repository's own config.** `.claude/temper.config` holds `block-on: [critical]`,
      `coverage-threshold: 80`, five packs and `enabled: false` (`:16, 31, 34, 72`). Run `config tidy --apply`
      on it in this commit and take the `run.default: ask` it writes out again: the owner asked for the run that
      asks twice. This is the one place a build step sets aside an opt out; write it in `PROGRESS.md` so the
      owner sees it.
- **Removed:** about 150 of the template's 171 lines; the default words at the call sites of `_cfg_get` and `cfg`; the
  sentence that sends an agent to the config, in seven pages; the home folder tier of packs; every key marked
  gone in step 3 from the template, the pages and the docs.
- **Documents in the same change:** `docs/commands.md`: one table of every key of `KEYS` (generated by
  `temper config show --markdown`, so it cannot drift) and the table of step 3 as "what became of an old key";
  `docs/packs.md` (two default packs, two tiers); `docs/flow.md` (the question and its two calls);
  `docs/enterprise.md:99-176` and `docs/recommended-setup.md:13, 94` (the dead keys); the decision record
  `docs/decisions/0023-two-commands-and-defaults-in-code.md` ("Defaults live in code; an old config is asked about
  once", with the two commands and the words of WP28); `CHANGELOG.md`.
- **Done when:**
  - `bash scripts/verify.sh quick` is green; `python3 scripts/check_config_keys.py` exits 0.
  - `python3 scripts/check_caps.py` exits 0 with `config_live_keys` at 10 and `config_lines` at 25 or fewer.
  - `bun scripts/e2e/run.ts all default-run fix --floor scripts/e2e/floor.json` exits 0 with the same dialogs.
  - `claude plugin test .`, `tsc -p tsconfig.mod.json`, `bash scripts/check-mod-calls.sh` pass.
  - The rows this package turns green are listed under its id in "Rows by package" of
    `docs/plans/one-go/done.md`; that section wins over this list. Rows `D61` and `D62` there name the config of
    9.8.4 first and the config of the base second.
- **Traps:**
  - `config_yaml` reads a small subset: inline lists only, and an empty value opens a block
    (`scripts/config_yaml.py:27-33`). `config_tidy.py` must write only that subset, and `asked` as a quoted
    string, or `9.8.5` fails the number parse and is kept as text by luck.
  - The mod guards `.claude/temper.config` during a run (`hooks/temper-mod/core/rules.ts:122, 173`). The write
    here is the CLI's own, inside a call the person picked; do not make the page edit the file.
  - The driver greps the config for the git pack (`hooks/temper-mod/core/driver.ts:502`) at the head. WP16
    replaced that line; if it is still there, a fix run on `main` gets no branch once the default packs are two.
  - `scripts/selftest/temper-cases-23.sh:18` counts three template lines on the setup block and the preflight
    keys; it states the old template on purpose. Rewrite it and list it in `changed-tests.md`.
  - A person's `block-on: [critical]` cannot be told from the 9.8.4 default. The question lists it as "high
    will block too"; a person who wants the old value answers "Keep my file" or writes the line again.
  - `scripts/check_config_keys.py` is a script under the directory rules: no path with a folder named `hooks`,
    `tests`, `mod`, `core` or `ui`, no wildcard after a variable (`scripts/validate-directory.sh:5-40`). It
    reads `scripts`, `agents`, `reference`, `commands`, `templates` and `docs` through `git grep` pathspecs.
  - `reference/pack.md` lets an entry of `packs:` be an object with `link` or `phases` (`:66, 194`), and
    `config_yaml` splits an inline list at every comma (`scripts/config_yaml.py:31-33`). Read the raw `packs:`
    line: a plain name resolves to its rules file; an entry in braces goes into a second prompt line
    `Pack entries:` as written, and `reference/pack.md` says what an agent does with it. `config tidy` keeps
    such a line as it is.
  - `Flow.agent` builds the prompt the mod compares word for word with the launch. The `Packs:` line must be in
    the view's prompt, which it is when it is added in `Flow.agent`; never add it in the page.
  - The live line `plan: opus` of the template restates the table of WP27, and a config line wins over the
    table. If the model test of WP32 changes the planner's default, its commit turns this line into a comment in
    the template and in this repository's own config (WP32 step 7 (e)); this package changes nothing for it.
- **Size:** L.

## WP30 Packs, skills and dormant machinery removed

- **Goal:** What no default run reads is not shipped: six stack packs, three skills nobody can call, the OCR
  text, the bands monitor, review memory, the metrics writes and the key `evidence.claimed-runs`. For each
  piece the proof that nothing a run needs depends on it is a command in the table below, run again before the
  delete.
- **Depends on:** WP16, WP19, WP27, WP28, WP29.
- **Lane:** `flow core` (it edits `scripts/temper`, `scripts/runs.py` and the config the selftest writes).
- **Touches:** `packs/stacks/` (deleted), `skills/temper-core/`, `skills/context-engineering/`,
  `skills/source-driven-development/` (deleted), `.claude-plugin/plugin.json`, `agents/build.md`,
  `agents/fix.md`, `reference/review.md`, `reference/build.md`, `reference/check.md`, `reference/fix.md`,
  `reference/design.md`, `reference/plan.md`, `reference/config-suggestions.md`,
  `reference/orchestrator-patterns.md`, `scripts/temper` (`cmd_bands`, `cmd_metrics`, the dispatch, the help,
  the two file names, `gate_build`, `gate_check`), `scripts/bands.py` (deleted), `scripts/runs.py`,
  `scripts/defaults.py`, `scripts/validate-plugin.sh`, `scripts/selftest/test-temper.sh`,
  `scripts/selftest/case-helpers.sh`, `scripts/selftest/temper-cases-1.sh`, `-2.sh`, `-3.sh`, `-4.sh`, `-15.sh`,
  `-31.sh` and every case file that simulates a test run with `evidence add`, `.gitignore`, `CONTRIBUTING.md`,
  `docs/packs.md`, `docs/recommended-setup.md`, `docs/trust.md`, `docs/directory-submission.md`,
  `docs/privacy.html`, `docs/commands.md`, `docs/flow.md`, `docs/plans/ocr-notes/` (deleted), `scripts/caps.json`,
  `scripts/selftest/temper-cases-74.sh` (new), `docs/decisions/0024-what-9-8-5-removed.md` (new),
  `docs/plans/one-go/changed-tests.md`, `CHANGELOG.md`.
- **Tests first:** `scripts/selftest/temper-cases-74.sh` (new).
  1. `w30 no stack pack`: `git ls-files packs/stacks` prints nothing, and no tracked file but the CHANGELOG and
     `docs/history` holds `packs/stacks`.
  2. `w30 two skills`: the `skills` of `.claude-plugin/plugin.json` are `./skills/grill-me` and
     `./skills/teach-me`; no tracked file outside the CHANGELOG, `docs/history` and `docs/decisions` holds
     `temper-core`, `context-engineering` or `source-driven-development`.
  3. `w30 the dormant words are gone`: `git grep -il` over `agents`, `reference`, `commands`, `templates`,
     `scripts`, `README.md` and `docs` (history, plans, evidence and decisions left out) finds no file for
     `review-memory`, `open-code-review`, `tools.ocr`, `metrics append`, `metrics.json`, `temper bands` or
     `claimed-runs`.
  4. `w30 the two commands are gone`: `temper bands` and `temper metrics append x 1` exit non zero with the
     usage text, and `temper --help` names neither.
  5. `w30 a claim never counts`: a build ledger with a red and a green test row written by `temper evidence add`
     and no row run by the CLI gives the Build gate's test first row as failed, with no config key that can
     change it (`evidence: claimed-runs: count` in the config changes nothing and `temper config show` prints
     it as `not read`).
  6. `w30 the run still works with five packs listed`: a config with `packs: [quality, tdd, security, git,
     performance]` gives a `Packs:` line of the five rule files for the plan agent (the packs stay shipped).
  7. `scripts/e2e`: `default-run` and `fix` pass with the floor unchanged.
- **Mechanism:**
  1. **The pieces, each with its proof.** Run the command; the answer at the head is in the last column. If it
     differs after the earlier packages, stop and read what was added.

     | Piece | Files | Proof that no run needs it | At the head |
     |---|---|---|---|
     | Six stack packs | `packs/stacks/*.md` (5,513 bytes) | `git grep -n "packs/stacks" -- agents reference commands scripts` | only `.claude/packs/stacks/{stack}.md`, the project's own file (`reference/build.md:15`, `reference/design.md:15`); no line loads the plugin's |
     | `temper-core` | `skills/temper-core/SKILL.md` | its frontmatter says `user-invocable: false`; `git grep -n "temper-core" -- agents reference commands scripts` | three cites: `reference/review.md:14`, `reference/build.md:169`, `reference/check.md:17` |
     | `context-engineering` | `skills/context-engineering/SKILL.md` | the same two checks | one cite: `reference/fix.md:23` |
     | `source-driven-development` | `skills/source-driven-development/SKILL.md` | the same two checks | four cites: `agents/build.md:17, 104`, `agents/fix.md:18`, `reference/build.md:145` |
     | OCR text | no script; lines of `reference/review.md`, `reference/status.md` (gone with WP28), `reference/orchestrator-patterns.md`, the docs | `git grep -il "ocr" -- scripts` | no script reads `tools.ocr` |
     | Bands | `scripts/bands.py`, `cmd_bands` (`scripts/temper:4886-4926`) | `git grep -n "bands" -- scripts/flow.py scripts/go.py scripts/check_run.py scripts/cli_ctx.py` | nothing; the one caller was `commands/status.md:26-27` |
     | Metrics writes | `cmd_metrics` (`scripts/temper:4822-4883`); `reference/check.md:111-114`, `reference/review.md:262` | the same grep with `metrics` | nothing: only an agent was told to call it |
     | Review memory | no script; `reference/review.md:14, 32, 186, 209, 264`, `reference/config-suggestions.md:77`, `reference/orchestrator-patterns.md:122-134`, `.gitignore:24` | `git grep -il "review-memory" -- scripts` | nothing |
     | `evidence.claimed-runs` | `scripts/runs.py:30-33`, `scripts/temper:3633-3634, 3869` | the key is off by default at the base: pull request #115 added it, and in 9.8.4 a claimed run counted | only the selftest's own config sets it (`scripts/selftest/test-temper.sh:78`) |

  2. **Stack packs.** Delete the six files, the part `Add a New Stack` of `CONTRIBUTING.md:53-77`, the count in
     `docs/packs.md:12`, and the clause on the project's stack file in `reference/build.md:15` and
     `reference/design.md:15` (the `Packs:` line of WP29 is the whole list; a project that wants stack rules
     lists a pack of its own).
  3. **Skills.** Delete the three folders and their lines in `.claude-plugin/plugin.json:53-59`; the key
     `skills` stays with two entries (`scripts/validate-plugin.sh:31` needs the key). Put the cited words where
     they are used: the meaning of SUGGEST, WARN and BLOCK in one sentence at `reference/build.md:169`; the
     confidence levels in two lines at `reference/review.md:14`; the detection order in one line at
     `reference/check.md:17`; "check a framework call against the version the project pins before you write
     it" in one line at `agents/build.md:17` and `agents/fix.md:18`, and delete `agents/build.md:104`,
     `reference/build.md:145` and `reference/fix.md:23`. `grill-me` and `teach-me` stay: a person can call
     them and eleven options of the flow name them (`scripts/flow.py:632-648, 731-732, 750, 777, 785`).
  4. **OCR.** Take the lines out of `reference/review.md` and `reference/orchestrator-patterns.md`, out of
     `docs/recommended-setup.md:45`, `docs/commands.md`, `docs/trust.md`, `docs/directory-submission.md` and
     `docs/privacy.html` (each says a diff may go to another provider when OCR is on; with it gone the sentence
     is that no diff leaves the machine through Temper), and delete `docs/plans/ocr-notes/`.
  5. **Bands and metrics.** Delete `scripts/bands.py`, `cmd_bands`, `cmd_metrics`, their two lines of the
     dispatch (`scripts/temper:5013-5014`), of the help (`:5066-5067`) and of the header (`:20-22`), the two
     names in the list at `:5110`, `METRICS_FILE` and `BANDS_FILE` (`:101-102`). Keep `metrics` and `bands` in
     the list of run file names at `:238`: an older project still has the two files and the link check must
     still see them. Take the paragraph that tells the Check agent to append metrics out of
     `reference/check.md:111-114`, and the append out of `reference/review.md:262`.
  6. **Review memory.** Take every instruction to read or write `.temper/review-memory.json` out of
     `reference/review.md`, `reference/config-suggestions.md` and `reference/orchestrator-patterns.md`, and the
     line of `.gitignore:24`. A rejected config suggestion is simply not written (`config-suggestions.md:77`).
  7. **A claim never counts.** In `scripts/runs.py` delete the mode: `counts` (`:30-33`) is true only for a row
     that is not void and whose `executed_by` is `cli` or `person`; `build`, `check` and `main` lose the
     argument. `gate_build` and `gate_check` stop passing the key (`scripts/temper:3634, 3869`). The key goes
     into `GONE` of `scripts/defaults.py`.
  8. **The selftest's simulated runs.** The config every case starts from sets `claimed-runs: count`
     (`scripts/selftest/test-temper.sh:78`) because many of the 225 `evidence add` calls in 23 files of
     `scripts/selftest` write a test run with
     `temper evidence add --exit N`. With the key gone those rows no longer count. Add two helpers to
     `scripts/selftest/case-helpers.sh` that record a real run: `ev_red <stage> <claim>` and
     `ev_green <stage> <claim>`, each a `temper evidence run --stage <s> --phase <red|green> --claim <c> --`
     with `false` or `true` as the command (`cmd_evidence_run`, `scripts/temper:1715-1737`). Replace only the
     `evidence add` calls whose claim is a test run (the word "test" in the claim and an `--exit`: that is what
     `runs.is_test` counts, `scripts/runs.py:36-37`); a finding, a coverage value or a note stays an
     `evidence add`. `scripts/selftest/temper-cases-31.sh` tests both modes: keep its strict half, delete the
     half for `count` (`:14`) and list it in `changed-tests.md`.
  9. **The validators.** `scripts/validate-plugin.sh:211` names eight packs and they all stay; nothing there
     changes for packs. Its check that `scripts/pack-discover.py` and the guardrails files exist
     (`:250-271, 310-327`) stays true.
  10. **Counts.** Write the new `now` of `listed_skills` (2), `pack_skill_bytes`, `prompt_bytes` and
      `cli_bytes` in `scripts/caps.json`.
- **Removed:** `packs/stacks/` (6 files); three skills; `scripts/bands.py`, `temper bands`,
  `temper metrics append`; every instruction on OCR, review memory and metrics in the reference pages;
  `evidence.claimed-runs` and the `count` mode of `scripts/runs.py`; `docs/plans/ocr-notes/`.
- **Documents in the same change:** `docs/packs.md`, `CONTRIBUTING.md`, `docs/recommended-setup.md`, `docs/trust.md`,
  `docs/directory-submission.md`, `docs/privacy.html`, `docs/commands.md` (no `temper bands`, no `temper metrics`),
  `docs/flow.md:257` (the sentence on `claimed-runs: count`); the decision record
  `docs/decisions/0024-what-9-8-5-removed.md` ("What 9.8.5 removed, and what a project that used it does"; the
  project is one of 9.8.4, so the record also says that a test run an agent only claimed no longer counts),
  which amends ADR 0006; `CHANGELOG.md`, with a line for each removed piece and what replaces it or that nothing
  does, each written for a project of 9.8.4.
- **Done when:**
  - `bash scripts/verify.sh full` is green: this package ends the changes to code, and it touches every case
    file through the helpers of step 8.
  - `bash scripts/validate-plugin.sh`, `bash scripts/validate-docs.sh`, `bash scripts/validate-directory.sh`
    exit 0; `python3 scripts/check_config_keys.py` exits 0.
  - `python3 scripts/check_caps.py` exits 0 with `listed_skills` at 2.
  - `wc -c scripts/temper` is at least 3,000 bytes lower than before this package.
  - The rows this package turns green are listed under its id in "Rows by package" of
    `docs/plans/one-go/done.md`; that section wins over this list.
- **Traps:**
  - Step 8 is the long part: do it first, with the key still read, and see the selftest green; then delete the
    key. A case that fails after the switch was resting on a claim.
  - `temper evidence run` runs its command in the project folder and records the real exit code. A case that
    needs exit 2 or 124 uses `sh -c 'exit 2'`; never write the row into the ledger file by hand to save time.
  - The scripted agents of `scripts/e2e` hold 20 `evidence add` calls. Read each: one that claims a test run
    needs the same change, a finding or a note does not.
  - `validate-docs.sh` rule 6 greps `reference` and `packs` for four patterns (`:191-192`); a sentence moved in
    from a skill must not hold "max 3 parallel" or the like.
  - `docs/privacy.html` is the page the README links for the directory. Change only the OCR sentence.
  - `.temper/metrics.json` and `.temper/review-memory.json` of an existing project are left where they are:
    nothing reads them and nothing deletes them. Say so in the CHANGELOG.
  - The git pack stays shipped and off by default. Its one live use at the head, the fix branch
    (`commands/fix.md:67-68`, `hooks/temper-mod/core/driver.ts:502`), was replaced by WP16; confirm with
    `git grep -n "git pack" commands hooks` before this package ends.
- **Size:** L.

## WP31 Words and documents; decision records; CHANGELOG; version 9.8.5

- **Goal:** A user learns at most 12 words, and no text a user reads uses a retired one. Every page says what
  the code does at the result, version 9.8.5, and the product README says it in at most 80 lines. The decisions
  of this pull request are on record. Every version stamp says 9.8.5, the number the base already carries, and
  the CHANGELOG has one entry under that number.
- **Depends on:** WP01 to WP30.
- **Lane:** `flow core` for steps 1 to 3 (labels, the notice, the fixtures); the documents after them touch no
  code.
- **Touches:** `scripts/words.json` (new), `scripts/check_words.py` (new), `scripts/quality-check.sh`, the flow
  modules and `scripts/panel.py` and `scripts/card.py` where a label or a text holds a retired word,
  `hooks/temper-mod/core/commands.ts` and the mod's drawn texts, one mod test, both view fixture files,
  `scripts/temper` (`_RUN_FILES`, `cmd_init`), `scripts/selftest/temper-cases-75.sh` (new),
  `scripts/selftest/expected-fail.txt`, `scripts/check-known-limits.sh`, `scripts/caps.json` (the `now` of
  `readme_lines`),
  `scripts/validate-docs.sh`, `.claude-plugin/plugin.json`, `README.md`, `docs/getting-started.md`,
  `docs/index.md`, `docs/index.html`, `docs/commands.md`, `docs/flow.md`, `docs/mod.md`, `docs/trust.md`,
  `docs/auto-mode.md`, `docs/grouped-build.md`, `docs/packs.md`, `docs/enterprise.md`,
  `docs/recommended-setup.md`, `docs/context-hygiene.md`, `docs/directory-submission.md`,
  `docs/ai-native-sdlc.md`, `docs/methodology.md`, `reference/autonomy.md`, `agents/review.md`,
  `commands/temper.md`, `CONTRIBUTING.md`, `.claude/CLAUDE.md`, `docs/decisions/` (`0025-one-route.md`, new; the
  part of `0020` on WP19 and WP20; the status lines), `CHANGELOG.md`, `docs/plans/one-go/PROGRESS.md` (the items
  for the owner).
- **Tests first:** `scripts/selftest/temper-cases-75.sh` (new), and `python3 scripts/check_words.py` in
  `scripts/quality-check.sh`.
  1. `w31 at most 12 words`: `scripts/words.json` holds at most 12 entries under `words`; the part
     `## The words` of `docs/getting-started.md` has one line for each and no other entry.
  2. `w31 no retired word in a question`: for every view of the two fixture files (one view a line since WP01),
     the question, each option's label and description, the `say` and the card text hold no entry of `retired`,
     as a whole word, in any letter case.
  3. `w31 no retired word on a page a user reads`: the same for `README.md`, `docs/getting-started.md`,
     `docs/index.md`, `docs/commands.md`, the comments of `templates/temper.config.default`, the Arguments table
     of `commands/temper.md` and the `description` of `.claude-plugin/plugin.json`, code spans and key names
     left out.
  4. One mod test with the retired list written in the test: `HELP` and every text the mod draws for the bar,
     the pane and a toast hold none of them.
  5. `w31 the notice is said once`: in a project that has `.temper/specs` from an earlier run and no notice
     mark, which is how a project of 9.8.4 looks (and one of the base), the `say` of the first
     `temper next --json` starts with the notice of step 3 and the second does not; in a project that
     `temper init` just made it is never said.
  6. `w31 the stamps agree`: the version of `.claude-plugin/plugin.json` is `9.8.5`, as at the base, and the
     three existing checks hold (`scripts/selftest/temper-cases-4.sh:68-77`, `scripts/validate-plugin.sh:123-148`,
     `scripts/quality-check.sh:111-134`). One assert no existing check makes: `docs/index.html` says
     `"version": "9.8.5"`. It fails first, because the base says 9.8.4 there (`docs/index.html:35`). The one
     CHANGELOG heading is held by the changelog case of WP01 (`case 32 tooling:`, row `D86`): write no second
     assert for it.
  7. `w31 the pages match the code`, one assert for each of the 12 places of
     `docs/plans/one-go/evidence/ux-onboarding.md` part 7 that a string can prove: `docs/commands.md` holds no
     "Share HTML review" option list for the plan question and no "Confidence: 94%"; `.claude/CLAUDE.md` and
     the template hold no "enabled: false"; `commands/temper.md` holds no "HTML page too"; `agents/review.md`
     names the default `critical, high`; `docs/commands.md` and the mod's `GATE_MESSAGE` do not say that Claude
     makes a typed change itself; `docs/packs.md` holds no `8 built-in`; `docs/context-hygiene.md` holds neither
     "224" nor "about 10 KB"; `docs/trust.md` holds no "ten Python scripts".
  8. `bash scripts/validate-directory.sh`, `bash scripts/validate-readme.sh`, `bash scripts/validate-docs.sh`
     and `bash scripts/check-known-limits.sh` exit 0.
  9. From `scripts/selftest/expected-fail.txt`: what is left of row `D29` (`D29c` and `D29d` of
     `scripts/selftest/temper-cases-46.sh`; `D29a` and `D29b` left with WP28) passes and leaves the list here,
     and so do `D79b`, `D102` and `D103` of the same file. "Rows by package" of `docs/plans/one-go/done.md`
     is the list that counts.
  10. Row `D108`, the README. WP07 wrote `case 46 D108` failing first, with what the row lists: the line count,
      the two headings the directory needs and their order, the two commands, and that a number of cost or time
      (one that stands with a dollar sign, a percent sign or the word times, seconds, minutes or hours) is only
      on a line that names the scorecard file, and only when that file exists. It passes here and leaves the
      list. The row's second check is the cap: `python3 scripts/check_caps.py` holds `readme_lines`, whose
      `final` is 80.
  11. `w31 the README has its parts`, for what the row does not hold: the `## ` headings of `README.md` are
      `Install`, `Commands`, `How it works`, `What the mod reads and writes` and `Read more`, in this order,
      and no other but `See it`, which the owner may bring back with new videos (the row holds no case against
      it); exactly one line starts `**Cost and time:**`; under `How it works` at most 8 other lines are not
      blank.
- **Mechanism:**
  1. **The 12 words.** `scripts/words.json`:

     | Word | The one line a user gets |
     |---|---|
     | run | one request, carried from your words to a commit |
     | stage | one step of a run: Intent, Plan, Build, Review, Check |
     | intent | what will be true when the run is done, from your request and your answers |
     | criterion | one line of the intent that a test or a command can prove |
     | plan | the tasks and the files that will change |
     | task | one small change with its own test, written first |
     | gate | the question where you decide; its header is `Temper gate` |
     | check | something the CLI runs and judges: your suite, coverage, the acceptance tests |
     | finding | something Review found, with a level from low to critical |
     | repair | one counted fix a rule makes after a failed check |
     | override | you pass a failed check, with a reason that is kept |
     | loop back | the run goes to an earlier stage and does it again |

     Words such as approve, commit, group, risk, sensitive path and setup block are plain words explained where
     they appear and are not in the list. The list was chosen from the texts of the two cards and of the stop
     question; "park" of the earlier 12 word proposal is left out because the plan retires it.
  2. **The retired words and what replaces each**, under `retired` in the same file. The plan demands three:
     `armed`, `arm`, `arms`, `arming` ("runs by itself"); `parked`, `park`, `parks` ("stopped for you", "stops
     and waits"); `phase`, `phases` ("stage"). Four more name things that are gone or have a second name:
     `door`, `doors`; `Autonomous Build` and `Stage by stage` (the options of WP11 replaced them); `preflight`
     ("your commands run once on the current code"); `band` ("bar"); `hand back` ("the run goes on in the
     conversation"). Change each text that test 2, 3 or 4 names. One gate row name holds a retired word and can
     reach a question's text: rename `park-on-touch paths` (`scripts/temper:4219-4221`) to `sensitive paths`,
     with the tests that name it. The key names `autonomy.park-on-touch` and `phases.pipeline`, the option key
     `phaseModels` and identifiers in code keep their spelling: only what a user reads changes. In
     `.claude-plugin/plugin.json` the description says "stage bar" (`:4`) and the title of `phaseModels` says
     "Models per stage" (`:85-86`). Regenerate the fixtures. The words tier, blast radius and ledger are not
     retired here: they are in row names and in the report, and the plan does not ask for it.
  3. **The notice.** A project that ran an earlier Temper is told once: a project of 9.8.4 first, which is what
     users have, and a project that ran the base in the same way. The mark is `.temper/notice.json`, with
     the version as its key; add the name to `_RUN_FILES` (`scripts/temper:632-634`) so git ignores it, keep it
     out of what `state clear` removes, and have `temper init` write it for a new project. When the mark is
     absent and `.temper/specs` or `.temper/archive` exists, the first action of `temper next` puts this in
     front of its `say` and writes the mark:

     ```text
     Temper 9.8.5 asks twice: before any code is written, and at the commit. Pick Ask me at every stage at the
     first question for the old flow. What changed: docs/getting-started.md.
     ```

     It is a line of text in both carriers, never a dialog.
  4. **`README.md`, by contract.** The owner asked for a concise README. At most 80 lines: the page has 89 at the
     base, and the 300 that `scripts/quality-check.sh:99` and `scripts/validate-readme.sh:27` allow stay as
     those scripts' own bound. The cap holds the 80: `readme_lines` of `scripts/caps.json`, which WP05 added
     with `now` 89 and `final` 80 (`docs/plans/one-go/contracts.md` section 12). Write its new `now` here. The
     page holds these parts, in this order, and nothing else:

     | Part | What it holds | At the base |
     |---|---|---|
     | the top | the title, the version badge, and what Temper is in two sentences. One of the two is the promise: "You approve once before any code is written and once at the commit" | `:1-9` |
     | `## Install` | the install lines and the first command | `:11-20` |
     | `## Commands` | `/temper:temper` and `/temper:fix`, one line each, and the words of `/temper:temper` in one line | `:64-71` |
     | `## How it works` | what a run looks like, in at most 8 lines: the plain line `Intent, Plan, Build, Review, Check`, the two questions, that in between Temper stops only when a check still fails after one repair, and the exception WP17 left to this page (a trivial fix ends with no question) | `:28-36` |
     | one line that starts `**Cost and time:**` | one honest line on cost and time. A figure stands in it only when `docs/evidence/scorecard-9.8.5.json` holds it, and then the line names that file (row `D108`). The file does not exist when this package runs, so the line says in words that a run costs more and takes longer than plain Claude Code, and links where the earlier measurements are, `docs/evidence/bench-2026-11.md`. WP32 writes figures into this one line when the bench ran | `:38-50` |
     | `## What the mod reads and writes` | as at the base, with the hook line WP28 wrote | `:73-87` |
     | `## Read more` | Getting Started, the flow (`docs/flow.md`) and the decision records (`docs/decisions/`); then one closing line with the links the listing needs: Trust, the CHANGELOG, Privacy and the license (`docs/directory-submission.md:82` says the README links the privacy page) | `:89` |

     What goes: the part "See it" with the two videos (`:22-26`; they show a run that asks at every stage) until
     the owner records them again, with a line in `PROGRESS.md` that says so; the price paragraph (`:38-50`),
     which becomes the one line; the part "When to use it, and when not" (`:52-62`), which moves to
     `docs/getting-started.md` with its link to `docs/evidence/comparison.md`. The rules of the directory still
     hold (`scripts/validate-directory.sh:66-88`, `scripts/quality-check.sh:125-135`): no raw HTML, the Install
     heading, the heading "What the mod reads and writes", the plain line `Intent, Plan, Build, Review, Check`
     before any diagram, alt text on every image, the version badge.
  5. **`docs/getting-started.md`, one page.** In this order: what you need (`bash`, `git`, `python3`; the CLI
     stops without it, `scripts/temper:264`); install; the first run on an existing project, walked through
     with the real texts (what the CLI finds and says first, the baseline, the approval card, the commit card,
     taken from the fixtures, never invented); what you can do in between (Ask me at every stage, Esc, then
     `/temper:temper`); a failed check; `/temper:fix`; the config in its 10 lines and `temper config show`;
     without the mod (the same questions; a background agent may leave the run waiting, and the setting that
     cures it, `:92-108` at the head); Claude Code's own permission prompts in one sentence; when to use Temper
     and when not (moved from the README, step 4); `## The words`; what changed from 9.8.4 (the commands, the
     config, the first run after the upgrade). Keep a mention of `grouped-build.md` and of install
     (`scripts/validate-docs.sh:134, 207`). The examples no code prints go (`:127-152, 192-209` at the head).
  6. **The other pages.** `docs/index.md:77` (two commands); `docs/flow.md` (read once against
     `temper next --json` of the fixtures); `reference/autonomy.md` rewritten for the default run, and with it
     the three rows of `scripts/validate-docs.sh:255-257` (the second demands the sentence "The run waits for
     you at the gate it parked at"); `docs/mod.md:55-74` (the pane, the report question that no longer exists,
     "bar" for "band"); `docs/trust.md:5-6` (the count of scripts, measured with `wc`) and its sentences that
     `scripts/check-known-limits.sh` holds; `docs/auto-mode.md`; `docs/grouped-build.md` (keep the six strings
     of `scripts/validate-docs.sh:204-206`); `docs/enterprise.md:159-176`; `docs/context-hygiene.md:33, 41`;
     `docs/directory-submission.md:46-50` (the listing text) and `:35-37, 81` (they speak of the README's images
     and a hero GIF: with the part "See it" out the page's only image is a badge, and the page says so until the
     videos are back); `agents/review.md:27`; `commands/temper.md:104`; `CONTRIBUTING.md`. In
     `.claude/CLAUDE.md`: two commands and the words; the paragraph on Autonomous Build becomes the two
     approvals and `run.default`; the known mistakes say "gate logic lives in the CLI (the script and its
     Python modules), never in a prompt", lose the two on doors, and gain "before a fault adds a row, a
     question, a key or an agent, show that the failing step cannot be removed or merged" and "a cap of
     `scripts/caps.json` is raised only in a pull request of its own".
  7. **What only the mod holds.** Rule 11 of `docs/plans/one-go/README.md` section 6: add to `docs/trust.md` the
     sentence that with the mod off nothing but the page's rule holds that a person, not the model, picked an
     option, and add a `need TRUST` line for it to `scripts/check-known-limits.sh`.
  8. **Decision records.** In `docs/decisions/`, in the house form of ADR 0018. The files and their numbers are
     those of `docs/plans/one-go/contracts.md` section 11. A record an earlier package wrote is read against its
     row and not written twice. This package writes `0025`, adds to `0020` what WP19 and WP20 decided, and takes
     no other number.

     | File | Holds | Written by | It amends |
     |---|---|---|---|
     | `0019-a-run-that-asks-twice.md` | one budget for every repeat; Design only when asked; a run asks twice: the approval starts the run to the commit, `run.default`; the approval is bound to what was shown; the run leaves Intent by rule | WP10, then WP14, WP11, WP12 and WP13; WP25 adds one exception | 0011 (the loop limits, and where it says a run is armed only at the plan gate), 0012 decision 4, 0013 decision 1, 0016 |
     | `0020-checks-judged-against-the-project.md` | plan commands run once on the base; the environment check and the baseline; checks judged against the project | WP21; this package adds what WP19 and WP20 decided | 0018 (the preflight) |
     | `0021-a-finding-is-repaired-in-its-stage.md` | a finding is repaired in its stage; `plan amend` and `plan patch` | WP24, WP25 | 0009, 0011, 0013 (what a rule may do) |
     | `0022-the-acceptance-tests-keep-their-own-writer.md` | the acceptance tests keep their own writer; `code` and `metric` criteria are commands | WP27 | none |
     | `0023-two-commands-and-defaults-in-code.md` | two commands and their words; defaults in code; the one time config question | WP29, with the commands of WP28 | 0012 (doors), 0005 (the marked command) |
     | `0024-what-9-8-5-removed.md` | what 9.8.5 removed | WP30 | 0006 |
     | `0025-one-route.md` | one route: Design on request (WP14), the plan contract (WP26), the spec route not built | this package | 0017 |

     Status lines to set: 0002 "Rejected (never built)"; 0003 and 0004 "Accepted" (shipped in 8.0.0); 0006
     "Superseded" by `0024`; 0017 "Rejected: not built (9.8.5)"; 0005, 0011, 0012, 0013 and 0018 keep
     "Accepted" and get one line "Amended by" with the record, and so do 0009 and 0016, which `0021` and `0019`
     amend. In 0011 correct the task block budget to 2,048 bytes (`scripts/temper:108`).
  9. **CHANGELOG: one entry, and no new version heading.** The base's entry,
     `## v9.8.5: a run that checks its own environment first, and asks less` (`CHANGELOG.md:6-68`; the heading
     of 9.8.4 follows at `:70`), is the text of pull request #115, which no user had. Replace it by one entry
     with the heading `## v9.8.5: a run that asks twice`, in the form the base's entry has (a short lead, then
     parts under bold lines). WP01 put that heading in the place of the base's, and every package since wrote
     its lines under it, above the text of the base. Parts: what a run looks like now (the two
     questions, the two cards, a failed check); what a project of 9.8.4 meets (the notice, the config question,
     a saved run, the installed commit hook), with one closing line for a project that ran the head of pull
     request #115; the table "gone, and what to use" (nine commands, the doors, the keys of WP29 step 3, the
     pieces of WP30); what is measured and what is a target, in two separate lists; the caps and the floor as
     what keeps it from growing back. Sort the lines the packages wrote into these parts. Fold in what of pull
     request #115 stays, the list "Stays, and the build stands on it" at the end of
     `docs/plans/one-go/pr-115-fixes.md` (section 4) and the two lines of "Changes its form" under it, as
     lines of this release: for a user of 9.8.4 each of them is new. What that section lists under "Goes" is
     not told as a removal, because no user ever had it: it stands only in the one closing line for a project
     that ran the head of pull request #115. Delete the rest of the base's entry, and any other heading a
     package used, so that exactly one heading starts with `## v9.8.5`. The part on a
     project of 9.8.4 is the one text of what a user must know: WP32 takes it into the pull request text and
     into the summary it writes last, `docs/history/build-9.8.5.md`.
  10. **The version, last: a check, no bump.** The base already carries 9.8.5 and the result keeps the number,
      so `scripts/version-bump.sh` is not run. Check each place that states the plugin's version and change
      nothing else: `.claude-plugin/plugin.json:5`, the `**Version:**` line of `.claude/CLAUDE.md` (`:37`), the
      badge of `README.md` (`:8` at the base), `docs/index.html`, and `docs/index.md` and
      `docs/getting-started.md` wherever they state the version (neither does at the base). One stamp is stale
      at the base, and no existing check reads it: `docs/index.html:35` says `"version": "9.8.4"`. Set that one
      line to 9.8.5 by hand; test 6 holds it from here. `bash scripts/quality-check.sh` holds the version blocks
      (`:111-135`). No tag and no push of a tag: the workflows `.github/workflows/release-bump.yml` and
      `.github/workflows/release.yml` are the owner's.
- **Removed:** the retired words from every text a user reads; from the README the part "See it" until the
  videos are recorded again, the price paragraph and the part "When to use it, and when not" (step 4); the text
  of the base's CHANGELOG entry that step 9 does not fold in; the emoji examples of `docs/getting-started.md`
  and `docs/commands.md`; the status "Proposed" from four records.
- **Documents in the same change:** this package is the documents. Its last act, in the progress commit that
  follows the package commit (`docs/plans/one-go/README.md` section 4), is the line in
  `docs/plans/one-go/PROGRESS.md` that names what is left for the owner (the brief's section 10): the two videos,
  and the figures of the README's cost line if the bench round did not run.
- **Done when:**
  - `bash scripts/verify.sh full` is green, with `python3 scripts/check_words.py` inside
    `scripts/quality-check.sh`.
  - `bash scripts/validate-directory.sh`, `bash scripts/validate-readme.sh`, `bash scripts/validate-docs.sh`,
    `bash scripts/validate-plugin.sh` and `bash scripts/check-known-limits.sh` exit 0.
  - `grep -m1 '^## v' CHANGELOG.md` prints `## v9.8.5: a run that asks twice`,
    `grep -c '^## v9\.8\.5' CHANGELOG.md` prints 1, and `git grep -n "checks its own environment first" CHANGELOG.md`
    prints nothing.
  - `git diff 10e965a -- .claude-plugin/plugin.json` shows no change of the `"version"` line, and
    `grep -c '"version": "9.8.5"' docs/index.html` prints 1.
  - `wc -l < README.md` prints 80 or less, and `python3 scripts/check_caps.py` exits 0 with the `now` of
    `readme_lines` at that count.
  - `git ls-files -z | xargs -0 wc -c | awk '$1 > 262144'` prints only the total line.
  - The rows this package turns green are listed under its id in "Rows by package" of
    `docs/plans/one-go/done.md`; that section wins over this list.
- **Traps:**
  - Three checks compare the first `## v` heading of the CHANGELOG with the manifest's version (test 6 names
    them). Both say 9.8.5 from the base on, so the three stay green all through the build as long as that
    heading stays the first version heading of the file. A heading with a version above it, or a second heading
    that starts `## v9.8.5`, is the fault to look for; the changelog case of WP01 fails on the second.
  - `scripts/version-bump.sh` stays in the tree as the owner's tool and is not run. Of the stamps it writes
    (`scripts/version-bump.sh:58-147`) every one already says 9.8.5 at the base but the one of `docs/index.html`
    (`:123-128`), and that line is set by hand.
  - On every page a user reads, 9.8.5 is this release and the version before it is 9.8.4. No such page says
    "the base" or names pull request #115; the one place for it is the closing line of the CHANGELOG part on a
    project of 9.8.4. A marker `(9.8.5)` that the base wrote on a part that stays (the docs, the briefs and the
    comments in the code hold many) is still true and stays; one on a part that went goes with the part.
  - `scripts/validate-readme.sh` asks more of the README than the directory does: a line that matches
    "How it works", "Overview" or "What it does" (`:34`), an install word in the first 50 lines (`:87`), and
    every relative link target tracked in git (`:64-75`). The heading `## How it works` of step 4 is there for
    the first.
  - 80 lines is tight, and a blank line counts. The part "What the mod reads and writes" has 15 lines at the
    base (`README.md:73-87`) and stays, so about 65 are left for the rest. Count with `wc -l` before the commit.
  - `scripts/check_words.py` may not name a path with a folder called `hooks`, `tests`, `mod`, `core` or `ui`
    (`scripts/validate-directory.sh:5-40`): the mod's texts are checked by the mod test, with the list written
    in the test, because a plugin test can read no file.
  - A retired word is matched as a whole word. "phase" inside `phases.pipeline` or `phaseModels` is a key, and
    the check skips code spans and key names; "park" must not match "sparkline", "arm" must not match "alarm".
  - A new name in `_RUN_FILES` makes the setup check of every existing project ask for `temper init` once
    (`_excludes_current`, `scripts/temper:636`): that is the list working, not a fault. The floor of a fresh
    project is not touched by it.
  - Changing a label changes the fixtures, the scripted persons that still match on label text, and the mod's
    tables that hold a label. After WP04 the policy and the driver select by id; a test that still matches a
    label is moved to the id here, not deleted.
  - `scripts/validate-docs.sh:208` needs ADR 0011 to say `**Status:** Accepted` and to hold `D-07`; amend
    it below its header.
  - `docs/getting-started.md` examples must be copied from what the CLI prints on a fixture. An invented
    example is how the 12 disagreements came about.
  - The README is the listing page of the plugin directory: no raw HTML, alt text on every image, and the
    bundled assets folder named only as a link target (`scripts/validate-directory.sh:65-90`).
- **Size:** L.
