# Contracts: the names every package must use

The packages WP00 to WP32 are built one after another by agents that each read one spec. This page holds every name
that more than one package touches, with the package that creates it and the packages that use it. Where a spec says
a name differently, this page wins and the spec is wrong on the name only. A package that needs a new shared name
adds one line here in its own commit. Section 14 lists the names that were chosen where two specs differed.

"Creates" names the package whose commit first holds the thing. A role such as "the caps file of WP05" in a spec is
the name of this page: `scripts/caps.json`. Every `file:line` of the specs is of the head `10e965a`.

"9.8.5" on this page and in every spec is the result of the build (the brief, section 3, decision 7). The tree
the build starts from is "the base (`10e965a`)", or "the head" where a column says where a thing first exists.
What users have is 9.8.4 (`7c7a1c1`).

## 1. Files and modules

| Name | What it is | Creates | Uses or extends |
|---|---|---|---|
| `docs/plans/one-go/PROGRESS.md` | the state of the build | WP00 | every package; WP01 adds numbers, it does not create the file |
| `scripts/verify.sh` | the gate, with the words `quick`, `full` and `final` | WP01 (`final`: WP07) | WP05, WP06, WP07 and WP32 add steps |
| `scripts/selftest/check-names.py` | no script reads a name it does not define | WP01 | WP02, WP03, every new Python module |
| `scripts/json_ops.py`, `scripts/state_ops.py`, `scripts/ledger_ops.py`, `scripts/spec_text.py`, `scripts/commit_rows.py`, `scripts/report_ops.py`, `scripts/groups_ops.py` | the code moved out of `scripts/temper` | WP02 | every later package puts new CLI logic into a module and one line into the bash file |
| `scripts/temper-help.txt`, `scripts/selftest/capture-cli.sh` | the help text; the capture of every CLI output | WP02 | WP03 |
| `scripts/flow_base.py` | the tables of the flow: `MOVES`, `SEQ`, and the registries `QUESTIONS`, `OPTION_IDS`, `NEEDS` | WP03 (the registries: WP04; `NEEDS`: WP16) | every package that adds a question, an option, a move or a kind |
| `scripts/flow_run.py`, `scripts/flow_ask.py`, `scripts/flow_work.py`, `scripts/flow_build.py`, `scripts/flow_commit.py`, `scripts/flow_view.py` | `Run`; the four parts of `Builder`; the view | WP03 | "the flow modules" of every later spec |
| `scripts/flow.py` | the facade: `Builder`, `core_next`, `main` | WP03 | every caller of the flow, unchanged |
| `tests/mod/ids.test.ts` | the mod reads ids and still takes a view of the base (`10e965a`), which has none | WP04 | kept by every package (`D65`) |
| `scripts/e2e/floor.json`, `scripts/check_floor.py` | the counts of the scripted runs, `now` and `final` | WP05 | every package that moves a count lowers `now` in the same commit |
| `scripts/caps.json`, `scripts/check_caps.py` | the growth caps, `now` and `final` | WP05 | every package sets `now` to the measure; nobody raises a `final` |
| `scripts/stops.json` | the stops an unattended run must keep | WP05 (the list), WP07 (the checks) | WP10, WP11, WP12, WP24 and WP29 add stops |
| `scripts/run_summary.py` | one line a finished run | WP05 | WP15 (a time estimate), WP17 (the trivial line), WP23 (counts by class) |
| `bench/agentlog.py`, `bench/scorecard.py` | the scorecard of a bench round | WP05 | WP32 |
| the counts of the e2e `World` | `w.counts` (`dialogs`, `by_stage`, `by_kind`, `launches`, `auto`, `back`, `handbacks`, `suite_runs`), `w.finalCounts()`, `w.guardAsk(questions, stage, kind)` (one dialog), `w.countLaunch(type)`, and `launchByHand(w, agents, type)` in `scripts/e2e/scenarios.ts` for an agent a scenario launches outside the loop | WP05 | WP06, WP07 and every scenario that asks or launches outside `orchestrate` |
| `scripts/e2e/faketools.ts`, `scripts/e2e/slow.ts`, `scripts/e2e/broken.ts`, `scripts/e2e/persons.ts`, `scripts/e2e/xfail.ts` | the fake tool chain, the two scripted projects, the scripted persons, the expected to fail rule | WP06 | WP07, WP11, WP19 to WP23 |
| `scripts/selftest/expected-fail.txt` | the checks still expected to fail | WP06 (four lines), WP07 (the rest) | each package takes off the lines it makes pass |
| `scripts/e2e/accept.ts` | the acceptance scenarios of `done.md` | WP07 | the packages of section 9; the reviewers of WP32 add scenarios |
| `scripts/check_done.py`, `scripts/check_changed_tests.py`, `docs/plans/one-go/changed-tests.md` | every promise has its check; every changed assertion is listed | WP07 | every package that rewrites an assertion of the base adds its line |
| `scripts/selftest/saved-old.json`, `scripts/selftest/make-saved-old.sh` | five run states saved by 9.8.4, from a work tree of `7c7a1c1`, and the same five saved by the base, from one of `10e965a`; the file holds them under the keys `7c7a1c1` and `10e965a` | WP07 | WP11, WP24 (`D60`: one token a state, `D60a` to `D60e`, and each runs the state of 9.8.4 and the state of the base); the script also stores the config template of each tree (`D61` to `D63`) and the commit hook its installer writes (`D64a`) |
| `scripts/budget.py` | the one budget: `SPENDS`, `spend`, `room`, `grant` | WP10 | every package of section 2 that spends |
| `scripts/rule_log.py` | appends to the record of what a rule decided | WP11 | WP15 reads it for the cards; WP24 and WP25 append |
| `scripts/sensitive.py` | the one matcher of sensitive paths: `match`, `declared` | WP11 | WP15, WP24, WP25, WP27 |
| `scripts/approval.py` | `intent_digest`, `plan_digest`, the row of the binding | WP12 | WP13, WP17, WP25 |
| `scripts/guards/hold_before_approval.py` | the write rule before the approval with the mod off: only the stages Intent, Plan and Design of a feature run, only the tools that write a file | WP12, only if the directory accepts it | none |
| `scripts/card.py`, `scripts/selftest/cards/` | the cards as data and as text; three golden texts | WP15 | WP17, WP19, WP20, WP22, WP24, WP25 and WP27 add rows here and nowhere else |
| `run_summary.median_minutes`, `output_ops.last_run` and `last_failed`, `acceptance.out_of_scope`, `plan_ops.CARD_ROWS`; the flow's `record_parts`, `commit_message` and `commit_calls` | the readers the cards use (the estimate, the kept output lines, the out of scope bullet both the Intent gate and the card read, the rows of the `context` section; the message and the files of the commit) | WP15 | WP17, WP24, WP25 |
| `scripts/cli_words.py` | the CLI words `group take-out`, `group feedback` and `drift ask` (the last through `scripts/drift.py`); `next_feedback` | WP16 | the flow (`flow_build.py`) |
| `scripts/trivial.py` | the trivial verdict and its bound | WP17 | none |
| `scripts/baseline.py` | the environment check, the baseline, the limits | WP20 | WP21 (plan commands), WP22, WP23 |
| `scripts/failure.py` | the one typed failure record | WP23 | WP24, WP25 |
| `scripts/repair_ops.py` | the repair in the stage | WP24 | none |
| `scripts/plan_amend.py` | the amendment by rule | WP25 | none |
| `agents/plan-revise.md` | the narrow revise agent, type `temper:temper-plan-revise` | WP27 | none |
| `reference/draft.md` | the page of the word `draft` | WP28 | none |
| `scripts/defaults.py`, `scripts/config_tidy.py`, `scripts/check_config_keys.py` | every default in one table; the one time question; the reader test | WP29 | WP30 adds to `GONE` |
| `scripts/words.json`, `scripts/check_words.py` | the 12 words and the retired ones | WP31 | none |
| `scripts/e2e/replay_compare.py`, `docs/evidence/scorecard-9.8.5.json` | the replay gate; the bench result | WP32 (WP05 writes the code that makes the scorecard file) | WP07 reads the scorecard file in `final`; the README's one line on cost and time may state a figure only from it (`D108`) |
| `docs/evidence/ab-replay-9.8.5.md` | the replay page; at the base it compares 9.8.4 with the base | the head | WP32 rewrites it in place as one page with three columns: 9.8.4, the base, the result. No second replay page is made |
| `docs/history/build-9.8.5.md` | the summary of what happened, for the owner: the eight parts of section 8, at most 150 lines | WP32, last, after its green `final` | `python3 scripts/check_done.py --summary` (`D107`); the pull request text opens with its parts 1, 2 and 6 |
| `scripts/e2e/live-smoke.sh`, the check `approval` | a run with a real model that must end at the approval; off unless `TEMPER_E2E_LIVE=1`, never in CI | the head (the script, with `start`, `fresh` and `cost`); WP32 (the check `approval`) | row `D109` |

Files that go: `scripts/preflight.py` and `agents/env.md` (WP21); nine command files, `reference/status.md` and
`scripts/earlier_build.py` (WP28); `scripts/bands.py`, `packs/stacks/` and three skills (WP30);
`docs/plans/one-go/evidence/` (WP32, the commit before its final gate).

## 2. CLI words

| Word or flag | Creates | Used by |
|---|---|---|
| `temper task gate N --no-env` | WP08 | WP21 keeps it |
| `temper budget`; `temper budget grant --key K --reason R`; `python3 scripts/budget.py spend` and `room` | WP10 | WP11, WP14, WP16, WP18, WP20, WP22, WP24, WP25, WP27 |
| `temper state set run_mode autonomous` (the call that starts the unattended run); `temper park --end [--answer ID]`; `temper go --taken-up`; `temper override sensitive-path:<path>` | WP11 | WP13, WP15, WP16, WP17 |
| `temper state advance plan_complete <next> --shown intent.md=<digest> --shown tasks.md=<digest>`; `temper intent accept --digest <digest>`; `python3 scripts/approval.py digest`, `row`, `check` | WP12 | WP13, WP17 (`rca.md` in the place of `intent.md`), WP25 |
| `temper state set want_design true` | WP14 | WP15 |
| `python3 scripts/approval.py plan-digest <parsed tasks.md>` (the one plan digest the CLI's `_plan_digest` calls) | WP12 | WP25 |
| `temper card` | WP15 | WP17 |
| `temper spec commit '<message>' -- <the uncommitted code>`, the first call of the option `commit` of `commit.confirm` when code is uncommitted (the message the commit card shows); `python3 scripts/card.py text VIEW_JSON` | WP15 | WP17, WP24 |
| `temper spec branch --carry NAME`, `--if-protected`; `temper group take-out G SHA...`; `temper group feedback G --text T`; `temper drift ask --path P --why W --change C` | WP16 | WP17 (`--if-protected`) |
| `temper intent trivial --why TEXT` and `--close` | WP17 | none |
| `temper review files`; `temper evidence add --read FILE`; `temper evidence resolve --fixed-by <commit>`, a commit and never a note | WP18 | WP24 |
| `python3 scripts/check_run.py coverage-verdict`; `python3 scripts/gate_rows.py check-rows` | WP19 | WP23 |
| `temper baseline start [--again] [--env-only]`, `temper baseline clean`, `temper baseline accept-red --reason R`; `temper doctor --propose --write --expect <hash>`; `python3 scripts/check_run.py owner` | WP20 | WP21, WP22, WP23 |
| `temper baseline plan`; `temper baseline skip --cmd C --reason R` | WP21 | WP25 |
| `temper baseline plan --cmd C` (runs C again), `python3 scripts/baseline.py ROOT CONFIG SPEC wait CMD` (the group gate waits for a plan command still running) and `plan-run STARTED` (the process `baseline plan` starts) | WP21 | WP25 |
| `--fresh` on `temper check run`, `temper group gate` and `temper integrate` | WP22 | WP24 |
| `python3 scripts/run_env.py tree DIR` (the digest of a folder, the tree a verdict names) and `checked GATES DIR` (`FAIL <why>` when the project is no longer the tree of the Check verdict); the variable `TEMPER_FRESH=1`, which `--fresh` sets for the runner | WP22 | WP23, WP24 |
| `temper check build-checks` | WP23 | WP24 |
| `temper repair start`, `test`, `commit`, `close`, `revert`, `status`; `temper evidence add --detail --fix --proof` | WP24 | none |
| `temper plan amend task N --add-file F [--failure ID]`; `temper plan patch task N --add-file F`; `temper group keep` | WP25 | WP27 |
| `temper model --all --source` | WP27 | WP29 |
| `temper packs --stage S`; `temper config show [--markdown]`; `temper config tidy --apply` and `--keep` | WP29 | WP30, WP31 |
| `python3 scripts/check_done.py --summary`; `TEMPER_E2E_LIVE=1 bash scripts/e2e/live-smoke.sh approval` | WP32 | none |

Words that go: `temper panel plan` (WP15); `temper plan preflight` and `temper doctor --candidate` (WP21);
`temper state init --enter` (WP28); `temper bands` and `temper metrics append` (WP30).

## 3. State keys and run files

Keys of `.temper/build-state.json`:

| Key | Meaning | Creates | Used by |
|---|---|---|---|
| `run_mode` | `autonomous` or `interactive`; exists at the head | the head | WP08 (a step back sets `interactive`), WP11 |
| `unattended_from` | the stage at which the person started the unattended run; `state set` refuses it | WP11 | WP12, WP13, WP17 |
| `parked` | a recorded stop; from WP11 it no longer ends the mode | the head | WP11, WP15, WP16 |
| `want_design` | the person asked for Design | WP14 | WP15 |
| `intent_hash` | the digest of the intent as approved, beside `plan_hash` and `approved_files` | WP12 | WP13, WP17, WP24, WP25 |
| `from_branch` | the branch the run stands on before its approval, which the commit hook gates too; `state set` refuses it | WP12 | none |
| `repair`, `repairs` | the open repair window; the closed repairs. Each entry of `repairs` holds the number `n` of its repair (case file 65 counts the repairs of a stage by it), and a repair that changed nothing records `changed: 0`; the window `adhoc_ops.open_window` opens for it carries the mark `kind: repair` | WP24 | WP25 |
| `trivial` | the trivial verdict, until the flow closes the run | WP17 | none |
| `rca_notes` | in a fix run, how many notes typed at the root cause question the root cause agent has taken | WP17 | none |
| `saved_by` | the Temper version that saved the state (`state init` stamps it); `state set` refuses it; a state saved at Review without it runs Review once more (row D60) | WP11 | WP28 |

Keys that go: `intent_asked` (WP14), `env_agent` (WP21), `record_pass` (WP27), `enter` and `built_before` (WP28; the
two stay refused keys and stay in the mod's guard list). `cli_commits` of `.temper/groups.json` exists at the head;
WP18 reads it, WP24 and WP25 write it.

Run files:

| File | What it holds | Creates | Used by |
|---|---|---|---|
| `.temper/runs.jsonl`, `.temper/asked.json` | the run summary; the questions counted once | WP05 | WP15, WP17, WP23 |
| `.temper/budget.json` | the budget store, for the whole build | WP10 | read only through `scripts/budget.py` |
| `.temper/rule-log.json` | what a rule decided since the approval | WP11 | written only through `scripts/rule_log.py append` |
| `.temper/trivial.json` | the spent or open trivial record | WP17 | the commit gate |
| `.temper/evidence/mutation.json`, `.temper/check/mutation.stop` | the planted bug score as information | WP19 | WP23 |
| `.temper/evidence/baseline.json` | the environment check, the baseline, `limits`, `plan` | WP20 | WP19 reads `coverage` when it is there; WP21, WP22, WP23 |
| `.claude/worktrees/temper-baseline` | the one detached worktree of the baseline | WP20 | WP21 |
| `temper-results.json` in the git common folder | the reuse store; exists at the head | the head | WP08 (guarded, tested), WP20, WP22 (the key) |
| `.temper/evidence/failures.json` | the failure record | WP23 | written only through `scripts/failure.py` |
| `.temper/evidence/amendments.json` | amendments and patches, appended | WP25 | the commit card |
| `.temper/notice.json` | the one time notice was said | WP31 | none |
| `.claude/temper.config.before-9.8.5` | the copy the config question keeps, of a config of 9.8.4 or of the base | WP29 | none |

Files that go: `.temper/preflight.json` and `.temper/setup-tried.json` (WP21), `.temper/check/ahead.json` (WP22).
Three duties come with a new run file, in the package that adds it: the name joins `_RUN_FILES` of `scripts/temper`
when git must ignore it; it joins the `rm` line of `state clear` when it must not outlive the run; and a file that
can turn a gate row joins the mod's guarded list with a test in `tests/mod/guard.test.ts` (`D54`).

## 4. Fields of `temper next --json`, `temper go` and `.temper/view.json`

The view stays version 1: a field is added, none is renamed or removed (`D65`).

| Field | Where | Creates | Used by |
|---|---|---|---|
| `id`, `kind` on a question; `id`, `kind`, `recommended` on an option | `next`, `go`, the view | WP04 | every test and every scripted person selects by them |
| `verdicts` | `temper go` | WP09 | WP16 |
| `run.armed` | `next` | WP11 | WP13, WP16 |
| `rule_log` | the view | WP11 | WP15, WP24, WP25 |
| `card` | `next`, the view; in `go` the text rows | WP15 | WP17, WP19, WP20 |
| `typed`, `needs` | a gate question; an option | WP16 | WP17 |
| `needs`, `option` on a `work` action | `next`, `go`: steps that are the conversation's one step (`pull-request`), and the id of the option they came from | WP16 | the mod's run driver |
| `step_kinds` beside `steps`, on a `work` action and on an option | `next`, `go`, the view: the kind of each step, `show-last` (the report step), `note` (the no record note) or `""`; absent when no step has a kind (`scripts/flow_base.py`) | WP16 (the phase 4b fix of its step 4) | the mod's run driver (`stepPlan`) |
| `state` beside `pass` in `checks`; the entry `mutation` of `check_markers` | the view | WP19 | WP20 (`skipped`), WP23 |
| `guard.adhoc_kind` | the view; the mod reads it as `adhocKind` beside `adhocStage` (`core/runview.ts`, `RunFacts`) | WP24 | the mod |
| `drift_ids` beside the options of `drift`, their ids at their places | the view | WP04 | every test |

## 5. Question ids and option ids: the closed list

The registry is `QUESTIONS` and `OPTION_IDS` in `scripts/flow_base.py`. A question id is `<stage or scope>.<state>`.
A follow up question takes the id of its parent and one of `.more`, `.accept`, `.reason`, `.name`. An option id is
lower case words joined by a hyphen, one id a meaning, kept when the label changes and never used for a second
meaning. Tests, the policy, the driver and the scripted persons select by id and never by label.

| Question id | The question | Creates | Changed by |
|---|---|---|---|
| `plan.approve` | the approval of a feature run: the intent and the plan | WP04 | WP11, WP12, WP13, WP14, WP15 |
| `rca.approve` | the approval of a fix run: the root cause and the proposed fix | WP04 | WP17 |
| `commit.confirm`, `commit.fail` | the commit question; the failed commit gate | WP04 | WP08, WP11, WP15 |
| `intent.accept`, `intent.fail`, `intent.blocking` | asked only when the run does not leave Intent by rule | WP04 | WP13 |
| `plan.fail`, `plan.context` | the failed plan gate; the Context check when it is not folded | WP04 | WP08, WP13, WP14, WP20 |
| `design.pass`, `design.fail` | Design, when the person asked for it; `design.pass` is then the approval, with the approval card and the digests of `plan.approve` | WP04 | WP14, WP11, WP12, WP15 |
| `build.pass`, `build.fail`, `build.foreign`, `fix.pass`, `fix.fail` | Build and Fix | WP04 | WP11, WP23 |
| `group.pass`, `group.fail`, `group.parked` | the group questions | WP04 | WP10, WP11, WP20, WP25 |
| `task.covered`, `task.manual`, `task.env` | the task questions | WP04 | WP08, WP21 |
| `review.pass`, `review.fail`, `check.pass`, `check.fail` | Review and Check | WP04 | WP08, WP11, WP19, WP23, WP24 |
| `scope.drift`, `run.restart` | the scope drift question; the restart question | WP04 | WP16 |
| `run.budget` | the question at the limit of the budget | WP10 | WP16 |
| `base.red` | a fault of the environment or a red base | WP20 | WP21 |
| `plan.command` | a command the plan wrote fails or times out on the base; one site with `base.red` | WP21 | WP25 |
| `repair.stop` | a repair that the rule may not resolve or that was reverted | WP24 | none |
| `config.tidy` | the one time config question | WP29 | none |
| `intent.branch` | the run's branch exists from an earlier run: continue on it or on a new branch | WP04 | none |
| `build.ungrouped` | `tasks.md` has tasks and no group: Plan runs again to write them in groups | WP04 | none |
| `group.change` | which task of a passed group changes, after the group question's Change | WP04 | none |
| `pipeline.pass`, `pipeline.fail` | the Pipeline stage: every job passed; a job failed, the result is missing or the fix limit is reached | WP04 | none |
| `adhoc.fail` | the Review of a small change made at Check or Commit failed | WP04 | none |
| `run.walked` | a stage an earlier session ran, checked and asked, not run, when a door entered the run later | WP04 | none |

Question kinds: `gate`, `group`, `resume`, `drift`, `blocking`, `context`, `reason`, `name`. Option kinds: `more`,
`accept`, `cancel`, `carry`, `type`. The `needs` kinds of WP16 are the three that stay in the driver (`more`,
`accept`, `cancel`) and the seven hand back kinds: `talk`, `html-review`, `depth-review`, `config-suggestions`,
`small-change`, `pull-request`, `pipeline-fix`.

| Option id | Meaning | Creates | Used by |
|---|---|---|---|
| `approve-run` | approve and let the run go on to the commit (move `arm`); in a fix run "Approve and fix" | WP04 | WP11, WP12, WP13, WP14, WP17 |
| `ask-every-stage` | approve and ask at every stage | WP04 | WP11, WP13, WP17, the person `stagePerson` |
| `continue`, `commit`, `back`, `redo`, `override`, `save`, `more`, `accept-finding`, `small-change`, `confirm`, `as-planned`, `carry`, `cancel`, `type`, `add-setup`, `start-over`, `choice-1` to `choice-3` | the options of the head, as WP04 lists them | WP04 | every package; `add-setup` and `save` also at `base.red` |
| `it-is-the-code` | the failure is the code, not the environment | WP08 | WP21, WP23 |
| `check-again` | run the same check again after a repair made outside the run: "Check again", "Run it again" | WP08 | WP11, WP20, WP21, WP23 |
| `grant-more` | "Allow two more" at `run.budget` | WP10 | WP16 |
| `run-design` | "Run Design first" | WP14 | none |
| `go-on-anyway` | "Go on anyway" at `base.red`, a recorded skip | WP20 | none |
| `more-time` | "Allow it more time" at `plan.command` | WP21 | none |
| `run-anyway` | run a check whatever the store holds (`--fresh`) | WP22 | none |
| `correct-test` | "Correct the acceptance test" | WP23 at the latest | none |
| `repair-again` | "Repair again", the one more repair on the person's click | WP24 | none |
| `revert-repair` | "Revert the repair" | WP24 | none |
| `add-file` | "Add the file to the task", the person's `plan patch` | WP25 | none |
| `tidy-config`, `keep-config` | the two answers of `config.tidy` | WP29 | none |
| `choice-4` | the fourth ready answer of a question, as `choice-1` to `choice-3`: a reason, a task, a finding | WP04 | none |
| `grill-me`, `teach-me` | the skill options: Grill Me, Teach Me | WP04 | none |
| `html-review`, `share-review` | "Open HTML review", "Share HTML review" of the plan | WP04 | none |
| `revise-plan` | "Revise the plan": Plan fixes or contests the open findings of the fresh review | WP04 | none |
| `fresh-review`, `fresh-again` | "Fresh review first"; "Run the fresh review again" | WP04 | none |
| `find-setup` | "Let an agent find the setup", the other answer to a fault of the environment beside `add-setup` | WP04 | none |
| `walk-through` | "Walk through step by step" at the Design question | WP04 | none |
| `change` | "Change something" at a passed Build or Fix, "Change" at a passed group: the person says what to change | WP04 | none |
| `depth-review` | "Architecture Depth Review" at Review | WP04 | none |
| `commit-pr`, `commit-stacked-prs` | "Commit and open PR", "Commit and open stacked PRs" | WP04 | none |
| `config-suggestions` | "Review config suggestions" at a passed Check | WP04 | none |
| `restore-tests` | "Restore the locked tests" a builder changed | WP04 | none |
| `end-run`, `apply-fix` | the Pipeline answers: "End the run"; "Apply the fix and push" | WP04 | none |
| `continue-on-branch`, `new-branch` | the answers of `intent.branch` | WP04 | none |
| `merge-groups` | "Merge the groups" again, after foreign commits were kept or taken out | WP04 | none |
| `take-out`, `keep-commits` | take out or keep commits the CLI did not make | WP04 | none |
| `accept-done` | "Accept it as done" at `task.covered` | WP04 | none |
| `twice-the-time`, `fix-group`, `change-command` | at `group.fail`: the gate again with twice the time; one fix agent on the merged work; the person types the group's command | WP04 | none |
| `add-to-plan` | "Add to plan" at `commit.fail`: the files changed outside the plan belong to it | WP04 | none |
| `include-left-out` | "Include what is left out" at `plan.context` | WP04 | none |
| `revert`, `allow-once` | "Revert", "Allow once" at `scope.drift`; its "Add to plan" is `add-to-plan` | WP04 | none |

An option of the head keeps the id WP04 gave it. WP04 adds one line here for every id it gives to a question or an
option of the head that these tables do not name. An option a later spec adds with a label and no id gets its id by
the rule above, in that package, with one line in this table.

## 6. Gate rows and override names

| Row | Gate | Package |
|---|---|---|
| `tasks agree with decisions` | the plan gate (it leaves the Design gate) | WP08 makes it pass with a note; WP14 moves it |
| `intent unchanged since the approval` | Build, Check and commit; one row for both files | WP12 |
| `review completed` | Review; from WP18 it also fails when a changed file was not read | WP18 keeps the name |
| `trivial exit` | the commit gate with no run active | WP17 |
| `coverage` | Check, and Build from WP23; it takes the place of `coverage >= threshold` | WP19 |
| `acceptance tests written before Build` | Check, and Build from WP23 | WP23 |
| `repair commit` | the commit gate's carve out for the CLI's own repair commit | WP24 |
| `group validate command` | the plan gate | WP25 |
| `tier recorded` | the plan gate; from WP26 it bounds the simple tier | WP26 |
| `criteria validated`, `criteria validate` | Build and Check; Intent | WP27 changes what they read |
| `sensitive paths` | the commit gate; renamed from `park-on-touch paths` | WP31 |
| `checked tree` | the commit gate, only when it fails: the project is no longer the tree the Check verdict names, and its detail names both trees. From WP24 the same row fails when the Review verdict is of another tree than the commit and the difference is not only closed repairs whose recheck completed (case file 65) | WP22, WP24 |

Rows that go: `mutation score >= threshold` (WP19); `preflight` (WP21); `criteria -> scenarios`,
`cross-repo search recorded`, `blast radius documented` and `target users action chain` (WP26).

A row is `pass` true or false, or `pass` null with `state` set to `not measured` (WP19) or `skipped` (WP20).
Override names beside the stage names: `sensitive-path:<path>` (WP11), `base-suite` (WP20), `plan-command` (WP21).

## 7. Config keys

| Key | Creates | Notes |
|---|---|---|
| `run.default`: `to-commit`, `ask` or `never-unattended` | WP11 | a live line of the template from WP29; `autonomy.enabled: false` reads as `ask` |
| `budget.per-failure` (2), `budget.per-run` (6) | WP10 | defaults in code; in the table of WP29, not in its template |
| `models.<agent>`, `models.high.<agent>`, `models.task`, `models.task-escalation` | WP27 | old names `build.grouped.task-model` and `build.grouped.escalation-model` stay readable; after WP27 the default table has one writer, the bench block of WP32 |
| `upgrade.asked` | WP29 | written by `config tidy --keep` |
| `check.coverage-threshold` | the head | from WP19 it counts only when the project's config holds it |
| `autonomy.park-on-touch` | the head | the key keeps its spelling; user text says "sensitive paths" |

Keys that go, each in the package that removes its reader: `fix.max-loops`, `feedback.enabled`, `loops.max-per-type`
and the `autonomy.budget` block (WP10); `phases.design` (WP14); `autonomy.policy` (WP11);
`check.mutation-threshold` (WP19); `plan.preflight-timeout` and `plan.preflight-skip` (WP21);
`evidence.claimed-runs` (WP30). WP29 checks each one and removes none twice; its `GONE` table holds them all.

Environment variables of the tests: `TEMPER_E2E_TRACE_DIR` and `TEMPER_E2E_LIMIT_S` (WP01), `TEMPER_CAPTURE_DIR`
(WP02), `TEMPER_E2E_COUNT` (WP05), `MOCK_SLOW_S`, `MOCK_RED`, `MOCK_FLAKY_BASE` and `MOCK_FLAKY_LATER` (WP06),
`TEMPER_BASELINE_FOREGROUND` (WP20: the baseline and the plan commands run in the foreground).
`TEMPER_BASELINE_TIMEOUT_S` (WP20: the baseline's own limit, when set; else Check's, `TEMPER_CHECK_TIMEOUT_S`; the slow
scripted project sets it, so its base is measured whole while its other limits stay at 1 s).
`TEMPER_WRITE_CARDS` (WP15: set to 1, case file 56 writes the three golden texts of `scripts/selftest/cards/`).

## 8. Marker lines and closed lists

| Name | Form | Creates | Read by |
|---|---|---|---|
| the verdict marker | a stdout line `VERDICT: <scope> <PASS or FAIL or PARKED>`; the scope is `gate:<stage>`, `task:<N>`, `group:<G>` or `integrate` | WP09 | `scripts/go.py`, the driver, `scripts/e2e/loop.ts`, the command pages; WP16 |
| the gate's last line | `verify quick: PASS` or `FAIL`, and the same for `full` and `final` | WP01 | the session |
| the expected to fail lines | `XFAIL: <name>`, `UNEXPECTED PASS: <name>`, a total `XFAIL: <n>`; for a scenario `XFAIL <name> [<mode>]` | WP06, WP07 | `scripts/check_done.py` |
| the world check of row `D105` | `withRemote(w)` in `scripts/e2e/faketools.ts`: a bare `origin` and a fake `gh`. `worldCheck(w)` in `scripts/e2e/persons.ts`: the shared assert, every message starts with `D105`. While a line of `approval-first` is on the expected to fail list it only reports, as `XFAIL world <scenario> [<mode>]` | WP06 | every scenario of `accept.ts`, `slow.ts` and `broken.ts`; `scripts/check_done.py`; WP12 takes `approval-first` off the list, and from then on a failure of it fails the scenario |
| the shared fake tool chain | `installTools(w)` (the fake `mvn`, `java` and database of the replay, with the four `MOCK_*` switches), `toolRuns(log)` (the whole suite runs of a tool log) and `recordOf` in `scripts/e2e/faketools.ts` | WP06 | `scripts/e2e/replay.ts`, `slow.ts`, `broken.ts` and the scenarios of WP07 and later |
| the budget's answer | `OK: repeat <n> of <m> for <key>` or `BLOCKED: <key> was repeated ...` | WP10 | the callers of section 2 |
| budget keys | `gate:<stage>`, `group:<G>`, `task:<N>`, `acceptance`, `pipeline` (WP10); `plan-revise:<reason>` (WP27) | WP10 | a failure record's `scope` is its budget key (WP23); a failed `integrate` spends its repeat under `gate:build`, and that is the `scope` of its record |
| rule log kinds | `advance`, `repair`, `group fix`, `covered`, `stop`, `answer`, `ended` (WP11); `amend` (WP25) | WP11 | the card section `rule_log` |
| failure classes | `environment`, `command`, `plan`, `code`, `not measured`; the kinds are a closed list in `scripts/failure.py` | WP23 | WP24 (`code`), WP25 (`blocked-task`, `no-validate`) |
| the results of the plan's commands | in `plan` of `.temper/evidence/baseline.json`, one entry for each command `temper baseline plan` ran, keyed by the command's text: `{"result", "exit", "seconds", "class", "kind", "why", "fail_lines", "tail"}`; `result` is `pass`, `fail`, `timeout` or `fails like the base` (`running` while it runs); `class` is `command` or `environment`, as in the failure classes; a skip with a reason is an override row named `plan-command` | WP21 | the flow (`plan.command`), the approval card, case file 62, case 45 `D99`; WP23, WP25 |
| the plan's commands, more fields | each entry of `plan` also holds `where` (`G1 Validate`, `Integration`), `limit`, `started`, `pid` and `ended`; a skip adds `skipped` `{"by", "reason", "ts"}`, with `result` `not run` when the command never ran; a program of the plan that does not resolve adds a fault of kind `program-missing` to `env`, file `the plan` | WP21 | the flow (`plan.command`), the approval card |
| the reuse store | `temper-results.json` in the git common folder, changed under the lock file `temper-results.json.lock` beside it; one entry a key (`run_env.result_key`: the digest `run_env.tree_key`, the command, the setup block, the folder inside the repository, the first version line of each program, what the caller adds): `{"pass": {"ts", "tail", "seconds", "extra"}, "fail": {"ts", "rc", "tail", "fail_lines", "answer", "class", "limit", "again"}, "flaky", "forced", "last"}`; the byproduct list under the reserved key `byproducts`; the baseline's `baseline:<key>` entries; one lock file a key in `temper-locks/` | WP22 | `scripts/baseline.py`, WP23, WP24 |
| the fields of a row the runner made | `tree`, `key`, `seconds`, `reused` (the date of the kept result, or null), and when they hold `flaky` (`{ts, rc, lines, text}`) and `forced`; each verdict of `.temper/gates.json` holds `tree` | WP22 | the commit card, WP23, WP30 |
| the budget kind of a run anyway | `run anyway`, under `gate:check` (`check run --fresh`), `group:<G>` (`group gate G --fresh`) or `gate:build` (`integrate --fresh`) | WP22 | `temper budget` |
| card kinds and marks | `approval`, `commit`, `stop`; the marks of WP15 step 1 | WP15 | the mod's drawing |
| the card entry of an end to end trace | one line `card <kind>` (indent allowed) in the step of the question that carries the card, before the calls of its answer, in plain, mod and driver mode; in driver mode a question `temper go` reached by its own steps gets its own line (`ask:<stage>:<id>:<option ids>`) before it | WP15 | `scripts/e2e/loop.ts`, the scenario `full-run`; WP17 |
| the driver's effect `card` and the port's `card(rows)` | the card's rows, given once before the question is asked; the engine's port logs them outside full mode | WP15 | the mod; `scripts/e2e/loop.ts` |
| the saved stop of the run driver | `saved(what)`, a `done` whose text starts `Temper stopped: ` and names `/temper:temper`; `isSavedStop` (`hooks/temper-mod/core/driver.ts`) | WP16 | `hooks/temper-mod/register.tsx`, the mod's tests |
| the drift rows of the Build ledger | `drift ask <path>` with `Why:` and `Change:` lines (phase `drift`), the answer `drift <path>: <label>: <why>` (phase `feedback`), and `drift decided` (phase `drift`) once the agent got its lines | WP16 | the flow (`Run.drifts`), the scope row of the commit gate |
| prompt lines the CLI writes | `Drift decision:` (WP16), `Repair in place:` and the brief section `Re-check:` (WP24), `Affected tasks:` (WP27), `Packs:` (WP29) | as named | the briefs |
| the rows of the recheck | one a finding of the repair: `recheck #<id>: fixed` with exit 0, or `recheck #<id>: not fixed` with exit 1; then one completion row, the claim `review completed` with `--cmd recheck`, `--value <the count of ids checked>` and one `--read` for each changed file (the claim the scripted reviewer of `scripts/e2e/accept.ts` writes) | WP24 | `agents/review.md`, `scripts/repair_ops.py`, case file 65, `scripts/e2e/accept.ts`, `scripts/e2e/replay.ts` |
| the driver's hand back | the end of the run driver (`DriveEnd`, `hooks/temper-mod/core/driver.ts`): `{kind: 'done', text}`, or `{kind: 'handback', needs, option}` with `needs` one of the seven hand back kinds and `option` the id of the option picked; the note after the command's text ends `step <kind> <option id>`; the trace line of the e2e driver is `driver handback: step <kind> <option id>` | WP16 | `hooks/temper-mod/register.tsx`, `commands/temper.md`, `commands/fix.md`, `scripts/e2e/loop.ts`, `scripts/e2e/scenarios.ts`, `tests/mod/driver.test.ts`, `tests/mod/driver-wiring.test.ts`; WP17 |
| selftest helpers | `_unattended <stage>` (WP07; WP11 changes its body), `_base_known` (WP20: the baseline is on record as not run, so no case of the base meets the new first step), `ev_red` and `ev_green` (WP30) | as named | the case files |
| the one CHANGELOG entry | the heading `## v9.8.5: a run that asks twice`, in the place of the heading of the base at `CHANGELOG.md:6`; no other heading starts with `## v9.8.5`, and no package adds a version heading | WP01 | every package writes its lines under it, above the text of the base; WP31 gives the entry its final parts and folds in what stays of pull request #115 (`pr-115-fixes.md` section 4); WP32 adds the measured lines (`D86`) |
| the one time notice | one line that starts `Temper 9.8.5 asks twice`; the mark that it was said is `.temper/notice.json` | WP31 | `D102`; WP32 quotes it in the pull request text |
| the title of the pull request | `Temper 9.8.5: a run that asks twice` | WP00 | WP32; it does not change |
| the headings of the summary | eight headings of level two, in this order: `In five lines`, `The numbers, before and after`, `The plan, item by item`, `What changes for someone who used 9.8.4`, `What went differently from the plan`, `What is not done, and what is yours to do`, `The build in numbers`, `Was it run for real` | WP32 | `python3 scripts/check_done.py --summary` (`D107`) |
| the states of a plan item in the summary | `built and proven`, `built and not proven` or `not built`, one in each line of part 3; the item ids are those of releases 0 to 7 of `docs/plans/two-approval-run.md`, `0a` to `7e` | WP32 | the same check |
| the fixed headings of the product's README | `## Install` and, after it, `## What the mod reads and writes`. The part `## See it` is out until the owner records the videos again; no check holds it out | the head; WP31 keeps the two | `case 46 D108`; the directory's rules |
| the README's line on cost and time | exactly one line of the product's `README.md` starts `**Cost and time:**`. It holds a figure only when it also names `docs/evidence/scorecard-9.8.5.json` and that file exists | WP31, with no figure | the case `w31 the README has its parts` of WP31; `case 46 D108`; WP32 step 7 (g) writes the figures into this one line when the bench ran |
| the version stamps | the six places of row `D86`: `.claude-plugin/plugin.json`, `.claude/CLAUDE.md`, the README badge, `docs/index.html`, `docs/index.md`, `docs/getting-started.md`. All that state the version say 9.8.5 at the head but `docs/index.html:35`, which says 9.8.4 | the head | WP31 sets the one stale line by hand and holds it with the case `w31 the stamps agree`; no package runs `scripts/version-bump.sh` |
| the open lines of `final` | `OPEN: the bench gate (needs the owner's word and a model access)` when there is no scorecard file; `OPEN: the summary of the build` when `docs/history/build-9.8.5.md` is not there yet | WP07 (the first), WP32 (the second) | the session; the pull request text |
| the owner of the suite command | `python3 scripts/check_run.py owner ROOT [SPEC]` (SPEC the run's spec folder, whose `tasks.md` gives the plan's line) prints one JSON line `{"test", "run", "source", "why"}`: `source` is `configured`, `detected`, `plan` or `none`; `run` is the coverage form or the test text again; with `none` the two texts are empty and `why` says why | WP20 | the baseline; case file 61; WP21 |
| the baseline's other fields | `run` (the coverage form of the command), `notes`, `exit_code`, `answered` (`{by, reason, ts, kept}` of "go on anyway"), `env_only` (a door), `reused` (a green run taken from the store); the store holds `baseline:<key>` entries (`result`, `seconds`, `coverage`, `answer`) beside the head's; `python3 scripts/baseline.py ROOT CONFIG SPEC limit CMD DEFAULT`, `timeout CMD LIMIT` and `skip-row LEDGER` are the CLI's own calls | WP20 | the CLI (the group gate, Check's gate), the flow, the card; WP21, WP22, WP23 |
| the baseline's results and kinds | in `.temper/evidence/baseline.json`: `result` is `running`, `green`, `red` or `unknown`; a red result's `kind` is `tool-version`, `program-missing`, `service-down`, `setup-line` or `red-base`; `env` holds one entry for each fault of the environment check, and each names the file that states the need; `answer` is set once the person went on anyway, and is `fix-run` for a red base a fix run recorded | WP20 | the flow (`base.red`), the card, case file 61; WP21, WP22, WP23 |

## 9. Scenario names

A scenario has a function (camelCase) and a registered name, lower case words joined by a hyphen. The registered
name is what `bun scripts/e2e/run.ts <mode> <name>` takes, what `scripts/e2e/floor.json` and
`scripts/selftest/expected-fail.txt` hold, and what this page uses. A spec that names a function means this row.

| Registered name | File | Creates | Made to pass or changed by |
|---|---|---|---|
| `full-run`, `fix`, `design`, `armed-run`, `three-groups`, `context-check`, `branch-clash`, `branch-clash-carry`, `pr-and-pipeline`, `failing-scenario` | `scripts/e2e/scenarios.ts` | the head | WP11 (`full-run` takes the person who asks at every stage; `armed-run` becomes the default run with one failed group), WP12, WP13, WP14, WP16, WP17, WP22 |
| `default-run` | `scripts/e2e/scenarios.ts` | WP05 | the floor counts it at every commit; 2 dialogs from WP13 |
| `slow-first-run`, `slow-at55` | `scripts/e2e/slow.ts` | WP06 | WP19 (coverage), WP20 (limits, the base value), WP21, WP22 (run counts), WP23 (`D11`) |
| `broken-first-run`, `broken-flaky` | `scripts/e2e/broken.ts` | WP06 | WP20, WP21 (`D13`), WP22 (`D14`) |
| `two-dialogs`, `vague-run` | `scripts/e2e/accept.ts` | WP07 | WP13 |
| `approval-first` | `scripts/e2e/accept.ts` | WP07 | WP12, which so arms the shared assert of `D105` in every scenario (section 8); WP20 adds the two places a baseline writes |
| `integrate-fail` | `scripts/e2e/accept.ts` | WP07 | WP09 |
| `budget-stop` | `scripts/e2e/accept.ts` | WP07 | WP10 |
| `design-on-ask` | `scripts/e2e/accept.ts` | WP07 | WP14 |
| `ask-every-stage`, `stop-keeps-mode` | `scripts/e2e/accept.ts` | WP07 | WP11 |
| `flagged-map` | `scripts/e2e/accept.ts` | WP07 | WP15 |
| `group-fail`, `group-fail-twice` | `scripts/e2e/accept.ts` | WP07 | WP16 |
| `fix-two` | `scripts/e2e/accept.ts` | WP07 | WP17 |
| `acceptance-wrong-test` | `scripts/e2e/accept.ts` | WP07 | WP23 |
| `repair-finding`, `repair-worse` | `scripts/e2e/accept.ts` | WP07 | WP24 |
| `criteria-by-cli`, `revise-narrow` | `scripts/e2e/accept.ts` | WP07 | WP27 |
| `fix-breaks-suite`, `policy-run` | `scripts/e2e/scenarios.ts` | WP08 | WP09 (`policy-run` in driver mode), WP11 (the policy key goes; the scenario stays as a default run) |
| `failed-checks` | `scripts/e2e/scenarios.ts` | WP16 | none |
| `trivial` | `scripts/e2e/scenarios.ts` | WP17 | none |
| `coverage-drop` | `scripts/e2e/scenarios.ts` | WP19 | WP24 (it then asserts the repair in the stage) |
| `red-base-after-approval` | `scripts/e2e/scenarios.ts` | WP20 | none |
| `plan-command-fails` | `scripts/e2e/scenarios.ts` | WP21 | none |
| `setup-at-build` | `scripts/e2e/scenarios.ts` | WP23 | none |
| `blocked-task-amended`, `blocked-outside-plan` | `scripts/e2e/scenarios.ts` | WP25 | none |
| `context-fold` | `scripts/e2e/scenarios.ts` | WP13 | WP15 (the card shows the flagged line) |

## 10. Selftest case files

The runner of WP01 finds a case file by its name, so a new file needs no list. Each package writes new cases only
into the file reserved for it here, into an existing file its spec names, or into a file of WP07 whose token it
makes pass. A token is the first word of an assertion name and is never shared by two files.

| Number | Package | Names start with |
|---|---|---|
| 1 to 31 | the head | as they are |
| 32 | WP01 creates; WP02 and WP03 add | `tooling:`, `room:`, `flow:` |
| 33 to 39 | spare for phase 1 | |
| 40 | WP04 | `ids:` |
| 41 | WP05 | `floor:`, `caps:`, `summary:` |
| 42 | WP06, reserved; its checks are scenarios and `scripts/e2e/xfail.ts` | |
| 43 | WP07 | `xfail:`, `done:` |
| 44, 45, 46 | WP07 | the tokens of `done.md` (`D02b` to `D108`) |
| 47 | WP08, reserved; its cases go into the files that build the state and into 45 | |
| 48, 49 | spare | |
| 50, 51, 52, 53, 54, 55 | WP09, WP10, WP11, WP12, WP13, WP14, in this order | `verdict:`, `budget:`, `run:`, `bound:`, `intent rule:` and `context:`, `design:` |
| 56, 57, 58 | WP15, WP16, WP17 | `card:`; the cases of WP16; `fix:` and `trivial:` |
| 59 | WP18: its new cases, with state builders of their own. Files 1, 2 and 5 are edited only where an assertion of the base changes, each listed in `changed-tests.md` | as its spec names them |
| 60, 61, 62, 63, 64 | WP19, WP20, WP21, WP22, WP23 | `w19` to `w23` |
| 65 | WP24 | `repair:` |
| 66 | WP25, reserved; its cases go into 20, 29 and 46 | `amend:`, `patch:`, `replan:` |
| 67 to 69 | spare | |
| 70, 71, 72, 73, 74, 75 | WP26, WP27, WP28, WP29, WP30, WP31 | `w26` to `w31` |
| 76 to 79 | spare | |
| 80 | WP32 | `final:` |
| 81 to 89 | the checks the reviewers of WP32 add | |
| 90 to 99 | a repair of CI or of a defect found on the way that needs a file of its own | |

After an edit of case file 5: `bash scripts/selftest/make-helpers-5.sh > scripts/selftest/case-helpers-5.sh`, then
`TEMPER_CASES_ONLY="6 31" bash scripts/selftest/test-temper.sh`, and run `quick` as a background command: file 5
alone takes 13 minutes.

## 11. Decision records

| File in `docs/decisions/` | Holds | Written by | Amends |
|---|---|---|---|
| `0019-a-run-that-asks-twice.md` | decision 1 one budget; 2 Design only when asked; 3 the approval runs to the commit, `run.default`, the closed list of what a rule may do, the stops; 4 the approval is bound to what was shown; 5 the run leaves Intent by rule | WP10 creates it; WP14, WP11, WP12 and WP13 add one decision each; WP25 adds the one exception to decision 3 | 0011, 0012, 0013, 0016 |
| `0020-checks-judged-against-the-project.md` | plan commands run once on the base; the environment check and the baseline; checks judged against the project | WP21 creates it; WP31 adds what WP19 and WP20 decided | 0018 |
| `0021-a-finding-is-repaired-in-its-stage.md` | the repair in the stage; `plan amend` and `plan patch` | WP24 creates it; WP25 adds its decision | 0009, 0011, 0013 |
| `0022-the-acceptance-tests-keep-their-own-writer.md` | the writer stays its own agent; `code` and `metric` criteria are commands the CLI runs | WP27 | none |
| `0023-two-commands-and-defaults-in-code.md` | two commands and their words; defaults in code; the one time config question | WP29, with the commands of WP28 | 0005, 0012 |
| `0024-what-9-8-5-removed.md` | title "what 9.8.5 removed": what it removed and what a project that used it does | WP30 | 0006 |
| `0025-one-route.md` | Design on request, the plan contract, the spec route not built | WP31 | 0017 |

WP31 reads each record against its row, sets the status lines and writes none twice. The status line of 0017
becomes `Rejected: not built (9.8.5)`.

## 12. Caps and floor keys

Keys of `scripts/caps.json`, each with `now` and `final`: `question_sites`, `option_sites`, `option_labels`,
`question_ids`, `gate_rows`, `agent_briefs`, `listed_commands`, `listed_skills`, `config_live_keys`,
`config_comment_keys`, `config_lines`, `prompt_bytes`, `pack_skill_bytes`, `cli_bytes`, `readme_lines`, and the
list `flow_files` (WP05); `handback_kinds`, exactly 7, counted from `NEEDS` in `scripts/flow_base.py` (WP16).
`gate_rows` is one number: the row names of the CLI, of the Python scripts and of `scripts/gate_rows.py` added up.
`readme_lines` is the line count of the product's `README.md`: 89 at the head, `final` 80. WP05 adds the key
with `now` 89, and WP31 brings the page under it (`D108`).

`agent_briefs` is 13 at the head, 12 after WP21 (the environment agent goes) and 13 after WP27 (the revise agent
comes), or 12 if WP27 finds the Check brief no longer launched. Its `final` is 13. It never ends at 10.

Keys of a scenario in `scripts/e2e/floor.json`, for each mode: `dialogs`, `by_stage`, `by_kind`, `launches` by agent
type with `launch_total` as their sum, `auto`, `back`, `handbacks`, `suite_runs`; and the entry `replay`, which
also holds `shipped`, `defect_in_commit`, `bad_validate_line_in_plan_at_end` and its launches by type (`done.md`
row `D58`); and the entry `replay_base`, the numbers of the base (`10e965a`) on the same replay, which the base
column of `bash scripts/e2e/ab-replay.sh 10e965a` must equal in every `full` (WP05 records them and adds the check; from
WP08 on a package can move the column). The floor holds no count of gate rows. A `final` is never raised by the
build session; a cap or a floor it cannot meet is a recorded blocker in `docs/plans/one-go/PROGRESS.md` with the
measured number.

## 13. Rows of `done.md` and the build order

`docs/plans/one-go/done.md` was audited after the build order was fixed: its last column and its section "Rows by
package" name the package after which each row passes, for `D04`, `D12`, `D33`, `D34d`, `D55` and `D64b` too. Where
a spec cites this section for a moved row, read that column; nothing is to be noted under "Found on the way" for
it. Where a spec's "Done when" names another row or another package, `done.md` wins. No package edits `done.md`,
but for a check name that WP07 corrects and lists in `changed-tests.md`.

The owner's decisions of 2026-11-16 added three rows: `D107` (the summary, WP32), `D108` (the README of at most
80 lines, WP31; its case is `case 46 D108`, written by WP07 failing first) and `D109` (a run with a real model,
WP32). They added no token to rows `D60` to `D64`: each of their cases now runs on 9.8.4 and on the base.

## 14. Names chosen where the specs differed

| Thing | The name | The other name, and why this one |
|---|---|---|
| the scenario of the slow project | `slow-first-run` | phase 5 said `slowProjectRun`; WP06 creates it and `done.md` names it |
| the scenario of the broken project | `broken-first-run` | phase 5 said `brokenProjectRun`; the same reason |
| the wrong locked test met at `integrate` | `acceptance-wrong-test` | WP23 said `acceptanceAtBuild`; WP07 creates it and `done.md` names it |
| scenarios named by their function only | the registered names of section 9 | `run.ts` takes the registered name |
| the options of `base.red` | `add-setup`, `check-again`, `go-on-anyway`, `save` | WP20 said `base.add-setup`, `base.again`, `base.go-on`, `base.save`; WP04 owns the list and one id is one meaning |
| the options of `plan.command` | `more-time` ("Allow it more time", at a time out) or `check-again` ("Run it again"), `change-command` ("Change the command"), `revise-plan` (after the approval `back`, "Loop back to Plan"), `go-on-anyway` ("Go on anyway": the skip with a reason, `baseline skip`), `save` | WP21 named "Skip this check"; the label of `base.red`'s skip is kept, so the scope adds no option site and no label but "Allow it more time" and "Change the command" (`scripts/caps.json`) |
| the stops of WP20 and WP21 in `scripts/stops.json` | `base.red`, `plan.command`, `person.baseline` (`baseline accept-red`, `baseline skip`) | WP20 left `base.red` out of the list; WP21 adds it with its own two |
| the option that runs a check anyway | `run-anyway` | WP22 said `check.fresh`, which has the form of a question id |
| the tree of `.temper/evidence/mutation.json` | `run_env.tree_key` of the project folder | its row in this section names `check_run.tree_digest`, which WP22 deletes for the one digest |
| the id WP04 foresaw for a repair option | `repair-again` | WP04 said `repair-first`, which no package adds |
| the registry of ids | `scripts/flow_base.py` | WP29 said `scripts/flow_ids.py`; WP04 put the registry into the base module |
| the cap on gate rows | `gate_rows` | WP26 said `gate_rows_cli`; WP05 and `done.md` have one key |
| the cap on hand back kinds | `handback_kinds` in `scripts/caps.json` | WP16 said a line `hand back kinds: 7`; it is counted from the flow's `NEEDS`, so the checker names no file of the mod |
| the row for a short Review | `review completed` | an earlier draft of `done.md` said `review covered the diff`; WP18 adds no row, so the cap on gate rows does not move |
| the matcher of sensitive paths | `scripts/sensitive.py` | WP15 and WP27 named it by role, as a module of WP02 or of WP15; WP11 creates it |
| the one plan digest | `plan_digest` of `scripts/approval.py` | WP25 said `scripts/tasks_md.py`; WP12 moves the function first |
| the budget store | `.temper/budget.json`, to the end | WP10 and WP23 each said the counts might move into the failure record; they stay, and the record's `scope` is the budget key |
| what `plan amend` spends | the key `task:<N>`, the kind `plan amend` | WP25 said a step of class `plan`; the budget has keys and kinds, no classes |
| the decision records | the numbers of section 11 | WP21 and WP24 said "the next free number", WP27, WP29 and WP30 left the number to WP31 |
| the new case files | the numbers of section 10 | eleven specs said "the next free number" |
| the switch that keeps the baseline in the foreground | `TEMPER_BASELINE_FOREGROUND` | WP20 named none; WP21 needs the same switch |
| new ids with no name in a spec | `plan.command`, `repair.stop`; `more-time`, `revert-repair`, `add-file`, `tidy-config`, `keep-config` | chosen here by the rule of section 5 |
| the version of the result | 9.8.5 | the kit named a major version until the owner's decision of 2026-11-16. The base carries the same number and is never called by it: it is "the base (`10e965a`)" |
| the files that held the number | `docs/evidence/scorecard-9.8.5.json`, `.claude/temper.config.before-9.8.5`, `0024-what-9-8-5-removed.md`, and for the bench of WP32 `docs/evidence/bench-9.8.5.md` and `docs/evidence/bench-9.8.5/` | each held the number of a major version |
| the replay page | `docs/evidence/ab-replay-9.8.5.md`, rewritten in place | WP32 said a second page with its own number; the page of the base already has the name of the result, so there is one page with three columns |
| the saved states of an older Temper | `scripts/selftest/make-saved-old.sh` and `scripts/selftest/saved-old.json` | they were `make-saved-985.sh` and `saved-985.json`; the states now come from 9.8.4 first and from the base second |
| the input and output of `check_run.py coverage-verdict` | in: one JSON object on standard input, `{"measure": {"total", "command", "exit", "hint"}, "base", "changed": {"ran", "missed"} or null, "threshold"}`; out: the verdict as one JSON object on the last line, `{"state", "rule", "value", "floor", "why"}` | WP19 named the arguments of `coverage_verdict(measure, base, changed, threshold)` only; `case 60 w19 rule table` feeds this shape |
| the mark of a check not measured in the mod's pane | `?`, as the CLI's `[?]` | WP19 said "its own mark"; `tests/mod/drawings.test.tsx` looks for `? coverage` |
| the fields of the ledger row `coverage` | `value` (the total), `rule`, `floor`, `state`, `share` (rule `changed lines`), `changed` (`{ran, missed}` or null), `command`, `cov_exit`, `hint`, `note`; `exit_code` 0, 1 or null | WP19 named the verdict's fields; `value` stays the total so every reader of a coverage value reads a total, and the gate judges the row again from these (`gate_rows.py check-rows`) |
| the shape of `.temper/evidence/mutation.json` | `{state, why, ran, caught, survivors, tree, ts}`; `state` `measured`, `not run` or `running`; `tree` is `check_run.tree_digest` | WP19; the commit card and `check_markers` show it only when `tree` is the tree as it is |
| the arguments of `check_run.py run` and `ahead` | `run ROOT SPEC LEDGER BASE COMMAND [TEST_CMD] [COVERAGE_CMD] [KEY]`, `ahead ROOT SPEC BASE COMMAND [TEST_CMD COVERAGE_CMD KEY]`; KEY is `check.coverage-threshold` when the project's config holds it | WP19 |
| the mod's list of checks not measured | `unmeasured` of the mod's `View` (`hooks/temper-mod/core/view.ts`, `types/index.d.ts`) | WP19: the pane draws each `?`, in the Check section or in its own section when no marker is drawn |
