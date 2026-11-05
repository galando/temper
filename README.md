# Temper

**Claude cannot write code before you approve the intent.**

A Claude Code plugin that runs AI written code through gates you approve. A small CLI computes each gate from
recorded evidence; the model never decides a verdict.

[![Version](https://img.shields.io/badge/version-v9.8.0-blue)](CHANGELOG.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Install

```text
/plugin marketplace add galando/temper
/plugin install temper
```

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

An optional mod (Claude Code 2.1.287 or later) draws the stage bar and refuses writes outside the current stage. It
reads only `.temper/view.json` and its own store, makes no network call and runs no command ([details](docs/mod.md#what-the-mod-reads-and-writes)).

[Getting Started](docs/getting-started.md) · [Commands](docs/commands.md) · [Trust](docs/trust.md) · [CHANGELOG](CHANGELOG.md) · [Privacy](https://galando.github.io/temper/privacy.html) · MIT © [Gal Naor](https://github.com/galando)
