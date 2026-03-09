<div align="center">

# 🌡️ Temper

**Your AI writes fast. Temper makes it last.**

*Quality gates, blast radius analysis, and adaptive learning for AI-generated code*

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/galando/temper)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)](https://claude.ai/claude-code)
[![OpenCode](https://img.shields.io/badge/OpenCode-Compatible-orange.svg)](https://opencode.ai)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

[Quick Start](#-quick-start) • [Commands](#-commands) • [Documentation](https://galando.github.io/temper) • [Why Temper?](#-why-temper)

---

</div>

## ✨ What is Temper?

Temper is an **AI coding assistant plugin** that transforms your AI from a code generator into a **disciplined software engineer**. It's not a linter, not a CI tool — it's **instructions that shape AI behavior**.

Works with **Claude Code**, **OpenCode**, and any AI assistant that reads markdown instructions.

```
Before Temper:  AI writes code → you review → bugs slip through → technical debt accumulates
After Temper:   AI plans → validates → writes tests → implements → self-reviews → ships with confidence
```

## 🎬 Demo

```
You: /temper:plan "add user authentication"

Temper: 🔍 Analyzing blast radius...
        📦 12 files will be affected
        🔗 Dependencies: UserService, AuthMiddleware, SessionStore
        ⚠️  Risk areas: Password hashing, Token refresh

        Plan ready. 7 implementation steps with test gates.
```

## 🚀 Quick Start

### Claude Code

```bash
# Install the plugin
/plugin marketplace add galando/temper
/plugin install temper
```

### OpenCode

```bash
# Clone into your project or globally
git clone https://github.com/galando/temper.git
cp -r temper/.claude ~/.config/opencode/
```

### Use it

```bash
cd your-project
/temper:check           # Auto-detects your stack
/temper:plan "feature"  # Plan with impact analysis
/temper:build           # Build with TDD + quality gates
```

## 📋 Commands

| Command | Purpose | Example |
|---------|---------|---------|
| `/temper:plan` | Plan with blast radius analysis | `/temper:plan "add OAuth"` |
| `/temper:build` | Build with TDD + quality gates | `/temper:build` |
| `/temper:review` | Code review with confidence scoring | `/temper:review` |
| `/temper:check` | Stack validation (auto-detects) | `/temper:check` |
| `/temper:fix` | Root cause analysis + fix | `/temper:fix "JIRA-123"` |
| `/temper:standards` | Build team standards | `/temper:standards` |
| `/temper:status` | Quality metrics dashboard | `/temper:status` |

## 🎯 Why Temper?

| Feature | What it means |
|---------|---------------|
| **Zero Config** | Auto-detects your stack, runs your test commands |
| **Blast Radius** | Understands how changes ripple through your codebase |
| **Confidence Scoring** | High-signal findings, minimal false positives |
| **Adaptive Learning** | Tracks patterns, suppresses noise, suggests rules |
| **Debt Tracking** | Coverage trends, hotspots, improvement over time |
| **Company-ready** | Standards builder, custom packs, presets |
| **Context-efficient** | ~2KB always-on (not 60KB) |

## 🔧 Supported Stacks

| Stack | Detection | Auto-Commands |
|-------|-----------|---------------|
| ![Spring Boot](https://img.shields.io/badge/Spring_Boot-6DB33F?style=flat&logo=springboot) | `pom.xml` / `build.gradle` | `mvn compile`, `mvn test`, `mvn build` |
| ![React + TS](https://img.shields.io/badge/React_TS-3178C6?style=flat&logo=react) | `package.json` + `tsconfig.json` | `npm test`, `npm run build`, `npm run lint` |
| ![Node/Express](https://img.shields.io/badge/Node_Express-339933?style=flat&logo=node.js) | `package.json` + express | `npm test`, `npm run build`, `npm run lint` |
| ![FastAPI](https://img.shields.io/badge/FastAPI-009688?style=flat&logo=fastapi) | `pyproject.toml` + fastapi | `pytest`, `ruff check`, `mypy` |
| ![Go](https://img.shields.io/badge/Go-00ADD8?style=flat&logo=go) | `go.mod` | `go test`, `golangci-lint`, `go build` |
| ![Rust](https://img.shields.io/badge/Rust-000000?style=flat&logo=rust) | `Cargo.toml` | `cargo test`, `cargo clippy`, `cargo build` |

## 📦 Built-in Packs

Temper ships with 4 quality packs out of the box:

| Pack | What it enforces |
|------|-----------------|
| `quality` | Code quality — method length, DRY, naming conventions |
| `tdd` | Test-driven development — RED-GREEN-REFACTOR cycle |
| `security` | Security best practices — OWASP Top 10 |
| `git` | Git workflow — conventional commits, branching strategy |

Create your own by adding `rules.md` to `.claude/packs/{your-pack}/`.

## 🏢 For Companies

```bash
/temper:standards
```

Temper scans your codebase, asks the right questions, and generates your **engineering standards as a pack**. Distribute the `.claude/` directory to every project.

→ [Enterprise Setup Guide](docs/enterprise.md)

## 🏗️ How It Works

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        AI Coding Session                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  User Input ──────► Temper Commands ──────► AI Instructions             │
│                                               │                          │
│                      ┌────────────────────────┴────────────────┐        │
│                      │                                         │        │
│                      ▼                                         ▼        │
│               ┌─────────────┐                           ┌──────────┐    │
│               │   PHASE 1   │                           │  PHASE 2 │    │
│               │ Blast Radius │───────┬─────────────────►│ Quality  │    │
│               │   Analysis   │       │                  │  Gates   │    │
│               └─────────────┘       │                  └──────────┘    │
│                      │              │                        │          │
│                      │   Impact     │   Validation          │   Test    │
│                      │   Map        │   Rules               │   Gates   │
│                      │              │                        │          │
│                      └──────────────┴────────────────────────┘          │
│                                     │                                    │
│                                     ▼                                    │
│                    ┌────────────────────────────────┐                    │
│                    │   Production-Grade Code Output  │                   │
│                    │   • Tests pass                  │                   │
│                    │   • Quality gates satisfied     │                   │
│                    │   • Impact understood           │                   │
│                    │   • Technical debt tracked      │                   │
│                    └────────────────────────────────┘                    │
└─────────────────────────────────────────────────────────────────────────┘
```

**The pipeline is sequential, not parallel:**

1. **Blast Radius Analysis (Phase 1)** — First, Temper maps every file that will be affected by your change. It identifies dependencies, risk areas, and the true scope of work. This prevents "I just changed one thing and broke everything" surprises.

2. **Quality Gates (Phase 2)** — Then, Temper enforces validation rules. Tests must pass. Linting must be clean. Coverage thresholds must be met. The AI cannot proceed until gates are satisfied.

**Why this produces exceptional results:**

- **Forced discipline**: The AI can't cut corners — every gate must pass
- **Informed decisions**: Blast radius means the AI understands context before coding
- **Self-verification**: The AI reviews its own work against objective criteria
- **Learning loop**: Patterns from reviews feed back into future suggestions

**Key insight**: Temper is 100% markdown — no executables, no binaries, no external dependencies. It's AI instructions that teach any coding assistant engineering discipline.

| Component | Context Cost |
|-----------|-------------|
| Always-on config | ~2 KB |
| Per command | ~5-15 KB |
| Full pack | ~20-30 KB |

## 📖 Documentation

- [Getting Started](https://galando.github.io/temper) — Full documentation
- [Enterprise Setup](docs/enterprise.md) — Deploy across your organization
- [Pack Versioning](docs/pack-versioning.md) — Manage pack updates

## 🤝 Contributing

We love contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

```bash
# Quick contrib setup
git clone https://github.com/galando/temper.git
cd temper
# Make your changes, test with your own projects
```

## 📜 License

MIT © [Gal Naor](https://github.com/galando)

---

<div align="center">

**[⬆ Back to Top](#-temper)**

Made with ❤️ for the AI coding community

</div>
