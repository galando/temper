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

1. List all files that will be changed
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

### Phase 5: Ask Clarifying Questions (if ambiguous)

Only ask when genuinely ambiguous — don't ask for the sake of asking. Use AskUserQuestion with concrete options:

Good: "Should this integrate with existing PaymentService or create a new one?"
Bad: "What should the architecture be?"

Maximum 2-3 questions. If requirements are clear, skip this phase entirely.

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
- `tasks.md` — ordered implementation steps
- `quickstart.md` — 10-line summary

**For Complex:** Create `.temper/specs/{feature-slug}/`:
- `spec.md` — WHAT: requirements, acceptance criteria, edge cases
- `plan.md` — HOW: architecture, file changes, patterns, blast radius
- `tasks.md` — DO: ordered steps with validation command per task
- `quickstart.md` — TLDR: 10-line summary

Use templates from `$CLAUDE_PLUGIN_ROOT/templates/` (spec.md, plan.md, tasks.md, quickstart.md) as the base structure. Fill in from reference map and blast radius analysis.

### Phase 7: Present for Approval

Show the user:
- Plan summary (quickstart content)
- Risk level with justification
- Blast radius summary (if any consumers affected)
- File count

Use ExitPlanMode for user approval. User can modify the plan files before proceeding.

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
