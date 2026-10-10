# The Temper mod

The mod makes the Temper phases real inside Claude Code. It needs Claude Code 2.1.287 or later.

The mod does four things:

- It refuses a write that does not belong to the current phase.
- It refuses `git commit` until Check passes.
- It draws the phase bar, the pane and the actions.
- It keeps a report of the run. Run `/temper:temper report` to see it.

The README section "What the mod reads and writes" lists every file, hook and call of the mod.

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
