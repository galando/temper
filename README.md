# Temper

**Claude cannot write code before you approve the intent.**

A Claude Code plugin that runs AI written code through gates you approve. A small CLI computes each gate from
recorded evidence; the model never decides a verdict.

[![Version](https://img.shields.io/badge/version-v9.8.1-blue)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Install

```text
/plugin marketplace add galando/temper
/plugin install temper
```

On Claude Code 2.1.275 or later, one step: `/plugin install temper --marketplace galando/temper`.

Then run `/temper:temper "describe the feature"` in your project.

## How it works

Intent, Plan, Build, Review, Check, then commit. You decide each gate by clicking an answer.

- **Intent:** the rules your request left out (who, when, how much, exceptions) come back as questions with ready answers.
- **Plan:** tasks a builder can follow without guessing; files outside the plan need your OK.
- **Build:** tests first; acceptance tests written from your intent before any code, and locked.
- **Review and Check:** the CLI runs the suite, coverage, a mutation score and the acceptance tests. A red gate blocks
  `git commit`.

On vague requests it met 98% of what the person wanted, against 73% for plain Claude Code, at about 7 times the cost
per run ([the evidence](docs/evidence/bench-2026-11.md)).

## Commands

| Command | Purpose |
|---------|---------|
| `/temper:temper "..."` | The whole flow, from intent to commit |
| `/temper:fix "..."` | Root cause, a failing regression test, a minimal fix |
| `/temper:intent "..."` | Capture an idea now, build it later |
| `/temper:status` | Gates, metrics and spec drift |

## What the mod reads and writes

Temper ships three command hooks and an optional mod (Claude Code 2.1.287 or later). Neither makes a network call,
and neither reads a credential. In detail ([more](docs/mod.md#what-the-mod-reads-and-writes), [trust](docs/trust.md)):

- **Hooks** (`hooks/hooks.json`). `UserPromptSubmit` runs `scripts/guards/stage-marker.sh`, which notes that a
  `/temper:intent` session owes an intent gate. `Stop` runs `scripts/guards/verify-stage-gate.sh`, which asks Claude to
  keep working until that gate has a verdict. `PreToolUse` on Bash runs `scripts/guards/block_stdin_wait.py`, which
  denies a command whose `cat` would wait for input until the Bash timeout. The hooks never approve a tool call and
  never change a tool's input; every other path lets the call through.
- **Programs the mod runs.** With the mod loaded, `/temper:temper` and `/temper:fix` are carried by the mod: it runs
  the plugin's own `scripts/temper` by its path with plain arguments, never through a shell, in the project folder
  (a call that needs a shell goes to the conversation instead, under your permission settings). Between looks at its
  agents it runs `sleep` with a number of seconds.
- **Agents the mod starts.** It starts the Temper stage agent that `temper go` names (`temper:temper-plan`,
  `temper:temper-build-task`, and so on), with the model and prompt the CLI wrote. The prompt holds the stage brief to
  follow, your feature request and the paths of the run files under `.temper/`. The agents keep the permission mode
  you set and use tools under your own permission settings.
- **What the mod reads.** `.temper/view.json`, its own store, and the events it hooks: each tool call, the
  `/temper:*` commands and session start.
- **What the mod changes.** On a tool call it may deny the call (a write outside the current stage, `--no-verify`, a
  changed hooks path, a step only you may take). On an `AskUserQuestion` call of its own run it fills in each option's
  description and preview from the CLI's question, so the dialog shows what each choice does; it changes no other
  tool's input. On `/temper:temper` and `/temper:fix` it passes your command on unchanged and may add one note the
  model reads after it (the words the run continues with). When a run is active and the `prAttribution` option is on,
  it adds one Temper line to Claude Code's pull request attribution text. Session start events pass on unchanged.
- **Your GitHub login.** After a commit, the Pipeline stage agent runs `gh` (with your own GitHub login, as in your
  terminal) to read the checks of your pull request. It reads them only: it never pushes and never marks a draft
  ready. Neither the hooks nor the mod read it.

[Getting Started](docs/getting-started.md) · [Commands](docs/commands.md) · [Trust](docs/trust.md) · [CHANGELOG](CHANGELOG.md) · [Privacy](https://galando.github.io/temper/privacy.html) · MIT © [Gal Naor](https://github.com/galando)
