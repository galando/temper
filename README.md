<div align="center">

# Temper

**Your AI writes fast. Temper makes it last.**

*Quality gates, blast radius analysis, and adaptive learning for AI-generated code*

[![Version](https://img.shields.io/github/v/release/galando/temper?include_prereleases)](https://github.com/galando/temper/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)](https://claude.ai/claude-code)
[![OpenCode](https://img.shields.io/badge/OpenCode-Compatible-orange.svg)](https://opencode.ai)

[Website](https://galando.github.io/temper) • [Quick Start](#-quick-start) • [Commands](#-commands) • [Releases](https://github.com/galando/temper/releases)

---

</div>

## What is Temper?

Temper transforms your AI assistant from a code generator into a **disciplined software engineer**. Works with Claude Code, OpenCode, and any AI assistant that reads markdown instructions.

```
Before Temper:  AI writes code → you review → bugs slip through
After Temper:   AI plans → validates → tests → implements → self-reviews → ships
```

## Quick Start

```bash
# Claude Code
/plugin marketplace add galando/temper
/plugin install temper

# OpenCode
git clone https://github.com/galando/temper.git
cp -r temper/.claude ~/.config/opencode/

# Use it
/temper:check           # Auto-detects your stack
/temper:plan "feature"  # Plan with impact analysis
/temper:build           # Build with TDD + quality gates
```

## Commands

| Command | Purpose |
|---------|---------|
| `/temper:plan` | Plan with blast radius analysis |
| `/temper:build` | Build with TDD + quality gates |
| `/temper:review` | Code review with confidence scoring |
| `/temper:check` | Stack validation (auto-detects) |
| `/temper:fix` | Root cause analysis + fix |
| `/temper:standards` | Build team standards |
| `/temper:status` | Quality metrics dashboard |

## Why Temper?

| Feature | Description |
|---------|-------------|
| **Blast Radius Analysis** | Maps affected files, dependencies, and risk areas before coding |
| **Enforced Quality Gates** | Tests must pass, coverage must be met — AI cannot proceed until verified |
| **Adaptive Learning** | Gets smarter over time, tracks patterns and suggests custom rules |
| **2KB Context** | Tiny footprint, commands load on-demand |

## Built-in Packs

| Pack | Severity | What it enforces |
|------|----------|-----------------|
| `quality` | BLOCK | Method length, DRY, naming, complexity |
| `tdd` | WARN | RED-GREEN-REFACTOR, coverage thresholds |
| `security` | BLOCK | OWASP Top 10, no secrets in code |
| `git` | SUGGEST | Conventional commits, branching |

## Supported Stacks

Spring Boot • React + TS • Node/Express • FastAPI • Go • Rust

## Documentation

Full documentation at **[galando.github.io/temper](https://galando.github.io/temper)**

## License

MIT © [Gal Naor](https://github.com/galando)
