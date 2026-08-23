<div align="center">

# Temper

**Your AI writes fast. Temper makes it last.**

*Deterministic quality gates, blast radius analysis, and intent-driven development for AI-generated code*

[![Version](https://img.shields.io/github/v/release/galando/temper?include_prereleases)](https://github.com/galando/temper/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code Plugin](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)](https://claude.ai/claude-code)
[![DeepWiki](https://img.shields.io/badge/DeepWiki-Documentation-blue.svg)](https://deepwiki.com/galando/temper)
[![Eval Fixtures](https://github.com/galando/temper/actions/workflows/eval-fixtures.yml/badge.svg)](https://github.com/galando/temper/actions/workflows/eval-fixtures.yml)

[Website](https://galando.github.io/temper) · [Getting Started](docs/getting-started.md) · [Releases](https://github.com/galando/temper/releases)

</div>

> **Quick Start:** `/plugin marketplace add galando/temper` then `/temper "add password reset"` — one command for the full pipeline.
>
> **Headless / CI (`claude -p`):** use the fully-qualified name, `/temper:temper "..."` — the bare `/temper` alias only resolves in an interactive session.

## The Problem

AI writes code fast. But "fast" without "right" creates bugs, technical debt, and features that miss the point. AI-generated code has **structural failure patterns**: happy paths that work while edge cases are never implemented, features nobody asked for, factories for something used once, calls to methods that don't exist, correct code that was never wired in.

Most AI tools check whether code compiles. Temper checks whether it solves the right problem — and it checks *mechanically*, not by asking the model to grade its own work.

## The Catch

The rate-limiting bug that vanilla AI always misses:

```gherkin
Scenario: Rate limiting on reset requests
  Given a user has requested 3 resets in 10 minutes
  When they request another reset
  Then the request is rejected with 429
```

AI built password reset. All tests passed. Temper's **scenario coverage gate** caught the gap: no test for rate limiting. Build wrote the test, it failed, Build implemented rate limiting. Without the gate, it would never have been built.

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

Scenarios are derived *before* architecture, so the file plan follows from what the system must do. That prevents over-engineering structurally.

Full methodology: [docs/methodology.md](docs/methodology.md)

## Deterministic Gates

Every gate verdict — Plan, Build, Review, Check, Commit — is computed by a small CLI (`scripts/temper`) from an evidence ledger, never asserted by a model:

```
> temper gate check
temper gate check -> PASS
  [v] tests pass — 24 green test run(s) recorded
  [v] coverage >= threshold — 87.0% >= 80% threshold
```

- **Every claim carries proof.** `temper evidence add` records a command, exit code, and artifact. `PROVEN` is mechanically re-checked — a missing artifact or nonzero exit auto-downgrades it to `HEURISTIC`.
- **`git commit` is physically blocked** while any gate is FAIL and unoverridden, by a real pre-commit hook. A human can always override (recorded, never erased); a confused model can't talk past a red gate.
- **Gate logic is ~20-30 lines of readable shell per stage**, unit-tested in `scripts/tests/test-temper.sh`. To know what "Check passed" means, read the function — not 1,000 lines of prompt.
- **Seeded-defect fixtures prove it catches real bugs — 3/3, verified live.** Three projects, each with one planted defect (missing rate limiting, a hallucinated API call, a component never wired in). A gate must mechanically FAIL naming the defect; "some text roughly matches" doesn't count. Full story: [`evals/README.md`](evals/README.md).

Design rationale: [docs/plans/v7-deterministic-spine.md](docs/plans/v7-deterministic-spine.md)

### Autonomous Continuation (opt-in)

After you approve the plan, `/temper` can run the remaining stages unattended and leave a report. It never pushes or merges, never re-plans on its own, and parks before commit — enforced by the same `temper gate` mechanism as the interactive path.

First run: pre-allow your build/test commands in `settings.json`, or the run parks on the first unpermitted command. No config yet? `/temper:init` seeds one.

## Commands

| Command | Purpose |
|---------|---------|
| [`/temper`](docs/commands.md#temper) | Full pipeline: plan → design? → build → review → check |
| [`/temper:intent`](docs/commands.md#temperintent) | Capture an idea as a committed draft `intent.md` — build later |
| [`/temper:plan`](docs/commands.md#temperplan) | Blast radius + BDD scenarios + architecture |
| [`/temper:design`](docs/commands.md#temperdesign) | System design (complex/medium features) |
| [`/temper:build`](docs/commands.md#temperbuild) | Scenario-driven TDD + coverage gate |
| [`/temper:review`](docs/commands.md#temperreview) | Intent validation + confidence scoring |
| [`/temper:check`](docs/commands.md#tempercheck) | Stack-aware validation pipeline |
| [`/temper:fix`](docs/commands.md#temperfix) | Root cause analysis + regression test |
| [`/temper:pack`](docs/commands.md#temperpack) | Manage quality packs |
| [`/temper:status`](docs/commands.md#temperstatus) | Quality dashboard + gate ledger |
| [`/temper:init`](docs/commands.md) | Seed `.claude/temper.config` + `.temper/` (idempotent) |

## Quality Packs

Rule sets enforced during generation and review. Three-tier resolution: project-local → global → built-in.

| Pack | What It Enforces |
|------|-------------------|
| `quality` | Method length, DRY, naming, complexity |
| `tdd` | RED-GREEN-REFACTOR, coverage |
| `security` | OWASP Top 10, no secrets in code |
| `performance` | N+1 detection, pagination, Core Web Vitals |
| `api-design` | Additive extension, idempotency, consistent naming |
| `architecture-depth` | Module depth: seams, adapters, locality, leverage |

Create custom packs with `/temper:pack` or add a `rules.md` to `.claude/packs/your-pack/`.

## Security & Trust

Temper is Markdown and ~500 lines of auditable shell — every command, skill, pack, and gate is a file you can read in this repository.

- **No network calls, no telemetry.** The only shell commands it runs are your project's own build/test/lint commands plus its gate script, under Claude Code's normal permission prompts.
- **Writes stay in your project** — `.claude/temper.config` (only with your approval) and working files under `.temper/`.
- **The commit gate is mechanical, not advisory.** See [Deterministic Gates](#deterministic-gates).
- **Autonomous Continuation is opt-in and fenced.** Armed per-run at the plan gate. Never commits, pushes, or merges.

## Installation

```bash
/plugin marketplace add galando/temper
/plugin install temper
bash "$CLAUDE_PLUGIN_ROOT/scripts/hooks/install.sh"   # installs the commit gate
```

## Recommended Setup

Temper works out of the box. Optional MCP servers upgrade heuristic analysis to mechanically verified findings:

| Server | Provides | Install |
|--------|----------|---------|
| [code-review-graph](docs/recommended-setup.md) | AST-level dependency graphs, call chains, impact radius | `pip install code-review-graph` |
| [semgrep](docs/recommended-setup.md) | SAST scanning, security vulnerabilities | `brew install semgrep` |
| [open-code-review](docs/recommended-setup.md) | External LLM-powered defect detection (Alibaba) | `npm install -g @alibaba-group/open-code-review` |

```bash
claude mcp add code-review-graph -- code-review-graph
claude mcp add semgrep -- semgrep --mcp
```

Every finding carries an evidence label — `PROVEN`, `HEURISTIC`, `SEMANTIC`, or `OCR` — recorded in `.temper/evidence/`.

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
- [AI-Native SDLC Alignment](docs/ai-native-sdlc.md) — Temper mapped against Anthropic's playbook, play by play
- [Recommended Setup](docs/recommended-setup.md) — MCP servers and live verification
- [Enterprise Setup](docs/enterprise.md) — Deploy across your organization
- [Privacy Policy](https://galando.github.io/temper/privacy.html) — No data collected, no servers, no telemetry

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT (c) [Gal Naor](https://github.com/galando)

---

<div align="center">

**[Back to Top](#temper)**

Made with care for the AI coding community

</div>
