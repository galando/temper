# The Temper CLI itself (`scripts/temper` and its helpers): map for the restructuring plan

Reader: cli-core, one of 17. Read on the local branch `pr115` at commit `9a01eff` (version 9.8.5).
All `file:line` references are to that commit, in `/home/user/temper`.

**Confidence words used below.** *verified*: I read the code at the cited lines. *measured*: I ran it
in a scratch clone and report the number. *doc-claim*: a comment or a doc says so and I did not check
the behaviour. *inferred*: my conclusion from several facts.

**Two things the planner must know first.**

1. The pull request moved while I was reading. GitHub's head of PR #115 is now `c417166`, two commits
   after the local `9a01eff` (`573bb66` adds an A/B replay script and three fixes in `flow.py` and
   `gate_rows.py`; `c417166` fixes one shell script). I fetched it into my scratch clone and diffed it:
   nothing in `scripts/temper` changed, so every finding here still holds for the CLI. (measured:
   `git diff --stat 9a01eff c417166` lists 9 files, none of them `scripts/temper`.)
2. All timings are from one machine (4 vCPU Xeon 2.1 GHz, Python 3.13.18, bash 5.2) on the e2e
   driver's toy project (2 groups, 2 tasks, `python3 -m unittest`). They show the CLI's own overhead.
   They say nothing about a real project's test time.

---

## 1. Architecture

### 1.1 What language each part is in

| Part | Size | Language |
|---|---|---|
| `scripts/temper` | 5,121 lines, 260,504 bytes (origin/main: 5,133 lines, 258,648 bytes) | bash (`#!/usr/bin/env bash`, `scripts/temper:1`) |
| of which bash statements | about 3,230 lines | bash |
| of which Python embedded in the bash file | about 990 lines, in 104 `python3 -I -c "..."` or heredoc blocks | Python source inside bash strings |
| of which comment-only lines | about 730 | |
| call sites in `scripts/temper` that start a helper `.py` file | 81 | |
| `scripts/*.py` | 48 files, 12,335 lines (`flow.py` is 3,111 lines, 205,263 bytes) | Python, standard library only |

(measured with `wc` and a line classifier; the embedded Python count is approximate.)

So the CLI is a bash dispatcher that starts a new Python process for almost every small step: read one
JSON field, build one JSON row, append one row, parse `tasks.md`. Each stage gate is bash that calls
`_req` (one Python start per row, `scripts/temper:2004-2010`) or a helper module per row family.

A hard ceiling shapes this: no tracked file may be over 256 KiB (`scripts/quality-check.sh:21-27`).
`scripts/temper` is at 260,504 of 262,144 bytes, 1,640 bytes below the limit (measured). Helper files
say they exist because of it (`scripts/intent_draft_rows.py:3`, `scripts/bands.py:5-6`,
`scripts/plan_rows.py:5-6`, `scripts/gate_rows.py:9`, `scripts/loop_step.py:5`). Any new logic in
`scripts/temper` today forces another split into another subprocess.

### 1.2 How a command is dispatched (verified)

1. Boot (`scripts/temper:45-121`). `REPO_ROOT` is the current folder, or the nearest folder above it
   that has `.temper` (never the home folder, never past a `.git`) (`:75-87`). `PLUGIN_ROOT` comes from
   the script's own real path (`:58-67`). All state paths are fixed under `$REPO_ROOT/.temper`
   (`:90-110`).
2. `main` (`:4981-5119`):
   - `_require_python` (`:4982`).
   - Refusals for every subcommand except `config`, `model`, `guards` and help (`:4997-5003`): the home
     folder (`_home_refuse`, `:218-225`), a folder inside the plugin (`_inside_plugin_refuse`,
     `:191-216`), a symlink on any run-state path (`_unsafe_temper_refuse`, `:227-261`, exit 3), and
     `_config_pin` (`:667-673`). `_unsafe_temper_refuse` starts one Python process on every call just
     to read `spec_path` (`:249`).
   - One `case` over 32 top-level subcommands (`:5004-5106`): init, state, evidence, gate, model,
     override, report, status, bands, metrics, config, schedule, group, task, integrate, usage, next,
     risk, adhoc, plan, doctor, guards, intent, park, drift, check, acceptance, go, spec, brief, output,
     panel. Seven of them are one line that starts one Python file (`doctor`, `drift`, `go`, `spec`,
     `brief`, `output`, `panel`, `:5025-5050`).
   - After the command, the view is rewritten unless the command is on a read-only list
     (`:5108-5117`), see 1.6.
3. `temper next` is `cmd_next` (`:4644-4648`): one Python process, `scripts/cli_ctx.py next`, which
   resolves the models, computes the setup calls, prints the action and writes the view
   (`scripts/cli_ctx.py:137-164`).
4. `temper go` is `scripts/go.py` (`scripts/temper:5036`): a loop that starts `temper next --json` as
   a subprocess, runs the action's calls each as `bash -c <call>` (so each is a full CLI start), and
   stops at the first agent launch or question (`scripts/go.py:84-121`).

### 1.3 Where state lives: every file under `.temper/`

"CLI" means `scripts/temper` or a helper it starts. Line numbers are in `scripts/temper` unless a
file is named. (verified, except where marked)

| File | Written by | Read by |
|---|---|---|
| `build-state.json` (the run: stage, next_stage, spec_path, branch, command, run_id, step, complexity, risk, base_sha, plan_hash, approved_files, enter, fresh, redo, adhoc, parked, review_snapshot, end_report, intent_asked, ...) | `state init` (`:743-776`, plain `json.dump`, no lock, not atomic); `_json_set_path` (`:458-493`); `_state_next` (`:995-1039`); `state advance` (`:1146-1164`, `:1190-1207`); `state redo` (`:1474-1490`); `_review_code save` (`:3793-3798`); `gate intent` sets `intent_asked` (`:2100`); `gate build` sets `built_before` (`:4300`); `adhoc_ops.py`; `fresh_review.py mark`; `plan_patch.py`; legacy migration (`:781-815`) | every command; `flow.py:115`; `cli_ctx.py:46-54`; `panel.py:115`; `gate_rows.py:271`; guard scripts (`scripts/guards/verify-tests-ran.sh`, `block-uncommitted-gate.sh`, `protect-regression-test.sh`); the mod protects it (`hooks/temper-mod/core/rules.ts:121`) |
| `gates.json` ({stage: {verdict, requirements, ts}}) | `_gate_write_verdict` (`:1834-1851`); `_redo_from` removes redone stages (`:1041-1092`); scaffold in `init`/`state init` | `_stage_satisfied` (`:3974-3979`); `gate commit` (`:4132-4144`); `report` (`:4712-4741`); `_archive_ledger` (`:1378-1413`); `flow.py:117`; `output_ops.py:62`; guards `stage-marker.sh`, `verify-stage-gate.sh` |
| `overrides.json` (the person's skips) | `override` (`:4399-4424`); `_redo_from` moves redone ones out | `_override_covers` (`:3981-4001`); `flow.py:118`, `:286-294`; report; archive |
| `feedback-loops.json` | `loop_step.py:70,122` (plain `json.dump`, no lock) via `state loop` (`:1222-1262`); scaffold | `flow.py:119`; `/temper:status` |
| `evidence/<stage>.json` for intent, plan, design, build, review, check, commit, pipeline, rca, fix (`:1859-1874`) | see 1.4 | every gate; `flow.py` (notes, findings); `acceptance.py status`; `output_ops.py`; `panel.py`; `group_report.py` |
| `evidence/approved-tasks.json` | `state advance plan_complete` and `design_complete` (`:1144`, `:1209`) | `flow.py:158` |
| `evidence/acceptance-lock.json` | `check_run.py acceptance` (`:4976`) | `check_run.py:724`; flow |
| `groups.json` (grouped Build: groups, tasks, attempts, integration verdict) | `_groups_mutate` (`:2216-2247`, 18 call sites); `group_fix.py`, `task_cover.py`, `task_blocked.py`, `plan_patch.py`; archived by `_groups_reset` (`:1297-1329`) | `tasks_md.py schedule`; `task_ops.py`; `gate build` (`:3695-3701`); `task_rows.py`; `flow.py:120`; `panel.py:240`; `output_ops.py:51` |
| `usage.json` | `_usage_append` (`:4769-4779`); `usage_ops.py fill` | `usage_ops.py json` for report and archive (`:4781-4784`); `flow.py:121` |
| `status.json` (criteria passed or open) | `_status_write` after every recorded gate (`:4304`, `:4344-4350`); `status` (`:4370`) | `/temper:status` (`commands/status.md`). The mod only lists it as protected (`rules.ts:120`); I found no reader in the mod (inferred from grep) |
| `view.json` | `flow.py:2878-2889`, started by `cli_ctx.py` | the mod (`hooks/temper-mod/adapter.ts`, `core/runview.ts`, `register.tsx`); `run_report.py:192`; `flow.py:2854-2863` as a fallback memory |
| `agents-named.json` | `flow.py:2866-2875` | `flow.py:2851-2863` |
| `preflight.json` (new in PR #115) | `preflight.py:166-181` | `preflight.py:167-173`, `:232`; `flow.py:1189`, `:1211` |
| `decisions.json` (new in PR #115) | `decisions.py:40-50` via `answer_ops.py:147` | `decisions.py:53-69` (the Design gate row) |
| `brief.md` | `brief.py` (`:5043`) | Plan, Design, RCA agents |
| `autonomy-report.md` | `park` (`:4510-4538`) | the person |
| `metrics.json`, `bands.json` | `metrics append` (`:4833-4883`, not atomic, no lock); `bands.py:93-95` | `bands.py`; `/temper:status` |
| `pending-stage.json`, `stage-gate.log` | guard scripts, not the CLI | guard scripts; `gate` removes the first (`:4316-4322`) |
| `security-map.json` | not the CLI (an agent, per `reference/plan.md`) | `risk.py` (`:4631`); `panel.py:125` |
| `archive/` | `_redo_from` (`overrides-redone.json`); `state init` pre-init copies (`:719-730`); `_groups_reset` | nobody in code |
| `check/` | `check_run.py` (coverage files, the background run) | `check_run.py` |
| `.lock/` and `.lock.new.*`, `.lock.break`, `.lock.dead.*`, `.lock.free.*` | the lock (1.5) | |
| `specs/<slug>/`: `intent.md`, `plan.md`, `tasks.md`, `design.md`, `rca.md`, `gate-ledger.json`, `report.html`, `pipeline-context.json`, `acceptance/` | agents write the `.md` files; the CLI edits them in place: `intent accept/complete/carry/answer` (`:4437-4505`), `_tier_lines` (`:950-977`), `plan review` (`plan_ops.py:122-146`), `_task_box` ticks (`:2849-2868`), `design-accept` (`flow.py:3028-3046`), `_archive_ledger` (`:1341-1417`), `run_report.py` | gates; flow |
| `<git common dir>/temper-results.json` (outside `.temper`) | `run_env.py:149-180` | same |

Names in the run-file list that nothing in `scripts/` writes: `observability.json`, `autonomy.lock`,
`coverage.json`, `coverage/`, `index/`, `reviews/`, `test-gap-report.json` (`scripts/temper:632-634`;
verified by grep over `scripts/` and `hooks/`).

### 1.4 The evidence ledger (verified)

One JSON array per stage, `.temper/evidence/<stage>.json`. A row is
`{claim, cmd, exit_code, artifact, sha256, value, severity, phase, scenario, criterion, label, ts}`
plus optional `confidence`, `kind`, `executed_by`, `task`, `group`, `attempt`, `output`, `fail_lines`,
`resolved`, `accepted`, `voided`, `contested` (`scripts/temper:1563-1577`, `:1754-1762`;
`task_ops.py:449-454`).

Two kinds of writer, and the difference decides what a gate believes:

- **A claim**: `temper evidence add` (`:1513-1580`). An agent passes `--exit N` itself. Label defaults
  to HEURISTIC; a PROVEN label is downgraded when the artifact is missing or the exit is nonzero
  (`:1546-1554`). No `executed_by` field.
- **A run the CLI made**: `temper evidence run -- <cmd>` executes the command itself (`:1748`) and
  writes `executed_by: cli` (`:1760`); so do `task test` (`task_ops.py:449-454`), the group gate's
  Validate (`task_ops.py:459-470`), `integrate` (`task_ops.py:483-490`), the scenario runs
  (`scenario_ops.py:145-150`), `check run` (`check_run.py:189-192`), and the CLI's own
  feedback-resolved row (`:3272-3277`). `task confirm` writes `executed_by: person` (`:3449-3453`).

Since PR #115, the Build gate's "RED then GREEN" and Check's "tests pass" count only CLI or person
rows unless the config says `evidence.claimed-runs: count` (`scripts/runs.py:30-33`,
`scripts/temper:3634`, `:3869`). Other rows still accept claims (section 2).

Rows are never deleted to pass a gate: `resolve`, `accept`, `void`, `contest`, `escalate` mark a row
(`:1617-1713`, `:1780-1804`, `runs.py:59-80`). A step back truncates the ledgers of the redone stages
(`_clear_evidence_downstream`, `:1876-1896`).

### 1.5 The lock (verified)

A `mkdir` lock at `.temper/.lock` with an owner token inside (`:331-334`, `:395-445`). Calls nest by
a depth counter (`:396`, `:446-454`). It waits `TEMPER_LOCK_WAIT_S` (default 10 s) and, for a live
holder, up to `TEMPER_LOCK_MAX_S` (default 120 s), then **fails with exit 75 and writes nothing**
(`:421-440`, new in PR #115). A stale lock (owner process gone, or no owner and older than 30 s) is
broken (`:335-385`).

Details that matter for a redesign:

- Each 20 ms poll while waiting is a new Python process (`python3 -I -c "import time; time.sleep(0.02)"`,
  `:433`, `:437`, `:442`).
- The lock is held around whole command bodies for `task start` (`:2918-2925`), `task gate`
  (`:3073-3080`) and `group reopen` (`:2593-2600`), which include git commits and merges.
- **Comment and code disagree.** The block comment still says a lock held past `TEMPER_LOCK_MAX_S (60)`
  "is written past with a WARN (fail open)" (`:326-328`); the code uses 120 and exits 75 (`:432-440`).
- **Comment and code disagree.** "Every JSON write below goes through a temp file ... and os.replace"
  (`:456-457`) is false for `state init` (`:775`), `evidence clear` (`:1776`),
  `_clear_evidence_downstream` (`:1894`), `_status_write` (`:4348`), `metrics append` (`:4871`),
  `loop_step.py:70,122` and `preflight.py:140`. None of those takes the lock either. `check run`
  replaces the Check ledger atomically but without the lock (`check_run.py:746-749`,
  `scripts/temper:4947`).

### 1.6 The view writer (verified and measured)

`_view_write` (`:4652-4656`) starts `cli_ctx.py view`, which builds the run, computes the next action
and writes `.temper/view.json` and `.temper/agents-named.json` (`cli_ctx.py:151-157`,
`flow.py:3098-3108`, `:2866-2889`). It runs after every command except `config`, `model`, `guards`,
help, `report`, `status`, `bands`, `metrics`, `schedule`, `drift`, `doctor`, `state get`,
`evidence list`, `group report`, `task show` (`:5108-5117`). `next` writes it in its own process
(`:5111`). `report --html` writes it once more before rendering (`:4690`) and `_report_end` again
(`:4674`).

Two facts about its cost:

- `temper next` computes everything **twice** in one process: `run_next` builds a `Run`, reads the git
  facts and calls `Builder.next()` (`flow.py:3088-3095`), then `run_view` builds a second `Run`, reads
  the git facts again and calls `Builder.next()` again (`flow.py:3098-3103`; `cli_ctx.py:161-163`).
  Measured: 21 to 31 `git` processes per `temper next`, against 9 to 14 for the view writer alone.
- The computation is cheap; the processes are not. In one process, `Run()` + `Builder.next()` +
  `view()` take about 7 ms, the git facts 24 to 33 ms, the imports 17 to 21 ms (measured with a small
  script that calls the same functions).

In the measured full run, `view.json` was written 83 times for 84 CLI calls (59 separate
`cli_ctx.py view` processes at about 85 ms each, plus 24 inside `next`).

---

## 2. Every row of every stage gate

`temper gate <stage>` is `cmd_gate` (`:4229-4336`). It computes the rows, writes the verdict to
`gates.json`, rewrites `status.json`, marks two small-change steps (`adhoc_ops.py`, two more Python
starts, `:4306-4309`) and prints the rows (all of them, or only failed ones with `--brief`,
`:4324-4333`). A verdict is PASS only when every row passes (`:4291-4292`).

The last column answers the planner's question: does the row need text or ledger rows **a model
wrote**, or is it computed from files and command runs alone? "Model text" means the row lints a file
an agent wrote (`intent.md`, `plan.md`, `tasks.md`, `design.md`). "Model ledger row" means an agent
must have run `temper evidence add`. "CLI" means the CLI ran a command or read git or its own state.

Row counts are from a real all-green run of the e2e driver (measured: `gates.json` of that run):
intent 18, plan 26, build 5, review 3, check 6, commit 6. 64 rows in all.

### 2.1 Intent (`gate_intent`, `:2027-2107`): 18 rows, all a lint of `intent.md`

| Row | What proves it | Source |
|---|---|---|
| intent artifact (only when `intent.md` is absent: PASS, "trivial path") | file absent | `:2038-2039` |
| problem stated | awk: a Problem section with a non-placeholder line | `:2044-2059` |
| success criteria | awk: at least one real `- ` criterion | `:2063-2074` |
| status header | grep: `**Status:** draft\|accepted\|completed` | `:2077-2083` |
| task context recorded; criteria ids; criteria priority; criteria validate; criteria why; target users action chain; open questions labeled; no duplicate question; header fields; no scenarios in draft; no soft words (11 rows; all auto-pass once the intent is accepted) | regex over sections of `intent.md` | `intent_draft_rows.py:28-34`, `:52-223` |
| out of scope stated; open questions resolved (the second never fails) | regex | `intent_closure_rows.py:27-51` |
| blocking question open | a `- Blocking:` line under Open Questions of a draft | `gate_rows.py:27-41` |
| rules checklist covered | a `### Rules covered` section with a line for each of Who, When, How much, Exempt, States, Where it shows, Exceptions | `gate_rows.py:46-90` |

Needs: model text only. No ledger row, no command. Side effect: a failed "blocking question open"
sets `intent_asked` in the run state (`:2100`), which later makes a complex plan run Design
(`flow.py:265-266`).

### 2.2 Plan (`gate_plan`, `:3494-3605`): 26 rows in the default run, up to 30

| Row | What proves it | Needs | Source |
|---|---|---|---|
| artifacts exist | `intent.md` and `tasks.md` exist | model text | `:3497-3502` |
| criteria -> scenarios | count of `Scenario:` lines >= count of criteria | model text | `:3507-3514` |
| criteria -> validation | ids, Validate lines and Covers references agree | model text | `:3517-3523`; `acceptance.py:336-394` |
| scenarios in gherkin blocks | every `Scenario:` is inside a gherkin fence | model text | `:3526-3546`, `:2109-2124` |
| cross-repo search recorded | `plan.md` has a Cross-Repo Search section with a `used:` or `not available:` line | model text | `:3549-3559`, `:2126-2151` |
| blast radius documented (medium and complex only) | a Blast Radius heading in `plan.md` | model text | `:3560-3568` |
| tier recorded (when complexity is set) | Complexity lines of `intent.md` and `plan.md` equal the run's tier | model text + CLI state | `:3570-3578`, `:950-977` |
| grouped plan; declared files; exact file paths; task test command; task test cases; group context; context budget; task block budget; dependencies; file ownership; group blast radius; group validate order; shared production files; integration command (14 rows) | the parsed `tasks.md` and the project's file tree | model text | `plan_rows.py:21-195` |
| scenario test commands | every scenario has a `Test:` line whose file a task declares or the project has | model text | `gate_rows.py:105-133` |
| maven group verify; maven filtered verify | regex over the plan's commands and `pom.xml` | model text + project files | `gate_rows.py:136-191` |
| request routes kept | every `METHOD /path` of the request text is in `plan.md` or `tasks.md` | model text + CLI state | `gate_rows.py:263-296` |
| context map reviewed (only with a `plan.md`) | `## Context Map` with entries and a `reviewed: human\|auto` line | model text, or **the person's answer** written by `temper plan review` | `plan_ops.py:81-101` |
| fresh review ran; fresh reader's paraphrase; no open plan blockers (3 rows, only when the fresh review applies: `plan.fresh-review` is `ask` by default, so only after the person asks) | rows the reviewer agent appended after the CLI's launch mark | **model ledger rows** | `fresh_review.py:299-324`, `:117-125` |
| preflight | the CLI runs every distinct Validate, task Test, Integration and scenario Test command once on a detached worktree of HEAD and sorts each into passes, needs new code, environment fault, command fault; only the two faults fail. Stored in `.temper/preflight.json` under a key of HEAD, the commands, the setup block and the time limit | **CLI command runs** | `:3600-3601`; `preflight.py:150-224` |

The preflight row means the first `temper gate plan` of a plan runs the project's whole Integration
suite and every other planned command on the clean base, each up to `plan.preflight-timeout`
(default 300 s, `preflight.py:31`, `:161`). On the toy project that was about 0.4 s (the first
`gate plan` took 1.6 s, later ones 1.17 s); I did not measure it on a real project.

### 2.3 Design (`gate_design`, `:3718-3739`): 2 rows

| Row | What proves it | Needs | Source |
|---|---|---|---|
| design artifact (PASS when `design.md` is absent) or concerns flagged | grep for an "Areas of Concern" heading | model text | `:3727-3734` |
| tasks agree with decisions | no Design answer in `decisions.json` carries the hash `tasks.md` still has | CLI state | `:3735-3736`; `decisions.py:53-69` |

### 2.4 Build (`gate_build`, `:3613-3716`): 5 rows

| Row | What proves it | Needs | Source |
|---|---|---|---|
| built in an earlier run (only for a run that entered at Review or Check; replaces all other rows) | the committed `gate-ledger.json` records Build PASS and no plan file changed since | CLI (git) | `:3618-3632`; `earlier_build.py` |
| RED then GREEN | at least one failing run with phase `red`, then a passing run with phase `green`, both with "test" in the claim, both run by the CLI or confirmed by the person | **CLI command runs** (a claim counts only with `evidence.claimed-runs: count`) | `:3633-3645`; `runs.py:30-45` |
| all tasks complete | every task of `tasks.md` is recorded passed in `groups.json` | CLI state (`task gate` wrote it) | `:3647-3649`; `task_rows.py:23-41` |
| criteria validated | scenario criteria: a CLI-run row with exit 0 per covering scenario. Code criteria: the latest row for the criterion with exit 0 and a command or a matching artifact hash, **claims included**. Manual: CONFIRM, never a fail | CLI runs for scenarios; a model ledger row is enough for a `Validate: code` criterion | `:3651-3652`; `acceptance.py:259-303` (`:267-269`) |
| checkpoint feedback answered | every `feedback #N` row has a `feedback-resolved` row | ledger rows (the CLI writes the resolved row when a reopened task passes, `:3262-3278`) | `:3657-3691` |
| integration (only with a `tasks.md`) | `groups.json` holds `integration.verdict: PASS`, written by `temper integrate` after the merges, the Integration suite and the Interfaces check | CLI command runs | `:3693-3713`; `:3301-3433` |

### 2.5 Review (`gate_review`, `:3812-3860`): 3 rows

| Row | What proves it | Needs | Source |
|---|---|---|---|
| no blocking findings | zero open rows at a severity in `review.block-on` (default `critical,high` since PR #115) | **model ledger rows** (the findings are whatever the Review agent recorded) | `:3814-3837`; `findings.py` |
| review completed | the latest row whose claim matches "review completed" has exit 0 | **model ledger row** | `:3840-3846`, `:3749-3761` |
| no code changed at Review | the tracked files and HEAD equal the snapshot taken when Review started | CLI (git, sha256) | `:3849-3857`, `:3763-3810` |

An empty Review ledger fails (no completion row); one agent-written row passes two of three rows.

### 2.6 Check (`gate_check`, `:3862-3972`): 6 rows in the default run, up to 8

| Row | What proves it | Needs | Source |
|---|---|---|---|
| tests pass | per test command, its latest run passed; CLI or person rows only | CLI command runs | `:3869-3879`; `runs.py:48-56` |
| scenarios traced to tests (when `intent.md` has scenarios) | a row with exit 0 for every scenario name. **No `executed_by` filter**: a claim counts | `check run` writes them itself (`check_run.py:717-722`); a model ledger row also passes | `:3880-3903`, `:1966-1978` |
| coverage >= threshold | the last row with a `value` whose claim matches "coverage" is >= `check.coverage-threshold` (80). No `executed_by` filter | `check run` writes it (`check_run.py:704-713`); a model ledger row also passes | `:3904-3914`, `:1902-1914` |
| mutation score >= threshold (only when measured) | the `mutation score` row's value >= `check.mutation-threshold` (70) | CLI command runs (up to 40 mutants, 300 s budget, `check_run.py:41-42`) | `:3918-3931` |
| acceptance tests written before Build (only with a row) | the locked acceptance tests' run has exit 0 | CLI command run | `:3933-3945` |
| regression proof (fix runs only) | the fix's tests fail on the code before the fix | CLI command run | `:3947-3957` |
| acceptance evidence (with an `intent.md`) | each scenario and each non-scenario criterion has a latest row with exit 0 and a command or a matching artifact hash. No `executed_by` filter | a model ledger row passes for `code`, `manual` and `metric` criteria | `:3958-3969`; `acceptance.py:396-410`, `:183-193` |

### 2.7 Commit (`gate_commit`, `:4033-4227`): 6 rows in the default run

Three early exits, each a single PASS row: every staged file is under `.temper/specs/`
(`:4042-4053`); no active run (`:4059-4064`); a build checkpoint commit while the run is at Build
with a green last test row (`:4066-4110`).

| Row | What proves it | Needs | Source |
|---|---|---|---|
| `<stage> gate`, one per stage owed: plan, build, review, check; intent when `intent.md` exists; design when `design.md` exists (fix runs: build, review, check) | `gates.json` says PASS, or a skip of the person covers the verdict | CLI state | `:4116-4144`, `:3981-4001` |
| blast radius (with a `tasks.md`) | every file changed since `base_sha` is declared in `tasks.md`, is a test file, is under the spec folder or `.temper/`, or was allowed in a `drift ...` ledger row | CLI (git) + plan text | `:4149-4190` |
| blast radius count and park-on-touch paths (only for a run that ran unattended) | file count <= `autonomy.max-blast-radius`; no undeclared changed file matches `autonomy.park-on-touch` | CLI (git) + config | `:4191-4224` |

The native pre-commit hook runs this gate on every commit (`--from-hook`, `:4266-4274`). Measured:
about 185 ms per commit with no active run, about 860 ms with one.

### 2.8 Pipeline (`gate_rows.py:203-235`)

pipeline result; jobs passed; fix paths. All from `pipeline-context.json`, which the Pipeline agent
writes: model text.

### 2.9 What the table adds up to

- Intent and Plan are format checks of agent-written Markdown: 43 of the 64 rows of a default run
  (all 18 Intent rows and 25 of the 26 Plan rows). They catch a malformed artifact, not a wrong
  one. The only Plan row that touches reality is the preflight.
- A gate FAIL on a format row costs a whole agent pass to mend (Plan on Opus is about 200 s per the
  benchmark), so each format row is also a possible loop.
- The rows that prove the code works are few and all CLI-run: RED then GREEN, integration, the
  scenario runs, tests pass, coverage, mutation, acceptance tests. Those could be computed with no
  Intent or Plan artifact at all.
- Review is the one stage whose verdict rests on agent-written ledger rows.

---

## 3. Runtime overhead

### 3.1 Method

A scratch clone at `pr115`; the repo's own e2e driver (`bun scripts/e2e/run.ts`, the real CLI with
scripted agents and a scripted person) with a two-line timing patch in my clone's
`scripts/e2e/world.ts`; snapshots of the toy project stopped at each stage's question; each call
timed 5 to 20 times on a fresh copy; processes counted with `strace -f` (successful `execve` by
program, and forks).

Baselines on this machine (median): `bash -c true` 2 ms; `python3 -I -c pass` 13 ms; `python3 -c
"import flow"` 49 ms; `git rev-parse HEAD` 2 ms; `scripts/temper --help` 18 to 31 ms (bash reading
the 260 KB script, no Python).

### 3.2 One call (measured)

| Call | Median ms | Forks | Programs started | python3 | git |
|---|---|---|---|---|---|
| `config get <key>` | 29 to 34 | | | 1 | 0 |
| `state get next_stage` | 69 | 12 | 7 | 2 | 0 |
| `evidence list --stage S` | 45 | 10 | 4 | 1 | 0 |
| `report` | 115 | 12 | 7 | 4 | 0 |
| **`next --json`** | **152 to 189** | 34 to 44 | 29 to 39 | 2 | 21 to 31 |
| **`go`** (stops at a question, runs no call) | **302 to 325** | 56 to 62 | 45 to 51 | 5 | 30 to 36 |
| `go` at Commit (runs `gate commit`, then stops) | 368, first run up to 1,458 | 246 | 196 | 40 | 97 |
| `usage add ...` | 176 | 32 | 26 | 4 | 9 |
| `evidence add ...` | 192 | 34 | 26 | 4 | 9 |
| `state set complexity simple` | 266 | 46 | 38 | 6 | 9 |
| `intent accept` | 177 | 26 | 20 | 4 | 9 |
| `state init <slug>` | 194 | 32 | 24 | 4 | 9 |
| `state advance intent_complete plan` | 345 | 47 | 37 | 7 | 9 |
| `state advance plan_complete build` | 659 | 82 | 64 | 16 | 12 |
| `state advance check_complete commit` | 409 | 69 | 55 | 10 | 14 |
| `gate intent` | 637 | 75 | 64 | 17 | 9 |
| **`gate plan`** (preflight already stored) | **1,169** | 122 | 90 | 45 | 13 |
| `gate build` | 668 | 80 | 61 | 23 | 11 |
| `gate review` | 543 | 73 | 54 | 19 | 15 |
| `gate check` | 757 | 92 | 62 | 29 | 11 |
| `gate commit` | 940 | 129 | 96 | 33 | 21 |
| `gate commit --from-hook`, no active run | 184 | 33 | 22 | 5 | 2 |
| `panel plan` | 189 | 27 | 21 | 4 | 11 |
| `risk` | 304 | 54 | 43 | 8 | 11 |
| `model --all` | 271 | 60 | 26 | 13 | 0 |
| `schedule` | 184 | 28 | 14 | 8 | 0 |
| `state archive` | 388 | 70 | 42 | 12 | 14 |
| the view writer alone (`cli_ctx.py view`) | 74 to 98 | 9 to 14 | 10 to 15 | 1 | 9 to 14 |

Where the time goes: process starts. One Python start that reads one JSON field or builds one row
costs 19 to 20 ms (measured). `gate plan` starts 45 of them. The same six plan rows computed inside
one Python process, imports included, took 17 to 23 ms (measured).

Fixed floor of any call that changes state: about 20 to 30 ms to read the bash script, about 20 ms for
the symlink check's Python, about 85 ms for the view. About 135 ms before the command does anything.

Output sizes at the Plan question (measured): `next --json` 5,852 bytes, `go` 3,147 bytes,
`view.json` 10,303 bytes.

### 3.3 A whole run (measured on the toy project; all gates green, no loop)

| Run of the e2e driver | CLI calls | CLI wall time | `next --json` calls |
|---|---|---|---|
| full run, 2 groups, 2 tasks, simple tier, "plain" loop over `next` | 84 | 31.3 s | 24 |
| same, carried by the mod's run driver ("driver" mode) | 97 top-level (15 `go`, 32 `next`), more inside `go` | 40.1 s | 32 |
| three groups, 3 tasks | 97 | 35.8 s | 26 |
| with Design | 94 | 33.4 s | 26 |
| with the fresh review | 110 | 37.7 s | 28 |
| `pyjokes-full` scenario (includes failures and step backs) | 185 | 62.3 s | 46 |

For the 84-call run, `strace` counted 4,600 forks and 3,509 programs started: `git` 1,521, `python3`
737, `grep` 274, `bash` 193, `date` 175, `rm` 117, `mv` 106, `mkdir` 88. Of the 737 Python starts,
448 were inline `python3 -I -c` snippets and 132 only read `spec_path` from `build-state.json`.

Per unit, from the same trace: one task costs 8 CLI calls and about 4.4 s (`task start` 0.8 to 0.9 s,
`task show` 0.3 s, two `task test` 0.65 s each, `task gate` 1.1 to 1.2 s, `usage add` 0.2 s,
`task gate --if-running` 0.35 s, `panel task` 0.2 s). One group costs 3 calls and about 1.4 s. The
rest is about 20 s.

The scripted person was asked **7 questions** in that all-green run, every one of them after a check
had already passed: Intent, Plan, Group G1, Group G2, Build, Review, Check (measured by printing each
question of the run).

### 3.4 Does the CLI's overhead matter?

- **Wall time: a little.** About 30 to 40 s of a 600 to 870 s feature run is 4 to 6 percent
  (inferred: my toy-project total against the benchmark's run time; the benchmark's task count is not
  the toy's). A single-process CLI could bring that to roughly 5 to 8 s (inferred from the in-process
  timings above). It will not close the gap to vanilla Claude Code (90 s) by itself.
- **Tool calls and turns: more.** Every CLI call an agent or the session makes is a tool call that
  re-reads its context. The loop page already batches (`commands/temper.md:66-79`, `temper go`). The
  Build task agent still makes 4 to 5 CLI calls per task by itself (`show`, `test` red, `test`
  green, `gate`, and `start` for each further task of a chain; `scripts/e2e/scenarios.ts:46-68`
  plays the brief this way).
- **Questions: most.** Seven confirmations of a passed check per small run come from one line of
  `flow.py`: whenever a stage has a verdict and the run is not armed, `core_next` asks
  (`flow.py:2473-2475`). `advance_ok` itself needs only PASS or a skip, not an answer
  (`flow.py:2510-2535`).
- **The project's own commands: unmeasured here, and probably the largest CLI-side cost on a real
  project.** See 3.5.

### 3.5 How often the CLI runs the project's commands (verified in code, not timed on a real project)

In an all-green run, in order:

1. Plan gate preflight: every distinct Validate, task Test, Integration and scenario Test command,
   once, on HEAD (`preflight.py:44-61`, `:189-210`). Stored; not rerun while HEAD and the commands
   are unchanged.
2. Build, per task: the task's Test twice, red and green, never cached (`task_ops.py:433-435`).
3. Build, per group gate: the group's Validate, reused when the same command already passed on the
   same clean tree (`task_ops.py:464`, `run_env.py:149-180`); then each scenario test the group
   owes, never cached (`scripts/temper:2505`; `scenario_ops.py:124-130`).
4. `integrate`: the Integration suite (reused on the same tree, `task_ops.py:488`), then every
   scenario Test, never cached (`scripts/temper:3421-3423`; `scenario_ops.py:133-150`).
5. Check: the whole suite with coverage, never cached (`check_run.py:691-693`); every scenario Test
   again (`check_run.py:717-722`); the locked acceptance tests; mutation testing, up to 40 mutants,
   each a test run, within a 300 s budget (`check_run.py:41-42`, `:358-400`).
   `check ahead` starts this in the background during Review and `check run` adopts it when the tree
   is unchanged (`scripts/temper:4948-4956`), so Check itself is not doubled.

So once the code exists, a scenario's test runs three times (group gate, integrate, Check) and the
full suite at least twice (integrate, Check), under different command strings, which the pass cache
cannot merge because its key holds the command text (`run_env.py:133-141`). `run_env.py:121-122`
says a measured run "ran the same 11,600 tests about eight times" (doc-claim).

---

## 4. Complexity hot spots

### 4.1 Where the 5,121 lines of `scripts/temper` are

| Lines | Area | Size |
|---|---|---|
| 1-270 | boot, path rules, refusals | 270 |
| 271-516 | JSON helpers and the lock (the lock alone: 315-454, 140 lines) | 246 |
| 518-677 | config, model resolution, init | 160 |
| 679-1507 | state: init, set, advance, loop, redo, archive, clear | 829 |
| 1509-1809 | evidence | 301 |
| 1830-2151 | gate helpers, evidence queries, `gate_intent` | 322 |
| **2153-3486** | **grouped Build: parser calls, schedule, group start/gate/reopen, task start/test/gate, integrate** | **1,334** |
| 3488-3972 | `gate_plan`, `gate_build`, `gate_design`, `gate_review`, `gate_check` | 485 |
| 3974-4336 | commit gate and `cmd_gate` | 363 |
| 4338-4819 | status, override, intent, park, plan, adhoc, risk, next, view, report, usage | 482 |
| 4821-4926 | metrics and bands | 106 |
| 4928-5121 | check, acceptance, main, help text | 194 |

Largest functions (verified by an outline of the file): `_task_gate_body` 210 lines (`:3082`),
`_group_reopen_body` 200 (`:2602`), `gate_commit` 196 (`:4033`), `main` 140 (`:4981`),
`cmd_integrate` 136 (`:3301`), `cmd_group_start` 130 (`:2310`), `cmd_state_set` 123 (`:827`),
`cmd_gate` 115 (`:4229`), `gate_plan` 113 (`:3494`), `gate_check` 112 (`:3862`),
`cmd_state_advance` 110 (`:1112`), `gate_build` 105 (`:3613`). In `flow.py`: `Builder.ask` 306 lines
(`flow.py:574`), `build_work` 137 (`:1635`), `core_next` 128 (`:2360`).

Grouped Build is the largest single subsystem: 1,334 lines here plus `task_ops.py` 775,
`tasks_md.py` 249, `scenario_ops.py` 175, `maven_loop.py` 125, `task_cover.py` 104, `group_fix.py`
101, `group_report.py` 93, `task_blocked.py` 69. About 3,000 lines for worktrees per group and per
task, attempts, parks, reopens and foreign commits.

### 4.2 The same rule written twice (verified)

| Rule | In bash | In Python |
|---|---|---|
| Which model a stage runs on | `scripts/temper:543-624` | `cli_ctx.py:27-79` ("the same as the CLI's `_resolve_task_model`", `cli_ctx.py:24`) |
| The setup a project lacks | `_setup_calls`, `:4545-4558`, **never called** | `cli_ctx.py:90-130`, which also checks one more string (`:127`) |
| The digest of the approved plan | `_plan_digest`, `:2163-2174` | `flow.py:131-144` |
| The stage sequences | `:152-153`, `:979-983`, hard-coded again at `:1050`, `:1889`, `:4119-4121`, `:4407` | `flow.py:47-55`; `output_ops.py:17`; `acceptance.py:41` (this list lacks `pipeline`) |
| Whether a skip covers a verdict | `_override_covers`, `:3981-4001` | `flow.py:286-294` |
| Counting scenarios and criteria in `intent.md` | awk and grep at `:2063-2068`, `:3507-3508`, `:3527`, `:3882`; regex at `:1990`, `:2120` | `acceptance.py:77-173` |
| The Complexity line | `:771` and `:954` | |
| What a test file is | `:4174` | `plan_rows.py:179-183`; `check_run.py:206`; `task_ops.py` `TEST_FILE` |
| Files changed since the base | `_changed_since_base`, `:4150-4155` | `flow.py:2892-2943` |
| Snapshot of dirty files by hash | `_review_code`, `:3763-3810` | `adhoc_ops.py` `dirty()` |
| Load JSON, write to a temp file, `os.replace` | 17 `os.replace` blocks inside `scripts/temper` | 18 more across the `.py` files; 9 separate `def git`, 8 `def load` |

### 4.3 Code a default run never needs

| What | Where | Lines | Status |
|---|---|---|---|
| `metrics append` and `bands` | `scripts/temper:4821-4926`; `scripts/bands.py` | 106 + 102 | Called only by `/temper:status` and docs (`commands/status.md:26`); `flow.py`, `go.py`, `check_run.py` never call them (verified by grep). Nothing in the default flow appends a metric, so the bands have no data unless a person feeds them (inferred) |
| `_setup_calls` and `_excludes_current` | `:4540-4558`, `:636-643` | about 27 | Dead: defined, never called (verified: one occurrence of `_setup_calls`) |
| `_state_migrate_legacy` | `:781-815` plus 12 call sites | 35 | Heals a v7.0.x state file (`eval` stage, missing `run_id`) |
| Old flags `--agent`, `--tokens`, `--token-count` | `:3091-3092`, `:4801-4802` | 4 | "Nothing reads it" (`:3091`) |
| The build checkpoint carve-out in the commit gate | `:4066-4110` | 45 | For per-task commits in the main tree while at Build (ADR 0009). Grouped Build commits in task worktrees through the CLI (`:3196-3211`), where the hook "fails open" (`:2904-2906`). Probably unreachable in a default run (inferred; not proven) |
| `status.json` and its writer | `:4338-4350`, `acceptance.py:206-256` | about 65 | Rewritten after every gate; `view.json` already carries the same criteria (`flow.py:2834`). Only `/temper:status` reads it (inferred from grep) |
| Seven dead names in `_RUN_FILES` | `:632-634` | | Nothing writes them |
| The old RCA panel format | `panel.py:212-214` | 3 | For files of 9.8.0's first release |
| OCR | no code in the CLI | 0 | Only prose in `reference/review.md:44-46` and `reference/status.md:37-40`, read through `config get tools.ocr.mode` |

`panel.py` (300 lines) is not retired: the Plan, Design, RCA and task panels are drawn by it
(`scripts/temper:5045-5050`), and its header says it replaced boxes each agent drew at 2,000 to 3,000
output tokens (`panel.py:8-11`, doc-claim).

### 4.4 What a user has to learn

32 top-level subcommands (`:5005-5050`); at least 36 distinct config keys read by the code, not
counting `models.<stage>` (9 stages) and the four keys of the `setup:` block (measured by grep);
the default config file is 171 lines (`templates/temper.config.default`); 7 `TEMPER_*` environment
variables that change timeouts or the lock (`TEMPER_LOCK_WAIT_S`, `TEMPER_LOCK_MAX_S`,
`TEMPER_TASK_TEST_TIMEOUT_S`, `TEMPER_INTEGRATION_TIMEOUT_S`, `TEMPER_CHECK_TIMEOUT_S`,
`TEMPER_MUTATION_BUDGET_S`, `TEMPER_CONFIG`). The `--help` text omits `evidence void`, `task confirm`,
`task accept`, `task retry`, `gate pipeline` and `acceptance triage` (`:5052-5103` against `:1803`,
`:3480-3481`, `:4238`, `:4976`).

---

## 5. What a second, lighter route through the CLI would have to touch

### 5.1 What exists today

- One full sequence for `/temper`: intent, plan, design (conditional), build, review, check, commit,
  pipeline (conditional) (`scripts/temper:152`, `flow.py:47`, `:228-236`).
- One second route already: `/temper:fix`, with `command: fix` in the run state and the sequence
  rca, fix, review, check, commit (`scripts/temper:153`; `flow.py:48`). Its Fix stage is judged by
  the build gate (`flow.py:52`), and with no `tasks.md` the build gate is only RED then GREEN and
  the feedback row (`:3635-3653`, `:3693`). **This is the precedent for a light route**: a run with
  no plan artifacts, one agent, and the CLI-run proof rows.
- The tier (trivial, simple, medium, complex) changes very little: whether Design runs
  (`flow.py:251-266`), the blast radius row (`:3560-3568`), the fresh review in `auto` mode
  (`fresh_review.py:123-124`), and the task model (`:577`). A simple run still walks every stage.
- "Trivial" is an exit, not a route: the Intent agent says TRIVIAL, the session runs `state clear`
  and works with no pipeline at all (`commands/temper.md:176-179`; `flow.py:2826-2827`).
- Doors (`state init --enter <stage>`, `:703-707`, `:762-774`) start a run at a later stage; the
  stages before are walked and checked, not skipped (`flow.py:2431-2433`).
- The small-change window (`adhoc_ops.py`) is a change inside a run at Build or later.

### 5.2 The list of places (verified)

For a route such as "light: build with one agent, check, commit" as a new `command` value:

| Place | Why |
|---|---|
| `scripts/temper:152-153`, `_run_seq` `:979-983` | the sequence |
| `cmd_state_init` `:683-779` (`--command temper\|fix`, first `next_stage`, artifacts, branch name `:742-753`) | start the run |
| `cmd_state_advance` `:1121-1132` | which `<stage>_complete` names are valid |
| `_redo_from` `:1049-1052`, `_clear_evidence_downstream` `:1886-1891` | the fix sequence is hard-coded as a second case; a third route is a third case or one table |
| `cmd_override` `:4406-4410` | which gates may be skipped |
| `gate_commit` `:4116-4131` | which stage verdicts a commit owes |
| `gate_plan` `:3497-3502`, `gate_build` `:3635-3653`, `:3693-3713` | Plan demands `intent.md` and `tasks.md`; Build demands grouped tasks and `integrate` whenever `tasks.md` exists |
| `_adr0009_upstream_check` `:2907-2915` | CLI commits demand a plan verdict |
| `flow.py:47-55` (`SEQ`, `GATE_OF`, `BACK_TO`), `Run.seq` `:228-236`, `advance_ok` `:2510-2535` | the flow's copy of the sequence and the step backs |
| `flow.py` `core_next` `:2360-2482`, `stage_work` `:1316`, `ask` `:574` | which agent runs and which question is asked; 26 `command == "fix"` or `"temper"` branches already (measured by grep) |
| `flow.py` `view()` `:2783-2840` and `VERSION` `:37` | the mod reads `guard.fix_run` and the stage list; a schema change is a version change (`flow.py:11-12`) |
| `scripts/selftest/view-fixtures.ts`, `temper-cases-8.sh` | the repository's rule for any flow change (`.claude/CLAUDE.md`, "Known mistakes") |
| outside my files: `hooks/temper-mod/core/stages.ts`, `rules.ts`, the guard scripts that read `build-state.json`, `commands/`, `agents/` | named for completeness; other readers cover them |

Cost of the precedent: the fix route is 8 branches in `scripts/temper` (`:742`, `:982`, `:1049`,
`:1123`, `:1888`, `:3947`, `:4118`, `:4407`) and 26 lines in `flow.py` that test the command or
`fix_run` (measured by grep). A third route written the same way roughly doubles that. Written as data (one
table: sequence, the gate each stage is judged by, the artifacts and rows each gate owes, the step
backs), it replaces the special cases instead.

The smallest light route that reuses what exists (inferred): a `command` whose Build is judged like
Fix's (CLI-run RED then GREEN, no `tasks.md`, no worktrees, no `integrate`), then the CLI-run Check,
then Commit. It needs no Intent or Plan gate rows, and its proof rows are all computed without a
model (section 2.9).

---

## 6. Defects and disagreements found on the way

| # | Finding | Evidence | Confidence |
|---|---|---|---|
| D1 | **The e2e `fix` scenario fails on the PR**, at the local head and at GitHub's head. The scenario's Fix agent records RED and GREEN with `evidence add --exit` (`scripts/e2e/scenarios.ts:611-614`); since 9.8.5 a claim does not count (`runs.py:30-33`), so the build gate fails, Fix runs again on already fixed code, and the scenario's own expectation fails. CI runs this suite (`.github/workflows/quality.yml:96`). | `bun scripts/e2e/run.ts plain fix` in a clean checkout of `9a01eff` and of `c417166`: `FAIL fix [plain]: expectation failed: the regression test fails first`. GitHub's "End to end" check for `c417166` was still in progress each of the three times I looked | measured locally; CI result unknown |
| D2 | **With the default config, every plan asks the person the Context check.** The Plan brief tells Plan to write `- reviewed: pending` (`agents/plan.md:91-93`). The row fails on `pending` unless the mode is `off` (`plan_ops.py:92-94`), and `next` then asks "Is this the right context for the plan?" (`flow.py:2338-2344`). Nothing in the CLI ever writes `reviewed: auto`; only test fixtures contain it. The config comment says `auto` asks "when the Context Map has an ignore or a gap" (`templates/temper.config.default:104`), and `reference/plan.md:70-71` says the same | In a copy of the Plan snapshot I changed `reviewed: auto` to `reviewed: pending`: `temper gate plan` gave FAIL on "context map reviewed" and `temper next` asked the Context question, with no ignore or gap entry in the map | measured |
| D3 | Two run-state files added by PR #115 are missing from the run-file list: `.temper/preflight.json` and `.temper/decisions.json`. They are not in `_RUN_FILES` (`scripts/temper:632-634`), so `init` does not exclude them from git, `state init` and `state clear` do not remove them (`:733-734`, `:1448-1449`), and the symlink check does not cover them (`:237-240`) | `git status --porcelain` in the Plan snapshot shows `?? .temper/preflight.json` | measured for preflight.json; verified in code for decisions.json |
| D4 | Lock comment out of date after PR #115 (`:326-328` against `:432-440`) | read | verified |
| D5 | "Every JSON write ... os.replace" is not true for seven writers, and they hold no lock (list in 1.5) | read | verified |
| D6 | `plan_ops.py:17` says "The CLI writes the `reviewed:` line, never Plan"; `agents/plan.md:91` tells Plan to write it | read | verified |
| D7 | `acceptance.py:41` lists the evidence stages without `pipeline`; `scripts/temper:121` has it | read | verified |
| D8 | `cmd_state_set`'s comment says leaving Intent and Plan "needs the person's answer" (`:927-929`); `advance_ok` checks only PASS or a skip (`flow.py:2529`) | read | verified |

---

## 7. Sources of avoidable cost, in the owner's units

| # | What | Where | Kind | Size and basis |
|---|---|---|---|---|
| W1 | A question after every passed check | `flow.py:2473-2475` | questions | 7 per all-green 2-group run (measured); 5 + one per group |
| W2 | The Context check asked on every plan | D2 | questions | 1 more question and 1 more `gate plan` per run (measured) |
| W3 | The project's tests run again at each stage; the pass cache covers only the group Validate and the Integration suite | 3.5 | time | A scenario test runs 3 times, the suite at least twice after the code exists (verified in code); "about eight times" on the Java run (doc-claim, `run_env.py:121-122`) |
| W4 | 43 of 64 gate rows are format checks of agent-written Markdown, each one a possible FAIL that sends Plan (about 200 s on Opus) or Intent back | 2.1, 2.2 | loops, tokens | Count measured; how often a format row fails in real runs I could not determine |
| W5 | One process per JSON field and per row | `scripts/temper` throughout | time | 737 Python starts and 1,521 git starts for 84 calls; 31 s of CLI time per small run, 5 to 8 s achievable (measured, then inferred) |
| W6 | `temper next` computes the action and the git facts twice | `cli_ctx.py:161-163`; `flow.py:3088-3108` | time | about 50 ms of each 170 ms call; 24 to 46 calls a run (measured) |
| W7 | The view rewritten after calls that change nothing the view shows (`usage add`, `panel`, `brief`, `evidence add` of a note), and `status.json` after every gate | `:5108-5117`, `:4304` | time | 59 extra processes, about 5 s per small run (measured) |
| W8 | The same rule in bash and in Python | 4.2 | complexity, reliability | 11 pairs listed; one pair has already drifted (`cli_ctx.py:127`) |
| W9 | The 256 KiB ceiling at 99.4 percent | `quality-check.sh:21-27` | complexity | 1,640 bytes of headroom (measured); every addition forces another subprocess helper |
| W10 | Dead and legacy code | 4.3 | complexity | about 390 lines in `scripts/temper` and `bands.py` together |
| W11 | Every commit in a project with the hook pays the commit gate | `:4266-4274` | time | 185 ms with no run, 860 ms with one (measured) |
| W12 | Loop budget per run is generous and "run again" has none | `loop_step.py:20-32`; `flow.py:54-55`; `state redo` `:1455-1492` has no count | loops | The five step backs the flow offers have budgets 2, 2, 1, 2, 2: up to 9 per run by default, and unlimited redos (verified in code) |
| W13 | A step back to Intent, Plan or Design throws Build away: `groups.json` is archived and worktrees removed | `_go_back` `:1269-1295`, `_groups_reset` `:1297-1329` | time, tokens | Every passed task is rebuilt; `plan patch` (PR #115) avoids this for one command line only (`:4565-4567`) |

---

## 8. What I would change here, most valuable first

1. **Stop asking after a passed check.** Make "go on when the check passed" the default from Build to
   Check, including the group Continue. The machinery exists: the armed path advances on PASS
   (`flow.py:2441-2467`), group Continue is automatic when armed (`flow.py:1760`), and PR #115's
   `autonomy.policy: decide` handles Review and Check (`flow.py:2468-2472`). Keep three decisions:
   accept the intent, approve the plan, commit. Effect: 7 questions to 3 in the measured run. Risk:
   a failed check must still stop for the person; the mod's answer matching must accept an advance
   with no answer. Effort: S to M (a default and its fixtures).
2. **Run each project command once per tree.** Key the pass cache by tree and by what the command
   covers, and use it in the scenario runs (`scenario_ops.py:127`, `:145`), in Check's suite and
   scenario runs (`check_run.py:693`, `:720`), and let Check adopt `integrate`'s suite run when the
   tree is the same. Effect: removes whole suite runs; on a slow suite this is minutes. Risk: a
   coverage run and a plain run are different commands; a reused pass must be shown as reused (it
   already is, `run_env.py:165`). Effort: M.
3. **A light route as data, not as a third set of special cases.** Replace the sequence copies and
   the `command == "fix"` branches with one route table read by both `scripts/temper` and `flow.py`,
   then add a route with no Intent or Plan artifacts whose Build is judged like Fix's. Effect: a
   clear, small request skips Plan on Opus (45 to 83 percent of a run's cost per the benchmark) and
   grouped Build. Risk: choosing the route wrongly; the mod and guards read the stage names. Effort: L.
4. **Fix the Context check default** (D2): the CLI writes `reviewed: auto` when the map has no
   `ignore` and no `gap`. Effect: one question and one gate pass fewer per run. Effort: S.
5. **One process per call.** Keep `scripts/temper` as a thin bash shim with the same path, output
   text and exit codes; move state reads, gate rows, the verdict write and the view into one Python
   entry. Effect: about 31 s to about 5 to 8 s of CLI time per small run; one language; the 256 KiB
   ceiling stops shaping the design; the duplicated rules of 4.2 collapse. Risk: 14,510 lines of
   selftest assert exact output; the installed pre-commit hook and the mod's reviewed call list name
   the CLI path and some of its strings (`cli_ctx.py:115-129`; `scripts/check-mod-calls.sh`).
   Effort: L. Do it gate by gate, since most row logic is already Python.
6. **Cheap wins first, in the current shape**: compute `next` once and reuse it for the view (W6);
   skip the view rewrite for calls on a no-change list and drop `status.json` (W7); read the state
   file once per call instead of once per field. Effect: roughly a third of the CLI time (inferred
   from the counts). Effort: S.
7. **Housekeeping**: add the two files to `_RUN_FILES` (D3); fix the e2e `fix` scenario (D1); delete
   the dead and legacy code of 4.3 after confirming the checkpoint carve-out; correct the comments
   (D4 to D8). Effort: S.

---

## 9. Invariants a redesign must keep

1. A gate verdict is computed by the CLI from files, the ledger and command runs, never asserted by
   a model; `git commit` is blocked while a gate is FAIL and not skipped (`.claude/CLAUDE.md`;
   `scripts/temper:1-8`, `:4132-4144`).
2. The person decides only in a question dialog; a skip is the person's and is recorded with a reason
   (`.claude/CLAUDE.md`; `:4399-4424`). The CLI keeps its own state keys (`:836-876`).
3. Python standard library only, no network (`scripts/temper:8`; each helper's header).
4. No tracked file over 256 KiB (`scripts/quality-check.sh:21-27`).
5. Run state lives only in the project's `.temper`; no write follows a symlink; the home folder and
   the plugin folder are refused (`:34-44`, `:191-261`).
6. Hooks fail open except on a detected violation; the commit gate passes with no active run
   (`.claude/CLAUDE.md`; `:4055-4064`).
7. `.temper/view.json` is the one CLI file the mod reads and is current after every change; its
   schema has a version (`flow.py:11-12`, `:37`; `scripts/temper:5108-5117`).
8. A gate change is a `scripts/temper` edit plus a `test-temper.sh` case; a flow change is `flow.py`
   plus a case in `temper-cases-8.sh` and regenerated view fixtures (`.claude/CLAUDE.md`).
9. Evidence is kept: a finding or a run is marked resolved, accepted or void, never deleted to pass
   (`:1617-1620`; `runs.py:12`).
10. A test run counts only when the CLI ran it or the person confirmed it (`runs.py:7-10`).
11. A new run inherits no verdict and no skip (`:708-734`); Build is held to the plan the person
    approved, by digest (`:1136-1164`, `:2179-2196`).
12. The CLI path `scripts/temper` is written into the installed pre-commit hook and checked by the
    setup test (`cli_ctx.py:115-129`).

---

## 10. What I could not determine

1. Whether GitHub's e2e check passes for the PR head (D1): in progress both times I looked.
2. How long the plan gate's preflight takes on a real project. It runs the full Integration suite.
3. How many CLI calls the model's own session makes in a real run (as opposed to calls inside
   `temper go` and inside agents). That needs a transcript.
4. Whether the build checkpoint carve-out (`:4066-4110`) is still reachable with grouped Build.
5. Whether anything outside `/temper:status` reads `status.json`.
6. How often each format row of Intent and Plan fails in real runs, which is what W4 costs.
7. Whether `reviewed: auto` was meant to be written by the CLI (D2); the code has no writer.
8. The task count of the benchmark's feature run, so my 4 to 6 percent share is an estimate.

## Scratch material

Everything is under
`/tmp/claude-0/-home-user-temper/1ba4743b-465f-5ae6-8b88-a04ebb2fe840/scratchpad/work-cli-core`:
`timing-plain.jsonl`, `timing-driver.jsonl`, `timing-more.jsonl` (per-call times), `full-plain.strace`
(the process trace of one full run), `bench.py` and `m.sh` (the timers), `repo/` (the clone, with my
timing patch in `scripts/e2e/world.ts` and two scratch scripts `snap.ts` and `asks.ts`), `tmp/` (the
stage snapshots).
