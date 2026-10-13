# The Temper mod

The mod makes the Temper stages real inside Claude Code. It needs Claude Code 2.1.287 or later.

The mod does four things:

- It refuses a write that does not belong to the current stage.
- It keeps the commit gate whole. The native `pre-commit` hook refuses `git commit` until Check passes;
  the mod refuses what would go around that hook (`--no-verify`, a changed hooks path, and a commit the
  hook does not check, such as a merge).
- It draws the run: the stage bar above the prompt and the pane.
- It keeps a report of the run. Run `/temper:temper report` to see it.

[What the mod reads and writes](#what-the-mod-reads-and-writes) lists every file, hook and call of the mod.

## One flow

Temper asks you at each gate with Claude Code's question dialog, header `Temper gate`. This is the same
with the mod and without it, in every mode. You decide there and only there: the mod reads your answer
from the dialog's result and lets through what that answer allows, at the step the run is at. Once the
run moves on, the answer is spent. A word you type, such as `/temper:temper approve`, is a wish: Temper
asks the question with that move first, and you confirm it there.

The CLI decides where the run is (`.temper/build-state.json`), and every verdict. The mod keeps no state
of its own about the run. Design notes are in
[ADR 0012](decisions/0012-the-cli-decides-the-dialog-asks-the-mod-shows.md).

## The three modes

Use `/temper:temper mode` to set how much Temper draws. The rules and the questions are the same in every mode.

- **Full** draws the bar (the stage timeline, the status, its details and two buttons), the pane, toasts
  and a status line under each answer.
- **Minimal** draws the stage timeline only.
- **Off** draws nothing. A write outside the stage is still refused.

A toast confirms a change to enforcement in every mode. The same mod runs in the desktop app (Code tab).

## The bar

The bar shows where the run is: each stage with its result (passed, failed, skipped, here, to come),
one sentence of status, and the details of the stage (the groups and tasks of Build, the open findings of
Review, the failed checks). It has one button, and it decides nothing:

- **Go on** (key `1`, while Claude is not working) takes the run up again: it runs `/temper:temper`, and
  Claude asks the gate question again.

The pane (`/temper:temper pane`) shows the whole run on one card: the intent and its criteria, the
stages, the status, the groups and tasks, the findings, the loops and your decisions. It has no button
that decides.

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

You lose the live refusals, the bar and the report. This was checked on 2.1.200 and 2.1.259.

The settings declare no picker options. This is intentional: a settings field with options stops the
plugin from loading on versions before 2.1.271.

### Surfaces

| Surface | Refusals (hooks) | Drawing |
|---|---|---|
| `claude` in a terminal, also in editor terminals | yes | yes |
| Desktop app, Code tab | yes | yes, but not the elements for the terminal only |
| Desktop app, WSL session | no (plugins are not available) | no |
| VS Code extension chat panel | yes | no |
| `claude -p` and the Agent SDK | yes. With enforcement on, a run stops at the first gate, because only a person can answer the gate question. With enforcement off, it continues. | no |
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

### Bash is best effort

The hard guarantee covers the tool layer (Write, Edit, NotebookEdit, MultiEdit) and the native
`pre-commit` hook for `git commit`.

For Bash, the mod does these steps:

- It resolves variables in order.
- It expands braces.
- It follows `cd`.
- It refuses a write that it cannot check when the command names Temper state.
- It refuses, while a run is active, a git command that runs a command of its own (`rebase --exec`,
  `bisect run`, `submodule foreach`, `filter-branch`, an editor, pager or diff program set for the
  call), and git plumbing that makes or moves a commit without `git commit` (`update-ref`,
  `stash create`, `stash store`, `replace`).
- It refuses any use of Claude Code's plugin data folder (`~/.claude/plugins/data/`), where it keeps
  your decisions, while a run is active.

Thus common tricks fail closed. But the mod cannot see a variable that an earlier call or a profile
set. A Bash command can still write ordinary source files. MCP file tools are not covered. The native
`pre-commit` hook is the backstop.

A decision comes from the result of the question dialog, after you chose. Its authenticity depends on
Claude Code. Claude writes the question and its options, so read the option you pick.

### Limits

While a run is active, the mod refuses a Bash command that names the Temper script and hides what it
runs. It refuses the command even when the text shows no decision word. Examples:

- `$(...)`, `${...}`, `$'...'` and a here-string.
- A script that the same command writes and starts.
- A launcher such as `env -S`, `make`, `awk` or `find -exec`.

The mod also refuses a shell, or a builtin that runs text as commands (such as `source`), when the
program is not in the text. Examples: a pipe from an unknown command, a file on stdin, or a word that
quotes, `$` or braces split.

A command that names a file of the run must be a plain read. These files are `gates.json`,
`build-state.json`, the evidence ledger, `.claude/temper.config` and the hooks of git and Temper. The mod
refuses `chmod`, `find -delete`, `git clean` and `--no-verify`.

If a run's `build-state.json` is hidden or removed, the run stays enforced from the last known state.
This continues until you turn enforcement off. The exception is the TRIVIAL exit (`state clear` at
Intent before the run ever moved and before Claude wrote an intent), which ends the run. Claude
decides that a change is trivial; it tells you so in one line, and you are not asked.

The rules hold through the Commit stage too, until the Commit steps clear the run. A `/temper:fix`
run is not judged move by move (its own page asks every gate), but nothing goes around the native
hook there either: `--no-verify`, a changed hooks path, a commit the hook does not check, and a write
to the config or the git hooks are refused.

A text reader cannot see some shell tricks. These are still possible:

- A link or a script that an earlier call made.
- A script that is already on disk and starts later.
- A program that builds the script name or a path at run time.
- The names inside a patch or an archive.
- Everyday git that moves a branch to another commit (`reset`, `checkout -B`, `rebase`), or a commit
  made in a worktree outside the project, where no run is: the native hook only sees `git commit` in
  the project.

MCP and PowerShell file tools are not checked. Thus the hard guarantees are the editing tools and the
native `pre-commit` hook, not the Bash reader.

A `Temper enforcement:` line can also be in any file that Claude can read.
An injected copy can only hide a question. It cannot advance a stage, because each advance needs your
answer at that step or a passed check.

A plain `git commit` goes to the native `pre-commit` hook in every stage, and the hook decides. A spec
only commit passes it mid run, as does a Build checkpoint commit with a green test run.

## What the mod reads and writes

Mods are not sandboxed, so this is the full list. The mod makes no network, `process` or `env` call
and starts no agent. Its one tool call is Claude Code's question dialog (`$.ui.ask`, AskUserQuestion),
to ask you for a mode. CI fails on a call outside `scripts/check-mod-calls.sh`.

- **Reads:** `.claude/temper.config`; the run files in `.temper/` (`build-state.json`, `gates.json`, `status.json`,
  `overrides.json`, `feedback-loops.json`, `groups.json`, `usage.json`, `evidence/review.json`, and a `report.md`
  an older Temper wrote); the spec folder of the run (`intent.md`, `plan.md`, `tasks.md`, `design.md`, and whether
  `config-suggestions.json` is there). To find the project it stats the
  session folder and looks for `.temper/build-state.json` there and in up to 11 folders above it. It reads its
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
  or off, the stage (and whether saved for later), task, run title, passed criteria, the next step (the gate
  question to ask, the answer to carry out, or the stage to run), a line when the mod cannot read the run, and
  one fixed line (answer a message at a gate; after a requested change, run the gate again and ask again).
- **Hooks:**
  - `tool.call` sees every tool call, a subagent's too. It reads the path of Write, Edit, MultiEdit and NotebookEdit
    and the text of Bash, then refuses the call with a fixed reason and next step for Claude (a next step that runs
    `scripts/temper` gives the plugin folder's path), or passes it on and returns its result unchanged; it never
    answers for a tool. After an AskUserQuestion call it reads your answer from the dialog's result: a `Temper gate`
    answer (Continue to, the arming choice, Commit, Save for later, and Loop back to, Override and continue,
    Accept finding, Override and commit or Keep the agent's commits with your reason), a `Temper resume` Start over,
    or a `Scope drift` answer (Add to plan, Revert or Allow once). It keeps it for the run and the step the CLI is at.
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
  the mode question. It waits 60 ms (`$.clock.sleep`, at most 4 times) to reread a run file the CLI is writing.
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
