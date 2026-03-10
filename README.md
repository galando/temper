<div align="center">

# Temper

**Your AI writes fast. Temper makes it last.**

*Quality gates, blast radius analysis, and adaptive learning for AI-generated code*

[![Version](https://img.shields.io/github/v/release/galando/temper?include_prereleases)](https://github.com/galando/temper/releases)
[![npm version](https://img.shields.io/npm/v/@galando/temper.svg)](https://www.npmjs.com/package/@galando/temper)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)](https://claude.ai/claude-code)
[![OpenCode](https://img.shields.io/badge/OpenCode-npm%20Plugin-orange.svg)](https://opencode.ai)
[![DeepWiki](https://img.shields.io/badge/DeepWiki-Documentation-blue.svg)](https://deepwiki.com/galando/temper)

[Website](https://galando.github.io/temper) • [DeepWiki](https://deepwiki.com/galando/temper) • [npm](https://www.npmjs.com/package/@galando/temper) • [Releases](https://github.com/galando/temper/releases)

---

</div>

## What is Temper?

Temper transforms your AI assistant from a code generator into a **disciplined software engineer**. It's not a linter, not a CI tool — it's **instructions that shape AI behavior**.

Works with **Claude Code**, **OpenCode**, and any AI assistant that reads markdown instructions.

```
Before Temper:  AI writes code → you review → bugs slip through → technical debt accumulates
After Temper:   AI plans → validates → writes tests → implements → self-reviews → ships with confidence
```

## Quick Start

```bash
# Claude Code
/plugin marketplace add galando/temper
/plugin install temper

# OpenCode (npm plugin - recommended)
opencode plugin add @galando/temper

# OpenCode (manual installation)
git clone https://github.com/galando/temper.git
cp -r temper/.claude ~/.config/opencode/

# Use it
cd your-project
/temper:check           # Auto-detects your stack
/temper:plan "feature"  # Plan with impact analysis
/temper:build           # Build with TDD + quality gates
```

### OpenCode Configuration

Add to your `opencode.json`:
```json
{
  "plugin": ["@galando/temper"]
}
```

Then use Temper tools:
```
temper_plan({ feature: "add OAuth" })
temper_build({})
temper_review({})
temper_check({})
```

## Why Temper?

| Feature | What it means |
|---------|---------------|
| **Blast Radius Analysis** | Understands impact before coding. Maps affected files, dependencies, and risk areas. |
| **Enforced Quality Gates** | Tests must pass. Coverage must be met. The AI cannot proceed until verified. |
| **Adaptive Learning** | Gets smarter as you use it. Tracks patterns and suggests custom rules. |
| **2KB Context** | Tiny footprint. Always-on config is minimal, commands load on-demand. |

## Commands

| Command | Purpose | Example |
|---------|---------|---------|
| `/temper:plan` | Plan with blast radius analysis | `/temper:plan "add OAuth"` |
| `/temper:build` | Build with TDD + quality gates | `/temper:build` |
| `/temper:review` | Code review with confidence scoring | `/temper:review` |
| `/temper:check` | Stack validation (auto-detects) | `/temper:check` |
| `/temper:fix` | Root cause analysis + fix | `/temper:fix "JIRA-123"` |
| `/temper:standards` | Build team standards | `/temper:standards` |
| `/temper:status` | Quality metrics dashboard | `/temper:status` |

## The User Flow

### 1. Plan — *You type*
```
/temper:plan "add user authentication"
```
You describe what you want. Temper automatically analyzes the blast radius — mapping affected files, dependencies, and risk areas.

### 2. Build — *Automated*
```
/temper:build
```
Temper implements automatically with TDD gates enforced. Tests written first, code follows. Cannot proceed until tests pass.

### 3. Review — *Automated*
```
/temper:review
```
Temper reviews automatically against enabled packs. Findings scored by confidence — high-confidence issues require attention.

### 4. Track & Learn — *Automated*
```
/temper:status
```
Temper learns over time. Tracks patterns, coverage trends, and suggests new rules based on your codebase.

## Adaptive Learning

Temper gets smarter the more you use it:

- **Pattern Detection** — Identifies recurring issues and anti-patterns in your code
- **Rule Suggestions** — Proposes new rules based on what it learns from your reviews
- **Noise Reduction** — Suppresses false positives as it learns your codebase patterns

---

## Quality Packs

Packs are collections of rules that Temper enforces during code generation and review. Each pack has rules at three severity levels:

| Severity | Behavior |
|----------|----------|
| **BLOCK** | Stops progress until issue is fixed. Used for critical rules. |
| **WARN** | Flags issue but allows progress. Requires acknowledgment. |
| **SUGGEST** | Informational. Logged but doesn't block or warn. |

### Built-in Packs

| Pack | Severity | What it enforces |
|------|----------|-----------------|
| `quality` | BLOCK | Code quality — method length, DRY, naming, complexity |
| `tdd` | WARN | Test-driven development — RED-GREEN-REFACTOR, coverage |
| `security` | BLOCK | Security — OWASP Top 10, no secrets in code |
| `git` | SUGGEST | Git workflow — conventional commits, branching |

### Pack Locations

Temper looks for packs in these locations (in order):

1. **Project packs** — `.claude/packs/` in your project
2. **Built-in packs** — Shipped with Temper

### Creating Custom Packs

Add a `rules.md` file to your project and Temper will automatically discover it:

```markdown
# .claude/packs/my-company/rules.md

# My Company Standards

## BLOCK
- All API responses use DTOs
- No raw SQL queries
- Services must be stateless

## WARN
- Constructor injection only
- Max method length: 20 lines
- Avoid nested conditionals (max 2 levels)

## SUGGEST
- Use Optional instead of null
- Prefer immutable data structures
- Document public APIs
```

That's it. Temper will now enforce these rules automatically during `/temper:build` and `/temper:review`.

### Creating Packs Interactively

Run `/temper:standards` to create a pack interactively:

1. Temper scans your codebase for patterns
2. Asks questions about your preferences
3. Generates a custom `rules.md` based on your answers

### Pack Structure

```text
.claude/packs/
├── my-company/
│   ├── rules.md        # Required: The rules file
│   └── examples/       # Optional: Code examples
│       ├── good.ts     # Good example
│       └── bad.ts      # Bad example
```

### Rule Syntax

```markdown
## BLOCK
- Rule description
- Another rule with details

## WARN
- Warning-level rule
- Another warning

## SUGGEST
- Suggestion for improvement
```

### Best Practices for Packs

1. **Start with WARN** — New rules should warn first, promote to BLOCK after team alignment
2. **Be specific** — "Max 20 lines per method" is better than "Keep methods short"
3. **Include rationale** — Add comments explaining *why* a rule exists
4. **Review periodically** — Remove outdated rules, promote working SUGGESTs to WARN

---

## Supported Stacks

| Stack | Detection | Auto-Commands |
|-------|-----------|---------------|
| Spring Boot | `pom.xml` / `build.gradle` | `mvn compile`, `mvn test`, `mvn build` |
| React + TS | `package.json` + `tsconfig.json` | `npm test`, `npm run build`, `npm run lint` |
| Node/Express | `package.json` + express | `npm test`, `npm run build`, `npm run lint` |
| FastAPI | `pyproject.toml` + fastapi | `pytest`, `ruff check`, `mypy` |
| Go | `go.mod` | `go test`, `golangci-lint`, `go build` |
| Rust | `Cargo.toml` | `cargo test`, `cargo clippy`, `cargo build` |

## How It Works

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        AI Coding Session                                 │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  You type ───────► Temper Commands ───────► AI Instructions             │
│                                                │                         │
│                      ┌─────────────────────────┴────────────────┐       │
│                      │                                          │       │
│                      ▼                                          ▼       │
│               ┌─────────────┐                            ┌──────────┐   │
│               │   PHASE 1   │                            │  PHASE 2 │   │
│               │ Blast Radius │───────┬─────────────────► │ Quality  │   │
│               │   Analysis   │       │                   │  Gates   │   │
│               └─────────────┘       │                   └──────────┘   │
│                      │              │                         │         │
│                      │   Impact     │   Validation           │   Test   │
│                      │   Map        │   Rules                │   Gates  │
│                      │              │                         │         │
│                      └──────────────┴─────────────────────────┘         │
│                                     │                                    │
│                                     ▼                                    │
│                    ┌────────────────────────────────┐                    │
│                    │   Production-Grade Code Output  │                   │
│                    │   • Tests pass                  │                   │
│                    │   • Quality gates satisfied     │                   │
│                    │   • Impact understood           │                   │
│                    │   • Learns from patterns        │                   │
│                    └────────────────────────────────┘                    │
└─────────────────────────────────────────────────────────────────────────┘
```

**The pipeline is sequential:**

1. **Blast Radius Analysis (Phase 1)** — Maps every file that will be affected, identifies dependencies and risk areas.

2. **Quality Gates (Phase 2)** — Enforces validation rules. Tests must pass, linting must be clean, coverage thresholds must be met.

**Why this produces exceptional results:**

- **Forced discipline** — The AI can't cut corners, every gate must pass
- **Informed decisions** — Blast radius means the AI understands context before coding
- **Self-verification** — The AI reviews its own work against objective criteria
- **Learning loop** — Patterns from reviews feed back into future suggestions

## Releases & Versioning

Temper follows [semantic versioning](https://semver.org/). Each release is tagged and includes a changelog.

**Installing a specific version:**
```bash
# Claude Code - Clone a specific release
git clone --depth 1 --branch v1.1.0 https://github.com/galando/temper.git

# OpenCode - Install specific npm version
opencode plugin add @galando/temper@1.1.0
```

See [Releases](https://github.com/galando/temper/releases) for full changelog.

### Distribution Channels

| Platform | Package | Install |
|----------|---------|---------|
| Claude Code | GitHub Repo | `/plugin marketplace add galando/temper` |
| OpenCode | `@galando/temper` on npm | `opencode plugin add @galando/temper` |

## Documentation

- [Website](https://galando.github.io/temper) — Full documentation
- [DeepWiki](https://deepwiki.com/galando/temper) — AI-powered documentation
- [Getting Started](https://galando.github.io/temper/getting-started) — Step-by-step guide
- [Enterprise Setup](docs/enterprise.md) — Deploy across your organization
- [npm Package](https://www.npmjs.com/package/@galando/temper) — OpenCode plugin

## Contributing

We love contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

```bash
git clone https://github.com/galando/temper.git
cd temper
# Make your changes, test with your own projects
```

## License

MIT © [Gal Naor](https://github.com/galando)

---

<div align="center">

**[Back to Top](#temper)**

Made with care for the AI coding community

</div>
