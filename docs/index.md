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

AI writes code fast. But speed without discipline creates bugs, technical debt, and subtle issues that slip through review.

You've seen it: hallucinated APIs, over-engineered abstractions, missing error handling, code that works in isolation but breaks integration.

## The Solution

Temper is an **AI coding assistant plugin** that transforms your AI from a code generator into a **disciplined software engineer**.

```
Before Temper:  AI writes code → you review → bugs slip through → debt accumulates
After Temper:   AI plans → validates → tests → implements → self-reviews → ships
```

## The Proof

**Before Temper:** You add user authentication. AI generates code. Tests pass. You deploy. Users report password resets don't work. The queue consumer crashed silently. You debug for hours.

**After Temper:**

```
/temper:plan "add password reset"     # Maps blast radius, identifies dependencies
/temper:build                         # TDD gates: tests first, then implement
/temper:review                        # Catches N+1 queries, missing rate limiting
/temper:status                        # Tracks hotspots, suggests improvements
```

The queue consumer issue? Temper's blast radius analysis flagged the async dependency. The N+1 query? Caught in review. The missing rate limiting? Flagged as HIGH confidence.

## How It Works

{: .important }
Temper is 100% markdown — no executables, no binaries, no external dependencies.

**Phase 1: Blast Radius Analysis** — Maps every file affected by your change, identifies dependencies, risk areas, and the true scope of work.

**Phase 2: Quality Gates** — Enforces validation rules. Tests must pass. Linting must be clean. Coverage thresholds must be met.

This produces **production-grade code** because:
- The AI can't cut corners — every gate must pass
- The AI understands context before coding (blast radius)
- The AI reviews its own work against objective criteria
- Patterns from reviews feed back into future suggestions

## Commands

| Command | Purpose |
|---------|---------|
| [`/temper:plan`](commands.html#plan) | Plan with blast radius analysis, parallel task detection |
| [`/temper:build`](commands.html#build) | Build with TDD gates, resume from checkpoint |
| [`/temper:review`](commands.html#review) | Diff-aware review, confidence scoring |
| [`/temper:check`](commands.html#check) | Stack validation (auto-detects) |
| [`/temper:fix`](commands.html#fix) | Multi-hypothesis root cause analysis |
| [`/temper:standards`](commands.html#standards) | Build team standards interactively |
| [`/temper:status`](commands.html#status) | Quality metrics, hotspot tracking |

## Why Not Just "Be Careful"?

AI-generated code has **specific failure patterns** that "be careful" doesn't catch:

| Pattern | Why "be careful" misses it |
|---------|---------------------------|
| Hallucinated APIs | The AI is confident they exist |
| Over-engineering | Looks like "good design" |
| Copy-paste drift | Each block looks correct in isolation |
| Missing integration | Code is correct, wiring is missing |
| N+1 queries | Only appears under load |

[Learn more →](why-temper.html)

## Next Steps

- [Why Temper?](why-temper.html) — Why "be careful" isn't enough
- [Getting Started Guide](getting-started.html) — Detailed installation and setup
- [Commands Reference](commands.html) — Full command documentation
- [Packs](packs.html) — Built-in and custom quality packs
- [Enterprise Setup](enterprise.html) — Deploy across your organization
- [DeepWiki](https://deepwiki.com/galando/temper) — AI-powered documentation
