---
description: "Execute plan with TDD and quality gates"
---

# Build: Execute Plan

**Goal:** Implement approved plan task by task with TDD and graduated quality gates.

## Execution

> **Full methodology:** See temper_build tool documentation

### Quick Reference
1. Load plan from `.temper/specs/{feature}/tasks.md`
2. Verify feature branch (create if on main)
3. For each task: test first (RED) → implement (GREEN) → validate
4. After all tasks: auto-chain → review → check
5. Report results, ask to commit

### Quality Gates

| Level | Behavior | Examples |
|-------|----------|----------|
| **SUGGEST** | Non-blocking, logged only | "Variable name could be more descriptive" |
| **WARN** | Highlighted, developer decides | "No test for this method" |
| **BLOCK** | Must fix before proceeding | "SQL injection", "Hardcoded secret" |

### TDD Workflow

**RED Phase: Write Failing Test**
1. Determine what to test from the task
2. Find or create the right test file
3. Write test using Given-When-Then structure
4. Run test → MUST FAIL

**GREEN Phase: Implement**
1. Write MINIMAL code to pass
2. Follow patterns from adjacent code
3. Do NOT add extra features
4. Run test → must PASS

**REFACTOR Phase: Clean Up**
Only when ALL of these are true:
- All tests are GREEN
- Improvement is obvious and low-risk
- Directly relates to current task

### Error Recovery

- **COMPILATION ERROR**: Read full error → identify type → fix → retry (max 3)
- **TEST FAILURE (new)**: Test may be wrong OR implementation wrong → investigate
- **TEST FAILURE (existing)**: REGRESSION → your code broke something → fix your code
- **STUCK**: Re-read plan → re-read similar code → break down task → ask user
