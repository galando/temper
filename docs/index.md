---
title: Home
nav_order: 1
---

# 🌡️ Temper

{: .fs-9 }

Your AI writes fast. Temper makes it last.
{: .fs-6 .fw-300 }

[Get started now](#quick-start){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View on GitHub](https://github.com/galando/temper){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## What is Temper?

Temper is an **AI coding assistant plugin** that transforms your AI from a code generator into a **disciplined software engineer**. It's not a linter, not a CI tool — it's **instructions that shape AI behavior**.

Works with **Claude Code**, **OpenCode**, and any AI assistant that reads markdown instructions.

```
Before Temper:  AI writes code → you review → bugs slip through → technical debt accumulates
After Temper:   AI plans → validates → writes tests → implements → self-reviews → ships with confidence
```

## Quick Start

### Claude Code

```bash
/plugin marketplace add galando/temper
/plugin install temper
```

### OpenCode

**Option 1: npm Plugin (Recommended)**

```bash
opencode plugin add @galando/temper
```

Or add to your `opencode.json`:
```json
{
  "plugin": ["@galando/temper"]
}
```

**Option 2: Manual Installation**

```bash
git clone https://github.com/galando/temper.git
cp -r temper/.claude ~/.config/opencode/
```

### Use it

```bash
/temper:check           # Auto-detects your stack
/temper:plan "feature"  # Plan with impact analysis
/temper:build           # Build with TDD + quality gates
```

## Features

| Feature | Description |
|---------|-------------|
| **Zero Config** | Auto-detects your stack, runs your test commands |
| **Blast Radius** | Understands how changes ripple through your codebase |
| **Confidence Scoring** | High-signal findings, minimal false positives |
| **Adaptive Learning** | Tracks patterns, suppresses noise, suggests rules |
| **Debt Tracking** | Coverage trends, hotspots, improvement over time |
| **Company-ready** | Standards builder, custom packs, presets |
| **Context-efficient** | ~2KB always-on (not 60KB) |

## Commands

| Command | Purpose |
|---------|---------|
| [`/temper:plan`](commands.html#plan) | Plan with blast radius analysis |
| [`/temper:build`](commands.html#build) | Build with TDD + quality gates |
| [`/temper:review`](commands.html#review) | Code review with confidence scoring |
| [`/temper:check`](commands.html#check) | Stack validation (auto-detects) |
| [`/temper:fix`](commands.html#fix) | Root cause analysis + fix |
| [`/temper:standards`](commands.html#standards) | Build team standards |
| [`/temper:status`](commands.html#status) | Quality metrics dashboard |

## How It Works

{: .important }
Temper is 100% markdown — no executables, no binaries, no external dependencies.

The pipeline is sequential:

1. **Blast Radius Analysis (Phase 1)** — Maps every file affected by your change, identifies dependencies, risk areas, and the true scope of work.

2. **Quality Gates (Phase 2)** — Enforces validation rules. Tests must pass. Linting must be clean. Coverage thresholds must be met.

This produces **production-grade code** because:
- The AI can't cut corners — every gate must pass
- The AI understands context before coding (blast radius)
- The AI reviews its own work against objective criteria
- Patterns from reviews feed back into future suggestions

## Next Steps

- [Getting Started Guide](getting-started) — Detailed installation and setup
- [Commands Reference](commands) — Full command documentation
- [Packs](packs) — Built-in and custom packs
- [Enterprise Setup](enterprise) — Deploy across your organization
