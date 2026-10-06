---
title: Home
nav_order: 1
---

# Temper

{: .fs-9 }

**Your AI writes fast. Temper makes it last.**
{: .fs-6 .fw-300 }

An intent-gated SDLC for AI-generated code — every gate verdict computed by a small
CLI, never asserted by a model.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

[Get started](#install){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[How it works](#how-it-works){: .btn .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View on GitHub](https://github.com/galando/temper){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## The Problem

AI writes code fast, but with structural failure patterns: happy paths without edge
cases, features nobody asked for, calls to methods that don't exist, correct code
never wired in. Most tools check whether the code compiles. Temper checks whether it
solves the right problem — **mechanically**, not by asking the model to grade itself.

## How It Works

One loop, a human gate at every stage, the cheapest artifact reviewed first:

```
INTENT → PLAN → DESIGN? → BUILD → REVIEW → CHECK → COMMIT
  ↑ WHY — approved before any tokens are spent downstream
```

- **Intent gate first** — you approve the Problem and success criteria before
  exploration or architecture runs. A wrong intent multiplies into wrong everything;
  correcting it at this gate costs words, after Plan it costs the plan.
- **Scenarios before architecture** — BDD scenarios are derived from a *measured*
  blast radius, so every planned file traces to a behavior.
- **Every gate is computed** — the `temper` CLI (auditable bash, no network) reads an
  evidence ledger and prints PASS/FAIL per requirement. A red gate blocks `git commit`
  via a real pre-commit hook; a human can override (recorded, never erased) — a
  confused model can't.
- **The loop closes itself** — `temper bands` watches metric history with control
  bands (pure arithmetic); a breach is drafted as the next intent and rides the same
  pipeline. Fixes write a committed `lessons.md` every future RCA reads first.

## The Temper mod (Claude Code 2.1.287 or later)

![Temper phase bar in Claude Code: Intent, Plan, Build, Review, Check, with numbered actions](https://raw.githubusercontent.com/galando/temper/c4b892bc6081ba77db0744de49410c79a1db93d2/docs/assets/temper-full.gif)

On Claude Code 2.1.287 or later, Temper also ships a mod. It enforces the phases at the tool
layer and shows them. Older versions load the plugin as before.

- **Claude cannot write code before you approve the intent.** The mod refuses an edit that does
  not belong to the current phase, and it refuses `git commit` until the gates pass or you
  override them. Every refusal names the next step.
- **You see where you are.** A phase bar shows Intent, Plan, Build, Review and Check. Numbered
  buttons give the same choices as the original `/temper` gates: Continue, Teach me, Grill me,
  Discuss, Skip with a reason.
- **You choose how much it shows.** `uiMode` is full, minimal or off. `enforcement` is on or off.
- **The CLI stays the source of truth.** The bar follows `.temper/build-state.json`. If the mod
  cannot tell where the run is, it blocks nothing.
- **Optional game.** Press 8 while Claude works to play Temper Run. It never changes the run.

The mod is early access, runs in the CLI and the desktop Code tab, and is not a sandbox. It
guards the editing tools and `git commit`; the Bash check is best effort. The
[README](https://github.com/galando/temper#readme) lists the limits and what the mod reads and
writes. To try a branch on your own machine, follow [Testing the mod](mods-testing.html).

## Commands

Three you'll actually type. `/temper:temper` runs and routes the rest:

| Command | Purpose |
|---------|---------|
| [`/temper:temper "…"`](commands.html#temper-unified-command) | The whole pipeline, intent gate to commit |
| [`/temper:fix "…"`](commands.html#temperfix) | Root cause → failing test (write-protected) → minimal fix |
| [`/temper:intent "…"`](commands.html#temperintent) | Capture an idea as a committed draft, build it later |

Each stage is also available on its own (`/temper:plan`, `:build`, `:review`,
`:check`, `:status`, `:pack`, `:init`) — see the [commands reference](commands.html).

**Autonomy (opt-in):** after you approve the plan, `/temper` can run the remaining
stages unattended, parking before commit. It never commits, pushes, or merges.

**Works with any CI:** temper ships no platform files — its automation surface is
commands and exit codes, the same under GitHub Actions, GitLab, Jenkins, or cron.

## Install

```text
/plugin marketplace add galando/temper
/plugin install temper
```

That's it. Your first `/temper:temper "…"` sets the project up: config, scaffold, and the
native commit gate. The short form `/temper` is an interactive shortcut that may not resolve in
every surface.

## Next Steps

- [Getting Started](getting-started.html) — installation and first run
- [Commands Reference](commands.html) — full command documentation
- [Testing the mod](mods-testing.html) — try the phase bar and enforcement on your machine
- [Methodology](methodology.html) — IDD + BDD + TDD, one contract file
- [Packs](packs.html) — built-in and custom quality packs
- [AI-Native SDLC Alignment](ai-native-sdlc.html) — temper vs Anthropic's playbook
- [Context Hygiene](context-hygiene.html) · [Enterprise](enterprise.html) · [Recommended Setup](recommended-setup.html)
