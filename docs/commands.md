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
- Detects parallel tasks for optimized ordering

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

## Task 1 — Create PasswordResetService [SEQUENTIAL]
  → Test: PasswordResetService.test.ts
  → Gate: All tests pass

## Task 2 — Add reset endpoint [SEQUENTIAL: after Task 1]
  → Test: AuthController.test.ts
  → Gate: Coverage > 80%

## Task 3 — Update email templates [PARALLEL: with Task 4]
  → Test: EmailTemplate.test.ts

## Task 4 — Add rate limiting [PARALLEL: with Task 3]
  → Test: RateLimiter.test.ts
...
```

**Note:** Tasks marked `[PARALLEL: with Task X]` can run concurrently since they touch different files.

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
- Resumes from checkpoint if interrupted

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

**Resume from Checkpoint:**

If your build is interrupted, Temper saves progress and offers to resume:

```
📁 Found .temper/build-state.json
   Last completed: Task 3/5
   Started: 2026-03-10 14:32

Resume from Task 4? [Y/n] > Y

🚧 Resuming from Task 4...

Step 4/5: Add rate limiting
  ✅ Tests already written
  ✅ Implement
  ...
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
- Diff-aware: focuses on changed lines
- Catches N+1 queries and performance issues

**Output:**
```
📊 Review Results

Files reviewed: 6
Issues found: 4
Confidence: 91%

🔴 HIGH (Confidence: 96%) [REGRESSION]
   Missing rate limiting on password reset endpoint
   └─ AuthController.ts:89 (CHANGED)
   → Suggestion: Add rate limiting middleware

🔴 HIGH (Confidence: 89%) [NEW ISSUE]
   N+1 query pattern: DB call inside loop
   └─ UserRepository.java:45 (CHANGED)
   → Suggestion: Use batch fetch or JOIN query

🟡 WARN (Confidence: 78%) [NEW ISSUE]
   Method 'processReset' exceeds 30 lines
   └─ PasswordResetService.ts:112 (CHANGED)
   → Suggestion: Extract helper methods

🟢 INFO (Confidence: 65%) [PRE-EXISTING]
   Consider extracting magic number to constant
   └─ TokenService.ts:23 (UNCHANGED)
   → Suggestion: EXPIRATION_HOURS = 24

✅ All tests passing
✅ No security pack violations
```

**Issue Classifications:**
- **REGRESSION** — Code that was working, now broken by your change
- **NEW ISSUE** — Problem introduced by this change
- **PRE-EXISTING** — Issue existed before (lower priority)

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
