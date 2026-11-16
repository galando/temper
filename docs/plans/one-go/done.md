# Done: every promise of the one pass build, and the check that proves it

The result is done when every row of the table below holds. WP07 writes the checks before the changes that make
them pass; `scripts/selftest/expected-fail.txt` lists the ones that still fail and must be empty at the end.

## How to read the table

- **Id.** The id is the first word of the name of every selftest assertion that proves the row (`D31a`, `D31b` are
  two assertions of row `D31`). `scripts/check_done.py` reads this table: keep the five columns and the ids.
- **Promise.** The promise in the final state, version 10.0.0. Where the plan gives a number for a middle release,
  the number here is the one after release 7.
- **Check.** Each item starts with its suite:
  - `case NN <token>`: an assertion of `scripts/selftest/temper-cases-NN.sh` whose name starts with the token. The
    token is the row id, with a letter when a row has several; a row may also name the token of another row.
  - `scenario <name>`: a scripted run of `scripts/e2e/accept.ts`, `scripts/e2e/slow.ts` or `scripts/e2e/broken.ts`,
    run by `bun scripts/e2e/run.ts <mode> <name>`. With no mode named it runs in plain, mod and driver mode.
  - `floor <key>`: a `final` value of `scripts/e2e/floor.json`, held by `python3 scripts/check_floor.py --final`.
  - `caps <key>`: a `final` value of `scripts/caps.json`, held by `python3 scripts/check_caps.py --final`.
  - `mod <file>`: a test of `tests/mod`, written by the package of the last column with its own change.
  - `gate <command>`: a command of `bash scripts/verify.sh final`.
  - `bench <key>`: a line of `docs/evidence/scorecard-10.0.0.json`, written by `python3 bench/scorecard.py --gate`.
- **No model call.** `yes`: the check runs with the real CLI, scripted agents and a scripted person, and costs
  nothing. `no`: it needs a credential for the model and money. `person`: it needs a reader.
- **Passes after.** The package after which the check must pass and leave the list. `the head` means it passes at
  `10e965a` already and must never fail.

The parts: A, a run in run units (`D01` to `D29`); B, the eleven rules of the frame (`D30` to `D40`); C, the 16
defects and the 4 flips of pull request #115 (`D41` to `D57`, ids of `docs/plans/one-go/evidence/v-pr115.md`);
D, the replay of the measured run (`D58`, `D59`); E, migration (`D60` to `D65`); F, the caps (`D66` to `D77`);
G, the suites that existed before (`D80` to `D86`); H, the bench gate (`D90` to `D97`).

## The table

| Id | Promise | Check | No model call | Passes after |
|---|---|---|---|---|
| D01 | A clean feature run with a clean Context Map asks 2 dialogs: the approval before any code, and the commit. The same in plain, mod and driver mode | `floor default-run.dialogs` = 2 in each mode; `scenario two-dialogs` (the questions asked are `plan.approve`, then `commit.confirm`, and no other) | yes | WP13 |
| D02 | A flagged Context Map is shown whole in the approval and still costs 2 dialogs; the review line of `plan.md` records that the answer was given at the approval. When a flagged line cannot be shown whole, the Context check stays its own question | `scenario flagged-map`; `case 44 D02b` | yes | WP15 |
| D03 | A clean bug run (`/temper:fix`) asks 2 dialogs: the root cause with the fix it proposes, and the commit. Its checks start beside Review | `floor fix.dialogs` = 2 and `floor fix.launch_total` = 3; `scenario fix-two` plain, driver (the questions asked are `rca.approve`, then `commit.confirm`) | yes | WP17 |
| D04 | A vague run asks 2 dialogs plus one dialog for every four rules the request left open; a design concern is one of those questions, never a stage | `scenario vague-run` (5 open rules: 4 dialogs) | yes | WP14 |
| D05 | One High finding of Review is repaired in the stage with 0 dialogs: the run still asks 2. One full Review is launched, then one fix agent and one narrow recheck | `scenario repair-finding` | yes | WP24 |
| D06 | A failed group check hands nothing back: 0 hand backs in driver mode, the fix agent is launched once, and `temper:temper-plan` is launched once in the whole run. When the fix does not pass, one question shows what was tried | `scenario group-fail`; `scenario group-fail-twice` | yes | WP16 |
| D07 | A failed `integrate` is a verdict for every carrier: the run is carried to its question with 0 hand backs | `scenario integrate-fail` driver | yes | WP09 |
| D08 | Repeats are bounded: 2 for one failure and 6 for one run, then one question that shows the count. No third launch for the same failure | `scenario budget-stop`; `case 45 D38a`, `case 45 D38b` | yes | WP10 |
| D09 | The launches of a default run on the two group fixture: Intent 1, Plan 1, the acceptance writer 1, one Build task agent a chain (2), Review 1. No Design, no fresh plan review, no Check agent, no environment agent, no Build fix or record pass | `floor default-run.launches`, compared by agent type | yes | the head; kept by WP14 and WP27 |
| D10 | A criterion validated by `code` or `metric` is recorded by the CLI: no record pass and no Check agent | `scenario criteria-by-cli` plain | yes | WP27 |
| D11 | The slow scripted project (build file one folder down, a suite slower than every default limit, no coverage tool) passes Check on correct code with no config edit, hits no limit, runs the whole suite at most 3 times and asks 2 dialogs | `scenario slow-first-run` plain, driver; `floor slow-first-run.suite_runs` at most 3 | yes | WP23 (WP19, WP20 and WP22 before it) |
| D12 | Coverage is judged against the project: 55% on the base and 55% after passes; a drop fails with a row that names it | `scenario slow-at55` plain | yes | WP19 |
| D13 | On the broken scripted project every fault is named before Build with no agent launched for it: the tool version and the service in the first question, before any agent, with the setup block on offer; the red test before the planner is launched. No environment agent and no fix pass in the run | `scenario broken-first-run` plain, driver | yes | WP21 (WP20 before it) |
| D14 | A check that is green on the base and then fails runs once more before any agent; fail then pass is recorded as flaky and shown at the commit | `scenario broken-flaky` plain | yes | WP22 |
| D15 | A failed check is never run again unchanged: the tree, the command, the environment or the limit must differ | `case 44 D15` | yes | WP22 |
| D16 | In a default run no question follows a passed check, other than the approval and the commit. Every question names the decision it asks for | `case 44 D16`; `case 40 ids:` (the decision field) | yes | WP11 |
| D17 | The second option of the approval, Ask me at every stage, keeps every gate's own question: Build, Review and Check each ask once | `scenario ask-every-stage` | yes | the head; kept by WP11 |
| D18 | `run.default` is `to-commit`, `ask` or `never-unattended`: `ask` puts Ask me at every stage first and recommended; `never-unattended` offers no option that runs to the commit | `case 44 D18a`, `case 44 D18b`, `case 44 D18c` | yes | WP11 |
| D19 | An unattended run that was interrupted and is taken up again asks the question of its stage once, with every option | `case 44 D19` | yes | WP11 |
| D20 | Design runs only when asked: a default run launches no Design agent at any tier or risk; the approval offers it | `scenario design-on-ask` plain | yes | WP14 |
| D21 | The locked acceptance tests run when Build ends, inside `integrate`. A failing one gets the triage first in every mode, and no fix agent changes code for a test the triage calls wrong; correcting the test is one question | `scenario acceptance-wrong-test` | yes | WP23 |
| D22 | The approval card and the commit card are fields of the view and text the CLI prints, the same with the mod and without: the request as typed, the criteria one line each, the files by group, a sensitive path on its own line, the gate commands word for word, and what the run does by itself | `case 44 D22a`, `case 44 D22b` | yes | WP15 |
| D23 | A reader decides each sample card in under a minute | none; WP32 puts three sample cards in the pull request text | person | WP32 |
| D24 | A revision of the plan is a narrow agent that gets the note or the findings and the task blocks they name, not a full planner pass | `scenario revise-narrow` plain | yes | WP27 |
| D25 | TRIVIAL is a verdict the CLI records, with a size bound the commit hook checks: after a trivial exit a commit that changes more than the bound is refused | `case 46 D25` | yes | WP17 |
| D26 | A plan amendment by rule only adds to a task a file the same group already owns; every command line and every file outside the approved set is `plan patch`, the person's. The approved record is appended to, never overwritten. The plan gate has the row for a group with no Validate. A full replan keeps built tasks whose approved fields did not change | `case 46 D26a`, `case 46 D26b`, `case 46 D26c`, `case 46 D26d` | yes | WP25 |
| D27 | At the simple tier Plan writes `tasks.md` only and the plan gate passes; nothing a brief asks an agent to write goes unread | `case 46 D27a`, `case 46 D27b` | yes | WP26 |
| D28 | Build task agents run on Sonnet by default with a key for Haiku; the planner stays on Opus behind a key | `case 46 D28` | yes | WP27 |
| D29 | Two listed commands, `/temper:temper` and `/temper:fix`; `draft`, `status`, `report`, `init` and `pack` are first words of `/temper:temper`; no door file is left. No question, panel or status line says armed or parked | `caps listed_commands` = 2; `case 46 D29a`, `case 46 D29b`, `case 46 D29c` | yes | WP31 (WP28 before it) |
| D30 | Rule 1. Before the approval a run writes only its spec folder: no project file, no branch, no commit | `scenario approval-first` plain, mod (asserts `D30a` at the approval: the branch, the commit count and the files outside the spec folder are as at the start); `case 44 D30b` (the step that leaves Intent runs no branch and no commit call); `case 44 D30c` (with the mod off, a commit of a project file before the approval is refused by the commit hook) | yes | WP12 |
| D31 | Rule 2. The approval is of what was shown; a later change to the intent or the plan fails the gates until approved again | `case 44 D31a` (the approval's calls carry the digests; a stale digest is refused and nothing advances); `case 44 D31b` (a changed criterion fails the Build, Check and commit gates with the row `intent unchanged since the approval`; the CLI's own Status and Completed writes do not); `case 44 D31c` (a changed File, Test or Validate line of `tasks.md` fails them too); `mod guard.test.ts` (a write to `intent.md` from Build on is refused) | yes | WP12 |
| D32 | Rule 3. Only an option the person picked starts an unattended run; a step back, a skip or an accepted finding ends it | `case 44 D32a` (no action of the CLI's own, in any fixture view, sets the unattended mode); `case 44 D32b` (after a step back to Plan or Intent the mode is interactive); `case 44 D32d` (the same after a skip and after an accepted finding); `scenario stop-keeps-mode` (asserts `D32c`: any other stop keeps the mode, and its question says the run goes on by itself); `case 44 D18c` | yes | WP11 (WP08 for `D32b`) |
| D33 | Rule 4. An unattended run never plans again, changes a gate's command, the intent or the approved file set, skips a check, accepts a finding, writes the config, pushes, opens a pull request or makes the final commit | `case 44 D33a` (the walk over `scripts/stops.json`: at each stop `next` is a question or a recorded stop); `case 44 D33b` (no `auto` action of a fixture view runs a forbidden call; every scenario of `accept.ts` asserts the same of its own trace); `scenario group-fail-twice` (asserts `D33c`: one planner launch); `scenario broken-first-run` (the config changes only through the answer that adds the setup block) | yes | WP11 (WP08 before it) |
| D34 | Rule 5. Every verdict is computed by the CLI from runs the CLI made or the person confirmed, and names the tree it judged | `case 44 D34a` (a claimed run passes no row); `case 44 D34b` (every verdict of `.temper/gates.json` names a git tree); `case 44 D34c` (a file changed after Check passed fails the commit gate, and the row names both trees); `case 44 D34d` (a Review that read fewer files than the change holds fails `review covered the diff`) | yes | WP22 (WP18 for `D34d`) |
| D35 | Rule 6. A failure's class picks the next step, never a verdict. A check that was not measured is shown as not measured | `case 44 D35a` (no class turns FAIL into PASS: the verdict stays until a CLI run passes on a new tree or the person skips with a reason); `case 44 D35b` (a missing coverage tool is `not measured` in the gate, the view and the commit card, never passed and never failed); `case 44 D35c` (the planted bug score is information: it fails nothing and moves nothing); `case 44 D35d` (a missing tool is told by exit 127, never by output text) | yes | WP23 (WP19 for `D35b` to `D35d`) |
| D36 | Rule 7. Tests come first, and the tests that gate the code are written and locked by an agent that did not write it | `case 45 D36a` (a task gate with no failing run before the passing one is refused); `case 45 D36b` (the acceptance tests are locked by digest before the first task gate, and a changed locked test fails the Build gate); `floor default-run.launches` (the acceptance writer is an agent type of its own) | yes | the head; kept by WP23 and WP27 |
| D37 | Rule 8. A finding is resolved only by the CLI, for a commit the CLI made, after its checks passed on that tree and a reader that did not write the fix confirmed it | `case 45 D37a` (`evidence resolve` with a note for `--fixed-by` is refused); `case 45 D37b` (refused for a commit the CLI did not record as its repair, and when no recheck row follows the commit); `case 45 D37c` (a repair that deletes test lines is never resolved by rule); `scenario repair-finding` (asserts `D37d`: the order of commit, runs, recheck, resolve); `scenario repair-worse` (asserts `D37e`: a repair that breaks a passing row is reverted and asked) | yes | WP24 (WP18 for `D37a`) |
| D38 | Rule 9. Every repeat is counted in the CLI against one budget, 2 per failure and 6 per run; only the person grants more | `case 45 D38a` (each kind of repeat spends one; the third for one failure is refused); `case 45 D38b` (the seventh of a run is refused); `case 45 D38c` (no argument exempts a call; at the limit `next` is one question and offers no refused call); `scenario budget-stop` (asserts `D38d`); `case 45 D38e` (the old loop keys are read by nothing); `mod guard.test.ts` (the call that grants more is person only) | yes | WP10 |
| D39 | Rule 10. The person decides only in a question dialog, and the commit question lists everything a rule decided since the approval | `gate bash scripts/check-mod-calls.sh` (the reviewed calls, none that decides); `mod audit.test.ts` (every option of every fixture view counts only on the exact match); `scenario repair-finding` (asserts `D39b`: the commit card lists the repair, its files and the recheck); `case 45 D39c` (an amendment by rule, a carried Medium finding, a check not measured, a stop with its answer and the budget used are each on the card); `case 45 D39d` (every stop of an unattended run is a question or a recorded stop) | yes | WP25 (WP15 for the card, WP24 for the repair) |
| D40 | Rule 11. Each rule holds in the CLI or the commit hook with the mod off; where only the mod holds something, the docs say so | `gate python3 scripts/check_done.py` (each of `D30` to `D39` names a case or a plain mode scenario); `gate bash scripts/check-known-limits.sh` (`docs/trust.md` says only the mod checks that a person clicked); `gate bun scripts/e2e/run.ts both` (the plain and mod traces are equal) | yes | WP31 |
| D41 | M1. After a fix that breaks the Integration suite the run is not stranded: `integrate` passes again once the code is repaired, and the failure in between asks | `case 45 D41` | yes | WP08 |
| D42 | M2. A passed Review with an open Medium finding keeps Accept a finding, Grill Me, Teach Me, Make a small change and Save for later in reach | `case 45 D42` | yes | WP08 |
| D43 | M3. In an unattended run the group fix agent is launched after a failed group check | `case 45 D43` | yes | WP08 |
| D44 | M4. An unattended run never steps back to Plan: it stops and asks | `case 45 D44`; `case 44 D33a` | yes | WP08 |
| D45 | M5. After a step back to Plan the run asks at every stage whatever the person answers, and a passed Design is not skipped | `case 44 D32b` | yes | WP08 |
| D46 | M6. A criterion only the person can confirm stops an unattended run with the confirmation on offer; it never loops back to Build | `case 45 D46` | yes | WP08 |
| D47 | M7. No brief records a claimed test run; where the CLI is given a test command, the run it makes passes the test row | `case 45 D47a`, `case 45 D47b` | yes | WP08 |
| D48 | M8. The config reader merges a repeated key, and the template has no empty key that hides a documented block | `case 45 D48a`, `case 45 D48b` | yes | WP08 |
| D49 | M9. A code bug that prints `Connection refused` is not held as an environment fault for good: the question offers `it-is-the-code`, and never recommends the same step twice | `case 45 D49` | yes | WP08 |
| D50 | M10. An environment fault at Check does not recommend the same repair a second time | `case 45 D50` | yes | WP08 |
| D51 | M11. When only the commit gate's own row fails, an option runs the gate again | `case 45 D51` | yes | WP08 |
| D52 | M12. The mod refuses every push during a run, a `temper-backup/` destination included | `mod session.test.ts` | yes | WP08 |
| D53 | M13. A setup block reaches the config only by the person's answer to a question that shows the block word for word; `doctor` with `--write` is person only; the environment agent is not offered | `case 45 D53a`, `case 45 D53b`; `mod v975.test.ts` | yes | WP08 |
| D54 | M14. Every file of the CLI that can turn a gate row is in the mod's guarded list: the reuse store, `.temper/decisions.json`, and each file a later package adds | `mod guard.test.ts` | yes | WP08; kept by WP22 and WP23 |
| D55 | M15. A plan command slower than its limit is a class of its own, with a longer limit, another command or a skip with a reason on offer; never an environment fault, never an agent | `case 45 D55` | yes | WP08; kept by WP21 |
| D56 | M16. After the environment was repaired the next check runs the command again: no stored failure is returned, and the failed plan question offers `check-again` | `case 45 D56a`, `case 45 D56b` | yes | WP08; kept by WP21 |
| D57 | The flips. A Medium finding is listed at the commit question and starts no loop by rule; an answered Design question passes its row with a note; a High finding blocks Review by default | `case 45 D57a`, `case 45 D57b`, `case 45 D57c` | yes | WP08 |
| D58 | The replay of the measured run ends with: 3 questions (the setup block, the approval, the commit), at most 7 agent launches with Plan launched once, 0 loops recommended, 0 repairs by hand, 1 setup click, at most 92 agent minutes by its own weights, the High defect not in the commit, the change committed, the bad Validate line not in the plan | `gate bun scripts/e2e/replay.ts final` with `floor replay` | yes | WP24 |
| D59 | Against 9.8.5 on the same replay no number is worse | `gate bash scripts/e2e/ab-replay.sh 10e965a`; the table goes into the pull request text | yes | WP32 |
| D60 | A run saved by 9.8.5 goes on: from each of five saved states (the plan question, Build with a group running, an armed run in Build, Review with an open finding, a parked run) `next` is never `broken` or `error`, and the run reaches the commit. A saved armed run is taken up asking at every stage: its approval was for Build alone | `case 46 D60a`, `case 46 D60b`, `case 46 D60c`, `case 46 D60d`, `case 46 D60e` | yes | WP11 (only the armed state fails at the head); kept by WP10, WP12, WP22, WP23 |
| D61 | An old config works: with the 9.8.4 and the 9.8.5 template as the project's config, `next`, every gate and `config get` run with no error; a key that is no longer read is named once and is never an error | `case 46 D61a`, `case 46 D61b` | yes | WP29 |
| D62 | The one time question: the first run after the upgrade asks once whether to remove the config lines that only repeat old defaults; yes rewrites the file to the lines the person changed and keeps a copy; no keeps the old behaviour; it is never asked again | `case 46 D62a`, `case 46 D62b`, `case 46 D62c` | yes | WP29 |
| D63 | An existing `autonomy.enabled: false` means `run.default: ask` | `case 44 D18b` | yes | WP11 |
| D64 | A commit hook installed by 9.8.5 still blocks a commit under a failed gate, and the setup check asks for a new install when the hook lacks a marker this build added | `case 46 D64a`, `case 46 D64b` | yes | WP24 |
| D65 | The view stays version 1: no field of a 9.8.5 view is renamed or removed, and the mod's reader takes a 9.8.5 view | `case 46 D65`; `mod ids.test.ts` | yes | the head; kept by every package |
| D66 | Cap: question sites at most 53 | `caps question_sites` | yes | the head; kept by every package |
| D67 | Cap: option sites at most 89 and option labels at most 71 | `caps option_sites`; `caps option_labels` | yes | the head; kept by every package |
| D68 | Cap: gate rows at most 55 | `caps gate_rows` | yes | the head; kept by every package |
| D69 | Cap: agent briefs at most 13 | `caps agent_briefs` | yes | the head; kept by every package |
| D70 | Cap: listed commands 2; listed skills at most 2 | `caps listed_commands`; `caps listed_skills` | yes | WP30 (WP28 for the commands) |
| D71 | Cap: the config template has at most 12 live key lines and at most 60 lines; every key in it, live or commented, has a reader in code | `caps config_live_keys`; `caps config_lines`; `case 46 D71` | yes | WP29 |
| D72 | Cap: prompt bytes (commands, agents, reference) at most 307,712; packs and skills at most 79,658 | `caps prompt_bytes`; `caps pack_skill_bytes` | yes | the head; kept by every package |
| D73 | Cap: no tracked file over 262,144 bytes; `scripts/temper` at most 222,144 bytes (the 40 KB of WP02 still free) | `gate bash scripts/quality-check.sh`; `caps cli_bytes` | yes | WP02; kept by every package |
| D74 | Cap: the mod makes exactly the 20 reviewed host calls of the head, none added | `gate bash scripts/check-mod-calls.sh` | yes | the head; kept by every package |
| D75 | Every count of the floor is at or under its final value, and no final value was raised | `gate python3 scripts/check_floor.py --final` | yes | WP31 |
| D76 | Every stop of `scripts/stops.json` still has its check; none left the list without a decision record | `case 46 D76` (no stop has an empty check, and each named check exists) | yes | WP07; kept by every package |
| D77 | Every rule of the plugin directory holds | `gate bash scripts/validate-directory.sh` | yes | the head; kept by every package |
| D80 | The selftest is green with nothing expected to fail | `gate bash scripts/selftest/run-selftest.sh` ends `PASS: N  FAIL: 0` and `XFAIL: 0` | yes | WP32 |
| D81 | The end to end suite is green in every mode, with the plain and mod traces equal and the floor met | `gate bun scripts/e2e/run.ts all --floor scripts/e2e/floor.json` | yes | WP32 |
| D82 | The mod's suite, the type check, the reviewed calls and the documented limits are green | `gate claude plugin test .`; `gate tsc -p tsconfig.mod.json`; `gate bash scripts/check-mod-calls.sh`; `gate bash scripts/check-known-limits.sh` | yes | WP32 |
| D83 | Every validator is green | `gate bash scripts/quality-check.sh`; `gate bash scripts/selftest/test-validate-directory.sh`; `gate bash scripts/validate-readme.sh`; `gate bash scripts/validate-docs.sh`; `gate bash scripts/validate-plugin.sh`; `gate python3 scripts/validate-panels.py`; `gate claude plugin validate --strict .` | yes | WP32 |
| D84 | Every assertion of a test of the base `10e965a` that was changed or removed is listed in `docs/plans/one-go/changed-tests.md` with what changed and why | `gate python3 scripts/check_changed_tests.py` | yes | WP07; kept by every package |
| D85 | The expected to fail list is empty, every row of this table has its check, and no test is skipped | `gate python3 scripts/check_done.py --final` | yes | WP32 |
| D86 | The version is 10.0.0 in the manifest, the changelog, the README and the docs | `gate bash scripts/quality-check.sh` (the version blocks) | yes | WP31 |
| D90 | Bench, a bug (`cent-mismatch`, `tenant-leak`): cost at most 1.5 times and time at most 2.5 times plain Claude Code; 2 dialogs; no clean run handed back | `bench bug` | no | WP32 |
| D91 | Bench, a clear feature (`partial-payments`, `ts-seat-holds`): cost at most 2 times and time at most 4.5 times; 2 dialogs | `bench clear` | no | WP32 |
| D92 | Bench, a vague feature (`vague-refunds`, `vague-late-fees`): cost at most 3 times and time at most 4.5 times; 2 dialogs plus one for every four open rules | `bench vague` | no | WP32 |
| D93 | Bench: hidden tests equal to the before round, the same six tasks run on `10e965a` | `bench hidden` | no | WP32 |
| D94 | Bench: at least 95% of the rules met on the vague tasks | `bench rules_met` | no | WP32 |
| D95 | Bench: a repaired finding costs no dialog and no second full Review; the share of runs with two or more Reviews is at most half of the before round | `bench reviews` | no | WP32 |
| D96 | Bench: no rise in blocked tasks or in steps back to Plan against the before round | `bench steps_back` | no | WP32 |
| D97 | One real Maven or Gradle project measured before and after: reported, with no pass line | none; the numbers go into the pull request text | no | WP32 |

## Notes on the table

1. **The bench gate (part H).** It needs a model credential and about 80 dollars and 6 hours: the before round on
   `10e965a` with plain Claude Code beside it (36 runs, 40 to 50 dollars) and the after round on the result (18
   runs, about 30 dollars), three runs a task and arm. The sizes are those of round M1 in
   `docs/plans/one-go/evidence/v-targets-scorecard.md`, section 4. The commands, the first on each tree:

   ```
   BENCH_TASKS="cent-mismatch tenant-leak vague-refunds vague-late-fees partial-payments ts-seat-holds" \
     bash bench/run-all.sh 3 vanilla temper
   python3 bench/scorecard.py --gate docs/evidence/scorecard-10.0.0.json
   ```

   A session with no credential leaves part H open: `bash scripts/verify.sh final` prints the open line and the
   pull request text says so. `D97` needs a project and about 25 to 75 dollars more and is the owner's to order.
2. **The clear feature's cost line.** The frame keeps the planner on Opus. With that, the arithmetic of
   `docs/plans/one-go/evidence/v-targets-scorecard.md`, section 3.3, expects about 2.5 times the cost, not 2. If
   `D91` misses on cost and holds on time and dialogs, report it as the plan's own second line (2.5 times with the
   planner on Opus), with the numbers, and do not tune.
3. **What the scripted checks cannot show.** Dollars, seconds, and whether a real model follows a brief. Parts A
   to G prove what Temper itself decides, asks, launches and checks.
4. **Rows that hold at the head.** `D09`, `D17`, `D36`, `D65`, `D66` to `D69`, `D72`, `D74` and `D77` pass today. They
   are in the table because a later package can break them; their checks are never on the expected to fail list.
5. **A cap that cannot be met.** The caps of part F are the values of 9.8.5 or lower. New questions and rows of
   this build (the red base, the budget, the repair stop, `intent unchanged since the approval`) must take the
   place of ones that go. A building session never raises a `final`: a cap it cannot meet is written to
   `docs/plans/one-go/PROGRESS.md` with the measured number and named in the pull request text, for the owner.
6. **Three finals are readings of the plan's words.** At most 12 live config lines stands for "about 10"; at
   most 60 template lines and at most 2 listed skills follow from release 7 and are not numbers of the plan.
7. **The order of the last column.** A row may pass earlier than its package; then its line leaves the list in
   that commit. It may not pass later.
