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
1. `$CLAUDE_PLUGIN_ROOT/reference/check.md` (this file)
2. `.temper/specs/{feature}/review-context.json` (if exists — review findings for context)

### Step 1: Detect Stack

For stack detection order, apply the temper-core skill. Detection produces a stack identifier that determines which validation commands to run.

Stack-specific validation commands:

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

Company preset OVERRIDES auto-detected commands.

### Step 2: Run Validation Levels (in order, stop on BLOCK-level failure)

NOTE: "Stop on failure" means halt the pipeline at the current level. Levels marked WARN continue to the next level. Only STOP/IMMEDIATELY/BLOCK results halt the pipeline.

```
Level 0: ENVIRONMENT
  Purpose: Verify not hitting production
  How: Check all .env* files (.env, .env.local, .env.production, etc.) for production indicators
       Verify DATABASE_URL and similar connection strings don't contain "production"
  If no .env files found: SKIP (not all projects use .env)
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

Level 4.5: SCENARIO VERIFICATION (Live Execution)
  Purpose: Execute each Gherkin scenario's matching test individually, showing real pass/fail
  Confidence: [PROVEN] — mechanical test runner output
  Prerequisite: intent.md exists at .temper/specs/{spec}/intent.md
    If running standalone: resolve {spec} by listing .temper/specs/ directories and
    using the most recently modified one. If build-state.json exists, read spec from there.
    If no specs found → SKIP Level 4.5 entirely.
  Config: check.live-scenarios in temper.config (default: prompt)
    Valid values: prompt | always | never
    prompt → ask user whether to run live verification
    always → always run live verification
    never  → skip live verification, use heuristic analysis only (v3.0.0 behavior)
    Any other value → treated as "prompt" (safe default)
  How:
    STEP 1 — Extract scenarios:
      Read intent.md → extract all Gherkin scenarios (name + Given/When/Then)

    STEP 2 — Match scenarios to tests:
      For each scenario, find the matching test file:
      a. If MCP code-review-graph available: call query_graph_tool to find test
         by scenario name annotation → [PROVEN] match
      b. Fallback: grep test files for scenario name (snake_case or camelCase)
         → [HEURISTIC] match
      c. If no match found → UNMATCHED

    STEP 3 — Gate (prompt mode only):
      Show matched/unmatched counts. Ask user:
      "Run live verification for {N} matched scenarios? [Y/n]"
      If user declines → skip to heuristic-only analysis (v3.0.0 behavior)

    STEP 4 — Execute each matched test individually:
      For each matched scenario + test, run the test individually:
      - Jest/Vitest: npx jest --testPathPattern="{test}" --testNamePattern="{scenario}" --no-coverage
      - pytest: pytest {test}::test_{scenario_snake} -v
      - Maven: ./mvnw test -Dtest="{TestClass#testMethod}"
      - Gradle: ./gradlew test --tests "{TestClass.testMethod}"
      - Go: go test -run Test{Scenario} -v
      - Rust: cargo test test_{scenario_snake} -- --nocapture

      Capture: test name, PASS/FAIL, assertion output, execution time
      Label: [PROVEN] — actual test runner output

    STEP 5 — Report with formatted table:
      SCENARIO VERIFICATION RESULTS
      ┌──────────────────────────────────────────────────────────────┐
      │ Scenario           │ Test              │ Result │ Time      │
      ├────────────────────┼───────────────────┼────────┼───────────┤
      │ User resets pw     │ test_reset        │ ✅ PASS │ 0.12s    │
      │ Invalid email      │ test_invalid      │ ✅ PASS │ 0.05s    │
      │ Rate limiting      │ test_rate_limit   │ ❌ FAIL │ 0.08s    │
      │ Token refresh      │ —                 │ ⚠️ MISSING │ —      │
      └──────────────────────────────────────────────────────────────┘

    STEP 6 — Gate rules:
      FAIL → BLOCK (cannot commit with failing scenario)
      MISSING → WARN (scenario has no matching test)
      PASS → proceed

    STEP 7 — Optional mutation spot-check (security-critical scenarios):
      If all scenarios pass and security-critical scenarios exist:
      1. Ask: "Run mutation spot-check on security-critical scenarios? [Y/n]"
      2. For 1-2 critical functions:
         a. Mutate one line (e.g., change auth check userId === owner to !==)
         b. Re-run the matching test
         c. If test FAILS → ✅ MUTATION CAUGHT (test proves security boundary)
         d. If test PASSES → ❌ MUTATION MISSED (test doesn't catch this)
         e. ALWAYS restore original code
      3. Report mutation results alongside scenario results
  Evidence: All results labeled [PROVEN] (tool output)
  If check.live-scenarios: never → use heuristic-only v3.0.0 behavior
  If no intent.md: SKIP (no BDD contract to enforce)

Level 4.75: HEURISTIC TEST GAP ANALYSIS
  Purpose: Find functions where tests are missing, trivial, or miss obvious edge cases
  Method: Static analysis — reads code + tests, identifies gaps via pattern inspection
  NOTE: This is NOT real mutation testing (which modifies code and runs tests).
  This is heuristic analysis — Claude reads implementation and test code, then identifies
  edge cases the tests likely miss. It catches common gaps (no null test, no boundary test)
  but cannot guarantee all mutations would be caught.
  Prerequisite: Level 2 (tests pass) AND Level 4.5 (scenarios covered) both passed
    If either failed → SKIP (fix those first)
  How:
    For each changed file that has corresponding tests:

    1. IDENTIFY testable logic:
       - Focus on business logic functions (not config, types, I/O wrappers)
       - Prioritize functions with: conditionals, calculations, transformations, state changes

    2. FOR each testable function, check for common test gaps:

       GAP PATTERNS TO CHECK:
       ┌─────────────────────────┬──────────────────────────────────────────────────┐
       │ Gap Pattern             │ What to look for                                 │
       ├─────────────────────────┼──────────────────────────────────────────────────┤
       │ Missing boundary test   │ Code has (x > 5) but no test at x=5, x=6         │
       │ Missing null/undefined  │ Function takes params but no test passes null     │
       │ Missing negative case   │ Function handles positive but no test for negative │
       │ Missing empty input     │ Function processes collection but no test for []   │
       │ Trivial assertion       │ Test only asserts status code, not response body  │
       │ Missing error path      │ Code has catch/throw but no test triggers error   │
       │ Untested branch         │ if/else exists but tests only cover one branch    │
       └─────────────────────────┴──────────────────────────────────────────────────┘

    3. FOR each function:
       a. Read the implementation code — identify branches, boundaries, error paths
       b. Read the test code — identify which paths are actually tested
       c. Compare: which implementation paths have no corresponding test?
       d. If gaps found → FLAG with specific missing cases

    4. CLASSIFY per function:
       STRONG — all branches and edge cases have tests
       WEAK   — some paths tested but obvious gaps (e.g., happy path only)
       NO TEST — no test exists for this function

    5. REPORT per function:
       ✅ UserService.validateEmail — STRONG (all branches covered)
       ⚠️  PaymentService.calculateRefund — WEAK (happy path only)
          Gaps: no test for amount=0, negative amount, null input
          Suggestion: "Add test cases for edge cases"
       ❌ AuthService.generateToken — NO TEST (security-critical)

    6. GATE behavior:
       CRITICAL (no test for security-critical code) → BLOCK
       HIGH (zero test coverage for any function) → WARN
       MEDIUM/LOW (some gaps) → INFO (show in summary, no gate impact)

    7. Write results to .temper/test-gap-report.json:
       {
         "version": 1,
         "run_date": "{ISO date}",
         "files_analyzed": {N},
         "functions_analyzed": {N},
         "edge_cases_checked": {N},
         "gaps_found": {N},
         "test_gap_score": {0.0-1.0},
         "weak_functions": [
           {
             "file": "{path}",
             "function": "{name}",
             "gaps_found": {N},
             "edge_cases_total": {N},
             "gaps": ["boundary", "null", "negative"]
           }
         ]
       }

Level 4.85: API DIFF REVIEW (Heuristic Contract Check)
  Purpose: Detect API contract changes and check if consumers are likely affected
  Method: Static analysis — reads git diff for API boundary files, greps for consumers
  NOTE: This is NOT real contract testing (which runs consumer tests against provider).
  This reads the diff, identifies API shape changes, and greps for consumer code.
  It catches obvious breaking changes (renamed fields, removed endpoints) but cannot
  verify runtime compatibility.
  Prerequisite: Changed files include API boundary files (controllers, routes, DTOs,
    shared types). If no API boundary files changed → SKIP.
  How:

    1. DETECT contract changes:
       a. For each changed API boundary file, extract the contract:
          - Endpoint path and HTTP method
          - Request structure (fields, types, required/optional)
          - Response structure (fields, types)
          - Error codes and error response format
       b. Compare old (git diff removals) vs new (current code):
          - ADDITIVE: new field, new endpoint, new optional param → LOW risk
          - MODIFIED: field type changed, required ↔ optional → HIGH risk
          - BREAKING: required field removed, endpoint renamed/removed,
            incompatible type change → CRITICAL

    2. FIND consumers for each changed contract:
       a. Grep test files: grep -r "{endpoint}" tests/ --include="*.ts|*.js|*.py|*.java"
       b. Grep frontend (if monorepo): grep -r "fetch.*{endpoint}" frontend/
       c. Grep for DTO/type imports: grep -r "import.*{TypeName}" src/
       d. Check webhook/event subscribers if applicable

    3. VERIFY consumers handle new contract:
       For each consumer found:
       a. Read the consumer code
       b. Check if it handles: new required fields, changed types, removed fields
       c. If consumer test exists: check if it passes with new contract

    4. CLASSIFY and gate:
       CRITICAL: Breaking change + consumer NOT updated → BLOCK
       HIGH: Modified contract + no consumer tests exist → WARN
       MEDIUM: Additive change + consumers not updated → INFO
       LOW: Internal contract (no external consumers) → INFO

    5. REPORT:
       CONTRACT CHANGES:
         ✅ GET /api/users — ADDITIVE (new field: emailVerified)
           Consumers: 3 tests, 1 frontend — all backward compatible
         ❌ POST /api/auth/login — BREAKING (response.token → response.access_token)
           Consumers: 2 tests ✅, 1 frontend ❌ NOT UPDATED
           BLOCKING: Frontend will break on deploy
         ⚠️ PaymentRequestDto.amount: number → string
           Breaking type change — runtime risk if non-numeric value

    6. Write results to .temper/contract-map.json:
       {
         "version": 1,
         "last_updated": "{ISO timestamp}",
         "contracts": [
           {
             "endpoint": "POST /api/auth/login",
             "change_type": "BREAKING",
             "consumers": [
               {
                 "type": "test",
                 "path": "tests/integration/auth.test.ts",
                 "verified": true
               },
               {
                 "type": "frontend",
                 "path": "frontend/src/services/AuthService.ts",
                 "verified": false
               }
             ]
           }
         ]
       }

Level 4.9: PERFORMANCE REGRESSION GUARD
  Purpose: Catch performance regressions before deploy
  Method: Runs project benchmarks and compares against baseline
  Prerequisite: Benchmarks must exist in the project AND must be runnable:
    - Check for: benchmarks/, perf/, .github/workflows/bench.yml
    - OR: package.json has "benchmark" script, pyproject.toml has pytest-benchmark
    - If no benchmarks configured → SKIP
    - If benchmarks exist but can't run (missing deps, env) → SKIP with note
  How:

    1. LOAD baseline from .temper/performance-baseline.json (if exists)
    2. RUN benchmarks:
       npm run benchmark OR pytest benchmarks/ OR cargo bench OR go test -bench=.
    3. CAPTURE metrics from benchmark output
    4. COMPARE each metric against baseline:

       THRESHOLDS:
       ┌──────────────────┬───────────────┬─────────────────────────────────────┐
       │ Slowdown         │ Classification│ Gate Action                         │
       ├──────────────────┼───────────────┼─────────────────────────────────────┤
       │ < 5%             │ NO REGRESSION │ Pass, update baseline               │
       │ 5-10%            │ WARNING       │ Show in summary, non-blocking       │
       │ > 10%            │ REGRESSION    │ BLOCK, suggest investigation        │
       │ > 20%            │ CRITICAL      │ BLOCK, require explicit approval    │
       └──────────────────┴───────────────┴─────────────────────────────────────┘

       EXEMPTIONS:
       - Benchmark variance > 20% (historically flaky) → downgrade by 1 level
       - Benchmark marked non-critical in config → WARN only (never BLOCK)

    5. REPORT:
       PERFORMANCE BASELINE COMPARISON:
         ✅ bcrypt.hash — 1.2% faster (acceptable)
         ⚠️  PDF.generate — 7.3% slower (WARNING: exceeds 5% threshold)
         ❌ UserSearch.query — 15.4% slower (REGRESSION: exceeds 10%)
            Expected: 45ms, Actual: 52ms
            Possible cause: N+1 query in UserSearchService (see review)
            Suggestion: Add LIMIT or batch the query

    6. UPDATE baseline (if no regressions):
       Write new metrics to .temper/performance-baseline.json:
       {
         "version": 1,
         "last_updated": "{ISO timestamp}",
         "benchmarks": [
           {
             "name": "UserSearch.query",
             "mean_ms": 45.2,
             "variance": 1.1,
             "history": [44.8, 45.1, 44.9, 45.2]
           }
         ]
       }

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
  Purpose: No known vulnerabilities in dependencies + SAST scan
  Command: {detected security scan command}
  Examples: npm audit, ./gradlew dependencyCheckAnalyze, pip-audit
  On failure: WARN for medium, BLOCK for critical CVEs
  If no security scanner configured: SKIP

  MCP SAST SCAN (after dependency scan):
    If semgrep MCP server is available and tools.mode is not heuristic-only:
    1. Call semgrep security_check on all source files (changed files, or entire
       project if no changed files detected)
    2. Call semgrep_scan_with_custom_rule for security pack rules.
       Load packs via the cached manifest, phase-filtered for this stage (check):
         1. Read `.temper/pack-manifest.json`. If missing or stale (config mtime
            changed, pack dirs added/removed, schema version mismatch, or any
            rules.md mtime newer than manifest `last_built`), rebuild it first —
            see `reference/pack.md` "Cached Pack Manifest" for the staleness
            contract. [G-4]
         2. From the manifest, keep only packs whose `phases` is `"all"` OR whose
            `phases` array contains `"check"`. This is the `reference/pack.md`
            phase-filter contract (lines 164-169). [G-3]
         3. For each surviving pack (e.g. security whose phases include check),
            read its `rules_path` and pass each rule to semgrep_scan_with_custom_rule.
         4. Read stack-specific rules from `.claude/packs/stacks/{detected-stack}.md`
            if present (unchanged behavior).
    3. Map severity:
       - semgrep error → CRITICAL (BLOCK)
       - semgrep warning → HIGH (WARN)
       - semgrep info → MEDIUM (WARN)
    4. SAST findings bypass confidence filtering — always shown
    5. Evidence label: [PROVEN] (tool output)
    If semgrep MCP unavailable:
       Fall back to OWASP pattern-matching in review.md Step 2 → [HEURISTIC]
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

### Step 3.5: Context Output

### Step 3.6: Config Suggestions (Post-Check)

After all validation levels pass, before showing the Commit gate, generate config suggestions:

```
1. CHECK: Did all validation levels pass? (no failures)
2. CHECK: Were files changed? (git diff --name-only returns results)

If all checks pass:
3. READ analysis inputs:
   - git diff --stat
   - .temper/specs/{feature}/intent.md (if exists)
   - .temper/specs/{feature}/tasks.md (if exists)
   - Existing CLAUDE.md
   - Existing AGENTS.md (if exists)

5. ANALYZE changed files for patterns (error handling, naming, structure, testing, config)
6. COMPARE against existing docs
7. GENERATE suggestions (max 5, confidence >= 0.6)
8. WRITE suggestions to .temper/specs/{feature}/config-suggestions.json
9. INTEGRATE with learning.json suggestion_queue (type: config-update)

Full methodology: $CLAUDE_PLUGIN_ROOT/reference/config-suggestions.md
```

Config suggestions are shown to the user at the Check gate (orchestrator handles display).

After all validation levels complete, write `check-context.json` to the spec directory:

```json
{
  "version": 1,
  "stage": "check",
  "timestamp": "{ISO timestamp}",
  "validation_results": {
    "compile": "{pass|fail|skip}",
    "tests": "{pass|fail|skip}",
    "coverage_pct": {N},
    "lint": "{pass|fail|skip}",
    "security": "{pass|fail|skip}"
  },
  "scenario_verification": {
    "total": {N},
    "passed": {N},
    "failed": {N},
    "missing": {N}
  },
  "test_failures": [
    {
      "test_name": "string",
      "error_message": "string",
      "file": "string",
      "line": {N},
      "scenario": "string (from intent.md)"
    }
  ]
}
```

### Feedback Loop to Build

When `feedback.enabled: true` in temper.config and test failures are found:

1. For each test failure in newly written code:
   - Create a targeted fix task with: test name, error message, file:line
   - Include the intent.md scenario that the test maps to
2. If failures found AND iteration < max-loops (default 2):
   - Offer "Loop back to Build" option in the stage gate
   - Write check-context.json with failure details
   - Signal orchestrator to loop back to Build
3. If failures found AND iteration >= max-loops:
   - Stop and show remaining failures to user
   - Offer "Save for later" or "Manual fix"
4. Circuit breaker: same test failing in 2 consecutive loops → stop immediately

The feedback loop counter is tracked in `.temper/feedback-loops.json`.

### Step 4: Nice Summary + Stage Gate

After all levels complete, show a nice summary:

```
┌─────────────────────────────────────────────────────────────┐
│ CHECK — {Project Name}                                      │
├─────────────────────────────────────────────────────────────┤
│ WHAT WAS VALIDATED                                           │
│    Compile:    {status} {time}                               │
│    Tests:      {status} {time} — {N} passed                  │
│    Coverage:   {status} {X}% (threshold: {Y}%)               │
│    Live Scen:   {status} {X}/{Y} ({N}P/{N}F/{N}M)             │
│    Test Gaps:  {status} {X}% ({N}/{N} functions analyzed)      │
│    API Diff:   {status} {N} changes ({N} consumers checked)    │
│    Perf:       {status} {N} regressions (baseline updated)   │
│    Lint:       {status} {time}                               │
│    Security:   {status} {time}                               │
│                                                             │
│ Skipped: Integration (no tool configured)                   │
│ Total: {time}                                               │
│                                                             │
│ TEST GAPS (if any WEAK/NO TEST found)                     │
│    ⚠️  {Function} — {N} edge cases untested (WEAK)         │
│    ❌ {Function} — NO TEST (security-critical)                │
│                                                             │
│ API DIFF (if Level 4.85 ran)                                │
│    ❌ BREAKING: {endpoint} — {description}                    │
│    ✅ ADDITIVE: {endpoint} — backward compatible              │
│                                                             │
│ PERFORMANCE (if Level 4.9 ran)                               │
│    ❌ {benchmark} — {X}% slower (REGRESSION)                  │
│    ⚠️  {benchmark} — {X}% slower (WARNING)                   │
│    ✅ All benchmarks within baseline                          │
│                                                             │
│ SCENARIO VERDICT (if intent.md exists AND Level 4.5 ran)    │
│    (Omit this entire section if pipeline stopped before 4.5) │
│    Scenarios: {X}/{Y} behaviorally verified                 │
│      Y = total scenarios in intent.md, X = those with       │
│      STRONG assertions (not TRIVIAL). WEAK count as half.   │
│      Note: This count is assertion-quality-weighted and     │
│      intentionally differs from build's binary pass/fail.   │
│    Build deviations: {N} unplanned, {N} skipped             │
│      (if build-state.json available; otherwise omit this line)│
│                                                             │
│ What next?                                                 │
│   ▸ Commit (Recommended)                                   │
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
    - label: "Save for later"
      description: "Keep changes uncommitted, save state."
  multiSelect: false
  Note: When feedback.enabled is true AND test failures exist in new code,
  an additional "Loop back to Build" option is offered by the orchestrator.
  The orchestrator handles feedback loop routing.
```

| Response | Action |
|----------|--------|
| **Commit** (first option) | Commit with conventional message, clear build-state.json |
| **Save for later** (second option) | Stop here, keep changes uncommitted |

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

**On Change (via "Other" free-text input):**

```
1. User types their change request in the "Other" field
2. Make the change
3. Re-run validation from the first failed level (inclusive) — no need to re-run levels that already passed
4. ⚠️ MANDATORY: Re-show AskUserQuestion with same options

GATE ENFORCEMENT: The user's change input is NOT approval to commit.
Do NOT commit after making changes. The user MUST explicitly select
"Commit" from the gate to proceed.
```

**On Save for later (second option):**

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
