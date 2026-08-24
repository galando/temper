<div align="center">

# Temper

**Your AI writes fast. Temper makes it last.**

*An intent-gated SDLC for AI-generated code — every gate verdict computed by a small CLI, never asserted by a model.*

[![Version](https://img.shields.io/github/v/release/galando/temper?include_prereleases)](https://github.com/galando/temper/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Eval Fixtures](https://github.com/galando/temper/actions/workflows/eval-fixtures.yml/badge.svg)](https://github.com/galando/temper/actions/workflows/eval-fixtures.yml)

[Website](https://galando.github.io/temper) · [Getting Started](docs/getting-started.md) · [Releases](https://github.com/galando/temper/releases)

</div>

## Install

```bash
/plugin marketplace add galando/temper
/plugin install temper
```

That's it. Your first `/temper "…"` sets the project up — config, scaffold, and the
native commit gate that physically blocks `git commit` while any gate is red.

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
  blast radius, so every planned file traces to a behavior. That's the structural
  defense against over-engineering.
- **Every gate is computed** — `scripts/temper` (auditable bash, no network) reads an
  evidence ledger (`temper evidence add/run`) and prints PASS/FAIL per requirement. A
  red gate blocks `git commit` via a real pre-commit hook; a human can override
  (recorded with their identity, never erased) — a confused model can't.
- **The loop closes itself** — `temper bands` watches metric history with control
  bands (pure arithmetic, no model); a breach is drafted as the next intent and rides
  the same pipeline. Fixes write a committed `lessons.md` every future RCA reads first.

Proof it catches real bugs: three seeded-defect fixtures run through the live pipeline
in CI and must *mechanically FAIL naming the defect* — [evals/README.md](evals/README.md),
[evidence gallery](docs/evidence/).

## Commands

Three you'll actually type — `/temper` runs and routes the rest:

| Command | Purpose |
|---------|---------|
| [`/temper "…"`](docs/commands.md#temper) | The whole pipeline, intent gate to commit |
| [`/temper:fix "…"`](docs/commands.md#temperfix) | Root cause → failing test (write-protected) → minimal fix |
| [`/temper:intent "…"`](docs/commands.md#temperintent) | Capture an idea as a committed draft, build it later |

<details><summary><b>Granular control</b> — each stage on its own, plus utilities</summary>

| Command | Purpose |
|---------|---------|
| [`/temper:plan`](docs/commands.md#temperplan) | Blast radius + BDD scenarios + architecture |
| [`/temper:design`](docs/commands.md#temperdesign) | System design, Areas of Concern gated |
| [`/temper:build`](docs/commands.md#temperbuild) | Scenario-driven TDD + coverage gate |
| [`/temper:review`](docs/commands.md#temperreview) | Confidence-scored review + intent validation |
| [`/temper:check`](docs/commands.md#tempercheck) | Stack-aware validation pipeline |
| [`/temper:status`](docs/commands.md#temperstatus) | Dashboard: gates, hotspots, control bands |
| [`/temper:pack`](docs/commands.md#temperpack) | Manage quality packs |
| [`/temper:init`](docs/commands.md#temperinit) | Explicit setup (idempotent) |

</details>

**Autonomy (opt-in):** after you approve the plan, `/temper` can run the remaining
stages unattended — checkpointing each green stage, parking before commit. It never
commits, pushes, or merges.

**Quality packs:** versioned policy (security, TDD, quality, performance, api-design,
architecture-depth) enforced during build and review, with deterministic hook
backstops for the rules that must always hold. [docs/packs.md](docs/packs.md)

**Works with any CI:** temper ships no platform files — its automation surface is
commands and exit codes (`temper bands`, `temper gate review`, `temper metrics
append`), the same under GitHub Actions, GitLab, Jenkins, or cron.
[examples/workflow/README.md](examples/workflow/README.md)

## Trust

Markdown plus ~1,500 lines of auditable shell. No network calls, no telemetry; writes
stay in your project (`.claude/temper.config`, `.temper/`). The committed artifact
chain — intent, plan, design, gate ledger, diff — is the audit trail: who asked, what
was planned, what the gates verified, in the same commits as the code.

## Documentation

- [Getting Started](docs/getting-started.md) · [Commands](docs/commands.md) · [Packs](docs/packs.md)
- [Methodology](docs/methodology.md) — IDD + BDD + TDD, one contract file
- [AI-Native SDLC Alignment](docs/ai-native-sdlc.md) — temper vs Anthropic's playbook, play by play
- [Recommended Setup](docs/recommended-setup.md) · [Enterprise](docs/enterprise.md) · [Privacy](https://galando.github.io/temper/privacy.html)

## Contributing & License

[CONTRIBUTING.md](CONTRIBUTING.md) · MIT © [Gal Naor](https://github.com/galando)
