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

AI writes code fast. But "fast" without "right" creates bugs, technical debt, and features that miss the point. AI-generated code has **structural failure patterns**:

| Pattern | What Goes Wrong |
|---------|----------------|
| Missing behaviors | Happy path works, edge cases never implemented |
| Wrong problem solved | Feature works perfectly, but nobody asked for it |
| Over-engineering | Factories and strategies for something used once |
| Hallucinated APIs | Methods called that don't exist |
| Missing wiring | Code correct, integration missing |

Most AI tools check if code compiles. Temper checks if it solves the right problem, handles edge cases, and is safe to ship — and since v7, it checks *mechanically*, not by asking the model to grade its own work.

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

## Deterministic Gates (v7)

Every gate verdict — Plan, Build, Review, Check, Eval, Commit — is computed by a small
CLI (`scripts/temper`) from an evidence ledger, never asserted by a model:

```
> temper gate check
temper gate check -> PASS
  [v] tests pass — 24 green test run(s) recorded
  [v] coverage >= threshold — 87.0% >= 80% threshold
```

- **Every claim carries proof.** `temper evidence add` records a command, exit code, and
  artifact. `PROVEN` is mechanically re-checked — a missing artifact or a nonzero exit
  auto-downgrades it to `HEURISTIC`. Nothing is labeled verified on faith.
- **`git commit` is physically blocked**, not just discouraged, while any gate is FAIL
  and unoverridden — a native pre-commit hook and an in-agent hook both run `temper gate
  commit`. A human can always override (recorded, never silently erased), but a
  confused model can't talk past a red gate.
- **The gate logic is ~20-30 lines of readable shell per stage** — `scripts/temper`, unit
  tested in `scripts/tests/test-temper.sh`. If you want to know exactly what "Check
  passed" means, read the function; you don't have to trust 1,000 lines of prompt.
- **Seeded-defect fixtures prove the pipeline catches real bugs — 3/3, verified live.**
  Three small projects, each with one known, planted defect (missing rate limiting, a
  hallucinated API call, a component never wired in). Run for real against both v6.0.1
  and this branch: both catch all three, and v7's catches are confirmed via the
  evidence ledger (`temper gate` mechanically FAILing with the defect named), not just
  a narrated summary. Details, including a real bug this run found and fixed:
  [`evals/README.md`](evals/README.md).

Full design rationale: [docs/plans/v7-deterministic-spine.md](docs/plans/v7-deterministic-spine.md)

### Autonomous Continuation (opt-in)

After you approve the plan, `/temper` can run the remaining stages
(design → build → review → check → eval) unattended and leave a report.
It never pushes or merges, never re-plans on its own, and parks before
commit and on anything needing a human — enforced by the same `temper gate`
mechanism as the interactive path, not a separate trust boundary.

First run: pre-allow your build/test commands in `settings.json`, or the run
parks on the first unpermitted command. No config yet? `/temper:init` seeds
one (and scaffolds `.temper/` for the CLI).

## Commands

| Command | Purpose |
|---------|---------|
| [`/temper`](docs/commands.md#temper) | Full pipeline: plan → design? → build → review → check → eval |
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

## Security & Trust

Temper is Markdown and ~500 lines of auditable shell — every command, skill, pack, and
gate is either a prompt file or a script you can read in this repository. The trust contract:

- **No network calls, no telemetry.** Temper never phones home. The only shell commands it runs are your project's own build/test/lint commands (plus its own gate script), and only under Claude Code's normal permission prompts.
- **Writes are confined to your project.** Temper writes `.claude/temper.config` (created by `/temper:init`, only with your approval) and its working files under `.temper/` in your project. It never touches files outside the project directory.
- **The commit gate is mechanical, not advisory.** `temper gate commit` — enforced by a real git pre-commit hook — blocks a commit whenever an upstream gate is FAIL and unoverridden. See [Deterministic Gates](#deterministic-gates-v7).
- **Autonomous Continuation is opt-in and fenced.** Armed per-run at the plan gate, never at invocation. It never commits, never pushes, never merges — it parks before commit and leaves a report.
- **Optional MCP servers are optional.** The recommended servers below only upgrade evidence quality; nothing breaks without them.

## Installation

### Claude Code

```bash
/plugin marketplace add galando/temper
/plugin install temper
bash "$CLAUDE_PLUGIN_ROOT/scripts/hooks/install.sh"   # installs the commit gate
```

### Cursor IDE (archived)

Cursor support is **archived** at the v6.0.1 snapshot (frozen feature set — CHANGELOG
v5.2.1 platform strategy) and is no longer regenerated per release; v7's CLI-backed
gates and `agents/` directory ship Claude Code-only. `./scripts/generate-cursor.sh`
still works if you want to hand-run it. Details: [`.cursor/README.md`](.cursor/README.md).

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

Every finding carries an evidence label — `PROVEN` (mechanically verified), `HEURISTIC`
(grep-based), `SEMANTIC` (judgment), `OCR` (external engine) — recorded in
`.temper/evidence/` by `temper evidence add`.

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
- [v7 Design](docs/plans/v7-deterministic-spine.md) — Why the CLI, the evidence ledger, the prompt diet
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
