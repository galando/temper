# The Temper mod

The mod makes the Temper stages real inside Claude Code. It needs Claude Code 2.1.287 or later.

The mod does four things:

- It refuses a write that does not belong to the current stage.
- It sends `git commit` to the hook. The native `pre-commit` hook refuses `git commit` until Check
  passes; the mod refuses `--no-verify` and a changed hooks path. A commit the hook does not check,
  such as a merge, is a known limit ([what the guard does not see](#what-the-guard-checks-and-what-it-does-not)).
- It refuses a step only you may take (leaving Intent or Plan, a skip, a step back, accepting a
  finding, arming autonomy) unless you chose it in the gate question.
- It draws the run: the stage bar above the prompt and the pane, and keeps a report of the run
  (`/temper:temper report`).

[What the mod reads and writes](#what-the-mod-reads-and-writes) lists every file, hook and call of the mod.

## One flow

Temper asks you at each gate with Claude Code's question dialog, header `Temper gate`, exactly as
`temper next --json` gives the question. This is the same with the mod and without it, in every mode. You
decide there and only there: the mod reads your answer from the dialog's result, counts it only when the
header, the question and the option you chose match what the CLI wrote for the step the run is at, and lets
through the calls that option maps to, word for word. A reworded question is no answer. Once the run moves
on, the answer is spent. A word you type, such as `/temper:temper approve`, is a wish: Temper asks the
question, and you decide there.

The CLI decides where the run is and every verdict, and writes `.temper/view.json` after every change: the
mod reads that one file of the CLI's and nothing else. It keeps no state of its own about the run. Design
notes are in [ADR 0013](decisions/0013-the-cli-says-what-next-the-mod-only-draws.md).

## The three modes

Use `/temper:temper mode` to set how much Temper draws. The rules and the questions are the same in every mode.

- **Full** draws the bar (the stage timeline, the status, its details and one button), the pane, toasts
  and a status line under each answer.
- **Minimal** draws the stage timeline only.
- **Off** draws nothing. A write outside the stage is still refused.

A toast confirms a change to enforcement in every mode. The same mod runs in the desktop app (Code tab).

## The bar

Everything the mod draws comes from `.temper/view.json` (ADR 0013), so it shows what the CLI knows.

The bar shows where the run is: each stage with its result (passed, failed, skipped, here, to come), the
loops back with their reasons, the time and the tokens of the run, one sentence of status, and the details
of the stage (the groups and tasks of Build, the open findings of Review, the failed checks). It has one
button, and it decides nothing:

- **Go on** (key `1`, while Claude is not working) takes the run up again: it runs `/temper:temper`, and
  Claude asks the gate question again.

The pane (`/temper:temper pane`) shows the whole run on one card: the intent, the stages with your skips
and the loops back, the plan's files by Build group as you approved them, the Build grid (each task's
state, waiting, running, RED, GREEN, PASS, FAIL or parked, with its model and retries), the Review
findings (severity, confidence, file and line, open, resolved or accepted), the Check markers (compile,
tests, coverage, lint, security, with the lines that failed), the acceptance criteria with their evidence,
and your decisions. It has no button. `minimal` draws the stages only; `off` draws nothing.

At the commit the run writes its report as one page, `report.html` in the spec folder
(`temper report --html`), from the same view: the stages, loops and skips with their reasons, the plan,
the Build grid, the findings, the Check markers, the criteria with evidence, and the time and tokens by
stage and by model. The
commit carries it, so the page goes with the change.

## Each stage

| Stage | Writes allowed |
|---|---|
| Intent | `intent.md` only |
| Plan, Design | `intent.md`, `plan.md`, `tasks.md`, `design.md` and new decision records |
| Build | The plan's files, test files and the spec folder. Another file waits for your answer to the Scope drift question. |
| Review | The spec folder only |
| Check | The spec folder only |

A step back is a loop: you choose "Loop back to {stage}" with a reason, and the run does that stage
again. "Save for later" stops the run where it is; every rule still holds. To work without the
rules for a while, turn enforcement off (`/temper:temper enforcement off`).

Build is held to the plan you approved: the mod keeps the plan's files with your approval, so a
`plan.md` edited during Build does not widen it. Your "Add to plan" answers to Scope drift do.

## Scope drift

Sometimes a task needs a file that the plan does not list. Then Claude asks you first. The question
shows the file, why the task needs it and the change. You choose one answer:

- **Add to plan.** The file becomes part of the plan.
- **Revert.** The task continues without the file.
- **Allow once.** Claude makes only this change. The why goes into the report as the reason.

This question is the same with the mod and without it. The mod also refuses the write until you answer.
The mod reads your answer from the result of the question, not from what Claude sends.

## Where enforcement works

The mod needs Claude Code 2.1.287 or later. This section shows where enforcement works, where it does
not work and what is not verified.

### Older versions, or no mod

Before 2.1.287 the mod does nothing, and the skills say one time that enforcement is off. The same
applies when the mod does not load. You keep the full pipeline:

- Every stage as a prompt.
- Every CLI gate verdict.
- The native `pre-commit` hook.
- The evidence ledger.

You lose the live refusals, the bar, the pane and the mod's report; `temper report` and the
report page written at the commit stay. This was checked on 2.1.200 and 2.1.259.

The settings declare no picker options. This is intentional: a settings field with options stops the
plugin from loading on versions before 2.1.271.

### Surfaces

| Surface | Refusals (hooks) | Drawing |
|---|---|---|
| `claude` in a terminal, also in editor terminals | yes | yes |
| Desktop app, Code tab | yes | yes, but not the elements for the terminal only |
| Desktop app, WSL session | no (plugins are not available) | no |
| VS Code extension chat panel | yes | no |
| `claude -p` and the Agent SDK | yes. With enforcement on, a run stops at the first gate, because only a person can answer the gate question. With enforcement off nothing checks that a person answered, so Claude may go on by itself. | no |
| Remote Control (phone or web) | yes, on your machine | only in the terminal of your machine |
| Cloud sessions (claude.ai/code) | yes, if server managed settings bring the plugin (most sessions get the stages as prompts) | no |
| claude.ai chat, Cowork | not documented, so not verified | not documented |
| GitHub Actions | not documented. It runs `claude -p`, so probably yes (not verified). | no |

### Early access API

The mods API of Claude Code is early access and can change. The adapter is thin, and the rules are
plain tested functions. CI runs the test suite on Claude Code 2.1.287.

### Organization policy

An administrator can turn off parts of the mod:

- `allowManagedModsOnly` is an option of the built in `sec-default` guard. When it is on, the Temper mod
  does not load unless the organization ships Temper. Commands, skills, agents and hooks still load.
- `allowManagedHooksOnly` also stops hooks from plugins. The classic Temper hooks then stop too, unless
  the plugin is force enabled.
- `disableAllHooks` in managed settings stops every mod and every settings hook.
- A managed guard that runs first and refuses a call wins, so two guards never conflict. This was
  tested only with a simulated `sec-default`, because the real guard needs managed settings on the machine.

### You can turn it off

Anyone can disable the plugin or run `/temper:temper enforcement off`. The mod guards a workflow for
honest use. It is not a security boundary.

### What the guard checks, and what it does not

Temper is not a sandbox. The guard keeps a cooperating Claude on the path and makes a skip visible; a
Claude set on getting around a gate through Bash can do it. The hard guarantees are the editing tools
(Write, Edit, MultiEdit, NotebookEdit) and the native `pre-commit` hook for `git commit`.

The guard has three jobs ([ADR 0013](decisions/0013-the-cli-says-what-next-the-mod-only-draws.md)):

- **The person's answer.** A temper call only the person may cause (leaving Intent or Plan, a skip, a
  step back, accepting a finding, arming autonomy, keeping an agent's commits, overriding the commit
  gate, starting over during a run) needs your answer in the question dialog, at the run and the step
  the CLI is at. The guard finds the call when it is written out in the command
  (`scripts/temper ...`).
- **Temper's own files.** The CLI's files in `.temper` (the gates, the run state, the evidence ledger,
  the loop counter, the view), and during a run `.claude/temper.config` and the git hooks, are written by
  neither the editing tools nor a plain Bash write (a redirect, or `rm`, `mv`, `cp`, `tee`, `sed -i`
  and the like naming the file, its folder, or a glob that reaches it). Each stage allows its own
  writes by the editing tools.
- **The native hook.** While a run is active, `--no-verify` (or an abbreviation git takes), `-n`, and a
  change of `core.hooksPath` (also by removing the `core` section, by including another config file,
  or by writing `.git/config.worktree`) are refused.

The guard reads a Bash command as text: it splits it into statements and words and honours quotes,
joins a line ended by a backslash, looks past shell keywords (`then`, `do`, `{`, `!`) and the programs
that run the next word (`sudo`, `env`, `nice`, `timeout` and the like), and expands a brace list
(`{a,b}`). It does not follow variables, substitutions, `cd` or links, and it does not read the program
another program runs. These are still possible, and listed as known limits in the mod's tests:

- A call or a path in a variable, or built at run time by a program.
- A call in a string another program runs (`sh -c`, `eval`, `xargs`, `perl -e`), or in a here document
  a shell reads.
- A link or a script that an earlier call made, or a script that is already on disk.
- A write after a `cd`, the names inside a patch or an archive, and a program the guard does not know
  as a writer.
- A commit the native hook does not check (`git merge`, `cherry-pick`, `revert`, git plumbing), a git
  command that runs a command of its own, and a git alias of yours.
- `TEMPER_DIR` and `TEMPER_CONFIG`, which point the CLI at other files.

MCP and PowerShell file tools are not checked.

If the guard itself fails while it checks a Bash command (an error, or it runs out of time) and a run
is active, it refuses that command rather than pass a command it could not check. Run it again; if it
keeps failing, you can turn enforcement off.

A decision comes from the result of the question dialog, after you chose. Its authenticity depends on
Claude Code. Claude writes the question and its options, so read the option you pick.

If a run's `view.json` is hidden or removed, the run stays enforced from the last known state.
This continues until you turn enforcement off. The exception is the TRIVIAL exit (`state clear` at
Intent before the run ever moved and before Claude wrote an intent), which ends the run. Claude
decides that a change is trivial; it tells you so in one line, and you are not asked.

The rules hold through the Commit stage too, until the Commit steps clear the run. A `/temper:fix`
run is not judged move by move (its own page asks every gate), but the native hook stays on there
too: `--no-verify`, a changed hooks path, and a write to the config or the git hooks are refused.

A `Temper enforcement:` line can also be in any file that Claude can read.
An injected copy can only hide a question. It cannot advance a stage, because each advance needs your
answer at that step or a passed check.

A plain `git commit` goes to the native `pre-commit` hook in every stage, and the hook decides. A spec
only commit passes it mid run, as does a Build checkpoint commit with a green test run.

## What the mod reads and writes

Mods are not sandboxed, so this is the full list. The mod makes no network, `process` or `env` call
and starts no agent. Its one tool call is Claude Code's question dialog (`$.ui.ask`, AskUserQuestion),
to ask you for a mode. CI fails on a call outside `scripts/check-mod-calls.sh`.

- **Reads:** `.temper/view.json`, the one file the CLI writes for it (ADR 0013; its fields are in
  [The flow](flow.md)). To find the project it stats the session folder and looks for `.temper/view.json` there
  and in up to 11 folders above it. It reads its
  settings, store and state and the Claude Code version. When you change the mode or enforcement it reads the
  `/config` list (every row) to find its two rows and whether your organization locked them. When `reviewerModel` is
  set it reads the session's agent list and keeps only the id and type, to find the Temper review agent.
- **Writes no file itself.** Your decisions (the answers you gave in the question dialogs, each with the run
  id and the step it counts at, for the last 40 runs), the report and whether you were
  asked for a mode stay in its plugin store, a JSON file in your Claude Code settings folder.
- **Session state:** for its drawing it keeps the bar's view (run title, stage, criteria, findings),
  the mode and the project folder in `$.state`, which other plugins can read.
- **Configuration and environment it sets:** no environment variable. Only `temper.uiMode` (you type
  `/temper:temper mode`, or answer the mode question your first `/temper:temper` or a bare `mode` asks)
  and `temper.enforcement` (you type `/temper:temper enforcement`). A row your organization locked stays.
- **Slash commands it runs, and when:** only `/temper:temper` with no words, written as fixed text, and only
  when you press Go on. No command is built from data.
- **What it puts in the prompts it submits:** nothing. It fills no prompt and suggests none. Apart from the
  refusals below and its state, it sends no text out.
- **System prompt:** `prompt.compose` adds one section, `temper:phase`, to each request: enforcement on
  or off, the stage (and whether saved for later), run title, passed criteria, the next step (the question to ask
  exactly as `temper next --json` gives it, the answer to carry out, or what `temper next --json` says), a line
  when the mod cannot read the run, and
  one fixed line (answer a message at a gate; after a requested change, run the gate again and ask again).
- **Hooks:**
  - `tool.call` sees every tool call, a subagent's too. It reads the path of Write, Edit, MultiEdit and NotebookEdit
    and the text of Bash, then refuses the call with a fixed reason and next step for Claude (a next step that runs
    `scripts/temper` gives the plugin folder's path), or passes it on and returns its result unchanged; it never
    answers for a tool. After an AskUserQuestion call it reads your answer from the dialog's result, matched exactly
    against the question view.json holds: a `Temper gate` option (with your reason, your note or your answer to the
    reason question, when the option needs one), a `Temper resume` Start over, or a `Scope drift` answer (Add to plan,
    Revert or Allow once). It keeps it, with the calls the option maps to, for the run and the step the CLI is at.
  - `command.run` handles only `/temper:temper`. It answers `status`, `timeline`, `help`, `report`, `mode`,
    `enforcement` and `pane`. A word that changes what is drawn or enforced is refused unless you
    typed it in your prompt box. Every other word (`approve`, `back`, `override` and the rest) and any other command
    pass on unchanged, and the mod records nothing from them.
  - `session.start` and `classic.SessionStart` find the project root and load the run; in full mode
    `session.start` also opens the pane during a run. Both return what the engine gives them: no
    context, instruction or setting is added.
  - `turn.step` sets the model and effort from `phaseModels` and the Temper review agent's model from `reviewerModel`;
    empty options change nothing. `attribution.text` adds one Temper line to a pull request description during a run
    when `prAttribution` is on. `turn.complete` adds a one line status under an answer in full mode.
  - `ui.render` draws the bar, pane, spinner word, prompt hint and a line above Claude's question
    dialog, which stays unchanged. `ui.close` notes a closed pane.
- **Other:** toasts tell a stage change (full mode), an enforcement change and the default mode when you dismiss
  the mode question. The CLI replaces view.json whole, so the mod never reads half of it.
- **The tests never run in your session.** The mod's test suite runs only under `claude plugin test`; the plugin never
  loads it. Every `$` call there (`$.session.start`, `$.ui.mount`, `$.tool.call`, `$.agent.spawn` and the rest) goes
  to Claude Code's own test kit (`claude-code/testing`), not another plugin. Tests hand Bash, Write, Edit,
  NotebookEdit and Read calls to the guard. Temper's fake engine answers each tool call, question, prompt,
  `config.set`, `fs.write` and `command.run` with a stub and keeps what the mod sent in memory for the test to check,
  so nothing runs and nothing leaves the test. One test spawns a stub review agent (prompt `review it`, type
  `temper:temper-review`, no model); a stub answers it, so no agent runs, and the mod leaves the spawn unchanged.
- **Tests, lint, git and `scripts/temper`** run as prompts to Claude with its normal permissions. Auto
  mode may refuse a skip as a gate bypass. Allow that one `scripts/temper override` command, or run it
  yourself with `!`.
