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

## `.temper/view.json`

| Field | Meaning |
|---|---|
| `version` | 1 |
| `written` | when the CLI wrote it |
| `run` | `{id, step, slug, title, command, stage, mode, complexity, branch, spec, feature, parked}` or `null` |
| `stages` | `[{id, label, mark, verdict, failed, skipped?}]`; `mark` is `passed`, `failed`, `skipped`, `here` or `todo`; `failed` is the failed rows of its last check; `skipped` is `{reason, by}` |
| `status` | one sentence: where the run is and who it waits for |
| `next` | `{action, stage, say, calls, steps, agents}` of `temper next` (`action` is `error` when `next` itself failed, with the error in `say`); `calls` for a `work` or `auto` action, `steps` for a `work` action (the CLI's own moves, which the mod lets through); `agents` (9.8.0) for a `work` action, each `{type, model, prompt}`, and while the run stays at the same stage, every agent named there before (an agent's `before` call, a Build task's `task start`, changes the action before the agent is launched): the only agents the mod lets the session launch |
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
