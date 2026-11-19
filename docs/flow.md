# The flow: `temper next` and `view.json`

Two outputs of the `temper` CLI carry the whole flow of a run ([ADR 0013](decisions/0013-the-cli-says-what-next-the-mod-only-draws.md)).

With the mod off, every phase works the same; the mod adds the band, the pane and its write guards. Nothing falls back silently.
Both are computed by `scripts/flow.py` and its `flow_*.py` modules from the run's own files; nothing else decides what
comes next. `flow.py` is the facade: `Builder`, `core_next` and the words the CLI starts it with. `flow_base.py` holds
the tables (`SEQ`, `MOVES`) and the readers, `flow_run.py` the class `Run`, `flow_ask.py`, `flow_work.py`,
`flow_build.py` and `flow_commit.py` the four parts of `Builder`, and `flow_view.py` the view.

- `temper next --json` prints the next action, with the full view. The orchestrator runs
  `temper go` instead (9.8.0, `scripts/go.py`): it runs the CLI's own steps itself (an `auto` action's
  calls, a `work` action's calls) and prints one compact object at the first agent launch, question,
  steps, wait or end: `{action, stage, say, ran, agents | ask, blocking, gate | steps | tasks}`. It
  never runs an option's calls (the person's answer); a failed call stops it with `action: error`.
  9.8.5, the verdict marker: `temper gate <stage>`, `temper task gate <N>`, `temper group gate <G>` and
  `temper integrate` print one line on stdout once they recorded a verdict, `VERDICT: <scope> <verdict>`, with the
  scope `gate:<stage>`, `task:<N>`, `group:<G>` or `integrate` and the verdict `PASS` or `FAIL` (`PARKED` only for
  `group:<G>`, from a task gate a parked group refuses). Exit codes do not change. A gate the commit hook runs, a
  gate of another spec folder and a call that recorded nothing print none. `temper go` reads the last marker line of
  a call's stdout (`recorded()` of `scripts/go.py`): a call that exits non zero is an error only when no marker of
  its own scope is there (a task gate's own task, or any group), and the marker is read only from a call `temper go`
  ran itself, never from text. Its object gains `verdicts`, the list of `{scope, verdict}` it read, in order (`[]`
  when none). The mod's run driver (`recordedVerdict`) and the scripted loop read the marker by the same rule. The
  marker decides only that a carrier goes on: what comes next is always `temper next`, which reads the record.
  9.8.0, to shrink what every later turn reads again: an agent's gate call is `temper gate <stage> --brief`
  (its failed rows only; the question after it names them); `ask` keeps `question` as it is and, per option,
  only what the answer runs (`label`, `calls`, `steps`, `do`, `needs`, `stop`, `reason`, `reason_question`,
  `answer_question`), and the question's `typed` (WP16); `blocking` is the list of `{question, answer, carry}` below.
- `.temper/view.json` is written by the CLI after every command that may change the run, and by
  `temper next`. The mod reads this file and nothing else of the CLI's, to draw the run and to check
  the person's answers.

Both carry a version: `v` in `next`, `version` in the view. This page describes version 1. A field may
be added within a version; a field is never renamed or removed without a new version, and a reader
that meets a version it does not know draws nothing and refuses nothing.

## `temper next --json`

```json
{"v": 1, "action": "...", "run": {...}, "restart": {...}, "stage": "...", "say": "..."}
```

| Field | Meaning |
|---|---|
| `v` | 1 |
| `run` | `{id, step, slug, stage, command, mode}`, or `null` when no run is active |
| `action` | what to do: `none`, `work`, `ask`, `wait`, `auto`, `broken` (below) |
| `stage` | the stage the action belongs to |
| `say` | one sentence for the person |
| `restart` | the `Temper resume` question (Start over or Cancel) for this run and step; 9.8.5: id `run.restart`, kind `resume`, options `start-over` and `cancel` (kind `cancel`) |
| `blocking` | with `ask`: the Blocking open questions of `intent.md`, asked before the gate question |
| `blocking_asks` | 9.8.0, with `blocking`: each as the session asks it, `{question, answer, carry}`: `question` is the AskUserQuestion entry (header `Question N`, the text before `choices:`, the choices as options, the first marked `Recommended`, then `Carry forward`); 9.8.5: `question` goes to the dialog as it is, so its ids sit beside it in `question_ids`: `{id, kind, options}`, with id `intent.blocking`, kind `blocking`, and each option's `id` in the same order (`choice-1` to `choice-3`, `type`, `carry`), Carry forward with the kind `carry`; `answer` is `temper intent answer '<question>' '{answer}'`, which writes the answer into Decisions (and a `Design:` question's concern in design.md), and `carry` is `temper intent carry '<question>'`. `temper go` prints this list as `blocking` |
| `gate` | with `ask`: the `temper gate` call of the question's stage (Fix is judged by the build gate), run again after a change the person typed at the question |
| `context_map` | at Plan, when `plan.md` has a Context Map: `{intro, file, rows, answer, table}`, the table as plain text |
| `context_check` | at Plan, while the map's `reviewed:` line is not `human` or `auto` and the person is asked about it (9.8.5, WP13: a flagged map under `auto`, every map under `always`, none under `off`, and not a map folded into the approval; else `null`): the CLI's own question (header `Temper gate`). 9.8.0: its text names what the plan leaves out and could not find (the map's `ignore` and `gap` lines); the options are `As planned (Recommended)` (runs `temper plan review --answer 'As planned'` then `temper gate plan`), `Include what is left out` (runs `temper plan review --answer '...' --redo`: the answer becomes the person's note and Plan runs again with it), `Something else` (typed) and `Carry forward`, each with the table as its preview; 9.8.5: id `plan.context`, kind `context`, options `as-planned`, `include-left-out`, `type` and `carry`; `answer` is the call a typed answer fills (`--redo` too). When the pending check is the plan gate's only failed row, `ask` is this question |
| `guard.adhoc_stage` | the stage a small change window (`temper adhoc open`) was opened at, or `null` |
| `card` | 9.8.5 (WP15), with `ask`: the card of a question that decides, or `null` for any other question. `{kind, run_id, step, title, tag, sections: [{id, title, note, rows: [{text, mark}], total, file}], foot}`; `kind` is `approval` (`plan.approve`, `rca.approve`, and `design.pass`, the approval when the person asked for Design), `commit` (`commit.confirm`, and `check.pass` of a run that asks at every stage) or `stop` (any other question at a stage whose check failed and is not skipped, or a stop of a run that goes on by itself); `run_id` and `step` are the question's. A section is cut when `total` is larger than the count of its rows, and `file` says where the rest is; `mark` is one of `proposed`, `create`, `modify`, `sensitive`, `left out`, `not found`, `not measured`, `open`, `skipped`, `by rule`, or `null`. The sections of the approval, in order: `request`, `assumptions`, `criteria`, `out_of_scope`, `answers`, `files`, `commands` (word for word, never cut), `context` (every flagged line whole), `launches`, `risk`, `baseline`; of the commit: `criteria`, `suite`, `coverage`, `planted_bugs`, `review`, `files`, `rule_log`, `skips`, `tree`, `run`, `message` (the message the click uses); of a stop: `what_fails`, `tried` (the budget used for the failure and the run), `reading`, `still_green`, `spent`. A section with no source is left out. No card holds dollars; a time is in minutes, and the approval's estimate is the median of the finished runs `.temper/runs.jsonl` keeps. The card is built by `scripts/card.py` in the same call as the question, and never goes into the question text. `temper card` prints its rows (76 columns), `temper go` gives them as `card` |
| `setup` | when the project still lacks it, the calls that set Temper up (the config, the `.temper` scaffold, the commit hook); each is idempotent |

The stages are Intent, Plan, Design, Build, Review, Check and Commit, and an optional **Pipeline** stage after a Commit that opened a pull
request (`phases.pipeline` not `false`; [ADR 0014](decisions/0014-the-pipeline-stage-after-commit.md)). Its agent reads the checks and
writes `pipeline-context.json`; the push is the orchestrator's, after the person's yes. An agent's gate call is named `gate` (the last of
its `after` calls) in `agents[]`.

A **small change** (`temper adhoc open --stage S --reason R`, `adhoc close`) is offered at the Build, Review, Check and Commit questions as
`Make a small change`. After `adhoc close`, `next` runs the steps the change touches: Review of the changed files, then Check, then the
commit gate (a change made at Build, or of docs only, runs only the stage's gate).

### The actions

- **`none`**: no run is active.
- **`work`**: run each of `calls` in order (CLI calls, written out in full); launch every agent of
  `agents` in one turn; when an agent returns, run its `after` calls, filling `{ms}` from the Agent
  result. `steps`, when present, are the commit steps in order. Then ask `next` again.
  An agent is `{type, model, prompt, after}`; a Build task agent also has `before` (its `task start`
  call) and names its `task`, `group`, `title` and `attempt`.
- **`ask`**: ask `ask.question` with the AskUserQuestion tool exactly as given (header, question,
  options and their descriptions). See "Questions" below.
- **A failed call stops its action.** A call or step that exits non-zero stops its action, and the loop runs
  `temper next --json` again. One exception: a call that prints a `VERDICT:` line (above, under `temper go`) has
  recorded a verdict that `next` asks about, whatever its exit code, so the action goes on.
- **`wait`**: tasks are running; `tasks` lists each as `{task, after}`. When their agents were launched
  in this conversation, wait for each result and run its `after` calls; otherwise run the `after` calls now.
- **`auto`**: the CLI's own move: an armed autonomous run, or a step with nothing to decide (9.8.0: the one group of a plan passing, a Build task an earlier task already built in an armed run). Run `calls`, then ask `next` again.
  `run.armed` of `next` (WP11) says whether the run goes on by itself now.
- **`broken`**: the run state does not fit its spec folder; ask the `restart` question.

### Questions

`ask` is `{stage, step, run_id, id, kind, question, options, more?, accept?}`. `question` is exactly what
goes to the AskUserQuestion tool, and it holds no other key: the tool takes only `question`, `header`, `options` and
`multiSelect`, and an option only `label`, `description` and `preview`, so every question the CLI writes for the dialog
has its ids beside it. 9.8.5: `id` is the question's id in the registry
`QUESTIONS` of `scripts/flow_base.py` (`plan.approve`, `check.fail`), which also says what decision it asks for, and
`kind` is its kind: `gate`, `group`, `resume`, `drift`, `blocking`, `context`, `reason` or `name`. A More question has
the id of its parent and `.more`, an accept question `.accept`. Each entry of `options` is the same option with what it
means:

| Field | Meaning |
|---|---|
| `id` | 9.8.5: one id a meaning, kept when the label changes, from the closed list `OPTION_IDS` (`approve-run`, `save`, `back`) |
| `kind` | 9.8.5, only on an option a reader acts on: `more` (opens `more`), `accept` (opens `accept`), `cancel`, `carry`, `type` |
| `recommended` | 9.8.5, only when true: the recommended option, the one whose label ends in `(Recommended)` |
| `label`, `description` | as in the question |
| `move` | `approve`, `arm`, `advance`, `override`, `back`, `accept` (a review finding), `covered` (a Build task an earlier task already built), `keep`, `commitOverride`, `redo`, `pause`, `restart`, `grant` (more repeats, at `run.budget`), or `null` for an option that decides nothing |
| `calls` | the CLI calls this answer makes, in order; `{reason}` is the person's reason. Every `{...}` text stands inside single quotes: put the text there with each `'` written as `'\''`, so a backquote or a `$` in it stays text |
| `steps` | for Commit at a parked run: the commit steps |
| `step_kinds` | WP16, beside `steps` (on an option and on a `work` action) when a step has a kind: one entry a step, `show-last` for the report step, `note` for the note of a run with nothing to stage, `""` for any other. The mod's run driver selects these two steps by kind, never by their words |
| `do` | for an option that decides nothing: what to do, then ask the question again (words for a person or a model; the mod's run driver never reads it) |
| `needs` | WP16, on every option with a `do` and on More options, Accept a finding and Cancel: one kind of the closed list `NEEDS` (`scripts/flow_base.py`). `more`, `accept` and `cancel` are navigation the run driver does itself; the other seven are the hand back kinds, each one step the conversation does for the person: `talk`, `html-review`, `depth-review`, `config-suggestions`, `small-change`, `pull-request`, `pipeline-fix`. `opt()` refuses any other kind, and a `do` with none. A `work` action whose steps are the pull request's carries `needs: pull-request` and `option`, the id of the option the person chose them by |
| `skill` | 9.8.0, with `do`: the skill the option carries out (`grill-me`, `teach-me`); the mod lets its own questions through while it runs |
| `stop` | the run stops here (Save for later) |
| `reason`, `reason_question`, `reason_ids` | the move needs the person's reason: their note on the option, or their answer to `reason_question` (any answer but Cancel, typed text included). 9.8.5: `reason_question` goes to the dialog as it is, so its ids sit beside it in `reason_ids`: `{id, kind, options}`, with the id of its question and `.reason`, the kind `reason`, and in the order of its options each ready reason's id `choice-N` and Cancel's id `cancel` with the kind `cancel` |
| `answer_question`, `answer_ids` | the move needs a typed value (a name, a command), asked by `answer_question`. 9.8.5: its ids sit beside it in `answer_ids`, as `reason_ids`: the id of its question and `.name`, the kind `name`, and `type` (kind `type`) and `cancel` (kind `cancel`) in the order of its options |

`more` is the second question of "More options"; `accept` is the question of "Accept a finding". Both
have the same shape. A question holds four options at most.

WP16: a question of kind `gate` (and its More question) carries `typed`, `{calls, again}`: the calls a typed answer
runs, in order, with the person's text in place of `{text}`. The first is the note for the next agent (`temper evidence
add --stage S --phase note --kind input --claim '{text}'`); at Intent, Plan, Design, Build and Fix, on the stage's own
question and while the budget has room, the second is `temper state redo S --reason '{text}'` and `again` is false (the
stage's agent runs again with the note). Elsewhere, and at the budget's limit, the note is the only call and `again` is
true: the same question is asked again after it.

Scope drift (WP16) is the CLI's question. A Build or Fix agent that needs a file outside the plan records it with
`temper drift ask --path P --why W --change C` (a `drift` row of the Build ledger; a path of the plan is refused) and
returns. Before the gate question and before any launch, `next` asks `scope.drift` (header `Scope drift`, first line
`Outside the plan: P`, then `Why:` and `Change:` lines) with `Add to plan`, `Revert` and `Allow once`, each with move
`drift` and the call that records the answer (`drift P: <label>: W`, phase `feedback`), in an unattended run too. With
every one answered, the stage's agent runs again with one `Drift decision: P: add|revert|allow-once` line a file; its
`before` call marks them given.

The CLI words that take the place of calls that were no CLI calls (WP16): `temper spec branch --carry NAME` (the switch
to the branch an earlier run left, carrying the spec files through a temp folder; a refused switch puts them back,
fails, and names the folder), `temper spec branch --if-protected` (a fix run: from main, master or the default branch,
the switch to the run's branch; on any other branch, that branch becomes the run's), `temper group take-out G SHA...`
(commits the CLI did not make, taken out only when they are recorded as such and are the newest of the branch) and
`temper group feedback G --text T` (Change at a passed group: the next `feedback #K` row, and `group.change` follows
with K in its calls). No call of the flow is a foreign program, and no option call holds a placeholder outside a
typed question.

The person decides only by choosing an option. The mod counts an answer only when its header, its
question and its label match exactly what `next` gave for the run and step it is at, so a reworded
question is no answer. A typed message is never a move: it is a change request or a question. An id is a
lookup: the policy, `temper go`, the mod's run driver and the scripted persons select an option by its `id`,
`kind` and `recommended`, never by its label, and the answer still counts only on the exact header, question,
label, run and step.

### Loop backs and replans (9.8.4)

A step back carries what was learned. `temper state loop` keeps what the stage it leaves left open
(`scripts/loop_step.py`): Review's open findings, Check's failed runs, Plan's open fresh review findings, and
from Build each failed group check first (its reason, how many times it failed, its first FAIL lines),
never a task's RED run, which fails by design. The stage the run goes back to gets the reason and those
items (`Loop back from`), and so does each later stage the run comes through again (`Earlier loop back
from`): a loop from Plan to Intent reaches the Intent agent and then the Plan agent.

The fresh review's round limit (`plan.fresh-review-rounds`) survives a step back, so a loop back that
cleared the plan ledger could leave the gate failing on "fresh review ran: not run yet" while the limit
forbade a new round. The choice made: a loop back to Intent, Plan or Design, or a replan
(`temper state redo plan`), earns **one more round**, granted once `plan.md` or `tasks.md` changes after it.
A loop back that changes neither earns nothing (the plan the earlier rounds read stands), and a second
loop back before that round is taken earns no second one. The round is counted in the run state
(`fresh.grant`, then `fresh.extra`), and the question names the limit with it.

### A failed group check (9.8.4)

The group gate keeps the first FAIL lines of its Validate output and counts its failures
(`groups.json`: `gate.fail_lines`, `gate.ran`, `fails`). The question shows the first three lines. When
every task of the group passed and its check ran and failed, the first and recommended option is one Build
fix agent on the group's merged tree (`temper group fix G<n>`; the agent's work is committed by
`temper group fix G<n> --commit`, which also clears the group's gate when the agent changed something, so the next
action checks the group again as an ordinary CLI call and a FAIL there asks the question again; see 9.8.5 below for a
fix that changed nothing). From the second failure on, "Run the
group's tasks again" is never recommended. The fix is recommended once (`fix_tries`): when it did not make the group
pass, the loop back to Plan is recommended. That step back spends the group's budget key, so following the
recommendation always ends (see the budget below).

To read a failure, the session runs `temper output G<n>` (the group's last Validate run: its command, exit,
FAIL lines and recorded output) or `temper output <stage>` (the gate's failed rows and the stage's last failed
run). It is read only; with the mod on, the session may run the CLI but not `printenv` or a test runner.

### The environment check and the baseline (9.8.5, WP20)

A fault of the environment or of the base is named before any agent is paid for. Before any other step of an active
run, while `.temper/evidence/baseline.json` is absent, `next` is the CLI's own action `auto` with the one call
`temper baseline start` (`--env-only` at a door into Review or Check). `state init` empties `.temper/evidence`, so every
new run starts one; a step back does not. The call always exits 0 and returns in seconds (`scripts/baseline.py`):

- **The owner of the suite command** (`python3 scripts/check_run.py owner ROOT [SPEC]`): the config's
  `check.commands.test` (with `check.commands.coverage`); else what `detect` reads in the root; else the one folder one
  level down that `detect` reads, with `cd <folder> && ` in front (none when two do); else the plan's `**Integration:**`
  line; else none, with the reason. For Maven, `detect` gives `mvn -q verify`.
- **The environment check** (`doctor.needs`, under 5 s, no suite): the JDK a `pom.xml`, a Gradle file, `.java-version`,
  `.tool-versions` or the CI names, the Node version of `package.json` or the CI, the config's `setup.tools` and
  `setup.services`, against one shell call under the setup block (each program the suite command starts must resolve,
  and the version lines of `java` and `node`) and a connect to each service. A fault (`program-missing`,
  `tool-version`, `service-down`, `setup-line`) names the file that states the need, the need and what the shell has.
- **The baseline**: the suite once on the current code, in the detached worktree `.claude/worktrees/temper-baseline`
  at HEAD (the place Build uses: no branch, no commit, no project file), in its own process
  (`TEMPER_BASELINE_FOREGROUND=1` keeps it in the call). `green` on exit 0, with `seconds` and `coverage` (the floor of
  WP19); `red` on any other exit, with its `kind` and the `fail_lines`; `unknown` with the reason (no commit, no
  command, a run over its limit with `seconds_over`). `temper baseline clean` removes the worktree; `state clear` and
  `state init` call it.

Nothing waits for it: the approval card shows the baseline line in one of four forms (passes with its seconds and the
floor, running, fails on the current code, unknown with the reason). A red result with no answer is the question
`base.red`, before any other step: an environment fault before the first agent, a red suite known before the approval
before it, one that ends while an agent works when that agent returns. Its text holds the command, the exit, the
seconds, the fault or the first fail lines, and the exact proposed setup block when there is one. Options:
`add-setup` (Add this setup block and run it again, first and recommended, when the config has no block and
`temper doctor --propose` gives one: `doctor --propose --write --expect <hash>` writes the block as shown, refused when
the proposal changed, then `baseline start --again`), `check-again` (Run it again), `go-on-anyway` (Go on anyway, with
a reason: `baseline accept-red`, the person's only) and `save`. After the approval, Build launches no new task agent on
a red base; a run that goes on by itself records a stop with its notice, then asks `base.red`.

"Go on anyway" is a recorded skip: a row `base-suite` in `.temper/overrides.json` (by the person), the answer in the
file and in the reuse store under the baseline's key (the base tree, the command, the setup block, the tool versions).
At Check the row `tests pass` of a failed suite run that shows only the base's fail lines (numbers masked) is
`pass: null, state: skipped`; one new fail line fails it. A later run with the same key asks nothing and records its own
skip row; a changed key asks again. A fix run records a red base of kind `red-base` with the answer `fix-run` and asks
nothing: there the red suite may be the bug.

**Limits from measured time.** `baseline.limit_for(cmd, default)` is the larger of the site's default and three times
the seconds the same suite took on the base (the same text, or the same steps with other flags; `seconds_over` counts
as measured). It sets the limit of the group gate (600 s), a task's test and its scenario tests (600 s), `integrate`
(3,600 s) and Check (1,800 s); the environment variables stay the defaults, and a gate waits for a baseline still
running that measures its suite. The first time out of a group's check is no question: the CLI runs `group gate G
--timeout-s <twice the limit>` itself (no repeat of the budget when the base measured that suite) and keeps the doubled
limit in `limits`; a second time out asks `group.fail`.

### A command the plan wrote, the setup block and an environment fault (9.8.5)

**A command the plan wrote (WP21).** The plan gate runs no project command. After the planner returned, its last calls
are `temper baseline plan` and then `temper gate plan` (a fresh reviewer, a revision and a changed command end the same
way). `baseline plan` (`scripts/baseline.py`) runs each distinct group Validate and the Integration line once on the
current code, one after another in a process of its own, in the baseline's worktree `.claude/worktrees/temper-baseline`
after the suite ended, each under the limit Build gives it: a Validate under the group gate's (`limit_for` of 600 s,
`TEMPER_TASK_TEST_TIMEOUT_S`), the Integration line under `integrate`'s (3,600 s, `TEMPER_INTEGRATION_TIMEOUT_S`). A
Maven command runs as written. Left out: a text equal to the suite the baseline ran (or the owner's test text), a
command that names a file a task declares and the base lacks, and every task Test and scenario `Test:` (they fail on
the base by design). Only a command with no result runs, so a second call is cheap; then the worktree goes. Each result
is kept in `plan` of `.temper/evidence/baseline.json` under the command's text, judged by its exit code alone: 0 is
`pass` (its seconds feed `limit_for`); 124 is `timeout`, never a fault of the environment; 125 (the setup line failed)
and 127 or a first word that does not resolve are class `environment`; any other exit is `fails like the base` when the
base is red, else `fail` (class `command`). No output text takes part. The same process resolves the first word of each
step of every command of the plan, the task and scenario Tests too, in one shell call under the setup block; a program
that does not resolve turns the base red, so `base.red` names it before any agent. A `fail` or a `timeout` is the
question `plan.command` (the scope of `base.red`'s function): the command, where the plan wrote it, the exit, the
seconds and the first fail lines; `Allow it more time` first at a time out (a longer limit kept in `limits`), else `Run
it again`; `Change the command` (typed, `temper plan patch`, then the plan is checked again); `Revise the plan`;
`Go on anyway` (a skip with a reason, the override `plan-command`); `Save for later`. No setup block and no agent are
offered. A result that comes after the approval asks the same before the next task agent, with `Loop back to Plan` in
place of `Revise the plan`; a result still running is `running` on the approval card, and only the first group gate of
the group whose Validate it is waits for it. A run that goes on by itself stops there: it never changes a gate's
command and never plans again.

**The setup block.** `setup:` in `.claude/temper.config` holds `run:` (one shell line), `env:`, `services:` and
`tools:`. `scripts/run_env.py` runs the line in the same shell before every command the CLI runs (task tests, group
and scenario checks, integrate, Check, the baseline and the plan's commands), prints `temper-setup: OK`, and adds the variables; a failing
line prints `temper-setup: FAIL (exit N)` and exits 125. A variable whose name says it holds a credential is never set
or shown. Every agent prompt ends with an `Environment setup` line that carries the run line and the variables. No
block: every command and prompt is as before. The person rarely writes the block: when the environment check or
Check fails on the environment and there is none, the question (`base.red`, or Check's) offers `Add this setup block and
run it again (Recommended)`, made by `temper doctor --propose` from the project's own files and its CI, and the question
shows every line of the block. It is written only as the call of that answer, as shown (its hash): at `base.red` the
baseline that runs next is its check, at Check the run of Check again (`docs/commands.md`). No agent drafts a block
(WP08, WP21). When no rule proposes a block, the question says what is missing, in the words of the fault.

**An environment fault at a task gate.** When the last run of a task's attempt is a failing GREEN, a RED came before it,
nothing else is wrong, and the run shows one of three sure signs (WP21: the setup line failed, exit 127 for a program
the command starts, or a service of `setup.services` that does not answer right after the run; a text such as
`Connection refused` alone is no sign, so a code bug that prints it spends the attempt), `temper task gate` prints `ENV:
Task N failed on the environment, not on the code: <reason>`, exits 0, spends no attempt, keeps the worktree and the
status `running`, and marks the task `env_fault` in `groups.json`. `temper next` then asks, in every mode: `Check it
again (Recommended)` (runs `task test N --phase green` and `task gate N --model M`) or `Save for later`. Here a time-out
is the code's, as before: it spends the attempt. Any status move clears the mark.

### Decisions, findings and integrate (9.8.5)

**Design runs only when asked (WP14, ADR 0019 decision 2).** A run of `/temper:temper` has the Design stage when the
person chose `Run Design first` (id `run-design`, in the More list of the passed plan question; its calls are
`temper state set want_design true` and then those that leave Plan, with `design` as the next stage), when the run was
started by the Design door, when `design.md` exists, or when the run is at Design or has a Design verdict. No tier, no
risk and no setting adds it: `phases.design` and the state key `intent_asked` are gone. What Design asked is now a
Blocking question Plan writes into intent.md, `- Blocking: {question} choices: {the answer the plan assumes} | ...`,
with the tasks written under the first choice. `state advance plan_complete` is refused while one is open, so it is
answered in front of the approval, with the mod or without it. At risk H the fresh review of the plan applies with no
request (under `plan.fresh-review: ask`), and the option that starts the unattended run is offered only when a round
ran on the plan as it is, every lens complete, with no open finding at high (`Builder.may_run_alone`).

**An answer reaches the tasks.** `temper intent answer` given after `tasks.md` exists keeps the answer with the hash
`tasks.md` has at that moment, and whether it is the first choice of its line (`.temper/decisions.json`,
`scripts/decisions.py`). The row `tasks agree with decisions` is a row of the plan gate. The first choice passes it with
a note that names the answers and counts the first choices. Another answer fails it while `tasks.md` is still that
file. Then `next` is `work` with the one call `temper state redo plan --reason <the answers>`, once (the budget counts
it under `gate:plan`); the same answers still unmet after that ask the failed plan question, with `Revise the plan`
recommended and `The tasks already agree` as the first reason of its skip. Each Build task prompt lists the answers,
newest first, as decisions that win over `tasks.md`. The Design gate has no such row.

**High findings block.** `review.block-on` defaults to `[critical, high]`. A passed Review with an open finding at
high or above recommends `Loop back to Build`; with a Medium one it recommends `Continue to Check`, and the passed Check
question lists the open findings (`open findings: 1 medium` and the first three claims) where the person commits. Both
Review questions name the open findings per level (`open findings: 1 high, 2 medium`). At a passed Review with an open
finding, `Accept a finding`, `Grill Me`, `Make a small change` and `Save for later` are under `More options`, and
`Teach Me` takes the place of `Architecture Depth Review`.

**What resolves a finding (WP18).** `temper evidence resolve --stage S --id N --fixed-by COMMIT` marks a finding
resolved only when four things hold: COMMIT is a commit; it is an ancestor of HEAD; it is no ancestor of the reviewed
HEAD (the `head` of `review_snapshot`, written as the run enters Review; with no snapshot the call is refused); and
it is in `cli_commits` of `.temper/groups.json`. The mark stores the full id. Each refusal is one `FAIL:` line that
names the check and the short ids. No commit of the CLI meets the last two yet, so a finding ends by the person's
accept, or by a loop back to Build and a second Review. With the mod, the call is refused as a tool call in a
`/temper` or `/temper:fix` run; with no run, the mod lets it through and the CLI refuses it, as no commit of the CLI
is recorded.

**Review names the files it read (WP18).** `temper review files` prints the changed files of the run, one a line: the
commit gate's set (since `base_sha`, plus uncommitted and untracked files) less `.temper/` and `.claude/` and less
files that no longer exist; after a small change that runs Review again, that window's files until its gate. The
completion row takes `--read FILE` once for each file read whole (only with `--stage review --claim 'review
completed'`). The row `review completed` passes when the latest completion row has exit 0 and names every file
(`read N of N changed files`); else it fails (`read K of N changed files; not read: ...`), `Run Review again` is
recommended, and the second launch names the files not read. The repeat spends the budget.

**Integrate after new commits.** `temper integrate` records the HEAD it passed on, and that the groups are merged.
Called again once they are merged, it runs the whole Integration command again when HEAD moved since (a fix pass
committed) or the last verdict was FAIL, records the new verdict and, when it passed, runs the scenario tests, as
before. It never merges the group branches a pass deleted. A rerun that fails records FAIL, prints its `FAIL:` line and exits 0: `gate build`
fails the row `integration`, and the Build question holds it. The fix pass that follows gets the findings of the loop
and what failed since in one prompt.

### Failure text, the SETUP verdict and recommendations that follow the evidence (9.8.5)

**What failed.** A failed group check keeps its failure lines most telling first: a time-out (exit 124) says so; then
the build tool's own summary (the last Maven `Failed to execute goal` line, `Rule violated` lines, failed test names);
then the lines that say FAIL, ERROR or an exception, without the log lines a passing test printed
(`20:01:44.264 [main] ERROR ...`). With none, the last three lines, never the first. An armed run's park reason keeps
1200 characters of it.

**No empty fix pass.** Build's fix pass after integrate gets the integrate verdict and the Build gate's failed rows in
its prompt. When nothing names a fault (no feedback, no failed row, no note of the person), no agent is launched: the
CLI runs `integrate` and `gate build` again, and a failure there names the fault.

**A fix that changed nothing.** `temper group fix G<n> --commit` with no change keeps the group's check failed (the same
tree would fail the same way, so it does not run again) and counts `fix_empty`. The next question recommends the loop
back to Plan (or Save for later), and says the cause is the plan's command or the environment. A first time-out is
no question: the CLI runs the check again with twice the limit (WP20, above); a second one asks, with the command change
first.

**SETUP at Check.** When the suite or the acceptance run of Check fails on its environment (a project marker `<script>:
SETUP: <reason>`, or one of the three sure signs of an environment fault: a failed setup line, a missing program, a
declared service that does not answer), Check records a `setup fault: <reason>` row beside the red suite row, so the
gate still fails. The question says `SETUP`, offers `Repair the environment and run again (Recommended)` first, and
never recommends a loop back. The same fault after Check ran again recommends `Save for later`, first, and the repair
loses its mark. Rows no longer carry the JVM's start text (`Picked up JAVA_TOOL_OPTIONS`, the `sun.misc.Unsafe`
warnings).

**Overrides at the commit gate.** `Override and commit` clears a failed stage gate the commit gate names. It never
cleared the commit gate's own rows (blast radius, scope, park-on-touch), so it is no longer offered for them; the question
says what to change instead, and `Add to plan` stays for files outside the plan. When no file is outside the plan, the
first option is `Check again` (with no mark), which runs the commit gate again once the change is made (WP08).

**Questions.** A question has four options at most; the CLI puts the rest under `More options`. The Context check
accepts an answer of up to 2000 characters (the `Include what is left out` option carries the whole list); plan.md
shows its first 100.

### A plan patch (9.8.5)

`temper plan patch G<n>|task N|integration --cmd '<command>'` changes one command line of the approved `tasks.md`
(a group's Validate, a task's Test, the Integration line) and nothing else (`scripts/plan_patch.py`). The passed tasks
keep their work, the patch spends one repeat of the budget, the approved plan's hash follows the change, a patched group's check runs again, and
the plan ledger records the old and the new line as the person's. It refuses a `tasks.md` that differs from the
approved plan in anything else (that is a loop back to Plan). It is the person's: the group question offers `Change
the group's command`, recommended when the cause is the command (a second time-out, or a fix agent that changed
nothing), and the person types the command. The mod lets it run only as that answer.

### The budget (9.8.5, ADR 0019)

Every repeat that follows a failed check is counted by the CLI in one record, `.temper/budget.json`, read only through
`scripts/budget.py`: 2 for one failure (`budget.per-failure`) and 6 for one run (`budget.per-run`). A failure is the
check that failed, its key: `gate:<stage>`, `group:<G>`, `task:<N>`, `acceptance` or `pipeline` (a failed `integrate`
spends under `gate:build`). The table `SPENDS` says which calls spend and when: a step back or a run again from a failed
gate (from Build, a failed or parked group's key), a group fix, the group's tasks again, more time at a failed group
check, a plan patch, a task retry, a task checked again after an environment fault, a reopened acceptance test, a CI
fix round, and a merge again after a failed `integrate`. A step back by `state set next_stage` spends as a
`state loop` does. One CI fix round is one entry, under `pipeline`: the `state redo pipeline` of its steps answers the
failure that round paid for and spends nothing more. A change at a passed gate spends nothing. The CLI's dispatcher
checks the call before it runs: past a limit it prints `BLOCKED: ...`, exits 1 and writes nothing. No flag and no
variable exempts a call, and a call refused later for its own reason has spent its repeat.

`temper next` never offers a call the budget refuses: the calls and steps of one option are checked
together, in order, against both limits. A question that would offer one becomes `run.budget` (header
`Temper gate`): the stage's first sentence, the count, then Save for later (recommended), `Allow two more` (move
`grant`, the call `temper budget grant --key <key> --reason '{reason}'`, the person's only) and the options of the
stage's question that spend nothing. An `auto` or `work` action that holds one parks an armed run, or asks the same
question. After a grant `next` asks the stage's own question again. `temper budget` prints the record. The record
survives a step back; `state clear` and `state init` remove it. So following the recommendation always ends.

### The run to the commit (9.8.5, WP11)

The approval's first option, `approve-run` ("Approve and build", move `arm`), runs `temper state set run_mode
autonomous` and then the stage's calls; `ask-every-stage` ("Ask me at every stage") runs `state set run_mode
interactive` first. `run.default` orders them: `to-commit` (the default) puts `approve-run` first and recommended, `ask`
the other way round, `never-unattended` offers `ask-every-stage` alone. With the key absent, `autonomy.enabled: false`
reads as `ask`; an unknown value is `ask`. `approve-run` is left out for a skipped check, when Design follows the plan
question (the Design question is then the approval), and when `may_run_alone()` says no. The CLI refuses the call
unless the run is at Plan or Design with that check passed and not skipped, and under `never-unattended`; it records
the stage in `unattended_from`, which `state set` refuses. A state with `run_mode: autonomous` and no `unattended_from`
(a run of 9.8.4 or of the base, approved for Build alone) reads as `interactive`. `state init` stamps `saved_by`; a
state with none, saved at Review, loses its Review verdict once, so Review runs once more.

`Run.armed` is `run_mode: autonomous`, an `unattended_from` other than the stage the run is at, and no `parked`. Then a
passed Design, Build, group, Review or Check is an `auto` advance. Review: an open finding at a level of
`review.block-on` takes the repair; one below goes on and is named at the commit question. Check: a setup fault, a
missing test run, the acceptance rows, a criterion only the person can confirm and the row `intent unchanged since the
approval` stop; anything else, a measured coverage drop with it, takes the repair. A coverage not measured fails
nothing: the run moves on and the commit card names it; no rule repairs it. The planted bug score moves nothing.
The repair is one counted `state loop
<stage> build --reason 'rule: ...'`; a second one, a plan that declares a file under `autonomy.park-on-touch`, or a key with no room stops. A failed group check takes its
recommended option when it has calls, needs nothing typed, does not save the run, is no step back and the group declares
no sensitive file. Every other case is a stop (`scripts/stops.json`).

A stop is the park call, then the stage's own question. `temper park` keeps `run_mode`; `parked` makes `Run.armed`
false and ends when the run changes stage or by `temper park --end [--answer ID]` (not at Commit). The question asked
while `parked` is set says `After your answer the run goes on by itself.`, every option with calls and no `stop` ends
with `park --end --answer <its id>`, and `ask-every-stage` ("Ask me at every stage from here") is added. A skip, an
accepted finding and a step back to Intent, Plan or Design end the run to the commit, and so does a refused approval
and the advance out of Commit: a run that opened a pull request reaches Pipeline asking. The commit question always
asks: `commit`, `commit-pr`, `back` (`state loop check build`), and under More the stacked pull requests, the small
change and `save`. A failed commit gate with a changed sensitive file outside the plan offers `confirm`
(`temper override sensitive-path:<path>`). `temper go --taken-up` records a stop of such a run first, so its stage asks
once. What a rule decided, each stop and each answer are entries of `.temper/rule-log.json` (`scripts/rule_log.py`).

### The approval is bound to what was shown (9.8.5, WP12, ADR 0019 decision 4)

- **The arguments.** The approving options of `plan.approve` (and of `design.pass` when the person asked for Design)
  end in `state advance plan_complete <next> --shown intent.md=<H1> --shown tasks.md=<H2>` (or `design_complete`). The
  digests are taken by `scripts/approval.py` in the `next` call that builds the question: of `intent.md` without its
  `Status`, `Accepted-by` and `Completed` lines, of `tasks.md` the plan digest. The CLI hashes each named file again
  before it writes anything and refuses the call with `FAIL: intent.md changed since the question was shown; ask
  again`. The arguments are optional: a call without them records what it finds. `plan_complete` is refused while
  `intent.md` is a draft. `intent accept --digest <H1>` refuses the same way. `python3 scripts/approval.py digest FILE`
  prints a digest, `row STATE SPEC` the row, `check STATE SPEC NAME=DIGEST...` the refusal.
- **The check comes first.** Every approving option starts with `state set run_mode autonomous|interactive --shown
  intent.md=<H1> --shown tasks.md=<H2>` (`Run Design first` after its `state set want_design true`, the plan
  question with Design to follow and the skip's way on too). `state set run_mode` compares the digests before it
  writes the mode, so a stale approval writes no mode, makes no branch and no commit, and leaves the run at its
  question, which `next` asks again with the digests of the files as they are now.
- **The state keys.** `state advance plan_complete` records `intent_hash` beside `plan_hash` and `approved_files`;
  `design_complete` records both digests again. `state set` refuses them, and `from_branch`: the branch the run stands
  on before its approval (written at `state init` and when the run leaves Intent), which the commit hook gates too.
- **The row.** `intent unchanged since the approval`, a row of the Build, Check and commit gates (in the commit gate
  after the stage rows, so a spec only commit and a Build checkpoint commit do not compute it). It passes with no
  `intent_hash` recorded or with both digests as recorded, and fails naming `intent.md` or `tasks.md`. In a run that
  goes on by itself it is a stop (`approval.changed` of `scripts/stops.json`).
- **No branch and no commit before the approval.** Leaving Intent is `intent accept` and the advance (WP13: or the
  advance alone, by rule). The approval is `spec branch`, `intent accept --digest <H1>` for a draft, one `spec commit`
  (`docs(plan): accept the intent and approve the plan of <slug>`, or `approve the intent and the plan` for an intent
  already accepted) and the advance. When the
  run's branch exists from an earlier run with commits the project lacks, the approval's text says `The branch <name>
  exists from an earlier run; its last commit is <subject>.` and `The approval continues on it.`; its switch is the
  carried one (the spec files go across through a temp folder), and its More list holds `Build on a new branch <new>`
  (`new-branch`, the one call `state set branch <new>`), after which the approval is asked again with no clash.

### The run leaves Intent by rule; the approval accepts the intent (9.8.5, WP13, ADR 0019 decision 5)

- **The rule.** At Intent `next` gives `work` (never `auto`) for the stage `intent`, no agents and the one call `state
  advance intent_complete plan`, when all of these hold (`Builder.intent_by_rule`): a `/temper:temper` run; the Intent
  check passed and was not skipped; `intent.md` exists (a trivial request has none); no Blocking question is open (an
  answer is no note: once the gate passes again the rule moves on); the run did not come back to Intent; the person
  typed no note at Intent; no door walked Intent. Otherwise `intent.accept` (or `intent.fail`, or `run.walked`) is
  asked as before. `temper go` runs that work by itself. The intent stays a draft.
- **The approval accepts it.** Its first options run, in order: `state set run_mode autonomous` (or `interactive`,
  each with the `--shown` digests),
  the folded Context check's `plan review` call, `spec branch` when the project is on another branch, `intent accept
  --digest <H1>` while the intent is a draft (`Accepted-by: the person, at the plan approval`), one `spec commit` and
  the advance with its `--shown` digests. The text says `Accept the intent, approve the plan and continue to <next>?`
  and both descriptions start `Accept the intent.` The More list holds `back` (`Loop back to Intent`).
- **A skip never accepts it.** With a draft intent the skip of a failed plan gate is `override plan` alone. `next` then
  asks `intent.accept` at Plan (`Accept the intent (Recommended)`, the one call `intent accept --digest <H1>`), and the
  plan question follows with `ask-every-stage` and no `approve-run`.
- **The Context check.** Under `auto` only a map with an `ignore` or a `gap` line is asked about; a clean pending map
  passes its row (`not asked: no flagged line`) and keeps `reviewed: pending`. A flagged map is folded into the
  approval when the `context` section of the approval card holds every flagged line whole (WP15: a line of any length,
  as many as a map holds; a card whose section is cut keeps the question): the row passes (`N flagged line(s),
  answered at the approval`), the approval's text names the lines (cut at 90 characters), the approving options
  run `plan review --answer 'As planned (at the approval, N flagged lines shown)'`, and `Include what is left out`
  joins the More list. Any other flagged map keeps its own question; `always` asks every map, `off` none. When no
  Design follows and the run's branch clashes (WP12), the approval has no room for the fold (its More list would need
  a third dialog), so the Context check is asked first as its own question, and the approval after it.
- **The draft beside its plan.** The Intent row `no scenarios in draft` passes once `tasks.md` is beside the intent:
  Plan wrote those scenarios.

### A fix run asks twice; a trivial request is a verdict (9.8.5, WP17)

- **The root cause question is the approval.** `rca.approve` asks `RCA: the root cause and the proposed fix are on the
  card. Approve the fix?`. Its first options are those of the plan question, ordered by `run.default` as there:
  `approve-run` (`Approve and fix`, move `arm`) and `ask-every-stage` (move `approve`), each with the calls `state set
  run_mode autonomous|interactive --shown rca.md=<H>`, `spec branch --if-protected` (the fix branch, off main or
  master only) and `state advance rca_complete fix --shown rca.md=<H>`; then `save`. `rca.md` is bound by the
  mechanism of WP12: the CLI refuses a stale call, and the advance records its digest as `intent_hash`, so the row
  `intent unchanged since the approval` names `rca.md` in a fix run. `state set run_mode autonomous` is taken at RCA in
  a fix run (RCA has no gate). A typed answer is the note at stage `rca`: while the run state's `rca_notes` counts
  fewer notes than the RCA ledger holds, `next` gives `work` with the root cause agent (the bug from `feature`, the
  notes, the after calls `usage add` and `state set rca_notes N`), then asks again. The question's card (kind
  `approval`, `scripts/card.py`) has the sections `request` (the bug as typed: `state init S --command fix --feature
  BUG`), `cause`, `fix`, `test`, `files`, `commands` and `risk`, read from `rca.md` by `panel.rca_fields`; its foot
  names the branch the click makes and ends `Nothing is pushed.`
- **In between.** Approved with `approve-run`, a passed Fix, Review and Check move on as the CLI's own action, a failed
  check takes the one repair (`state loop <stage> fix`), and Review starts Check's run (`check ahead`), as in a feature
  run. The commit question of a fix run offers `commit`, `back` (`state loop check fix`) and `save`: no pull request
  and no small change; its card's `message` is the message the CLI drafts from `rca.md`.
- **TRIVIAL.** The Intent agent of a `/temper:temper` run at Intent, at step 0, with no spec file, calls `temper
  intent trivial --why TEXT` (`scripts/trivial.py`): the run state takes `trivial: {why, head, at, dirty_before}` and
  `guard.trivial_exit` turns true, the window in which the Intent agent makes its one change (with the mod, and with
  the classic hook of the mod off). Once the Intent verdict is recorded, `next` gives `auto` with the one call `intent
  trivial --close`: it writes `.temper/trivial.json` (`{request, why, head, at, dirty_before, bound: {files: 1,
  lines: 10}}`), the kept run summary takes a line of kind `trivial`, and the run is cleared as `state clear` does.
  With no run active and that record's `head` at HEAD, `next` says so in one line: the change is not committed, the
  commit is the person's, and the commit hook holds it to one file and 10 lines. The commit gate with no run then
  counts the staged production files outside `.temper/` and outside `dirty_before` and their lines: the row `trivial
  exit` passes within the bound and fails above it, naming the two ways on. A record whose `head` is not HEAD is
  spent; `state init` and the view writer remove it. No state clear is let through at Intent.

### Evidence, the lock and a note (9.8.5)

- **One digest, the reuse store (9.8.5, WP22).** The same command on the same tree runs once. The digest
  (`run_env.tree_key`) is the git tree of the work tree as it is: tracked files with their content now and every
  untracked file git does not ignore, without `.temper/`, `.claude/` and the byproducts of a run (a path a run made that
  is no tracked, declared, source or test file). The key adds the command text, the setup block, the folder inside the
  repository, the first version line of each program and what the caller adds (the acceptance command: the lock's
  digests). The store is `temper-results.json` in the git folder, shared by every worktree, changed under a lock. Every
  command of a group check, `integrate`, Check, a task's scenario tests and the baseline goes through it; a task's RED
  and GREEN do not. A row the runner made carries `tree`, `key`, `seconds` and `reused` (the date of the kept result).
  A failure is kept beside the pass and is not run again on the same key (an environment or not measured failure runs
  again at most twice, a time out under a larger limit runs). A failure whose command passed on the base, that names no
  declared file, runs once more at once: fail then pass is `flaky`, the pass counts and the commit card lists it.
  `--fresh` (`check run`, `group gate`, `integrate`; the person's Run it anyway) runs whatever the store holds, spends
  one repeat and marks the row `forced`. Each verdict of `.temper/gates.json` names its `tree`; the commit gate fails
  (`checked tree`) when the project is no longer the tree the Check verdict names.
- **The lock.** A write waits for a live holder of `.temper/.lock` up to `TEMPER_LOCK_MAX_S` (120 s) and breaks a gone
  holder's old lock. Past that it fails with exit 75 and writes nothing; it never writes past the lock.
- **The failing-first proof.** `task start` records each declared code file (not its tests) as the attempt finds it, and a
  RED run records them again. A RED whose code files are already the final code, when this attempt wrote that code,
  does not count: the gate says the RED was made on the final code. This holds for every attempt, a retry or a reopen
  included (kept code from before is the attempt's start). A stub before the RED is allowed by default (in Python a
  missing function makes pytest exit 2, which is no RED); `build.red-before-code: true` allows none: the RED must run
  on the code as the attempt found it, so a compile failure is the RED.
- **Interfaces.** The integrate check finds a planned signature as written, or with the same shape once type names are
  unqualified (an imported `AgencyHealth` for a planned `MonitoringSummary.AgencyHealth`, and the reverse).
- **The person's note** (`evidence add --phase note --kind input`) is labelled `PERSON`, not `HEURISTIC`.
- **Runs the CLI saw.** The Build gate's `RED then GREEN` row and Check's `tests pass` row count a test run only when the CLI
  ran it (`temper evidence run`, a task test, a group check, integrate, Check) or the person confirmed it
  (`scripts/runs.py`). A run an agent recorded with `evidence add --exit` is a claim and counts nowhere, unless the
  config says `evidence.claimed-runs: count`. `temper evidence void --stage S --id N --reason R` marks a false pass void:
  the row stays, `evidence list` shows `[void: R]`, and it counts in no mode. Only a pass is voided.
- **A note in the question.** `temper state set ask_note '<step>: <text>'` adds the orchestrator's note to the question
  of that step, marked `Note from Claude (not from Temper)`; the options stay the CLI's.

## `.temper/view.json`

| Field | Meaning |
|---|---|
| `version` | 1 |
| `written` | when the CLI wrote it |
| `run` | `{id, step, slug, title, command, stage, mode, complexity, branch, spec, feature, parked}` or `null` |
| `stages` | `[{id, label, mark, verdict, failed, skipped?}]`; `mark` is `passed`, `failed`, `skipped`, `here` or `todo`; `failed` is the failed rows of its last check; `skipped` is `{reason, by}` |
| `status` | one sentence: where the run is and who it waits for |
| `next` | `{action, stage, say, calls, steps, agents}` of `temper next` (`action` is `error` when `next` itself failed, with the error in `say`); `calls` for a `work` or `auto` action, `steps` for a `work` action (the CLI's own moves, which the mod lets through); `agents` (9.8.0) for a `work` action, each `{type, model, prompt}`, and while the run stays at the same stage, every agent named there before (an agent's `before` call, a Build task's `task start`, changes the action before the agent is launched), kept in `.temper/agents-named.json` so a lost or rewritten view does not forget them: the only agents the mod lets the session launch |
| `ask` | the current question, as `next` gives it, or `null`; 9.8.5: with the `id` and `kind` of the question and of each option, and `recommended` (see Questions) |
| `blocking` | the Blocking open questions |
| `blocking_asks` | 9.8.0: the same questions as the session asks them (see `temper next`); the mod lets the session ask these |
| `restart` | the `Temper resume` question |
| `drift` | the `Scope drift` question's header, the first line prefix (`Outside the plan:`) and its three options; 9.8.5: id `scope.drift`, kind `drift`, and `drift_ids`, the ids of the three options at their places |
| `guard` | what the guard needs: `{stage, spec, slug, fix_run, grouped, armed, autonomy_enabled, plan_files, step, run_id, trivial_exit, prefix}`; `trivial_exit` is true while the run state holds the trivial verdict (WP17); `plan_files` are the files the person approved at the plan gate (before it, the plan's files as they are); `prefix` is the project's folder from the top of its git repository (`packages/app/`, or empty) |
| `plan` | `{approved, files, groups: [{id, title, files}]}` |
| `fresh` | 9.7.6: the fresh review of the plan, `null` when it does not apply: `{paraphrase, missing, stale, findings: [{id, severity, lens, claim, state, cite}]}`; `missing` names each lens and reviewer with no completion row (`readiness A`); `state` is `open`, `resolved`, `accepted`, `contested` or `escalated`; `cite` is a contest's checked citation |
| `build` | `{groups: [{id, title, status, verdict, tasks: [{n, title, files, state, model, attempts}]}], integration}`; a task's `state` is `waiting`, `running`, `red`, `green`, `pass`, `fail` or `parked` |
| `findings` | `[{id, severity, confidence, claim, file, line, state, label}]`; `confidence` is the reviewer's 0 to 1 (`temper evidence add --confidence`) or `null`; `file` and `line` come from a claim that starts `file:line`; `state` is `open`, `resolved` or `accepted` |
| `checks` | the rows of the Check gate: `[{name, pass, detail, state?}]`; 9.8.5 (WP19): `pass` is `null` and `state` is `not measured` for a measurement that was not taken (the row `coverage` with no coverage tool or no base value), which fails nothing and passes nothing |
| `check_markers` | `[{name, state, detail, value?, lines}]` for compile, tests, coverage, lint and security, and `mutation` (WP19) when `.temper/evidence/mutation.json` measured the tree as it is: the planted bug score beside Review, always `info`; `state` is `pass`, `fail`, `info` or `none`; the coverage marker follows the gate's row `coverage`, `info` with the detail `not measured: <why>` for the third state |
| `criteria` | `[{id, priority, status, text, evidence}]` of the intent's success criteria |
| `loops` | `[{from, to, reason, iteration, max, at}]` |
| `skips` | `[{stage, reason, by}]` |
| `usage` | `{ms, by_stage, by_model}` from `temper usage add`; each of `by_stage` and `by_model` maps a name to `{ms, runs}`, and a stage also to `models` (the models its launches asked for). The time is the total Claude Code gives for each agent; since 9.7.4 no token count is recorded |
| `card` | 9.8.5 (WP15): the object `card` of `temper next`, or `null` |
| `rule_log` | 9.8.5 (WP11): `[{kind, stage, what, ts}]` of `.temper/rule-log.json`; `kind` is `advance`, `repair`, `group fix`, `covered`, `stop`, `answer` or `ended` |
| `time` | `{started, updated}` |

The file is replaced whole each time (written beside it, then moved), so a reader never sees half of
it, and a link at that path is replaced, never written through.

## The end of run report

`temper report --html [-o OUT]` renders the view as one page (`scripts/run_report.py`): the stages with
the skips and the loops and their reasons, the plan's files by group, the Build grid, the Review findings,
the Check markers with their failing lines, the criteria with their evidence, and the time by stage and
by model. Its head says Done only once the Commit
gate has passed. By default it writes `report.html` in the run's spec folder. At a passed Commit, `temper
next` gives three actions in turn: steps that end with `temper report --end`, which prints the report for
the orchestrator to show; `temper report --html`, which writes the page with no question (9.8.0; the run used to ask
whether to write it); then the commit steps. The run's `end_report` records the first two (the CLI keeps it), and
the page is carried by the commit. Every value is escaped, and it never writes inside the plugin's own folder.

## The run summary (9.8.5)

A finished run leaves one line in the project. `temper state clear` appends it to `.temper/runs.jsonl`
(`scripts/run_summary.py`) before it deletes the run's files, and the file keeps its last 200 lines:

```json
{"v": 1, "at": "...", "run": "<run id>", "slug": "...", "command": "temper", "version": "9.8.5", "mode": "interactive",
 "ended": "committed", "asks": {"n": 8, "by_stage": {"plan": 2}, "by_kind": {"gate": 5}},
 "steps_back": [{"from": "review", "to": "build", "n": 1}], "launches": {"by_stage": {"plan": 1}},
 "seconds": 1200, "agent_seconds": 900, "skips": 0}
```

`ended` is `committed` when the commit gate's verdict is PASS, else `cleared`; the line of a trivial request (WP17) has
`"kind": "trivial"` and `ended` `trivial`. The steps back come from
`feedback-loops.json`, which keeps one record a pair of stages: its iteration is the steps back it made. The launches
and the agent seconds come from `usage.json` (the agents recorded with their stage and time); a row of a task gate is
no launch, except the gate of a task an earlier conversation left running, which records that launch with its time.
The skips come from `overrides.json`. The asks are the questions the CLI asked: each time `temper next` (which
`temper go` and the run driver call) answers with a question, `.temper/asked.json` records
`<run id>:<step>:<question id>:<digest of its text>` once, with the stage and the kind, so `next` run twice at one step
counts one and the one question of two groups at one step counts two; the view another command writes records none. A
set of Blocking questions counts one for every four. Follow up dialogs (More options, a reason, a name) are asked by
the carrier and are not seen here, so `asks` counts the CLI's questions, not every dialog a person saw. Both files are
run files git ignores; `runs.jsonl` survives `state init` and `state clear`, and neither decides a gate row.

The end to end scenarios count the dialogs a person saw, the launches by agent type, the steps the CLI took by itself,
the steps back, the hand backs of the run driver and the runs of the whole suite; `scripts/e2e/floor.json` holds those
counts for each scenario and mode, and `bun scripts/e2e/run.ts <mode> <name> --floor scripts/e2e/floor.json` compares
them exactly (`scripts/check_floor.py`).
