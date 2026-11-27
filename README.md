# Temper

**Claude cannot write code before you approve the intent.**

A Claude Code plugin that runs AI written code through gates. You approve once before any code is written and once
at the commit; in between, a CLI judges every check from recorded evidence, and the model never decides a verdict.

[![Version](https://img.shields.io/badge/version-v9.8.5-blue)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Install

```text
/plugin marketplace add galando/temper
/plugin install temper
```

On Claude Code 2.1.275 or later, one step: `/plugin install temper --marketplace galando/temper`.

Then run `/temper:temper "describe the feature"` in your project.

## Commands

| Command | Purpose |
|---------|---------|
| `/temper:temper "..."` | The whole run, from your request to the commit |
| `/temper:fix "..."` | Root cause, a failing regression test, a minimal fix |

Its words, each alone after `/temper:temper`: `draft <idea>`, `status`, `report`, `init` and `pack`.

## How it works

Intent, Plan, Build, Review, Check

- **The first question** shows the intent and the plan on one card: the rules your request left out come back as
  questions with ready answers, and the tasks name every file that will change. Pick Approve and build.
- **In between**, tests come first; the CLI runs your suite, coverage and the acceptance tests, and a failed check
  gets one repair. Temper stops and asks only when a check still fails after that repair.
- **The second question** is the commit, with everything a rule decided since the approval. A red gate blocks
  `git commit`. A trivial request ends with no question: its one change is yours to commit.

**Cost and time:** 1.7 to 4x the cost and 3 to 6x the time of plain Claude Code: docs/evidence/scorecard-9.8.5.json

## What the mod reads and writes

Four command hooks and an optional mod (Claude Code 2.1.287 or later); neither calls the network or reads a credential:

- **Hooks** note the intent gate a `/temper:temper draft` owes, ask Claude to finish it, refuse a project file write
  before you approve the plan and deny a Bash command that would hang; they never approve a call or change its input.
- **The mod** runs only the plugin's own `scripts/temper` (never a shell) and `sleep`, and starts the Temper stage
  agents the CLI names, with your permission mode.
- **It changes** only what it denies (a write outside the stage, `--no-verify`, a changed hooks path) and the option
  descriptions of its own question. It never rewrites what you type; it answers a few `/temper:temper` words itself
  (`status`, `report`, `pane`).
- **`gh`** runs with your GitHub login only in the Pipeline stage, to read your pull request's checks.

The full list: [The mod](docs/mod.md#what-the-mod-reads-and-writes) and [Trust](docs/trust.md).

## Read more

[Getting Started](docs/getting-started.md) walks a first run; [the flow](docs/flow.md) is what the CLI says next;
[the decision records](docs/decisions/) say why it works this way.

[Trust](docs/trust.md) · [CHANGELOG](CHANGELOG.md) · [Privacy](https://galando.github.io/temper/privacy.html) ·
MIT © [Gal Naor](https://github.com/galando)
