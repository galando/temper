# The Temper mod

The mod makes the Temper phases real inside Claude Code. It needs Claude Code 2.1.287 or later.

The mod does four things:

- It refuses a write that does not belong to the current phase.
- It refuses `git commit` until Check passes.
- It draws the phase bar, the pane and the actions.
- It keeps a report of the run. Run `/temper:temper report` to see it.

[What the mod reads and writes](#what-the-mod-reads-and-writes) lists every file, hook and call of the mod.

## One flow, two views

The Temper bar has the same choices as the questions that Temper asks at each gate. Each choice is one
digit away. The bar also has Discuss, Play and Skip with a reason.

With the mod, Temper does not ask twice. It prints the result of the stage. Then it waits for the bar,
a typed `/temper:temper` word or a message. The full table is in
[Commands](commands.md#one-flow-two-views).

## The three modes

Use `/temper:temper mode` to set how much Temper draws. Refusals work in every mode.

- **Full** draws the bar with action buttons, the pane, toasts and suggestions.
- **Minimal** draws the phase bar only.
- **Off** draws nothing. A write outside the phase is still refused.

A toast confirms a change to enforcement in every mode. The same mod runs in the desktop app (Code tab).
The rows below show Full, Minimal and Off.

| Dark | Light |
|---|---|
| ![Full mode, dark: phase bar with action buttons and the pane](https://raw.githubusercontent.com/galando/temper/c4b892bc6081ba77db0744de49410c79a1db93d2/docs/assets/mode-full-dark.png) | ![Full mode, light: phase bar with action buttons and the pane](https://raw.githubusercontent.com/galando/temper/c4b892bc6081ba77db0744de49410c79a1db93d2/docs/assets/mode-full-light.png) |
| ![Minimal mode, dark: the phase bar only](https://raw.githubusercontent.com/galando/temper/c4b892bc6081ba77db0744de49410c79a1db93d2/docs/assets/mode-minimal-dark.png) | ![Minimal mode, light: the phase bar only](https://raw.githubusercontent.com/galando/temper/c4b892bc6081ba77db0744de49410c79a1db93d2/docs/assets/mode-minimal-light.png) |
| ![Off mode, dark: nothing drawn, refusals still apply](https://raw.githubusercontent.com/galando/temper/c4b892bc6081ba77db0744de49410c79a1db93d2/docs/assets/mode-off-dark.png) | ![Off mode, light: nothing drawn, refusals still apply](https://raw.githubusercontent.com/galando/temper/c4b892bc6081ba77db0744de49410c79a1db93d2/docs/assets/mode-off-light.png) |

## Each phase

- Key `1` is the main action. It changes when the phase is ready to move on.
- Key `9` is override in every phase. It always asks for a reason.
- Key `0` shows every action.

The keys of each phase are in [Commands](commands.md#each-phase).

| Phase | Writes allowed |
|---|---|
| Intent | `intent.md` only |
| Plan | `intent.md`, `plan.md`, `tasks.md`, `design.md` and new decision records |
| Build | The plan's files, test files and the spec folder. Another file waits for your answer to the Scope drift question. |
| Review | The spec folder only, unless a fix for that file is active |
| Check | The spec folder only. `git commit` stays refused until Check passes. |
| Fix | The failing files. After three failed loops, Temper stops and offers Plan again, Override or Take over. |

## Scope drift

Sometimes a task needs a file that the plan does not list. Then Claude asks you first. The question
shows the file, why the task needs it and the change. You choose one answer:

- **Add to plan.** The file becomes part of the plan.
- **Revert.** The task continues without the file.
- **Allow once.** Claude makes only this change. The why goes into the report as the reason.

This question is the same with the mod and without it. The mod also refuses the write until you answer.
The mod reads your answer from the result of the question, not from what Claude sends.

## A game while you wait

While a phase works, the band, the pane and the prompt hint show "Play while you wait". To open the
game, press `8` at the empty prompt or run `/temper:temper play`.

The game is Temper Run. Ember, a small dragon, runs in a forge hall.

- `r` runs.
- `w` jumps over anvils and buckets of cold water.
- `s` ducks under flying hammers.
- `q` or Esc closes the game.

If no key gets to the game in 3 seconds, the game tells you how to give it the keys. The game never
opens by itself. It shows a banner when a phase is ready. Refusals still apply while it is open.

The plugin setting `game` is `on` (the default), `command` (the command only) or `off`. The game runs
only in the terminal and the desktop app. It was checked by hand in the terminal with the keyboard.

## Where enforcement works

The mod needs Claude Code 2.1.287 or later. This section shows where enforcement works, where it does
not work and what is not verified.

### Older versions, or no mod

Before 2.1.287 the mod does nothing, and the skills say one time that enforcement is off. The same
applies when the mod does not load. You keep the full pipeline:

- Every phase as a prompt.
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
| `claude -p` and the Agent SDK | yes. With enforcement on, a run stops at the first gate, because only a person in an interactive session can approve. With enforcement off, it continues. | no |
| Remote Control (phone or web) | yes, on your machine | only in the terminal of your machine |
| Cloud sessions (claude.ai/code) | yes, if server managed settings bring the plugin (most sessions get the phases as prompts) | no |
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

The hard guarantee covers the tool layer: Write, Edit, NotebookEdit, MultiEdit and `git commit`.

For Bash, the mod does these steps:

- It resolves variables in order.
- It expands braces.
- It follows `cd`.
- It refuses a write that it cannot check when the command names Temper state.

Thus common tricks fail closed. But the mod cannot see a variable that an earlier call or a profile
set. A Bash command can still write ordinary source files. MCP file tools are not covered. The native
`pre-commit` hook is the backstop.

Button presses and the reason field carry no origin. Their authenticity depends on Claude Code.

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
Intent before Claude writes an intent), which ends the run.

A text reader cannot see some shell tricks. These are still possible:

- A link or a script that an earlier call made.
- A script that is already on disk and starts later.
- A program that builds the script name or a path at run time.
- The names inside a patch or an archive.

The staged list is the session's own picture. The mod does not see a script that stages files. MCP and
PowerShell file tools are not checked. Thus the hard guarantees are the editing tools and the native
`pre-commit` hook, not the Bash reader.

A `Temper enforcement:` line can also be in any file that Claude can read. An injected copy can only
hide a question. It cannot advance a phase, because each advance needs a decision of the person or a
passed check.

When the run is Done, a `git commit` from the model is allowed. The run is complete, and the person
pressed Continue. A later CLI could check a decision token that works one time only.

## What the mod reads and writes

Mods are not sandboxed, so this is the full list. The mod makes no network, `process` or `env` call
and starts no agent. Its one tool call is Claude Code's question dialog (`$.ui.ask`, AskUserQuestion),
to ask you for a mode or a reason. CI fails on a call outside `scripts/check-mod-calls.sh`.

- **Reads:** `.claude/temper.config`; the run files in `.temper/` (`build-state.json`, `gates.json`, `status.json`,
  `overrides.json`, `feedback-loops.json`, `evidence/`, and a `report.md` an older Temper wrote); the spec folder of the run (`intent.md`, `plan.md`,
  `tasks.md`, `design.md`, `events/`, `config-suggestions.json`); and `.git/HEAD`. To find the project it stats the
  session folder and looks for `.temper/build-state.json` there and in up to 11 folders above it. It reads its
  settings, store and state and the Claude Code version. When you change the mode or enforcement it reads the
  `/config` list (every row) to find its two rows and whether your organization locked them. When `reviewerModel` is
  set it reads the session's agent list and keeps only the id and type, to find the Temper review agent.
- **Writes no file itself.** Decisions, run events, the report, the game's best score and whether you
  were asked for a mode stay in its plugin store, a JSON file in your Claude Code settings folder.
- **Session state:** for its drawing it keeps the bar's view (run title, phase, criteria, findings),
  the mode, the project folder and the game's key counts in `$.state`, which other plugins can read.
- **Configuration and environment it sets:** no environment variable. Only `temper.uiMode` (you type
  `/temper:temper mode`, or answer the mode question your first `/temper:temper` or a bare `mode` asks)
  and `temper.enforcement` (you type `/temper:temper enforcement`). A row your organization locked stays.
- **Slash commands it runs, and when:** only `/temper:temper` and `/temper:temper continue <stage>`
  (intent, plan, design, build, review or check), each written as fixed text, and only when you press a
  button or Enter in the reason field. No command is built from data.
- **What it puts in the prompts it submits:** only on that press, the fixed text of the action, with the phase, a
  finding number, your reason, and the plugin folder's path wherever the text names a Temper file (the
  `scripts/temper` command that records your choice, the Stop and Commit steps, the plan review files). Discuss and
  Change put a fixed draft in your prompt box. After an answer in full mode it may suggest the next fixed prompt; it
  never sends one. Each prompt is a turn of your session, marked as from the Temper plugin. Apart from these, the
  refusals below and its state, it sends no text out.
- **System prompt:** `prompt.compose` adds one section, `temper:phase`, to each request: enforcement on
  or off, the phase (and whether paused), task, run title, passed criteria, stale phases, the next
  step, a warning when its state and the CLI's disagree, and one fixed line (answer a message at a
  gate; after a requested change, run the gate again).
- **Hooks:**
  - `tool.call` sees every tool call, a subagent's too. It reads the path of Write, Edit, MultiEdit and NotebookEdit
    and the text of Bash, then refuses the call with a fixed reason and next step for Claude (a next step that runs
    `scripts/temper` gives the plugin folder's path), or passes it on and returns its result unchanged; it never
    answers for a tool. A write outside the plan is refused until you answer Claude's Scope drift question (why, the
    change, then Add to plan, Revert or Allow once); the mod records your answer from the dialog's result only.
  - `command.run` handles only `/temper:temper`. It answers `status`, `timeline`, `help`, `report`, `mode`,
    `enforcement`, `pane`, `play`, `pause` and `resume`. It records an accepted decision (`approve`, `next`, `back`,
    `override`, `accept`, `drift`) and passes it on; a refused one is answered with the reason. A word that changes
    state, and `play`, is refused unless you typed it in your prompt box; with enforcement off, a decision from any
    origin is accepted and its origin recorded. A bare `/temper:temper` you type toggles the pane in full mode during
    a phase. `pr`, `discuss`, `continue` and any other word or command pass on unchanged, even the two the mod runs.
  - `session.start` and `classic.SessionStart` find the project root and load the run; in full mode
    `session.start` also opens the pane during a phase. Both return what the engine gives them: no
    context, instruction or setting is added.
  - `turn.step` sets the model and effort from `phaseModels` and the Temper review agent's model from `reviewerModel`;
    empty options change nothing. `attribution.text` adds one Temper line to a pull request description during a run
    when `prAttribution` is on. `turn.complete` adds a one line status under an answer in full mode.
  - `ui.render` draws the bar, pane, game, spinner word, prompt hint and a line above Claude's question
    dialog, which stays unchanged. `ui.message` takes the game's score; `ui.close` notes a closed pane.
- **The game** is the mod's one surface module (the game client, with its runner, art and palette
  files), named as fixed text and imported statically. It makes no engine call and posts only the score.
- **Other:** key `9` moves the keys to the reason field. Toasts tell a phase change (full mode), an enforcement
  change, the default mode when you dismiss the mode question, and the result of a press. It waits 60 ms
  (`$.clock.sleep`, at most 4 times) to reread.
- **The tests never run in your session.** The mod's test suite runs only under `claude plugin test`; the plugin never
  loads it. Every `$` call there (`$.session.start`, `$.ui.mount`, `$.tool.call`, `$.agent.spawn` and the rest) goes
  to Claude Code's own test kit (`claude-code/testing`), not another plugin. Tests hand Bash, Write, Edit,
  NotebookEdit and Read calls to the guard. Temper's fake engine answers each tool call, question, prompt,
  `config.set`, `fs.write` and `command.run` with a stub and keeps what the mod sent in memory for the test to check,
  so nothing runs and nothing leaves the test. One test spawns a stub review agent (prompt `review it`, type
  `temper:temper-review`, no model); a stub answers it, so no agent runs, and the mod leaves the spawn unchanged.
- **Tests, lint, git and `scripts/temper`** run as prompts to Claude with its normal permissions. Auto
  mode may refuse a skip as a gate bypass; the bar then says "Press 1 to record it". Allow that one
  `scripts/temper override` command, or run it yourself with `!`.
