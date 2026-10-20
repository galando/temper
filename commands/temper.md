---
description: "Unified SDLC command: intent → plan → design? → build → review → check → commit, gated by the temper CLI"
argument-hint: "<feature-description>"
---

# Temper

**First output.** Look at your system prompt for a line that starts with `Temper enforcement:`. With
none, your first line is exactly `Temper enforcement is off here (no mods support); continuing with
prompt based phases.` With `Temper enforcement: off (UI only)`, it is exactly `Temper enforcement is
off (turned off by the user); continuing with prompt based phases.` With `active`, say nothing about
it. Say it once per conversation; it is never an error. A stage agent never sees that line, so never
ask one to say it.

The temper CLI is `${CLAUDE_PLUGIN_ROOT}/scripts/temper`. It decides every step of a run:
`${CLAUDE_PLUGIN_ROOT}/scripts/temper next --json` prints what to do next, and this page only does
that (its format: `${CLAUDE_PLUGIN_ROOT}/docs/flow.md`). Every path it prints is written out in full:
run it exactly as printed. Never compute a gate, an option or a next stage yourself.

## Arguments

When the first word is one of these, do this and start no run. Any other first word begins a
feature description.

| Word | What to do |
|---|---|
| `status` | Print `${CLAUDE_PLUGIN_ROOT}/scripts/temper status` and the `say` of `temper next --json`. |
| `report`, `timeline` | Print `${CLAUDE_PLUGIN_ROOT}/scripts/temper report`. |
| `help` | List these words with one line each. |
| `approve`, `next`, `back`, `override`, `accept`, `drift` | A wish, never a decision: run the loop below. When it reaches a question, ask it as given; the person chooses there. |
| `pr` | Write a pull request description from `${CLAUDE_PLUGIN_ROOT}/scripts/temper report` (the verdicts), `.temper/overrides.json` (each skip with its reason), `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence list --stage review` (each accepted finding with its reason), `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence list --stage build` (the drift answers) and the `loops` of `.temper/view.json`. |
| `discuss <text>` | The person's message at the current question: answer it; if it asks for a change, make it, run the action's `gate` call, and ask the question again. It moves nothing. |
| `mode`, `enforcement`, `pane` | These belong to the Temper mod. Without it, say they are not available here. |

## Start

Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper next --json`.

- When it lists `setup`, run those calls first, each once, and say in one line what was set up. When
  `scripts/guards/install.sh` exits non zero, show its `FAIL` line (or its whole output in a fenced
  block), the lines it printed between BEGIN and END in a fenced block, and its `Hint:` line, as
  written; then go on: the commit gate is not installed, and Temper says so. A `FAIL: run temper from a
  project folder` line from any call means stop and show it.
- When `action` is `none`: with no feature in the arguments, say "No run is active. Start one with
  `/temper:temper "<feature>"`." and stop. Otherwise pick the slug: when a folder in the project's
  `.temper/specs` already holds an `intent.md` for this feature, its name; else a short name of
  letters, digits, `.`, `_` or `-` (a ticket key keeps its case, as in `PROJ-123-login`). Run
  `${CLAUDE_PLUGIN_ROOT}/scripts/temper state init {slug} --feature '{the feature as the person typed it}'`
  and go on with the loop.
- When a run is active and the arguments name a different feature, ask its `restart` question. On
  "Start over", run its calls, then start the new run as above. On "Cancel", go on with the loop.

## The loop

Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper next --json` and do what its `action` says. Then run it
again. Stop only where this section says so. When it lists `setup`, run those calls first, each once.

- **`work`**: say its `say` in one line (it names the model each agent runs on), then run each of
  `calls`, launch each agent of `agents`, all in one turn, then do each of `steps` in order.
  - An agent: first run its `before` calls. Then launch it with the Agent tool: `subagent_type` its
    `type` (when that type is not offered, the general purpose agent), `model` its `model`, its
    `prompt` exactly, and `run_in_background: false` where the tool takes it, so the run goes on the
    moment the agent returns; the agents of one action go in one message, so they still run at once.
    When it returns, print the box it returns verbatim, then run its `after` calls: `{tokens}` and `{ms}`
    come from the Agent result, or, for an agent run in the background, from the usage of its completion
    notice (`subagent_tokens`, `duration_ms`), and are `none` only when neither gave a value. Then go on
    with the loop in the same turn.
  - **An agent the tool runs in the background anyway:** say in one line what is running, that the run
    goes on when it returns, that if it waits after the agent finished, any message moves it on, and
    that `/temper:init` can keep agents in the foreground in this project.
    Its return is the first of its report (a message from the agent) and its completion notice: in the
    turn that starts, print its box, run its `after` calls and go on with the loop. At the report, fill
    `{tokens}` and `{ms}` from the notice when it came first, else with `none`. Never wait for the notice;
    Claude Code may start no turn for it. Never end a turn with an agent's `after` calls not run: nothing
    else moves the run.
  - A `steps` entry is a command to run as written, or a short instruction to carry out; `{...}` in it
    is yours to fill (a commit message that says what the feature does).
  - **The report.** When a call prints the run's report (`temper report --end`), copy what it printed into
    your reply, as it is, in a code block, before the next call: the person does not see a Bash call's
    output. Then run `next`: it asks whether to write the report as an HTML page too.
  - **Filling a placeholder.** Every `{...}` text in a call or a step stands inside single quotes. Put the
    text there as it is, with each `'` in it written as `'\''`, so a backquote or a `$` in it stays text. Run `git commit` in a Bash call
    of its own, after the `git add` call.
- **`ask`**: when it has `blocking`, ask those first (see "Every question"). Then ask `ask.question`
  with AskUserQuestion exactly as given, and do what the chosen option of `ask.options` says: run its
  `calls`, then its `steps`; or, for an option with `do`, do what it says, then ask the same question
  again unless it says what comes next;
  "More options" asks `ask.more.question`, "Accept a finding" asks `ask.accept.question`. An option
  with `stop` ends the turn: the run is saved.
- **`wait`**: tasks are running. For a task whose agent you launched in this conversation, wait for
  its result, then run its `after` calls. Otherwise (a new conversation) run its `after` calls now.
- **`auto`**: an armed run moves by itself: run its `calls`. The person is not watching: never ask
  "Shall I...?"; the only stop is a park, which `next` turns into a question.
- **`broken`**: say its `say` in one line and ask its `restart` question.
- **`none`** after a commit: the steps printed the report before they cleared the run (a report printed
  now is empty); when the person asked for the page, it is `report.html` in its spec folder. Say where it
  is and stop.

Run the calls of one action in one Bash call, one per line, when they are only `temper` calls; a
`git` call goes in a call of its own.

## Every question

- **Exactly as given.** The header, the question, every option label and description, in the order
  given, four options at most. With the Temper mod, an answer counts only when it matches the question
  the CLI wrote for the step the run is at; a reworded question is no answer, and the call it would
  allow is refused. Never add "(Recommended)" or any other word.
- **The person decides.** Only the person's choice in the dialog is a decision. Never choose for
  them, never answer a question for them, and never choose "Start over" yourself.
- **Reasons.** An option with `reason` needs the person's reason: their note on the option, or else
  ask its `reason_question` exactly as given. Any answer to it but "Cancel" is the reason, typed text
  included; "Cancel" asks the first question again. Put the reason in place of `{reason}`, as "Filling a
  placeholder" says.
- **Typed text.** An answer typed in "Other" (not to a reason question), or a message the person
  writes at a question, is a change request or a question: answer it; for a change, make it, run the
  action's `gate` call when it has one, and ask again. It never moves the run.
- **Blocking questions** (the `blocking` list): ask them in one AskUserQuestion call, one question
  each, with the question's choices as options, the recommended one first, three at most, and a last
  option "Carry forward". Write each answer into intent.md's `### Decisions` and take the question out
  of Open Questions. Then run the action's `gate` call and run `next` again.
  Never list them as text to answer by typing.
- **A refused call.** When the mod or the CLI refuses a call an answer allowed, run it once more; when
  it is refused again, say so in one line and ask the question again.

## Agents

- **Intent returns TRIVIAL** (a typo or a one line change with no product problem): say "trivial,
  handling directly, no pipeline" in one line, run `${CLAUDE_PLUGIN_ROOT}/scripts/temper state clear`
  at once, make the change, run the project's tests, and commit normally. If it turns out not to be
  trivial, stop and start `/temper:temper` again.
- **A panel with a `DRIFT` section** (Build's fix pass): before anything else, ask the person about
  each row, one AskUserQuestion per row: header `Scope drift`, a question whose first line is
  `Outside the plan: {path}`, then `Why: {why}` and `Change: {change}` lines, and the options
  "Add to plan", "Revert" and "Allow once". Record each answer with
  `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence add --stage build --phase feedback --claim 'drift {path}: {choice}: {why}'`
  (for "Add to plan", also add the file to plan.md's Files to Modify table), then launch the same
  agent again with one `Drift decision: {path}: {add|revert|allow-once}` line per answer. A drift is
  never answered for the person, in an armed run either. A typed answer is a change request.
- **An agent that fails or blocks**: show what it returned and ask the current question again.

## Entering at a stage (the stage commands)

`/temper:plan`, `/temper:design`, `/temper:build`, `/temper:review` and `/temper:check` are doors into
this flow. Each reads this page and enters at its stage, with its arguments as the feature (Plan) or
the spec folder's name.

1. **A run is active:** the run is where the CLI says, and a door never moves it. When it is at
   another stage, say in one line where it is ("The run is at Review."). Then run the loop.
2. **No run, the Plan door:** start a run for the feature as Start says; Intent comes first.
3. **No run, a later door:** the run is for the folder in `.temper/specs` that holds `plan.md` and
   `tasks.md` (the one the arguments name, the only one, or else ask the person; with none, say in
   one line that this stage needs a planned feature and that `/temper:temper "<feature>"` starts one,
   and stop). Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper state init {slug} --enter {stage}` (it takes the
   tier from the Complexity line of `plan.md`, else of `intent.md`).
   The Design door enters at Build when the run has no Design stage, and says so. Then run the loop:
   the stages before the door's are checked and asked, not run again; the question of one whose check
   fails offers to run it.

The stage hooks mark only `/temper:intent`, which captures a draft on its own.

## When the CLI refuses

- **Exit 3:** a path the CLI keeps run state in is a symlink. Stop, show its one line reason, and
  wait for the person. Never remove, replace or follow the link yourself.
- **`FAIL:` from a move:** the CLI refuses to leave a stage whose check failed unless the person
  skipped it, and refuses a stage out of order. Never work around it: run `next` and ask its question.
