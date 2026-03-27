<div align="center">

# Temper

**Your AI writes fast. Temper makes it last.**

*Intent-driven development with behavioral testing and quality gates for AI-generated code*

<img src="docs/temper.png" alt="Temper Dashboard" width="100%">

[![Version](https://img.shields.io/github/v/release/galando/temper?include_prereleases)](https://github.com/galando/temper/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple.svg)](https://claude.ai/claude-code)
[![DeepWiki](https://img.shields.io/badge/DeepWiki-Documentation-blue.svg)](https://deepwiki.com/galando/temper)
[![Explained by GitHub Explainer](https://img.shields.io/badge/Explained%20by-GitHub%20Explainer-6366f1?style=flat&logo=github)](https://repoxplain.nl/repo/galando/temper?ref=badge)

[Website](https://galando.github.io/temper) | [Getting Started](docs/getting-started.md) | [Releases](https://github.com/galando/temper/releases)

---

</div>

## The Problem

AI writes code fast. But "fast" without "right" creates bugs, technical debt, and features that miss the point.

> "Why not just tell Claude to be careful?"

You can. And it helps. But AI-generated code has **structural failure patterns** that "be careful" doesn't address. These aren't sloppiness — they're limitations of how LLMs generate code:

- **Missing behaviors** — AI builds the happy path, skips edge cases. Rate limiting? Error recovery? Never implemented.
- **Wrong problem solved** — Feature works perfectly, but nobody asked for it. All tests pass, wrong thing built.
- **Over-engineering** — AI creates factories, strategies, and abstractions for something used exactly once.
- **Hallucinated APIs** — AI calls methods that don't exist. It's confident they do.
- **Missing wiring** — New code never registered in routing, DI, or config. The code itself is correct; the integration is missing.

These map to three unanswered questions:

| Question | What Goes Wrong Without It |
|----------|---------------------------|
| **Did we solve the problem?** | Feature works but nobody uses it. Wrong problem solved. |
| **Does it do the right things?** | Happy path works, edge cases ship broken. |
| **Does the code work?** | Tests pass, but they test implementation details, not behaviors. |

Most AI tools answer only the third. Temper answers all three.

---

## IDD + BDD + TDD: Three Layers, One File

Temper combines three development methodologies in a single artifact called `intent.md`. Each layer answers a different question and is enforced at a different stage of the pipeline:

```
intent.md
|
+-- Intent Section (IDD)        WHY are we building this?
|   |                            Problem statement
|   |                            Success criteria (each with a Validate: type)
|   |                            Constraints
|   |
+-- Scenarios Section (BDD)     WHAT should it do?
    |                            Gherkin Given/When/Then
    |                            Derived BEFORE architecture
    |                            Every planned file traces to a scenario
    |
    +-- /temper:build (TDD)      HOW do we build it?
                                 Tests written from scenarios
                                 RED -> GREEN -> REFACTOR
```

---

### IDD: Intent-Driven Development

**Question:** Did we solve the problem?
**When:** Defined during `/temper:plan`, validated during `/temper:review`

IDD captures the *why* behind a feature. Not "add a password reset endpoint" but "users should be able to reset their password without contacting support, completing the flow in under 2 minutes."

The Intent section of `intent.md` contains:

- **Problem** — What problem are we solving? For whom?
- **Success Criteria** — Measurable outcomes, each with a **`Validate:` type** that tells review *how* to check it
- **Constraints** — Technical or business limitations
- **Target Users** — Who benefits

#### Validate Types

Each success criterion gets a validation type. This is what makes IDD mechanical instead of subjective:

| Type | What It Means | How Review Checks It | Example |
|------|--------------|---------------------|---------|
| `scenario` | Criterion is satisfied when a linked BDD scenario's test passes | Finds the test, runs it, checks PASS | "Users can reset password" -> linked to scenario "Successful password reset" |
| `code` | Criterion is satisfied when specific code exists | Greps the codebase for the pattern | "POST /api/reset endpoint exists" -> greps for route definition |
| `metric` | Can't be verified before deployment | Flags for post-deploy monitoring | "Support tickets decrease 30%" -> requires production data |
| `manual` | Requires human judgment | Flags for human review, non-blocking | "Reset flow feels intuitive" -> UX review needed |

**Why this matters:** Without validate types, "intent validation" means the AI reads your success criteria and subjectively judges "yeah, this looks met." With validate types, most criteria are mechanically verified — a test passes or it doesn't, code exists or it doesn't. Only `metric` and `manual` require judgment.

#### Intent Validation in Review

When `/temper:review` runs, it produces:

```
Intent Validation (IDD): 4/5 (3 mechanical, 1 deferred, 1 manual)
  Problem: Users unable to reset passwords without support

  [x] Users can reset password without support
      validate: scenario -> test_successful_reset PASS
  [x] Reset endpoint exists at POST /api/reset
      validate: code -> route found in AuthController.ts:23
  [x] Rate limiting prevents abuse
      validate: scenario -> test_rate_limiting PASS
  [ ] Support ticket volume decreases 30%
      validate: metric -> post-deploy monitoring required
  [ ] Reset flow completes in under 2 minutes
      validate: manual -> requires human review

  Confidence: 3/5 mechanically verified
```

The higher the ratio of `scenario`/`code` criteria, the more confidence you have that the feature actually solves the stated problem.

---

### BDD: Behavior-Driven Development

**Question:** Does it do the right things?
**When:** Scenarios derived during `/temper:plan` (before architecture), enforced during `/temper:build`

BDD in Temper isn't an afterthought — **scenarios are derived before the architecture exists.** This is the key design decision. The flow is:

```
1. Blast radius analysis     -> identifies affected files and risk areas
2. Scenario derivation       -> behaviors from requirements + blast radius
3. Architecture from scenarios -> file list justified by scenarios
```

Not the other way around. This prevents the AI from planning 15 files and then writing scenarios that justify them. Instead, scenarios define what the system must do, and the file list follows.

#### Where Scenarios Come From

Scenarios aren't invented — they're derived from concrete sources:

| Source | Becomes |
|--------|---------|
| Feature description | Happy path scenarios |
| Acceptance criteria (Jira/GitHub issue) | Validation scenarios |
| Blast radius: risk areas | Edge case and error scenarios |
| Blast radius: affected consumers | Regression guard scenarios ("existing X still works") |

#### File-to-Scenario Traceability

Every file in the plan must justify its existence:

```
Scenario-traced files:
  src/services/PasswordResetService.ts  -> Scenario: "Successful password reset"
  src/middleware/RateLimiter.ts          -> Scenario: "Rate limiting enforced"

Infrastructure files (no scenario needed, but must state dependency):
  db/migrations/001_add_reset_tokens.sql -> Required by PasswordResetService
  config/email.ts                        -> Required by PasswordResetService
```

If the AI plans a file that no scenario needs and isn't infrastructure — that file shouldn't exist. This is how Temper prevents over-engineering structurally, not by hoping the AI "keeps it simple."

#### Scenario Coverage Gate

After all tasks complete, `/temper:build` runs the scenario coverage gate:

```
Scenario Coverage: 5/5
  [x] Successful password reset     -> test_successful_reset (PASS)
  [x] Expired token rejected        -> test_expired_token (PASS)
  [x] Rate limiting enforced        -> test_rate_limiting (PASS)
  [x] Invalid email format          -> test_invalid_email (PASS)
  [x] Non-existent user handled     -> test_nonexistent_user (PASS)
```

If any scenario has no passing test, build cannot proceed. It writes the missing test, runs it, and implements the feature if the test fails. This is how the rate-limiting example works — the scenario existed in intent.md, no test covered it, so build caught the gap.

---

### TDD: Test-Driven Development

**Question:** Does the code work?
**When:** During `/temper:build`, per scenario

TDD in Temper is **scenario-driven**. Instead of the AI deciding what to test, tests are derived from BDD scenarios:

| BDD Scenario | Becomes TDD |
|-------------|-------------|
| `Given` (preconditions) | Test setup |
| `When` (action) | Method/endpoint call |
| `Then` (expected outcome) | Assertions |
| Scenario name | Test name |

The cycle per scenario:

1. **RED** — Write test mapped to scenario name. Run it. Must fail (proves the test actually tests something).
2. **GREEN** — Write minimal code to make the test pass. Nothing more.
3. **REFACTOR** — Clean up only if safe and obvious. All tests must still pass.

#### How TDD and BDD Work Together

When both `intent.md` and the TDD pack are active:

- **intent.md drives WHAT to test** — scenarios define the test cases
- **TDD pack drives HOW to test** — RED-GREEN-REFACTOR discipline, naming conventions, test structure

When only TDD pack is active (no intent.md — trivial/simple features):

- TDD pack drives both what and how — freestyle test-first development

When neither is active:

- No enforced test-first — implement, then test

This priority chain means intent.md and TDD aren't competing methodologies. They're layers.

---

### How `/temper:plan` Generates intent.md

When you run `/temper:plan "add password reset"`, here's what happens:

**Phase 1 — Blast Radius:** Scans codebase. Maps every file affected. Finds dependencies. Identifies risk areas (security-critical code, high-defect modules, shared libraries).

**Phase 2 — Derive Scenarios (before architecture):** From requirements + blast radius:

- Feature description -> "Successful password reset" (happy path)
- Risk area: token expiration -> "Expired token rejected" (error path)
- Risk area: abuse vector -> "Rate limiting enforced" (edge case)
- Affected consumer: auth flow -> "Existing login still works" (regression guard)

Each scenario gets a testing approach (`Note:` field):

- `unit` — pure logic, no external dependencies (default)
- `mock` — test with mocked external dependency
- `integration` — cross-boundary test (database, multi-service)
- `manual` — can't be automated (UX, visual, email delivery)

**Phase 3 — Architecture from Scenarios:** Builds the file list. Each file must trace to a scenario. Infrastructure files (migrations, config) trace to the files they support. Untraced files are flagged.

**Phase 4 — Generate intent.md:** Writes the contract with:

- Intent section: problem, success criteria with `Validate:` types, constraints
- Scenarios section: Gherkin scenarios with `Note:` testing approach
- Coverage checklist: populated by build after implementation

**You review and edit intent.md before approving.** Add scenarios. Remove them. Change success criteria. This is the contract between you and the AI on what "done" means.

---

## Real Findings

### Missing Edge Case

AI built password reset. All tests pass. But intent.md had:

```gherkin
Scenario: Rate limiting on reset requests
  Given a user has requested 3 resets in 10 minutes
  When they request another reset
  Then the request is rejected with 429
  Note: unit
```

Scenario coverage gate caught it: no test for rate limiting. Build wrote the test. Test failed. Build implemented rate limiting. Test passed. Without intent.md, rate limiting would never have been implemented.

### Over-Engineering Caught by Traceability

AI planned `UserValidatorFactory`, `ValidationStrategy` interface, and `ValidationChain` — for a single validation rule. File-to-scenario traceability flagged it: only one scenario needed validation, and it mapped to a single function. Three files became one.

### Wrong Problem Solved

Success criterion: "Users can reset password without contacting support." Validate: `scenario`.

AI built it correctly. But also added an admin-only reset endpoint nobody asked for. The untraced file was flagged: "Unplanned file created. Trace to scenario or mark as infrastructure."

---

## Commands

### Unified Command (Recommended)

```
/temper "add login feature"     # One command for the full SDLC
```

Runs plan → build → review → check with **stage gates**. At each stage, you see a nice summary and choose to proceed, edit, or stop.

### Individual Commands (Granular Control)

| Command | Purpose |
|---------|---------|
| [`/temper:plan`](docs/commands.md#temperplan) | Blast radius + BDD scenarios + architecture |
| [`/temper:build`](docs/commands.md#temperbuild) | Scenario-driven TDD + coverage gate |
| [`/temper:review`](docs/commands.md#temperreview) | Structured intent validation + confidence scoring |
| [`/temper:check`](docs/commands.md#tempercheck) | Stack validation (auto-detects) |
| [`/temper:fix`](docs/commands.md#temperfix) | Root cause analysis + regression test |
| [`/temper:standards`](docs/commands.md#temperstandards) | Build team standards |
| [`/temper:status`](docs/commands.md#temperstatus) | Quality metrics dashboard |

### Stage Gates

Each stage ends with a gate:

```
┌─────────────────────────────────────────────────────────────┐
│ 📋 PLAN COMPLETE — Add Login Feature                        │
├─────────────────────────────────────────────────────────────┤
│ 🎯 INTENT                                                   │
│    Problem: Users can't access protected routes             │
│    Success: JWT auth with role-based access                 │
│    Scenarios: 5 (4 unit, 1 integration)                     │
│                                                             │
│ 📁 FILES: 3 create, 2 modify                                │
│ ⚡ RISK: Medium (touches auth layer)                        │
│                                                             │
│ ✅ Ready to build? [Y/e(dit)/n]                             │
└─────────────────────────────────────────────────────────────┘
```

- **Y** → Proceed, context clears, next stage begins
- **e** → Edit scenarios, then re-ask
- **n** → Stop, save state, resume later with `/temper --resume`

## Quality Packs

Packs are rule sets enforced during code generation and review:

| Pack | Severity | What it enforces |
|------|----------|-----------------|
| `quality` | BLOCK | Method length, DRY, naming, complexity |
| `tdd` | WARN | RED-GREEN-REFACTOR, coverage |
| `security` | BLOCK | OWASP Top 10, no secrets in code |
| `git` | SUGGEST | Conventional commits, branching |

Create custom packs with `/temper:standards` or add a `rules.md` to `.claude/packs/your-pack/`.

## Installation

```bash
/plugin marketplace add galando/temper
/plugin install temper
```

```bash
cd your-project
/temper:plan "your feature"    # Scenarios + blast radius + architecture
/temper:build                  # Scenario-driven TDD
/temper:review                 # Structured intent validation
```

## Adaptive Learning

- **Pattern Detection** — Identifies recurring issues in your code
- **Rule Suggestions** — Proposes rules based on review history
- **Noise Reduction** — Suppresses false positives over time
- **Hotspot Tracking** — Shows which files generate the most issues

## Documentation

- [Getting Started](docs/getting-started.md) — Step-by-step guide
- [Commands Reference](docs/commands.md) — Full command documentation
- [Packs](docs/packs.md) — Built-in and custom packs
- [Enterprise Setup](docs/enterprise.md) — Deploy across your organization

## Supported Stacks

| Stack | Detection | Auto-Commands |
|-------|-----------|---------------|
| Spring Boot | `pom.xml` / `build.gradle` | `mvn compile`, `mvn test` |
| React + TS | `package.json` + `tsconfig.json` | `npm test`, `npm run build` |
| Node/Express | `package.json` + express | `npm test`, `npm run lint` |
| FastAPI | `pyproject.toml` + fastapi | `pytest`, `ruff check` |
| Go | `go.mod` | `go test`, `golangci-lint` |
| Rust | `Cargo.toml` | `cargo test`, `cargo clippy` |

## Contributing

We love contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT (c) [Gal Naor](https://github.com/galando)

---

<div align="center">

**[Back to Top](#temper)**

Made with care for the AI coding community

</div>
