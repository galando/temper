---
title: Home
nav_order: 1
---

# Temper

{: .fs-9 }

**Your AI writes fast. Temper makes it last.**
{: .fs-6 .fw-300 }

[![Version](https://img.shields.io/github/v/release/galando/temper?include_prereleases)](https://github.com/galando/temper/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

[Get started now](#quick-start){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[Why Temper?](why-temper.html){: .btn .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View on GitHub](https://github.com/galando/temper){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## The Problem

AI writes code fast. But "fast" without "right" creates bugs, technical debt, and features that miss the point.

Three questions every AI-generated feature should answer:

1. **Did we solve the problem?** (Intent)
2. **Does it do the right things?** (Behavior)
3. **Does the code work?** (Tests)

Most AI tools answer only the third. Temper answers all three.

## IDD + BDD + TDD: Three Layers, One File

{: .important }
Temper is 100% markdown — no executables, no binaries, no external dependencies.

Temper combines three development methodologies in a single artifact called `intent.md`:

| Layer | Question | How Temper Does It |
|-------|----------|-------------------|
| **IDD** (Intent) | Did we solve the problem? | Success criteria with structured validation types |
| **BDD** (Behavior) | Does it do the right things? | Scenarios derived before architecture — they drive what gets built |
| **TDD** (Test) | Does the code work? | Tests written from scenarios — RED -> GREEN -> REFACTOR |

**Scenarios drive architecture.** Every planned file must trace to a behavior or infrastructure need. Success criteria are mechanically validated where possible.

## The Proof

**Before Temper:** You add user authentication. AI generates code. Tests pass. You deploy. Users report password resets don't work. The queue consumer crashed silently.

**After Temper:**

```
/temper:plan "add password reset"     # Blast radius + scenarios before architecture
/temper:build                         # Tests from scenarios -> coverage gate
/temper:review                        # Structured intent validation
/temper:status                        # Tracks hotspots, suggests improvements
```

The queue consumer issue? Blast radius flagged it. The missing rate limiting? Scenario coverage gate caught it — no test, so build wrote one, which failed, which forced the implementation.

## Commands

| Command | Purpose |
|---------|---------|
| [`/temper:plan`](commands.html#plan) | Blast radius + BDD scenarios + architecture |
| [`/temper:build`](commands.html#build) | Scenario-driven TDD gates, resume from checkpoint |
| [`/temper:review`](commands.html#review) | Structured intent validation + confidence scoring |
| [`/temper:check`](commands.html#check) | Stack validation (auto-detects) |
| [`/temper:fix`](commands.html#fix) | Multi-hypothesis root cause analysis |
| [`/temper:standards`](commands.html#standards) | Build team standards interactively |
| [`/temper:status`](commands.html#status) | Quality metrics, hotspot tracking |

## Quick Start

```bash
/plugin marketplace add galando/temper
/plugin install temper

cd your-project
/temper:plan "your feature"    # Scenarios + blast radius + architecture
/temper:build                  # Scenario-driven TDD
/temper:review                 # Intent validation
```

## Next Steps

- [Why Temper?](why-temper.html) — Why "be careful" isn't enough
- [Getting Started Guide](getting-started.html) — Detailed installation and setup
- [Commands Reference](commands.html) — Full command documentation
- [Packs](packs.html) — Built-in and custom quality packs
- [Enterprise Setup](enterprise.html) — Deploy across your organization
- [DeepWiki](https://deepwiki.com/galando/temper) — AI-powered documentation
