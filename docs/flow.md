# The flow: `temper next` and `view.json`

Two outputs of the `temper` CLI carry the whole flow of a run ([ADR 0013](decisions/0013-the-cli-says-what-next-the-mod-only-draws.md)).

With the mod off, every phase works the same; the mod adds the band, the pane and its write guards. Nothing falls back silently.
Both are computed by `scripts/flow.py` from the run's own files; nothing else decides what comes next.

- `temper next --json` prints the next action, with the full view. The orchestrator runs
  `temper go` instead (9.8.0, `scripts/go.py`): it runs the CLI's own steps itself (an `auto` action's
  calls, a `work` action's calls) and prints one compact object at the first agent launch, question,
  steps, wait or end: `{action, stage, say, ran, agents | ask, blocking, gate | steps | tasks}`. It
  never runs an option's calls (the person's answer); a failed call stops it with `action: error`.
  9.8.0, to shrink what every later turn reads again: an agent's gate call is `temper gate <stage> --brief`
  (its failed rows only; the question after it names them); `ask` keeps `question` as it is and, per option,
  only what the answer runs (`label`, `calls`, `steps`, `do`, `stop`, `reason`, `reason_question`,
  `answer_question`); `blocking` is the list of `{question, answer, carry}` below.
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
| `restart` | the `Temper resume` question (Start over or Cancel) for this run and step |
| `blocking` | with `ask`: the Blocking open questions of `intent.md`, asked before the gate question |
| `blocking_asks` | 9.8.0, with `blocking`: each as the session asks it, `{question, answer, carry}`: `question` is the AskUserQuestion entry (header `Question N`, the text before `choices:`, the choices as options, the first marked `Recommended`, then `Carry forward`); `answer` is `temper intent answer '<question>' '{answer}'`, which writes the answer into Decisions (and a `Design:` question's concern in design.md), and `carry` is `temper intent carry '<question>'`. `temper go` prints this list as `blocking` |
| `gate` | with `ask`: the `temper gate` call of the question's stage (Fix is judged by the build gate), run again after a change the person typed at the question |
| `context_map` | at Plan, when `plan.md` has a Context Map: `{intro, file, rows, answer, table}`, the table as plain text |
| `context_check` | at Plan, while the map's `reviewed:` line is not `human` or `auto`: the CLI's own question (header `Temper gate`). 9.8.0: its text names what the plan leaves out and could not find (the map's `ignore` and `gap` lines); the options are `As planned (Recommended)` (runs `temper plan review --answer 'As planned'` then `temper gate plan`), `Include what is left out` (runs `temper plan review --answer '...' --redo`: the answer becomes the person's note and Plan runs again with it), `Something else` (typed) and `Carry forward`, each with the table as its preview; `answer` is the call a typed answer fills (`--redo` too). When the pending check is the plan gate's only failed row, `ask` is this question |
| `guard.adhoc_stage` | the stage a small change window (`temper adhoc open`) was opened at, or `null` |
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
  `temper next --json` again. One exception: an agent's gate call, named `gate` (the last of its `after` calls).
  When it prints `temper gate <stage> -> FAIL`, it has recorded a verdict that `next` asks about, so the action
  goes on; any other failure of it stops the action.
- **`wait`**: tasks are running; `tasks` lists each as `{task, after}`. When their agents were launched
  in this conversation, wait for each result and run its `after` calls; otherwise run the `after` calls now.
- **`auto`**: the CLI's own move: an armed autonomous run, or a step with nothing to decide (9.8.0: the one group of a plan passing, a Build task an earlier task already built in an armed run). Run `calls`, then ask `next` again.
- **`broken`**: the run state does not fit its spec folder; ask the `restart` question.

### Questions

`ask` is `{stage, step, run_id, question, options, more?, accept?}`. `question` is exactly what goes
to the AskUserQuestion tool. Each entry of `options` is the same option with what it means:

| Field | Meaning |
|---|---|
| `label`, `description` | as in the question |
| `move` | `approve`, `arm`, `advance`, `override`, `back`, `accept` (a review finding), `covered` (a Build task an earlier task already built), `keep`, `commitOverride`, `redo`, `pause`, `restart`, or `null` for an option that decides nothing |
| `calls` | the CLI calls this answer makes, in order; `{reason}` is the person's reason. Every `{...}` text stands inside single quotes: put the text there with each `'` written as `'\''`, so a backquote or a `$` in it stays text |
| `steps` | for Commit at a parked run: the commit steps |
| `do` | for an option that decides nothing: what to do, then ask the question again |
| `skill` | 9.8.0, with `do`: the skill the option carries out (`grill-me`, `teach-me`); the mod lets its own questions through while it runs |
| `stop` | the run stops here (Save for later) |
| `reason`, `reason_question` | the move needs the person's reason: their note on the option, or their answer to `reason_question` (any answer but Cancel, typed text included) |

`more` is the second question of "More options"; `accept` is the question of "Accept a finding". Both
have the same shape. A question holds four options at most.

The person decides only by choosing an option. The mod counts an answer only when its header, its
question and its label match exactly what `next` gave for the run and step it is at, so a reworded
question is no answer. A typed message is never a move: it is a change request or a question.

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
pass, the loop back to Plan is recommended, or Save for later when that step is spent, so following the
recommendation always ends.

To read a failure, the session runs `temper output G<n>` (the group's last Validate run: its command, exit,
FAIL lines and recorded output) or `temper output <stage>` (the gate's failed rows and the stage's last failed
run). It is read only; with the mod on, the session may run the CLI but not `printenv` or a test runner.

### The preflight, the setup block and an environment fault (9.8.5)

**The preflight.** `temper gate plan` has a `preflight` row (`scripts/preflight.py`). It runs each distinct Validate,
task Test, Integration and scenario `Test:` command of the plan once, in a detached worktree of HEAD that it removes
after, and sorts each result into one of four classes: `passes`; `needs new code` (the tests of code not written yet
fail on the base; this does not fail the row); `environment fault` (a `temper-setup: FAIL` line, the time limit, the
Maven enforcer's `which is not in the allowed range` reported as `needs JDK <range> (found <version>)`, an unsupported
class file version, `Connection refused`, the command's own program not found, an uncached dependency offline);
`command fault` (`Rule violated for bundle`, `Coverage checks have not been met`, tests that pass followed by
`BUILD FAILURE`, an unknown phase or option). Either fault fails the row, which quotes the last 20 lines of the output
plus every `Failed to execute goal` and `Rule violated` line. Each command has `plan.preflight-timeout` seconds (300).
The result is stored in `.temper/preflight.json` with a key of HEAD, the command texts, the setup block and the time
limit; every later `gate plan` reads it while that key holds, so the commands run once per plan.
`temper plan preflight` runs them again. `plan.preflight-skip: "<reason>"`, which only the person writes, skips the row
(it passes and says `skipped by the person: <reason>`; the plan ledger gets one row); a skip with no text fails it.

**The setup block.** `setup:` in `.claude/temper.config` holds `run:` (one shell line), `env:`, `services:` and
`tools:`. `scripts/run_env.py` runs the line in the same shell before every command the CLI runs (task tests, group
and scenario checks, integrate, Check, the preflight), prints `temper-setup: OK`, and adds the variables; a failing
line prints `temper-setup: FAIL (exit N)` and exits 125. A variable whose name says it holds a credential is never set
or shown. Every agent prompt ends with an `Environment setup` line that carries the run line and the variables. No
block: every command and prompt is as before. The person rarely writes the block: when the preflight or Check fails on
the environment and there is none, the question offers `Add the proposed setup block (Recommended)`, made by
`temper doctor --propose` from the project's own files (`docs/commands.md`).

**An environment fault at a task gate.** When the last run of a task's attempt is a failing GREEN, a RED came before
it, nothing else is wrong, and the output names an environment fault, `temper task gate` prints `ENV: Task N failed on
the environment, not on the code: <reason>`, exits 0, spends no attempt, keeps the worktree and the status `running`,
and marks the task `env_fault` in `groups.json`. `temper next` then asks, in every mode: `Check it again
(Recommended)` (runs `task test N --phase green` and `task gate N --model M`) or `Save for later`. Here a time-out is
the code's, as before: it spends the attempt. Any status move clears the mark.

### Decisions, findings and integrate (9.8.5)

**A Design answer reaches the tasks.** `temper intent answer 'Design: ...'` keeps the answer with the hash `tasks.md` has
at that moment (`.temper/decisions.json`, `scripts/decisions.py`). The Design gate's row `tasks agree with decisions`
fails while `tasks.md` is still that file: the answer may replace a rule a task or a scenario still carries, and the CLI
cannot read which. The Design question then recommends `Loop back to Plan`; the person may instead override with the
reason `The tasks already agree`, which the report shows. Each Build task prompt lists the Design answers, newest
first, as decisions that win over `tasks.md`.

**High findings block.** `review.block-on` defaults to `[critical, high]`. A passed Review with an open finding at
medium or above recommends `Loop back to Build`; both Review questions name the open findings per level
(`open findings: 1 high, 2 medium`).

**Integrate after new commits.** `temper integrate` records the HEAD it passed on. Called again on a PASS, it runs the
whole Integration command again when HEAD moved since (a fix pass committed), records the new verdict, then the
scenario tests, as before.

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
back to Plan (or Save for later), and says the cause is the plan's command or the environment. "Run the gate again with
twice the time" is recommended only at the first time-out; later it is offered, not recommended.

**SETUP at Check.** When the suite or the acceptance run of Check fails on its environment (a project marker
`<script>: SETUP: <reason>`, or the preflight's environment rule: a JDK out of range, `Connection refused`, a failed
setup line), Check records a `setup fault: <reason>` row beside the red suite row, so the gate still fails. The
question says `SETUP`, offers `Repair the environment and run again (Recommended)` first, and never recommends a loop
back. Rows no longer carry the JVM's start text (`Picked up JAVA_TOOL_OPTIONS`, the `sun.misc.Unsafe` warnings).

**Overrides at the commit gate.** `Override and commit` clears a failed stage gate the commit gate names. It never
cleared the commit gate's own rows (blast radius, scope, park-on-touch), so it is no longer offered for them; the question
says what to change instead, and `Add to plan` stays for files outside the plan.

**Questions.** A question has four options at most; the CLI puts the rest under `More options`. The Context check
accepts an answer of up to 2000 characters (the `Include what is left out` option carries the whole list); plan.md
shows its first 100.

## `.temper/view.json`

| Field | Meaning |
|---|---|
| `version` | 1 |
| `written` | when the CLI wrote it |
| `run` | `{id, step, slug, title, command, stage, mode, complexity, branch, spec, feature, parked}` or `null` |
| `stages` | `[{id, label, mark, verdict, failed, skipped?}]`; `mark` is `passed`, `failed`, `skipped`, `here` or `todo`; `failed` is the failed rows of its last check; `skipped` is `{reason, by}` |
| `status` | one sentence: where the run is and who it waits for |
| `next` | `{action, stage, say, calls, steps, agents}` of `temper next` (`action` is `error` when `next` itself failed, with the error in `say`); `calls` for a `work` or `auto` action, `steps` for a `work` action (the CLI's own moves, which the mod lets through); `agents` (9.8.0) for a `work` action, each `{type, model, prompt}`, and while the run stays at the same stage, every agent named there before (an agent's `before` call, a Build task's `task start`, changes the action before the agent is launched), kept in `.temper/agents-named.json` so a lost or rewritten view does not forget them: the only agents the mod lets the session launch |
| `ask` | the current question, as `next` gives it, or `null` |
| `blocking` | the Blocking open questions |
| `blocking_asks` | 9.8.0: the same questions as the session asks them (see `temper next`); the mod lets the session ask these |
| `restart` | the `Temper resume` question |
| `drift` | the `Scope drift` question's header, the first line prefix (`Outside the plan:`) and its three options |
| `guard` | what the guard needs: `{stage, spec, slug, fix_run, grouped, armed, autonomy_enabled, plan_files, step, run_id, trivial_exit, prefix}`; `plan_files` are the files the person approved at the plan gate (before it, the plan's files as they are); `prefix` is the project's folder from the top of its git repository (`packages/app/`, or empty) |
| `plan` | `{approved, files, groups: [{id, title, files}]}` |
| `fresh` | 9.7.6: the fresh review of the plan, `null` when it does not apply: `{paraphrase, missing, stale, findings: [{id, severity, lens, claim, state, cite}]}`; `missing` names each lens and reviewer with no completion row (`readiness A`); `state` is `open`, `resolved`, `accepted`, `contested` or `escalated`; `cite` is a contest's checked citation |
| `build` | `{groups: [{id, title, status, verdict, tasks: [{n, title, files, state, model, attempts}]}], integration}`; a task's `state` is `waiting`, `running`, `red`, `green`, `pass`, `fail` or `parked` |
| `findings` | `[{id, severity, confidence, claim, file, line, state, label}]`; `confidence` is the reviewer's 0 to 1 (`temper evidence add --confidence`) or `null`; `file` and `line` come from a claim that starts `file:line`; `state` is `open`, `resolved` or `accepted` |
| `checks` | the rows of the Check gate: `[{name, pass, detail}]` |
| `check_markers` | `[{name, state, detail, value?, lines}]` for compile, tests, coverage, lint and security; `state` is `pass`, `fail`, `info` or `none` |
| `criteria` | `[{id, priority, status, text, evidence}]` of the intent's success criteria |
| `loops` | `[{from, to, reason, iteration, max, at}]` |
| `skips` | `[{stage, reason, by}]` |
| `usage` | `{ms, by_stage, by_model}` from `temper usage add`; each of `by_stage` and `by_model` maps a name to `{ms, runs}`, and a stage also to `models` (the models its launches asked for). The time is the total Claude Code gives for each agent; since 9.7.4 no token count is recorded |
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
