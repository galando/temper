---
description: "Run the project's validation pipeline (tests, build, lint, security)"
---

# Check: Stack-Aware Validation Pipeline

**Goal:** Run the project's full validation pipeline. Auto-detects stack and runs the right commands.

## Execution

### Context Loading

This stage may run in two modes:
- **Standalone** (`/temper:check`) — runs in current context, handles its own gate
- **Agent subprocess** (from `/temper`) — starts with CLEAN context, no prior files needed

**Subprocess mode override:** When running as an Agent subprocess, do NOT show AskUserQuestion gates or clear context. Return the check summary to the orchestrator. The orchestrator handles all gate decisions and context transitions.

In both modes, the check methodology is identical.

Files to load at start:
1. `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/check.md` (this file)

### Step 1: Detect Stack

Read project files to determine stack:

```
DETECTION ORDER (first match wins):

1. Check .claude/temper.config → stack field (if not "auto")
2. Check .claude/presets/*.yaml → stack section
3. Auto-detect from project files:

   pom.xml OR build.gradle → Java/Spring Boot
     compile: ./mvnw compile OR ./gradlew compileJava
     test:    ./mvnw test OR ./gradlew test
     build:   ./mvnw package OR ./gradlew build

   package.json → Node.js (check scripts section for commands)
     Read package.json scripts:
     test:  npm test (or whatever "test" script runs)
     build: npm run build (or whatever "build" script runs)
     lint:  npm run lint (if exists)
     type:  npx tsc --noEmit (if tsconfig.json exists)

   pyproject.toml OR setup.py → Python
     test:  pytest
     lint:  ruff check . (or flake8, pylint)
     type:  mypy . (if configured)
     build: python -m build

   go.mod → Go
     test:  go test ./...
     lint:  golangci-lint run
     build: go build ./...

   Cargo.toml → Rust
     test:  cargo test
     lint:  cargo clippy
     build: cargo build

4. Company preset OVERRIDES auto-detected commands
```

### Step 2: Run Validation Levels (in order, stop on failure)

```
Level 0: ENVIRONMENT
  Purpose: Verify not hitting production
  How: Check for .env.local, verify DATABASE_URL doesn't contain "production"
  If no .env file: SKIP (not all projects use .env)
  If production detected: STOP IMMEDIATELY

Level 1: COMPILE/BUILD
  Purpose: Code compiles without errors
  Command: {detected compile command}
  On failure: STOP, show error output, suggest fix

Level 2: UNIT TESTS
  Purpose: All unit tests pass
  Command: {detected test command}
  On failure: STOP, show failing test names, suggest fix
  Report: tests run, passed, failed, duration

Level 3: INTEGRATION TESTS (if available)
  Purpose: Integration tests pass
  Command: {detected integration test command, if separate from unit}
  On failure: STOP, show failing tests
  If no integration tests configured: SKIP

Level 4: COVERAGE (if available)
  Purpose: Meets threshold
  Command: {detected coverage command}
  Threshold: from temper.config (default 80%) or company preset
  On failure: WARN (not block by default), show coverage %
  If no coverage tool configured: SKIP

Level 4.5: SCENARIO COVERAGE (BDD Final Gate)
  Purpose: Every scenario in intent.md has a passing test
  Prerequisite: intent.md exists at .temper/specs/{spec}/intent.md
  How:
    1. Read intent.md → extract all Gherkin scenarios
    2. For each scenario:
       a. Find matching test by name/description (grep test files for scenario name)
       b. Verify test exists and passes (from Level 2 test results)
       c. If scenario has Note: manual → mark as "requires manual verification"
    3. Compare against Scenario Coverage Checklist in intent.md (if populated by build)
  Report:
    "Scenario Coverage: X/Y scenarios covered (Z automated, W manual)
     ✅ Scenario: User resets password → PasswordResetTest.test_successful_reset
     ✅ Scenario: Expired token → PasswordResetTest.test_expired_token
     ⚠️  Scenario: Email delivered → MANUAL VERIFICATION NEEDED
     ❌ Scenario: Rate limiting → NO PASSING TEST FOUND"
  On failure (any ❌): BLOCK — cannot commit with uncovered scenarios
  If no intent.md: SKIP (no BDD contract to enforce)

Level 5: LINT/FORMAT
  Purpose: Code style checks pass
  Command: {detected lint command}
  On failure: WARN, show violations count
  If no linter configured: SKIP

Level 6: TYPE CHECK (if applicable)
  Purpose: Type checking passes
  Command: {detected type check command}
  Only for: TypeScript (tsc), Python (mypy), etc.
  On failure: WARN, show error count
  If not applicable: SKIP

Level 7: SECURITY (if available)
  Purpose: No known vulnerabilities in dependencies
  Command: {detected security scan command}
  Examples: npm audit, ./gradlew dependencyCheckAnalyze, pip-audit
  On failure: WARN for medium, BLOCK for critical CVEs
  If no security scanner configured: SKIP
```

### Step 3: Track Technical Debt (if enabled)

If `debt-tracking: true` in temper.config:

```
After validation, update debt metrics in .temper/metrics.json:

1. Coverage trend: append current coverage % to coverage_history array
2. Test count trend: append current test count
3. Lint violation count: append if available

Note: Full debt analysis (dead code, duplication) runs only on /temper:status
to avoid slowing down the validation pipeline.
```

### Step 4: Nice Summary + Stage Gate

After all levels complete, show a nice summary:

```
┌─────────────────────────────────────────────────────────────┐
│ CHECK — {Project Name}                                      │
├─────────────────────────────────────────────────────────────┤
│ WHAT WAS VALIDATED                                           │
│    Compile:   {status} {time}                               │
│    Tests:     {status} {time} — {N} passed                  │
│    Coverage:  {status} {X}% (threshold: {Y}%)               │
│    Scenarios: {status} {X}/{Y} covered (if intent.md exists) │
│    Lint:      {status} {time}                               │
│    Security:  {status} {time}                               │
│                                                             │
│ Skipped: Integration (no tool configured)                 │
│ Total: {time}                                               │
│                                                             │
│ What next?                                                 │
│   ▸ Commit (Recommended)                                   │
│     Change something first                                │
│     Save for later                                         │
└─────────────────────────────────────────────────────────────┘
```

#### Stage Gate

Use AskUserQuestion with these options:

```
AskUserQuestion:
  question: "What next?"
  options:
    - label: "Commit (Recommended)"
      description: "Commit with conventional message, clear build-state.json."
    - label: "Change something first"
      description: "Type what you want to change. Claude edits, re-runs validation."
    - label: "Save for later"
      description: "Keep changes uncommitted, save state."
  multiSelect: false
```

| Response | Action |
|----------|--------|
| **Commit** (first option) | Commit with conventional message, clear build-state.json |
| **Change something first** (second option) | User types what to change. Claude edits. Re-run validation. Re-ask. |
| **Save for later** (third option) | Stop here, keep changes uncommitted |

**On Commit (first option):**

```
1. ⚠️ MANDATORY: Delete .temper/build-state.json (clean up checkpoint)
2. Mark spec as completed:
   - If intent.md exists: add `**Status:** completed` and `**Completed:** {date}` to header
3. Commit with conventional message:
   {type}({scope}): {description}

   {Closes #{issue} or Implements #{feature}}
   - {X} files changed, {Y} tests added

   Co-Authored-By: Claude <noreply@anthropic.com>
4. Report:
   "✅ Committed: {hash}
    Branch: {branch}
    Ready to push?"
```

**On Change something first (second option):**

```
1. Ask: "What would you like to change?"
2. User types their change request
3. Claude makes the change
4. Re-run validation
5. ⚠️ MANDATORY: Re-show AskUserQuestion with same options

GATE ENFORCEMENT: The user's change input is NOT approval to commit.
Do NOT commit after making changes. The user MUST explicitly select
"Commit" from the gate to proceed.
```

**On Save for later (third option):**

```
1. Save state to .temper/build-state.json:
   {
     "stage": "check_complete",
     "spec": "{feature-slug}",
     "spec_path": ".temper/specs/{feature-slug}",
     "original_args": "{from prior state}",
     "next_stage": "commit",
     "artifacts": ["intent.md", "tasks.md"],
     "updated": "{ISO timestamp}"
   }
2. Report:
   "✅ Saved. Run /temper when ready to continue."
```

If levels were skipped (no tool configured), show them as `⏭️ Skipped`.

### Error Interpretation

When a validation level fails, help the user understand and fix it:

```
COMPILE FAILURE:
  - Read the FULL error output (not just the first error — cascade errors are noise)
  - Identify: missing import, type error, syntax error, dependency issue
  - Suggest: specific file:line and what to change

TEST FAILURE:
  - Show failing test names and assertion messages
  - Distinguish: new test failing (implementation incomplete) vs existing test failing (regression)
  - For regression: identify which recent change likely caused it

COVERAGE BELOW THRESHOLD:
  - Show which files/functions lack coverage
  - Prioritize: uncovered public methods in recently changed files
  - Do NOT suggest adding trivial tests just to hit the number

LINT/TYPE ERRORS:
  - Group by type (unused imports, type mismatches, style violations)
  - If auto-fixable (e.g., eslint --fix, ruff format): offer to run auto-fix
  - Show count, not every individual violation

SECURITY (critical CVE found):
  - Show CVE ID, affected dependency, severity
  - Check if upgrade is available: suggest version bump
  - If no fix available: note as accepted risk, suggest workaround if exists

COMMAND NOT FOUND / TOOL MISSING:
  - Stack file specifies a tool that isn't installed
  - SKIP the level, note: "{tool} not found — install with {command} to enable"
  - Never fail the entire pipeline because an optional tool is missing
```
