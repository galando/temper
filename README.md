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

## See it

[![Temper in 70 seconds: one run from intent to commit](https://galando.github.io/temper/media/workflow.jpg)](https://galando.github.io/temper/media/workflow.mp4)

[![The Temper mod in 55 seconds: the run driver, the band and the pane](https://galando.github.io/temper/media/tour.jpg)](https://galando.github.io/temper/media/tour.mp4)

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

Three command hooks and an optional mod (Claude Code 2.1.287 or later). Neither makes a network call or reads a
credential. In short:

- **Hooks** note an `/temper:intent` gate, ask Claude to finish it, and deny a Bash command that would hang; they never
  approve a call or change its input.
- **The mod** runs only the plugin's own `scripts/temper` (never a shell) and `sleep`, and starts the Temper stage
  agents the CLI names, with your permission mode.
- **It changes** only what it denies (a write outside the stage, `--no-verify`, a changed hooks path) and the option
  descriptions of its own question. It never rewrites what you type; it answers a few `/temper:temper` words itself
  (`status`, `report`, `pane`).
- **`gh`** runs with your GitHub login only in the Pipeline stage, to read your pull request's checks.

The full list: [The mod](docs/mod.md#what-the-mod-reads-and-writes) and [Trust](docs/trust.md).

[Getting Started](docs/getting-started.md) · [Commands](docs/commands.md) · [Trust](docs/trust.md) · [CHANGELOG](CHANGELOG.md) · [Privacy](https://galando.github.io/temper/privacy.html) · MIT © [Gal Naor](https://github.com/galando)
