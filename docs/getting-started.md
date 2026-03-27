---
title: Getting Started
nav_order: 2
---

# Getting Started

## Installation

### Claude Code

```bash
/plugin marketplace add galando/temper
/plugin install temper
```

{: .highlight }
Claude Code will automatically load Temper's commands and skills when you start a session in any project.

### Other AI Assistants

For any AI assistant that reads markdown:

```bash
# Clone the repository
git clone https://github.com/galando/temper.git

# Copy .claude folder to your project
cp -r temper/.claude /path/to/your/project/
```

## First Steps

### Option A: Unified Command (Recommended)

The simplest way to use Temper — one command for the entire SDLC:

```bash
cd your-project
/temper "add user authentication"
```

Temper runs plan → build → review → check with stage gates:

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

# Review options
review:
  block-on: [critical, high]
  confidence-threshold: 0.7

# Check options
check:
  coverage-threshold: 80
```

## Next Steps

- [Commands Reference](commands) — Full command documentation
- [Packs](packs) — Built-in and custom packs
- [Enterprise Setup](enterprise) — Deploy across your organization
- [DeepWiki](https://deepwiki.com/galando/temper) — AI-powered documentation
