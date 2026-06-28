<div align="center">

# Temper

**Your AI writes fast. Temper makes it last.**

*Quality gates, blast radius analysis, and intent-driven development for AI-generated code*

[![Version](https://img.shields.io/github/v/release/galando/temper?include_prereleases)](https://github.com/galando/temper/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)](https://claude.ai/claude-code)
[![DeepWiki](https://img.shields.io/badge/DeepWiki-Documentation-blue.svg)](https://deepwiki.com/galando/temper)

[Website](https://galando.github.io/temper) · [Getting Started](docs/getting-started.md) · [Releases](https://github.com/galando/temper/releases)

</div>

> **Quick Start:** `/plugin marketplace add galando/temper` then `/temper "add password reset"` — one command for the full pipeline.

## The Problem

AI writes code fast. But "fast" without "right" creates bugs, technical debt, and features that miss the point. AI-generated code has **structural failure patterns**:

| Pattern | What Goes Wrong |
|---------|----------------|
| Missing behaviors | Happy path works, edge cases never implemented |
| Wrong problem solved | Feature works perfectly, but nobody asked for it |
| Over-engineering | Factories and strategies for something used once |
| Hallucinated APIs | Methods called that don't exist |
| Missing wiring | Code correct, integration missing |

Most AI tools check if code compiles. Temper checks if it solves the right problem, handles edge cases, and is safe to ship.

## The Catch

The rate-limiting bug that vanilla AI always misses:

```gherkin
Scenario: Rate limiting on reset requests
  Given a user has requested 3 resets in 10 minutes
  When they request another reset
  Then the request is rejected with 429
```

AI built password reset. All tests pass. But Temper's **scenario coverage gate** caught the gap: no test for rate limiting. Build wrote the test. Test failed. Build implemented rate limiting. Test passed. Without the coverage gate, rate limiting would never have been implemented.

More: [Evidence Gallery](docs/evidence/)

## How It Works

Three methodologies, one contract file (`intent.md`):

```
intent.md
|
+-- Intent (IDD)           WHY are we building this?
|   Problem, success criteria, constraints
|
+-- Scenarios (BDD)        WHAT should it do?
|   Gherkin Given/When/Then, derived BEFORE architecture
|
+-- /temper:build (TDD)    HOW do we build it?
    Tests from scenarios, RED → GREEN → REFACTOR
```

**Key insight:** Scenarios are derived *before* architecture. The file plan follows from what the system must do, not the other way around. This prevents over-engineering structurally.

Full methodology: [docs/methodology.md](docs/methodology.md)

## Token Efficiency (v5.9.0)

Temper cuts a run's token cost with three optimizations — **all ON by default**, all revert to v5.8.0 when their flag is off:

| Optimization | Default | Quality tradeoff |
|--------------|---------|------------------|
| **Cache** static methodology reads | `on` | None — same reads, ~90% off re-read cost |
| **Adaptive depth** — size the pipeline to the change | `on` (`floor: simple`) | Only one with a tradeoff — see below |
| **Incremental loops** — inline auto-fix, no subprocess | `on` (`inline-threshold: 3`) | None for auto-fixable findings |

**The one decision you make:** adaptive-depth runs a lighter pipeline on small changes. It's safe when the change is genuinely isolated — but if it touches a shared interface, auth, money, or has an unclear blast radius, click **"Escalate to full pipeline"** at the plan gate (one click, that change only — no config editing). For a whole high-stakes codebase, set `floor: medium` in `.claude/temper.config` once and never think about it again.

Full explanation (mechanism, tiers, decision rule, when quality drops): **[docs/token-efficiency.md](docs/token-efficiency.md)**

### Autonomous Continuation (opt-in)

After you approve the plan, `/temper` can run the remaining stages
(design → build → review → check → eval) unattended and leave a report.
It never pushes or merges, never re-plans on its own, and parks before
commit and on anything needing a human. Turn it off and Temper behaves
exactly as before.

First run: pre-allow your build/test commands in `settings.json`, or the run
parks on the first unpermitted command. No config yet? `/temper:init` seeds
one. Details: docs/proposals/autonomous-mode.md

## Commands

| Command | Purpose |
|---------|---------|
| [`/temper`](docs/commands.md#temper) | Full pipeline: plan → design? → build → review → check |
| [`/temper:plan`](docs/commands.md#temperplan) | Blast radius + BDD scenarios + architecture |
| [`/temper:design`](docs/commands.md#temperdesign) | System design (complex/medium features) |
| [`/temper:build`](docs/commands.md#temperbuild) | Scenario-driven TDD + coverage gate |
| [`/temper:review`](docs/commands.md#temperreview) | Intent validation + confidence scoring |
| [`/temper:check`](docs/commands.md#tempercheck) | Stack-aware validation pipeline |
| [`/temper:fix`](docs/commands.md#temperfix) | Root cause analysis + regression test |
| [`/temper:pack`](docs/commands.md#temperpack) | Manage quality packs |
| [`/temper:status`](docs/commands.md#temperstatus) | Quality metrics + observability dashboard |

## Quality Packs

Rule sets enforced during code generation and review. Three-tier resolution: project-local → global → built-in.

| Pack | What It Enforces |
|------|-------------------|
| `quality` | Method length, DRY, naming, complexity |
| `tdd` | RED-GREEN-REFACTOR, coverage |
| `security` | OWASP Top 10, no secrets in code |
| `performance` | N+1 detection, pagination, Core Web Vitals |
| `api-design` | Additive extension, idempotency, consistent naming |
| `architecture-depth` | Module depth: seams, adapters, locality, leverage |

Create custom packs with `/temper:pack` or add a `rules.md` to `.claude/packs/your-pack/`.

## Installation

### Claude Code

```bash
/plugin marketplace add galando/temper
/plugin install temper
```

### Cursor IDE

```bash
# Into a Temper repo checkout (regenerates .cursor/ from .claude/ sources):
./scripts/install-cursor.sh

# Into an arbitrary project (downloads a static snapshot):
bash <(curl -fsSL https://raw.githubusercontent.com/galando/temper/main/scripts/install-cursor.sh)
```

Cursor support is **frozen at the v5.1 feature set** (CHANGELOG v5.2.1 platform strategy). New capabilities ship Claude Code-first. The `.cursor/` export is **regenerated from `.claude/` sources on every release** via `scripts/generate-cursor.sh` — parity is honest and consistent, not stale-by-accident. Running `install-cursor.sh` inside a repo checkout delegates to the generator (offline, idempotent).

## Recommended Setup

Temper works out of the box. Two optional MCP servers upgrade heuristic analysis to mechanically verified findings:

| Server | Provides | Install |
|--------|----------|---------|
| [code-review-graph](docs/recommended-setup.md) | AST-level dependency graphs, call chains, impact radius | `pip install code-review-graph` |
| [semgrep](docs/recommended-setup.md) | SAST scanning, security vulnerabilities | `brew install semgrep` |
| [open-code-review](docs/recommended-setup.md) | External LLM-powered defect detection (Alibaba) | `npm install -g @alibaba-group/open-code-review` |

```bash
# Register with Claude Code (requires restart)
claude mcp add code-review-graph -- code-review-graph
claude mcp add semgrep -- semgrep --mcp
```

Every finding carries an evidence label: `[PROVEN]` (tool-verified), `[HEURISTIC]` (grep-based), `[SEMANTIC]` (judgment), `[OCR]` (external engine).

Full setup: [docs/recommended-setup.md](docs/recommended-setup.md)

## Supported Stacks

| Stack | Detection | Auto-Commands |
|-------|-----------|---------------|
| Spring Boot | `pom.xml` / `build.gradle` | `mvn compile`, `mvn test` |
| React + TS | `package.json` + `tsconfig.json` | `npm test`, `npm run build` |
| Node/Express | `package.json` + express | `npm test`, `npm run lint` |
| FastAPI | `pyproject.toml` + fastapi | `pytest`, `ruff check` |
| Go | `go.mod` | `go test`, `golangci-lint` |
| Rust | `Cargo.toml` | `cargo test`, `cargo clippy` |

## Documentation

- [Getting Started](docs/getting-started.md) — Step-by-step guide
- [Commands Reference](docs/commands.md) — Full command documentation
- [Packs](docs/packs.md) — Built-in and custom packs
- [Methodology](docs/methodology.md) — IDD, BDD, TDD deep dive
- [Token Efficiency](docs/token-efficiency.md) — caching, adaptive depth, incremental loops (v5.9.0)
- [Recommended Setup](docs/recommended-setup.md) — MCP servers and live verification
- [Enterprise Setup](docs/enterprise.md) — Deploy across your organization

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT (c) [Gal Naor](https://github.com/galando)

---

<div align="center">

**[Back to Top](#temper)**

Made with care for the AI coding community

</div>
