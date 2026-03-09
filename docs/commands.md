---
title: Commands Reference
nav_order: 3
---

# Commands Reference

## `/temper:check`

Stack validation and quality status.

```bash
/temper:check
```

**What it does:**
- Auto-detects your tech stack
- Finds test, build, and lint commands
- Reports current quality status

**Output:**
```
🔍 Detecting stack...
✅ Detected: React + TypeScript
   • Build: npm run build
   • Test: npm test
   • Lint: npm run lint

📊 Quality Status:
   • Coverage: 78%
   • TypeScript errors: 0
   • Lint warnings: 2
```

---

## `/temper:plan`

Plan with blast radius analysis.

```bash
/temper:plan "feature description"
```

**What it does:**
- Analyzes which files will be affected
- Identifies dependencies and risk areas
- Creates step-by-step plan with test gates

**Example:**
```bash
/temper:plan "add password reset"
```

**Output:**
```
🔍 Blast Radius Analysis

📦 Affected Files: 8
   • src/auth/PasswordResetService.ts (CREATE)
   • src/auth/AuthController.ts (MODIFY)
   • src/email/EmailService.ts (MODIFY)

🔗 Dependencies: 4
   • Email delivery
   • Token generation
   • Rate limiting

⚠️  Risk Areas: 2
   • Token expiration handling
   • Email delivery failures

📋 Plan: 5 steps

Step 1: Create PasswordResetService
  → Test: PasswordResetService.test.ts
  → Gate: All tests pass

Step 2: Add reset endpoint to AuthController
  → Test: AuthController.test.ts
  → Gate: Coverage > 80%
...
```

---

## `/temper:build`

Build with TDD + quality gates.

```bash
/temper:build
```

**What it does:**
- Executes the plan step by step
- Runs tests after each step
- Blocks on quality gate failures
- Tracks coverage

**Workflow:**
```
🚧 Building...

Step 1/5: Create PasswordResetService
  ✅ Write tests
  ✅ Implement
  ✅ Tests pass (4/4)
  ✅ Coverage: 92%

Step 2/5: Add reset endpoint
  ✅ Write tests
  ✅ Implement
  ✅ Tests pass (6/6)
  ⚠️  Coverage: 74% (threshold: 80%)
  🔧 Adding more tests...
  ✅ Coverage: 82%

Step 3/5: Email integration
  ✅ Write tests
  ✅ Implement
  ✅ Tests pass (8/8)
  ✅ Coverage: 88%

...

✅ Build complete
   • Steps: 5/5
   • Tests: 18 passing
   • Coverage: 86%
   • Time: 4m 32s
```

---

## `/temper:review`

Code review with confidence scoring.

```bash
/temper:review
```

**What it does:**
- Analyzes changed files
- Checks against enabled packs
- Scores confidence of findings
- Suggests improvements

**Output:**
```
📊 Review Results

Files reviewed: 6
Issues found: 4
Confidence: 91%

🔴 HIGH (Confidence: 96%)
   Missing rate limiting on password reset endpoint
   └─ AuthController.ts:89
   → Suggestion: Add rate limiting middleware

🔴 HIGH (Confidence: 89%)
   SQL injection potential in search query
   └─ UserRepository.java:45
   → Suggestion: Use parameterized queries

🟡 WARN (Confidence: 78%)
   Method 'processReset' exceeds 30 lines
   └─ PasswordResetService.ts:112
   → Suggestion: Extract helper methods

🟢 INFO (Confidence: 65%)
   Consider extracting magic number to constant
   └─ TokenService.ts:23
   → Suggestion: EXPIRATION_HOURS = 24

✅ All tests passing
✅ No security pack violations
```

---

## `/temper:fix`

Root cause analysis + structured fix.

```bash
/temper:fix "issue description"
```

**What it does:**
- Analyzes root cause of the issue
- Creates fix plan
- Implements with tests

**Example:**
```bash
/temper:fix "JIRA-123: Users can't reset password"
```

**Output:**
```
🔍 Root Cause Analysis

Issue: Password reset emails not being sent

Investigation:
  1. Checked email service logs → No errors
  2. Checked token generation → Working
  3. Checked queue → Messages stuck

Root Cause: Queue consumer crashed at 2:34 AM
  → Consumer not auto-restarting

📋 Fix Plan:
  1. Add health check to queue consumer
  2. Implement auto-restart on failure
  3. Add alerting for queue depth

🔧 Implementing...

✅ Fix applied
   • Files changed: 3
   • Tests added: 2
   • Regression risk: Low
```

---

## `/temper:standards`

Build team standards interactively.

```bash
/temper:standards
```

**What it does:**
- Scans your codebase for patterns
- Asks clarifying questions
- Generates your engineering standards pack

**Workflow:**
```
🔍 Scanning codebase...

Found patterns:
  • Constructor injection (92% of classes)
  • DTO pattern (100% of APIs)
  • Structured logging (78% of services)

Questions:

1. I see you use DTOs for all API responses.
   Should this be a BLOCK rule?
   [Yes/No/Skip] > Yes

2. Constructor injection is common but not universal.
   Make it mandatory?
   [Yes/No/Skip] > Yes

3. Some services use console.log instead of logger.
   Should I suggest migration?
   [Yes/No/Skip] > Yes

Generating pack...

✅ Created: .claude/packs/company/rules.md

   • BLOCK rules: 2
   • WARN rules: 3
   • SUGGEST rules: 4

Next: Commit this pack and share with your team.
```

---

## `/temper:status`

Quality metrics dashboard.

```bash
/temper:status
```

**What it does:**
- Shows current quality metrics
- Tracks trends over time
- Highlights hotspots

**Output:**
```
📊 Temper Status Dashboard

Project: my-service
Stack: Spring Boot
Packs: quality, tdd, security, company

📈 Metrics (Last 30 days)
   • Reviews run: 47
   • Issues found: 23
   • Auto-fixed: 18
   • Coverage: 78% → 84% ↑

🔥 Hotspots
   • UserService.java — 4 issues (complexity)
   • OrderProcessor.java — 3 issues (coupling)

📚 Learning
   • Pattern detected: "Missing null check"
   → Suggestion: Add to company pack

⏱️ Technical Debt
   • Coverage gaps: 2 modules
   • TODOs: 12 (3 critical)
   • Deprecated: 1 dependency
```
