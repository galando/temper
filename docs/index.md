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

Proof it catches real bugs: three seeded-defect fixtures run through the live
pipeline in CI and must *mechanically FAIL naming the defect* —
[seeded-defect evals](https://github.com/galando/temper/tree/main/evals) ·
[evidence gallery](evidence/case-study.html).

## Commands

Three you'll actually type — `/temper` runs and routes the rest:

| Command | Purpose |
|---------|---------|
| [`/temper "…"`](commands.html#temper) | The whole pipeline, intent gate to commit |
| [`/temper:fix "…"`](commands.html#temperfix) | Root cause → failing test (write-protected) → minimal fix |
| [`/temper:intent "…"`](commands.html#temperintent) | Capture an idea as a committed draft, build it later |

Each stage is also available on its own (`/temper:plan`, `:build`, `:review`,
`:check`, `:status`, `:pack`, `:init`) — see the [commands reference](commands.html).

**Autonomy (opt-in):** after you approve the plan, `/temper` can run the remaining
stages unattended, parking before commit. It never commits, pushes, or merges.

**Works with any CI:** temper ships no platform files — its automation surface is
commands and exit codes, the same under GitHub Actions, GitLab, Jenkins, or cron.

## Install

```bash
/plugin marketplace add galando/temper
/plugin install temper
```

That's it. Your first `/temper "…"` sets the project up — config, scaffold, and the
native commit gate.

## Next Steps

- [Getting Started](getting-started.html) — installation and first run
- [Commands Reference](commands.html) — full command documentation
- [Methodology](methodology.html) — IDD + BDD + TDD, one contract file
- [Packs](packs.html) — built-in and custom quality packs
- [AI-Native SDLC Alignment](ai-native-sdlc.html) — temper vs Anthropic's playbook
- [Context Hygiene](context-hygiene.html) · [Enterprise](enterprise.html) · [Recommended Setup](recommended-setup.html)
