---
description: "Execute the plan, implementing tasks one-by-one with quality gates"
---

# Build: Execute Plan with Quality Gates

**Goal:** Implement the approved plan, task by task, with TDD and graduated quality gates.

## Prerequisites

- Approved plan exists (from `/temper:plan`)
- OR: user provides inline instructions for trivial tasks

## Execution

### Step 1: Load Plan

```
1. Check for active plan in .temper/specs/*/tasks.md
2. If multiple specs exist, ask user which to execute
3. Load tasks.md + quickstart.md
4. Read plan.md for architecture decisions and blast radius
5. Read all files listed in plan's "Prerequisites" or "Must Read" sections
6. Read active pack rules from .claude/packs/ (enabled packs only)
7. Read stack file from .claude/packs/stacks/{detected-stack}.md
```

**If no plan exists (trivial task):**
```
1. User gave direct instructions → treat as single-task build
2. Detect stack (same as /temper:check Step 1)
3. Read active pack rules
4. Read related existing code before implementing
5. Skip Step 2 (branch) — user decides if feature branch needed
```

### Step 2: Verify Branch

```
1. Run: git branch --show-current
2. If on main/master:
   - Ask user to create feature branch
   - Suggest name: feature/{ticket}-{description}
3. If already on feature branch: proceed
```

### Step 3: Execute Tasks (in order)

For each task in tasks.md:

**a. Read context** - Read existing files, understand patterns, check adjacent code
**b. Write test first** - If TDD pack enabled (see `.claude/packs/tdd/rules.md`)
**c. Implement** - Write minimal code to pass the test or fulfill spec
**d. Validate** - Run test → GREEN, run task validation command
**e. Refactor** - Only if obvious, low-risk, and all tests pass

### Step 4: Post-Implementation

After all tasks complete:

```
1. Run full test suite → all must pass
2. Auto-run /temper:review → fix issues (max 2 loops)
3. Auto-run /temper:check → all levels must pass
4. Report results:
   "Feature complete. {X} files created, {Y} modified, {Z} tests added.
    Branch: {branch name}
    Ready to commit?"
5. On user approval → commit with conventional message
```

## Quality Gates

| Level | Behavior | Examples |
|-------|----------|----------|
| **SUGGEST** | Non-blocking, logged only | "Variable name could be more descriptive" |
| **WARN** | Highlighted, developer decides | "No test for this method", "Method exceeds 30 lines" |
| **BLOCK** | Must fix before proceeding | "SQL injection", "Hardcoded secret", "Architectural violation" |

**Pattern-to-rule mapping:**

| Code Pattern | Pack Rule | Level |
|--------------|-----------|-------|
| SQL string concatenation | security: no SQL concat | BLOCK |
| Hardcoded API keys/passwords | security: no secrets | BLOCK |
| DB access from controller | architecture: use service layer | BLOCK |
| Public method without test | tdd: test all public methods | WARN |
| Method > 30 lines | quality: method length | WARN |
| Magic numbers | quality: named constants | SUGGEST |
| 4+ nesting levels | quality: max 3 nesting | WARN |
| Empty catch block | quality: no swallowed exceptions | WARN |

## Error Recovery

```
COMPILATION ERROR: Read full error → identify type → fix → retry (max 3)
TEST FAILURE (new test): Test may be wrong OR implementation wrong → investigate
TEST FAILURE (existing test): REGRESSION → your code broke something → fix your code
STUCK: Re-read plan → re-read similar code → break down task → ask user if needed
```
