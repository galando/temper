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

Five stages, Intent, Plan, Build, Review and Check, and two questions: you approve once before any code is written
and once at the commit.

```
INTENT -> PLAN -> (approval) -> BUILD -> REVIEW -> CHECK -> (commit question) -> COMMIT
```

- **The intent first.** The rules your request left out come back as questions with ready answers, and the approval
  shows the intent's criteria beside the plan, so a correction costs words, not code.
- **One approval before code.** The card shows what will be true, the files that will change and the commands the
  checks run. After Approve and build the run goes on by itself: a passed check moves on, and a failed check gets one
  counted repair. It stops and asks you only when a check still fails after that repair.
- **Every gate is computed.** The `temper` CLI reads an evidence ledger and prints PASS or FAIL for each row; a check
  it could not measure is shown as not measured. A red gate blocks `git commit` through a real pre-commit hook; a
  person can override it (recorded, never erased), a confused model cannot.
- **Fixes leave lessons.** A fix writes a committed `lessons.md` that every later root cause analysis reads first.

## The Temper mod (Claude Code 2.1.287 or later)

On Claude Code 2.1.287 or later, Temper also ships a mod. It enforces the stages at the tool
layer and shows them. Older versions load the plugin as before.

- **Claude cannot write code before you approve the intent.** The mod refuses an edit that does
  not belong to the current stage, and `--no-verify` or a changed hooks path, so `git commit` goes
  to the hook, which refuses it until the gates pass or you override them. Every refusal names the
  next step. Temper is not a sandbox: [Trust](trust.md) lists what the mod does not see.
- **You decide in one place.** Every gate is a question in Claude Code's own dialog, with or
  without the mod, with the options the CLI gives: Approve and build, Ask me at every stage, Commit, Loop back,
  Override and continue, Save for later.
- **You see where you are.** A stage bar shows Intent, Plan, Build, Review and Check with their
  results, the status and the details of the stage. It never decides anything.
- **You choose how much it shows.** `uiMode` is full, minimal or off. `enforcement` is on or off.
- **The CLI stays the source of truth.** The bar follows `.temper/view.json`, which the CLI writes. If the mod
  cannot tell where the run is, it blocks nothing.

The mod is early access, runs in the CLI and the desktop Code tab, and is not a sandbox. It
guards the editing tools and `git commit`; in Bash it checks only a short list. The
[The mod](mod.html) lists the limits and what the mod reads and
writes. To try a branch on your own machine, follow [Testing the mod](mods-testing.html).

## Commands

Two commands:

| Command | Purpose |
|---------|---------|
| `/temper:temper "..."` | The whole run, from your request to the commit |
| `/temper:fix "..."` | Root cause, a failing regression test, a minimal fix |

`/temper:temper` also takes a few words, each alone after it: `draft <idea>` captures an idea as a draft to build
later, and `status`, `report`, `init` and `pack` show the run or set the project up. See the commands reference.

**Works with any CI:** Temper ships no platform files. Its automation surface is commands and exit codes, the same
under GitHub Actions, GitLab, Jenkins, or cron.

## Install

```text
/plugin marketplace add galando/temper
/plugin install temper
```

That is all. Your first `/temper:temper "…"` sets the project up: config, scaffold, and the
native commit gate. The short form `/temper` is an interactive shortcut that may not resolve in
every surface.

## Next Steps

- [Getting Started](getting-started.html) — installation and first run
- [Commands Reference](commands.html) — full command documentation
- [Testing the mod](mods-testing.html) — try the stage bar and enforcement on your machine
- [Methodology](methodology.html) — IDD + BDD + TDD, one contract file
- [Packs](packs.html) — built-in and custom quality packs
- [AI-Native SDLC Alignment](ai-native-sdlc.html) — temper vs Anthropic's playbook
- [Context Hygiene](context-hygiene.html) · [Enterprise](enterprise.html) · [Recommended Setup](recommended-setup.html)
