# Temper

**Claude cannot write code before you approve the intent.**

Temper is an intent gated workflow for code that AI writes. A small CLI computes each gate verdict.
The model never decides a verdict. With Claude Code 2.1.287 or later, a mod refuses writes outside
the current stage ([the mod](docs/mod.md)).

[![Plugin directory](https://img.shields.io/badge/Claude%20Code-plugin-D97757)](https://code.claude.com/docs/en/discover-plugins)
[![Version](https://img.shields.io/badge/version-v9.7.3-blue)](CHANGELOG.md)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-2.1.287%2B%20for%20the%20mod-blue)](docs/mod.md#where-enforcement-works)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

https://github.com/user-attachments/assets/ec84e98e-7c28-45f9-87c2-8df0b80e19b8

[Website](https://galando.github.io/temper) · [Getting Started](docs/getting-started.md) · [Commands](docs/commands.md) · [The mod](docs/mod.md) · [Haiku Build](docs/grouped-build.md) · [Releases](https://github.com/galando/temper/releases)

## Install

```text
/plugin marketplace add galando/temper
/plugin install temper
```

On Claude Code 2.1.275 or later, one line does both:

```text
/plugin install temper --marketplace galando/temper
```

You can also open the Plugins page in Claude, choose **Discover** and search for "temper".

Your first `/temper:temper "describe the feature"` sets up the project. It adds the config, the
`.temper/` folder and a `pre-commit` hook. The hook blocks `git commit` while a gate is red.

The short form `/temper` is an interactive shortcut. It may not work on every surface. Claude Code
2.1.287 or later adds the stage bar and the refusals. Older versions run each stage as a prompt.

## The problem

AI writes code fast, but it fails in predictable ways:

- Happy paths without edge cases.
- Features that nobody asked for.
- Calls to methods that do not exist.
- Correct code that nothing uses.

Most tools check that the code compiles. Temper checks that the code solves the right problem. It does
this mechanically. It does not ask the model to grade itself.

## How it works

One loop, with a human gate at each stage. You review the cheapest artifact first.
The order is Intent, Plan, Build, Review, Check, then Done. You decide each gate in one question.
A failed Review or Check goes back to Build when you choose so.

```mermaid
flowchart LR
  I["Intent<br/>you approve it"] --> P["Plan<br/>files it may touch"]
  P --> B["Build<br/>failing test first"]
  B --> R["Review<br/>fix or accept"]
  R --> C["Check<br/>run all checks"]
  C --> D(("Done<br/>commit allowed"))
  C -- "a check fails, you loop back" --> B
```

- **The intent gate comes first.** You approve the problem and the success criteria before Claude
  explores or designs. A wrong intent costs words here. Later, it costs the whole plan.
- **Each gate is computed.** `scripts/temper` is auditable bash with no network. It reads an evidence
  ledger and prints PASS or FAIL for each requirement. A red gate blocks `git commit` through a real
  hook. A person can override a gate, and Temper records who did it. A confused model cannot.
- **The mod makes the stages real.** It refuses writes outside the stage, `--no-verify`, and a step
  only you may take when you did not choose it in the gate question. It draws the stage bar and the
  run's pane; at the end the run prints its report, and writes it as a page when you ask. It is not a
  sandbox: [Trust](docs/trust.md) lists what it does not see, and [the mod](docs/mod.md) has the details.

https://github.com/user-attachments/assets/31a9f4dc-8860-41be-97ca-f03460630f2f

## What the mod reads and writes

The mod makes no network, `process` or `env` call, starts no agent and writes no file itself. It sets no
setting and runs no command.

- **Reads:** `.temper/view.json`, the one file the CLI writes for it. To find the project it looks for that
  file in the session folder and in up to 11 folders above it. It also reads its own options, store and
  state, and the Claude Code version. When `reviewerModel` is set it reads the session's agent list (id and
  type only).
- **Configuration and environment it sets:** none. It sets no environment variable and changes no setting,
  its own included. You set its options in `/config`: Temper UI mode (`full`, `minimal` or `off`) and Temper
  enforcement (`on` or `off`), and the others below. `/temper:temper mode` and `/temper:temper enforcement`
  only say what is set and where to change it.
- **Slash commands it runs:** none. The bar has no button; you type `/temper:temper` to take a run up again.
- **Hooks, and what each changes:**
  - `tool.call` reads the path of Write, Edit, MultiEdit and NotebookEdit and the text of Bash, and refuses
    some calls with a reason. Always: a write to the CLI's run files in `.temper/`, and a Bash word that
    expands to more words than it reads (a long brace list). During a `/temper` or `/temper:fix` run:
    `--no-verify`, a changed hooks path, and a write to the config or git's hooks. During a `/temper` run: a
    write outside the stage, a write to the mod's plugin data folder, a step only you may take, an unquoted
    glob in a Temper call that could spell such a step, and a Bash call its own check failed on. Any other
    call goes on, and its result comes back unchanged. After a question dialog it reads your answer from the
    result.
  - `command.run` handles only `/temper:temper` (and `/temper`). It answers `status`, `timeline`, `help`,
    `report`, `mode`, `enforcement` and `pane` itself, and changes nothing with them. Typed in your prompt
    box, any other word opens the pane in full mode, then goes on unchanged; every other command goes on
    unchanged.
  - `session.start` and `classic.SessionStart` find the project folder and load the run. Neither adds or
    changes a context, an instruction, a setting or another hook: each returns what Claude Code gave it.
  - `prompt.compose` adds one system prompt section, `temper:phase`, to each request: enforcement on or off,
    the stage, the run title, the passed criteria, the next step for Claude (from `.temper/view.json`), a line
    when the mod cannot read the run as it should, and one fixed line (answer a message at a gate; after a
    requested change, run the gate again and ask again).
  - `turn.step` sets the model and effort from `phaseModels`, and the review agent's model from
    `reviewerModel`; empty options change nothing.
  - `attribution.text` adds one Temper line to a pull request description during a run, when
    `prAttribution` is on.
  - `turn.complete` adds a one line status under an answer in full mode.
  - `ui.render` draws the bar, the pane, the spinner word, the prompt hint and one line above the question
    dialog, which stays as it is; `ui.close` notes a pane you closed, so it does not open again by itself.
- **What reading the run again changes:** the session hooks, `tool.call` (after a Bash call or a question
  dialog), `turn.complete` and `command.run` read the run again. That changes only the mod's own state: the
  project folder, the bar's view and the mode in `$.state`, which other plugins can read; at Done the run
  report kept in its store; in full mode a toast for a stage change, and the pane opened for a run that
  started.
- **Keeps:** your answers in the question dialogs and the run report, in its plugin store.

Outside your project folder, Temper reads its own global pack folder `~/.claude/packs` (if you made one),
the mod's plugin store, and the folders above the session folder where the mod looks for the project. It
asks git for your name and email, to record who accepted an intent or overrode a gate, and for its hooks
folder, which may be one your git config names. It reads no key, login, transcript or other Claude Code
file. Setting up a project (`/temper:init`, or your first `/temper:temper`) points the repository's own
`core.hooksPath` at Temper's commit hook, or, when that would stop a hook of yours, prints one line to add
to it. Temper never edits a Claude Code settings file on its own; the guardrails pack writes guard entries
into the project's settings only after you confirm. The full list is in
[The mod](docs/mod.md#what-the-mod-reads-and-writes).

## Commands

Three you will actually type. `/temper:temper` runs and routes the rest.

| Command | Purpose |
|---------|---------|
| [`/temper:temper "..."`](docs/commands.md#temper-unified-command) | The whole pipeline, intent gate to commit |
| [`/temper:fix "..."`](docs/commands.md#temperfix) | Root cause, a failing test that is write protected, a minimal fix |
| [`/temper:intent "..."`](docs/commands.md#temperintent) | Capture an idea as a committed draft, build it later |

`/temper:temper` also takes `status`, `report`, `pr`, `mode` and `pane`. A word such as `approve` or
`back` only brings up the gate question, where you decide. See [Commands](docs/commands.md#subcommands).

**Granular control.** Each stage on its own: [`/temper:plan`](docs/commands.md#temperplan),
[`/temper:design`](docs/commands.md#temperdesign), [`/temper:build`](docs/commands.md#temperbuild),
[`/temper:review`](docs/commands.md#temperreview), [`/temper:check`](docs/commands.md#tempercheck). Utilities:
[`/temper:status`](docs/commands.md#temperstatus), [`/temper:pack`](docs/commands.md#temperpack), [`/temper:init`](docs/commands.md#temperinit).

**Autonomy (opt in)** runs stages after the plan gate unattended. It never pushes, never merges to a
remote and never makes the feature commit; its only commits are Build's local task commits and merges. **Packs:** [docs/packs.md](docs/packs.md). **CI:** [examples/workflow/README.md](examples/workflow/README.md).

## Documentation, contributing and license

- [Getting Started](docs/getting-started.md) · [Commands](docs/commands.md) · [The mod](docs/mod.md) · [Trust](docs/trust.md) · [Packs](docs/packs.md)
- [Methodology](docs/methodology.md) · [Testing the mod](docs/mods-testing.md) · [AI Native SDLC](docs/ai-native-sdlc.md)
- [Recommended Setup](docs/recommended-setup.md) · [Enterprise](docs/enterprise.md) · [Directory submission](docs/directory-submission.md) · [Privacy](https://galando.github.io/temper/privacy.html)
- [CONTRIBUTING.md](CONTRIBUTING.md) · MIT © [Gal Naor](https://github.com/galando)
