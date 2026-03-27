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
1. Check for .temper/build-state.json
   - If found: Ask user "Resume from Task {N}? [Y/n]"
   - If yes: Load checkpoint, resume from last completed task
   - If no: Delete the file and start fresh
2. Check for active plan in .temper/specs/*/tasks.md
3. If multiple specs exist, ask user which to execute
4. Load tasks.md + quickstart.md
5. Read plan.md for architecture decisions and blast radius
6. Read all files listed in plan's "Prerequisites" or "Must Read" sections
7. Read active pack rules from .claude/packs/ (enabled packs only)
8. Read stack file from .claude/packs/stacks/{detected-stack}.md
9. Load .temper/specs/{feature}/intent.md if it exists
   - Parse scenario names and Given/When/Then blocks
   - If no intent.md: proceed with current behavior (unchanged)
```

**Build State Schema:**

```json
{
  "spec": "{feature-name}",
  "started": "2026-03-10T10:00:00Z",
  "last_task_completed": 3,
  "tasks": [
    { "id": 1, "status": "completed", "timestamp": "..." },
    { "id": 2, "status": "completed", "timestamp": "..." },
    { "id": 3, "status": "in_progress", "timestamp": "..." }
  ]
}
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
**b. Write test first (priority order — first match wins)**

   1. **intent.md exists** → scenario-driven testing (regardless of TDD pack)
      - Each test maps to a Gherkin scenario by name
      - Given block → test setup
      - When block → action under test
      - Then block → assertions
      - One test per scenario minimum (some scenarios may need multiple tests)
      - When both intent.md AND TDD pack exist: intent.md drives WHAT to test, TDD pack enforces HOW (RED-GREEN-REFACTOR discipline, test conventions)
   2. **TDD pack enabled, no intent.md** → RED-GREEN-REFACTOR from pack rules
   3. **Neither** → implement without enforced test-first
**c. Implement** - Write minimal code to pass the test or fulfill spec
**d. Validate** - Run test → GREEN, run task validation command
**e. Checkpoint** - Write to `.temper/build-state.json`:

   ```json
   {
     "spec": "{feature-name}",
     "last_task_completed": {task_number},
     "tasks": [...],
     "updated": "{timestamp}"
   }
   ```

**f. Refactor** - Only if obvious, low-risk, and all tests pass

### Step 3.5: Scenario Coverage Gate (BDD Enforcement)

After all tasks complete, before Step 4:

```
If intent.md exists:
  1. Read all scenarios from intent.md
  2. For each scenario:
     a. Find test(s) by name/description match
     b. If no test found → write test + implement if needed
     c. Run the test → must PASS
  3. If any scenario has no passing test → build cannot proceed
  4. Report:
     "Scenario Coverage: X/Y scenarios covered
      ✅ Scenario: User resets password → PasswordResetTest.test_successful_reset
      ✅ Scenario: Expired token → PasswordResetTest.test_expired_token
      ❌ Scenario: Rate limiting → MISSING — writing test..."

If no intent.md:
  Skip gate, proceed to Step 4 as before
```

### Step 3.6: Success Criteria Validation (IDD Enforcement)

After scenario coverage gate, validate code-based success criteria:

```
If intent.md exists and has success criteria with Validate: code:
  1. For each success criterion with Validate: code — {pattern}:
     a. Grep for the specified pattern/endpoint/config
     b. If found → ✅ Success criterion met
     c. If not found → ❌ WARN: "Success criterion not met: {criterion}"
  2. Report:
     "Success Criteria Validation: X/Y code criteria met
      ✅ POST /api/reset exists → found in src/routes/auth.ts:45
      ❌ Rate limit middleware applied → NOT found"
  3. Non-blocking — WARN only, does not block build

For Validate: scenario → already covered by Step 3.5
For Validate: metric/manual → deferred to /temper:review
```

**Populate Scenario Coverage Checklist in intent.md:**
After reporting coverage, write the results back to intent.md's "## Scenario Coverage Checklist" section:

```
1. Find the "## Scenario Coverage Checklist" section in intent.md
2. Replace placeholder lines with actual scenario-to-test mappings:
   - [x] {Scenario Name} → {TestClassName.test_method_name} (for passing tests)
   - [ ] {Scenario Name} → NO TEST (for missing tests - should never occur if gate passed; indicates gate logic bug)
3. Keep the section header and any existing content, only update the checklist items
```

This makes intent.md a complete record of what was planned AND what was delivered.

**Scenario-to-test mapping rules:**

- Test name should contain scenario name (snake_case or camelCase)
- Test description/docstring should reference the Gherkin scenario
- Multiple tests can map to one scenario (e.g., happy path + variant)
- One test cannot satisfy multiple scenarios

**Scenario Note handling:**
Each scenario in intent.md may have a `Note:` field specifying the testing approach:

- `Note: unit` → standard unit test (default if no Note specified)
- `Note: mock` → test with mocked external dependency, verify interaction
- `Note: integration` → write integration test if test infra exists, otherwise mock
- `Note: manual` → skip from automated coverage gate, log as "requires manual verification"

Scenarios marked `manual` count as covered in the gate but are flagged in the report:

```
Scenario Coverage: 5/5 (4 automated, 1 manual verification needed)
  ✅ Scenario: User submits form → FormTest.test_submission (automated)
  ⚠️  Scenario: Email delivered → MANUAL VERIFICATION NEEDED
```

### Step 3.75: Traceability Check

After scenario coverage gate passes, verify file-to-scenario traceability:

```
If tasks.md has "Traced to:" fields:
  1. Compare actual files changed (git diff --name-only) to planned file list from tasks.md
  2. For each new/changed file not in plan:
     → WARN: "Unplanned file {path} created. Trace to scenario or mark as infrastructure."
  3. For each planned file not changed:
     → WARN: "Planned file {path} was not modified. Is the task complete?"
  4. Report: "Traceability: {N}/{M} files match plan"

If no "Traced to:" fields: skip (backward compatible)
```

Non-blocking — warnings only. The scenario coverage gate is the hard gate.

### Step 4: Post-Implementation

After all tasks complete:

```
1. Run full test suite → all must pass
2. Show build summary:

┌─────────────────────────────────────────────────────────────┐
│ 🔨 BUILD — {Feature Name}                                  │
├─────────────────────────────────────────────────────────────┤
│ ✅ WHAT WAS BUILT                                            │
│    Tasks: {N}/{N} completed                                 │
│    Tests: {N} added, all passing                            │
│    Files: {N} created, {N} modified                         │
│                                                             │
│ 📊 QUALITY                                                   │
│    Coverage: {X}% (threshold: {Y}%)                         │
│    All tests: PASS                                           │
│                                                             │
│ 📁 KEY CHANGES                                               │
│    + {file} — {one-line description}                         │
│    + {file} — {one-line description}                         │
│    ~ {file} — {one-line description}                         │
│                                                             │
│ What next?                                                  │
│   ▸ Continue to Review (Recommended)                            │
│     Change something first                                   │
│     Save for later                                           │
└─────────────────────────────────────────────────────────────┘

3. Use AskUserQuestion with options:
   - "Continue to Review (Recommended)" — proceed to review, clear context
   - "Change something first" — user types what to change, Claude edits, re-ask
   - "Save for later" — stop here, save state

4. On Continue:
   - Signal:
     "✅ Continuing to REVIEW...
      🧹 Clearing context for efficiency.
      📂 Loading: changed files only"
   - ⚠️ MANDATORY: Clear ALL context. Do NOT carry forward tasks.md,
     intent.md, or any build artifacts. This prevents stale context.
   - Load ONLY changed files (git diff --name-only)
   - Proceed to /temper:review

5. On Change something:
   - Ask: "What would you like to change?"
   - User types their change request
   - Claude makes the change
   - Re-show AskUserQuestion with same options

6. On Save:
   - Save state to .temper/build-state.json
   - Report: "✅ Saved. Run /temper when ready to continue."

7. Delete .temper/build-state.json (clean up checkpoint) after review+check complete
8. Mark spec as completed:
   - If intent.md exists: add `**Status:** completed` and `**Completed:** {date}` to header

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
