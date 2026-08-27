---
title: Getting Started
nav_order: 2
---

# Getting Started

## Installation

Temper's spine is a bash CLI (`scripts/temper`) and a native git `pre-commit` hook.
Neither belongs to any one agent, so the install differs only in how your agent loads
commands and skills. Pick your agent:

### Claude Code

```bash
/plugin marketplace add galando/temper
/plugin install temper
```

From the terminal instead:

```bash
claude plugin marketplace add galando/temper
claude plugin install temper@temper
```

### Cursor

The same repository ships a Cursor plugin manifest (`.cursor-plugin/`) over the same
commands, agents, and skills — there is no separate export to fall behind.

```bash
git clone https://github.com/galando/temper.git
ln -sfn "$(pwd)/temper" ~/.cursor/plugins/local/temper
```

Reload Cursor, then run `/temper "…"`. Cursor loads `commands/`, `agents/`, `skills/`,
and the plugin's `hooks/cursor-hooks.json` from that manifest.

### Codex, Gemini CLI, Aider, or any agent that reads AGENTS.md

Point the agent at a checkout and give it the contract:

```bash
git clone https://github.com/galando/temper.git ~/temper
cat ~/temper/templates/AGENTS.temper.md >> /path/to/your/project/AGENTS.md
```

Edit the `<TEMPER>` placeholder in what you just appended to your checkout's absolute
path. The snippet names the commands, the stage briefs, and the one setup step that
makes the commit gate real.

### Then, in your project

{: .highlight }
Your first `/temper "…"` sets the project up on the spot — config, `.temper/` scaffold,
and the native commit gate that blocks a red commit. To set up explicitly instead, run
`/temper:init`. For optional edit-time guardrails, `/temper:pack enable hooks`.

Under an agent with no plugin system, run the setup by hand once per project:

```bash
cp ~/temper/templates/temper.config.default .claude/temper.config
~/temper/scripts/temper init
bash ~/temper/scripts/hooks/install.sh      # the commit gate — do not skip this
```

## What Each Agent Gets

The pipeline, the CLI, the gate verdicts, and the committed artifact chain are
identical everywhere — none of that was ever agent-specific. What differs is which
lifecycle events an agent lets a hook *refuse*:

| | Claude Code | Cursor | Other agents |
|---|---|---|---|
| Commands, stage agents, skills | plugin | plugin | `AGENTS.md` + stage briefs |
| `temper gate` verdicts, evidence ledger, artifacts | yes | yes | yes |
| **Commit gate on `git commit`** (native git hook) | **enforced** | **enforced** | **enforced** |
| In-agent commit gate + secret scan on shell commands | blocks | denies | — |
| Pre-edit guards (protected paths, regression-test protection) | blocks | not available | — |
| Standalone-stage gate debt at end of session | blocks | advisory | — |
| Isolated per-stage context | subagent | subagent | inline, degraded |

The row that matters most is the bold one: the gate that physically stops a red commit
is a git hook, so it fires under every agent — and under an agent with no hook system
it is the *only* deterministic enforcement, which is why
`bash scripts/hooks/install.sh` is the step to never skip there.

Full detail, including why Cursor's `stop` and `afterFileEdit` hooks can only advise:
[`reference/portability.md`](https://github.com/galando/temper/blob/main/reference/portability.md).

## Try It First

Want to see Temper in action before installing? Clone the playground:

```bash
git clone https://github.com/galando/temper-playground
cd temper-playground
# Follow the README — see Temper's gates catch real bugs
```

The playground has intentional flaws that demonstrate Temper's scenario coverage gate, security hot path detection, and test gap analysis.

## First Steps

### Option A: Unified Command (Recommended)

The simplest way to use Temper — one command for the entire SDLC:

```bash
cd your-project
/temper "add user authentication"
```

Temper runs intent → plan → build → review → check with stage gates. The first gate is
the cheapest and highest-leverage: you approve the Problem and success criteria before
any exploration or architecture spends tokens — correcting the intent there costs
words; correcting it after planning costs the plan. Then:

```
┌─────────────────────────────────────────────────────────────┐
│ 📋 PLAN COMPLETE — Add User Authentication                  │
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

At each stage, choose:
- **Y** → Proceed to next stage
- **e** → Edit the plan/scenarios
- **n** → Stop and resume later with `/temper --resume`

### Option B: Individual Commands (Granular Control)

For more control, use individual commands:

### 1. Check Your Stack

```bash
cd your-project
/temper:check
```

Temper will auto-detect your stack and report:

```
🔍 Detecting stack...
✅ Detected: Spring Boot
   • Build: Maven
   • Test: mvn test
   • Compile: mvn compile
   • Lint: None configured

📊 Quality Status:
   • Coverage: 72%
   • Open issues: 3
   • Technical debt: Low
```

### 2. Plan a Feature

```bash
/temper:plan "add user authentication"
```

Temper will analyze the blast radius:

```
🔍 Analyzing blast radius...

📦 Affected Files: 12
   • src/main/java/.../UserService.java (MODIFY)
   • src/main/java/.../AuthController.java (CREATE)
   • src/main/java/.../UserRepository.java (MODIFY)
   • src/test/java/.../UserServiceTest.java (CREATE)

🔗 Dependencies:
   • Password hashing library
   • JWT token service
   • Session management

⚠️  Risk Areas:
   • Password storage (security-critical)
   • Token refresh logic (complex state)

📝 intent.md: 5 scenarios (3 happy, 1 error, 1 edge case)
   • Each scenario defines Given/When/Then
   • Tests must cover all scenarios before build completes

📋 Plan: 7 steps with test gates
```

### 3. Build with Quality Gates

```bash
/temper:build
```

Temper will:

1. Run tests for each step (derived from intent.md scenarios)
2. Check quality rules
3. Block on violations
4. Scenario coverage gate: every scenario must have a passing test
5. Track coverage

{: .highlight }
**intent.md** defines behavior scenarios — your tests must cover all of them before build completes.

### 4. Review Your Code

```bash
/temper:review
```

Temper will:

1. Analyze changed files
2. Check against enabled packs
3. Score confidence
4. Suggest improvements

```
📊 Review Results:
   • Files reviewed: 8
   • Issues found: 3
   • Confidence: 94%

🔴 HIGH: Missing password strength validation
   └─ AuthController.java:45

🟡 WARN: Method exceeds 30 lines
   └─ UserService.java:112

   Intent Validation: 5/5 (3 mechanical, 1 deferred, 1 manual)
   Scenario Coverage: 5/5

✅ All tests passing
✅ Coverage: 85% (threshold: 80%)
```

## Configuration

Create `.claude/temper.config` in your project:

```yaml
# Stack override (auto-detect by default)
stack: auto

# Enabled packs
packs:
  - quality
  - tdd
  - security
  - git

# Review options
review:
  block-on: [critical, high]
  confidence-threshold: 0.7

# Check options
check:
  coverage-threshold: 80
  live-scenarios: prompt    # prompt | always | never

# MCP-powered analysis (optional)
tools:
  mode: auto                # auto | heuristic-only | require
  label-findings: true      # Show [PROVEN]/[HEURISTIC]/[SEMANTIC] labels
```

### Live Scenario Verification

Every Gherkin scenario in `intent.md` can be executed individually against your project's test runner — real pass/fail, real output. No MCP servers required.

- `prompt` (default) — ask before running live verification
- `always` — always run during `/temper:check`
- `never` — skip, use heuristic analysis only

Works with: Jest, Vitest, pytest, Maven, Gradle, Go test, cargo test.

### MCP-Powered Analysis (Optional)

Install optional MCP servers to upgrade heuristic analysis to proven findings:

| Server | What it proves | Install |
|--------|---------------|---------|
| [code-review-graph](https://github.com/tirth8205/code-review-graph) | Blast radius, call chains, impact radius | `pip install code-review-graph` |
| [Semgrep](https://github.com/semgrep/semgrep) | Security vulnerabilities (SAST) | `brew install semgrep` |

Full setup instructions: [Recommended Setup](recommended-setup)

### Verify Your Setup

```bash
/temper:status
```

Shows live scenario verification status, MCP tool availability, and evidence ratio.

## Parallel Runs (worktrees)

Temper's state is per-checkout — `.temper/` lives in the working directory, so two
sessions in the same checkout would fight over `build-state.json`. Git worktrees make
parallel runs safe, and everything temper needs travels with each worktree:

```bash
claude --worktree feature-auth      # session 1: /temper "add auth"
claude --worktree fix-rate-limit    # session 2: /temper:fix "429 not returned"
```

- Each worktree gets its **own** `.temper/` state, evidence ledger, gates, and
  autonomy lock — sessions cannot collide on runtime state.
- Split work so parallel tasks touch **disjoint files** (the plan's blast radius shows
  where work is independent); tasks sharing files belong in one session, sequentially.
- The controls travel with the repo: packs, hooks in settings, and the pre-commit gate
  apply identically in every worktree — more sessions never means fewer guardrails.
- Practical ceiling: how many streams one person can *review*. Two or three is a
  sensible start; add sessions only while your review keeps up.

## Next Steps

- [Recommended Setup](recommended-setup) — Optional MCP servers and live verification setup
- [Commands Reference](commands) — Full command documentation
- [Packs](packs) — Built-in and custom packs
- [Context Hygiene](context-hygiene) — Run `/doctor` on your project; keep packs and `CLAUDE.md` lean
- [Enterprise Setup](enterprise) — Deploy across your organization
- [DeepWiki](https://deepwiki.com/galando/temper) — AI-powered documentation
