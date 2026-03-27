---
description: "Transform a feature request into a structured implementation plan with impact analysis"
argument-hint: "<feature-name-or-JIRA-123>"
---

# Plan: Feature Planning with Impact Analysis

**Goal:** Transform feature request into implementation plan with blast radius analysis and risk assessment.

## Usage

```
/temper:plan "feature description"
/temper:plan "JIRA-123"
/temper:plan "#123"
/temper:plan --full "feature"    # Force full spec-kit even for simple tasks
/temper:plan --quick "feature"   # Force lightweight plan
/temper:plan --reindex "feature" # Force full semantic index rebuild
```

## Feature: $ARGUMENTS

## Execution

### Phase 0: Detect Input Type

Determine what the user provided:

- Starts with a project prefix + numbers (e.g., `BKNG-1234`, `PROJ-567`) → fetch from Jira API using `gh` or `curl`
- Starts with `#` + numbers (e.g., `#1234`) → fetch from GitHub Issues using `gh issue view`
- URL containing `github.com` → fetch from GitHub using `gh`
- URL containing `atlassian.net` or `jira` → fetch from Jira API
- Everything else → use as direct feature description

**If issue tracker fetch fails:** Fall back to using the raw text as description. Never block on API failures.

### Phase 0.5: Initial File Count Estimate

Before launching the Explore subagent, make a rough estimate to guide planning depth:

```
ESTIMATION HEURISTIC:

| Feature Type | Typical Files | Complexity |
|-------------|---------------|------------|
| Single endpoint/page/handler | 3-5 | Simple |
| New domain/module | 7-12 | Medium-Complex |
| Cross-cutting (auth, middleware) | 10-25 | Complex |
| External service integration | 5-8 | Medium |
```

Pre-estimate only. Explore subagent refines with actual codebase knowledge.

### Phase 1: Auto-Prime (via Explore subagent)

Launch an Explore subagent with this prompt:

```
Scan this project to build a reference map for planning a new feature.

1. DETECT STACK
   - Look for: package.json, pom.xml, build.gradle, pyproject.toml, go.mod, Cargo.toml
   - Read the detected manifest to understand dependencies
   - Check for temper.config (stack override)

2. SCAN PROJECT STRUCTURE
   - List top-level directories
   - Identify source roots (src/, app/, lib/, etc.)
   - Count files by type to understand project scale

3. MAP PATTERNS
   For each layer found, note 1-2 example files:
   - Controllers/routes (API layer)
   - Services (business logic)
   - Repositories/DAOs (data access)
   - Models/entities
   - DTOs/schemas
   - Tests (unit + integration)
   - Configuration files

4. FIND SIMILAR IMPLEMENTATIONS
   Search for existing code similar to the planned feature.
   Use grep for keywords from the feature description.

5. CHECK FOR COMPANY PRESET
   - Read .claude/temper.config if exists
   - Read .claude/presets/*.yaml if exists
   - Read enabled pack rules from .claude/packs/

6. READ SEMANTIC INDEX (if exists)
   - Read .temper/index/modules.json for dependency graph
   - Read .temper/index/api-surface.json for API map
   - If index doesn't exist or is stale, build it:
     - Map all imports/requires across the project
     - List all API endpoints with their handler functions
     - List all test files and what they test

Return a reference map in this format (max 60 lines):

STACK: {detected stack}
PRESET: {preset name or "none"}
PACKS: {enabled packs}

PROJECT STRUCTURE:
  {directory tree, 2 levels deep}

PATTERNS:
  Controllers: {pattern + example file}
  Services: {pattern + example file}
  Repositories: {pattern + example file}
  Tests: {pattern + example file}

SIMILAR CODE:
  {1-3 similar implementations found, with file paths}

DEPENDENCY MAP (relevant to this feature):
  {which modules would be affected}

TEST COVERAGE:
  {files related to this feature and whether they have tests}
```

### Phase 1.5: Validate Subagent Results

```
Missing sections:
  - No controllers → look for entry points, exported functions, main files
  - No tests → TDD creates from scratch; lower coverage expectations; flag in risk
  - No similar code → new capability, higher risk, more questions in Phase 5
  - Stack detection failed → ask user, or check Makefile/Dockerfile/CI config

Reference map too large (>60 lines) → keep only sections relevant to feature
Subagent timeout/failure → fall back to manual exploration, flag lower confidence
```

### Phase 1.6: Semantic Index (Optional Enhancement)

The semantic index accelerates blast radius analysis by pre-computing dependency graphs. It's optional — if missing, the Explore subagent builds equivalent knowledge ad-hoc.

**Index files:**

```
.temper/index/
├── modules.json      # Import/dependency graph
└── api-surface.json  # API endpoints and handlers
```

**modules.json schema:**

```json
{
  "version": 1,
  "last_built": "2026-03-15T10:00:00Z",
  "modules": {
    "src/services/AuthService.ts": {
      "imports": ["src/models/User.ts", "src/utils/jwt.ts"],
      "imported_by": ["src/controllers/AuthController.ts", "src/middleware/auth.ts"],
      "exports": ["AuthService", "verifyToken"]
    }
  }
}
```

**api-surface.json schema:**

```json
{
  "version": 1,
  "last_built": "2026-03-15T10:00:00Z",
  "endpoints": [
    {
      "method": "POST",
      "path": "/api/auth/login",
      "handler": "src/controllers/AuthController.ts:login",
      "middleware": ["src/middleware/rateLimit.ts"]
    }
  ]
}
```

**Index staleness detection:**

- Compare `last_built` timestamp to git's last commit timestamp
- If `last_built` < last commit → rebuild (or use `--reindex` flag)

**Index building (if needed):**

```
1. Find all source files (exclude node_modules, vendor, dist)
2. For each file:
   a. Parse imports/requires
   b. Parse exports
   c. Build reverse dependency map
3. For API routes:
   a. Detect framework (Express, Fastify, Spring, etc.)
   b. Parse route definitions
   c. Map to handler functions
4. Write to .temper/index/
```

**Skip index if:**

- Project < 50 files (ad-hoc analysis is fast enough)
- No .temper/ directory exists yet
- User passed `--quick` flag

### Phase 2: Research (via Research subagent, if needed)

Only launch if the feature involves external libraries or APIs not already in the project:

```
Research the following for implementation guidance:
- {library/API name} documentation
- Known issues and gotchas
- Code examples for {specific use case}

Return only the relevant snippets (max 30 lines).
```

### Phase 3: Assess Complexity + Risk

Based on the reference map, determine:

**File count estimate:**

- How many files need to be created?
- How many files need to be modified?
- Total = created + modified

**Complexity level:**

| Files | Level |
|-------|-------|
| <3 | Trivial → skip planning, just implement |
| 3-5 | Simple → inline plan in conversation |
| 5-10 | Medium → tasks.md + quickstart.md |
| 10+ | Complex → full spec/plan/tasks/quickstart |

**Risk multipliers** (each adds +1 to complexity level):

- Touches payment, auth, or security code
- Modifies shared library consumed by 5+ other modules
- Changes database schema
- Module has historically high defect rate (check .temper/metrics.json if exists)

**Override:** If user passed `--full`, use Complex. If `--quick`, use Simple.

### Phase 4: Blast Radius Analysis

Using the reference map and semantic index:

1. List files that will likely be changed (preliminary — refined after scenarios in Phase 4.5)
2. For each changed file, find all importers/consumers
3. For each consumer, check if it has test coverage for the affected code path
4. Flag any contract changes (API response shapes, event payloads, DB schemas)
5. Flag any architectural drift (new code bypassing established patterns)

**Output format (included in plan and review):**

```
BLAST RADIUS — {feature-name}

  Direct impact:
    {File} ({action}) → used by {N} consumers
    {File} ({action}) → no existing consumers yet

  Transitive impact:
    {Module} → calls {changed-function}()
    {Module} → subscribes to {event}()

  Risk areas:
    {Module} has {X}% test coverage for {path}
    {Module} handler not updated for new payload shape

  Architectural compliance:
    ✅ {pattern} followed
    ✅ {pattern} followed
    ⚠️ {concern}
```

### Phase 4.5: Derive Scenarios (BDD — before architecture)

**Why before architecture:** Scenarios define the behaviors the system must support. Architecture decisions should be driven by these behaviors, not the other way around. This prevents over-engineering (planning files no scenario needs) and scope gaps (missing behaviors that blast radius revealed).

**Skip for Trivial/Simple** — no intent.md generated for these levels.

For Medium and Complex, generate Gherkin scenarios from:

```
SOURCE                              BECOMES
------                              -------
User's feature description    →     Happy path scenarios
Acceptance criteria (issue)   →     Happy path + validation scenarios
Blast radius: risk areas      →     Edge case / error scenarios
Blast radius: affected consumers →  Regression guard scenarios ("existing X still works")
```

**Scenario derivation rules:**

```
Every blast radius risk area → at least one scenario
Every acceptance criterion → at least one scenario
Every affected consumer → a regression guard scenario
Scenarios must be concrete: specific inputs, specific expected outputs
Each scenario must be testable (no "system works correctly")
```

**Scenario count:**

- Medium: 3-8 scenarios (happy path, error path, edge case)
- Complex: 5-15 scenarios (happy path, error paths, edge cases, regression guards)

**Assign testing approach (Note field) per scenario:**

| Behavior Type | Note | When to Use |
|--------------|------|-------------|
| `unit` | Default | Pure logic, no external dependencies |
| `mock` | External dependency | Calls API, sends email, writes to queue |
| `integration` | Cross-boundary | Database queries, multi-service flow |
| `manual` | Non-automatable | UI/UX verification, visual output, email delivery confirmation |

**Output:** A draft list of scenarios that will be written into intent.md in Phase 6. These scenarios now inform Phase 5 (questions) and Phase 6 (architecture/file planning).

**Reconcile with Phase 4 file list:**
After deriving scenarios, check if new files are needed that weren't in the Phase 4 preliminary list — add them. Also check if any Phase 4 files have no scenario or infrastructure justification — flag for removal or justify as infrastructure.

### Phase 5: Ask Clarifying Questions (if ambiguous)

Only ask when genuinely ambiguous — don't ask for the sake of asking. Use AskUserQuestion with concrete options:

Good: "Should this integrate with existing PaymentService or create a new one?"
Bad: "What should the architecture be?"

Scenarios from Phase 4.5 may reveal ambiguities that weren't visible from the feature description alone. Maximum 2-3 questions. If requirements are clear, skip this phase entirely.

### Phase 6: Generate Plan Artifacts

**For Trivial:** No artifacts. Tell user: "Small change. I'll implement directly."

**For Simple:** Inline plan in conversation. No files created:

```
Plan: {feature name}
Files to create: {list}
Files to modify: {list}
Tasks:
1. {task} → validate: {command}
2. {task} → validate: {command}
```

**For Medium:** Create `.temper/specs/{feature-slug}/`:

- `intent.md` — WHY + WHAT: Intent section (problem, success criteria, constraints) + Gherkin scenarios
- `tasks.md` — ordered implementation steps
- `quickstart.md` — 10-line summary

**For Complex:** Create `.temper/specs/{feature-slug}/`:

- `spec.md` — WHAT: requirements, acceptance criteria, edge cases
- `intent.md` — WHY + WHAT: Intent section (problem, success criteria, constraints) + Gherkin scenarios
- `plan.md` — HOW: architecture, file changes, patterns, blast radius
- `tasks.md` — DO: ordered steps with validation command per task
- `quickstart.md` — TLDR: 10-line summary

**For Trivial/Simple:** No intent.md

#### intent.md Generation

The intent.md file combines IDD (Intent-Driven Development) and BDD (Behavior-Driven Development) in one artifact:

**Intent Section (IDD):**

- Problem: derived from user's feature description + linked issue
- Success criteria: measurable outcomes from acceptance criteria, each with a `Validate:` field
- Constraints: technical/business limitations from blast radius + pack rules
- Target users: who benefits from this feature

**For Complex features (spec.md + intent.md both exist):**

- `spec.md` = WHAT (requirements from stakeholder perspective, acceptance criteria)
- `intent.md` = WHY + HOW TO VERIFY (success criteria, scenarios for validation)
- Derive intent.md success criteria FROM spec.md acceptance criteria
- Each spec.md acceptance criterion → at least one intent.md scenario
- spec.md edge cases → intent.md edge case scenarios

**Success criteria validation types:**

| Type | When to Use | Example |
|------|------------|---------|
| `scenario` | Criterion maps to a Gherkin scenario | `Validate: scenario — covered by "User resets password"` |
| `code` | Criterion verifiable by checking code exists | `Validate: code — endpoint exists at POST /api/reset` |
| `metric` | Criterion requires post-deploy measurement | `Validate: metric — measure support ticket volume post-deploy` |
| `manual` | Criterion requires human judgment | `Validate: manual — UX review needed` |

Prefer `scenario` and `code` — these are mechanically verifiable. Use `metric` and `manual` only when mechanical validation is impossible.

**Scenarios Section (BDD):**
Scenarios are derived in Phase 4.5 (before architecture). Write them into intent.md here.

Use templates from `$CLAUDE_PLUGIN_ROOT/templates/` (spec.md, plan.md, tasks.md, quickstart.md) as the base structure. Fill in from reference map and blast radius analysis.

**Populate `Traced to:` in tasks.md:**
When generating tasks.md, fill the `Traced to:` field for each task:

- If the task creates/modifies a file needed by a scenario → `Traced to: Scenario: "scenario name"`
- If a task covers multiple scenarios → list all: `Traced to: Scenario: "name1", "name2"`
- If the task is infrastructure (config, migration, build setup) → `Traced to: Infrastructure: required by {module/file}`
- If a task cannot be traced → question whether it's needed (see File-to-Scenario Traceability)

#### File-to-Scenario Traceability

Every file in the plan must justify its existence. Files fall into two categories:

```
Scenario-traced files (must link to at least one scenario):
  src/services/PasswordResetService.ts  → Scenario: "User resets password"
  src/middleware/RateLimiter.ts          → Scenario: "Rate limiting enforced"

Infrastructure files (no scenario required, but must state dependency):
  db/migrations/001_add_reset_tokens.sql → Required by PasswordResetService
  config/email.ts                        → Required by PasswordResetService
```

If a planned file cannot be traced to any scenario AND is not infrastructure:

- Question whether it's needed
- If it is needed, a scenario is missing — add one in Phase 4.5

This prevents over-engineering: no file exists without a behavioral or infrastructural reason.

#### Task Ordering in tasks.md

Order tasks by layer (dependencies first):

```
1. Infrastructure (config, DB migrations, build setup)
2. Core (models, services, business logic)
3. Integration (controllers, routes, API endpoints)
4. Tests (integration tests, E2E)
```

#### Parallel Task Detection

Analyze task pairs for file independence. Mark independent tasks with `[PARALLEL: with Task X]`:

```
ANALYSIS RULES:

Two tasks CAN run in parallel if:
- They modify different files (no overlap)
- Neither depends on the other's output
- No shared mutable state

Two tasks MUST be sequential if:
- Task B imports from Task A's file
- Task B tests Task A's code
- Task B depends on Task A's config changes

MARKING FORMAT:
- Sequential: `## Task 1 — {title} [SEQUENTIAL]`
- Sequential after another: `## Task 2 — {title} [SEQUENTIAL: after Task 1]`
- Parallel with another: `## Task 3 — {title} [PARALLEL: with Task 4]`

GUARD: When in doubt, keep sequential. Parallel marking is an optimization, not a requirement.
```

### Phase 7: Present for Approval

Show a nice summary box with intent included:

**For Medium/Complex features:**

```
┌─────────────────────────────────────────────────────────────┐
│ 📋 PLAN — {Feature Name}                                   │
├─────────────────────────────────────────────────────────────┤
│ 🎯 INTENT (Why)                                             │
│    Problem: {derived from feature description}              │
│    Success: {key success criteria, max 2}                   │
│                                                             │
│ 📝 PLAN (What & How)                                        │
│    Scenarios: {N} ({unit} unit, {mock} mock, {int} integ)   │
│    1. {scenario name}                                      │
│    2. {scenario name}...                                   │
│                                                             │
│ 📁 ARCHITECTURE                                             │
│    Create: {N} — {key files}                               │
│    Modify: {N} — {key files}                               │
│                                                             │
│ ⚡ RISK: {Low/Medium/High} — {reason}                       │
│                                                             │
│ What next?                                                  │
│   [Enter] Build it                                          │
│   [c]     Change something first                            │
│   [s]     Save for later                                    │
└─────────────────────────────────────────────────────────────┘
```

**For Simple features:**

```
┌─────────────────────────────────────────────────────────────┐
│ 📋 PLAN — {Feature Name}                                   │
├─────────────────────────────────────────────────────────────┤
│ Files: {N} create, {N} modify                               │
│ Risk: {Low/Medium}                                          │
│                                                             │
│ What next?                                                  │
│   [Enter] Build it                                          │
│   [c]     Change something first                            │
│   [s]     Save for later                                    │
└─────────────────────────────────────────────────────────────┘
```

**For Trivial features:**

```
┌─────────────────────────────────────────────────────────────┐
│ 📋 Small change — implementing directly                     │
│ {1-line description of what will be done}                   │
│                                                             │
│ What next?                                                  │
│   [Enter] Do it                                             │
│   [s]     Save for later                                    │
└─────────────────────────────────────────────────────────────┘
```

#### Approval Gate

Use AskUserQuestion with these options:

| Response | Action |
|----------|--------|
| **Enter** (default) | Proceed to build. Signal context clear, load tasks.md + intent.md |
| **c** (change) | User types what to change. Claude edits. Re-ask. |
| **s** (save) | Save state to .temper/build-state.json, stop here |

**On Enter (continue):**

```
1. Signal context transition:
   "✅ Continuing to BUILD...
    🧹 Clearing context for efficiency.
    📂 Loading: tasks.md + intent.md only"

2. Write to .temper/build-state.json:
   {
     "stage": "plan_complete",
     "spec": "{feature-slug}",
     "next_stage": "build",
     "artifacts": ["intent.md", "tasks.md"]
   }

3. Clear current context (planning artifacts)

4. Load only what's needed for build:
   - .temper/specs/{feature}/tasks.md
   - .temper/specs/{feature}/intent.md (if exists)

5. Proceed to /temper:build (or continue if using unified /temper)
```

**On c (change):**

```
1. Ask: "What would you like to change?"
2. User types their change request
3. Claude edits intent.md (adds/removes scenarios, modifies success criteria, etc.)
4. Re-show summary
5. Re-ask: "What next? [Enter/c/s]"
```

**On s (save):**

```
1. Save state to .temper/build-state.json
2. Report: "✅ Saved. Run /temper when ready to continue."
```

### Edge Cases

```
Vague feature description ("improve performance"):
  → Ask with AskUserQuestion: "Which part? API response times, page load, DB queries, background jobs?"
  → Narrow scope before exploring

No tests in project:
  → Flag in risk assessment, lower coverage expectations
  → Add Task 0 to plan: "Set up test infrastructure"
  → Focus on testing NEW code only

Monorepo (multiple manifests found):
  → Ask user which package/module to plan for
  → Still check blast radius across packages (shared libraries)

Database migration needed:
  → Add migration as Task 1 (before code depending on schema)
  → +1 risk multiplier for schema changes
  → Note rollback migration in plan

Feature already partially exists:
  → Reference map shows similar code → build on it, don't duplicate
  → Flag in plan: "Extending existing {module}, not creating from scratch"
```
