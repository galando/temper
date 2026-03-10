import { type Plugin, type ToolContext, tool } from "./types"

/**
 * Temper Plugin for OpenCode
 *
 * Quality gates, blast radius analysis, and adaptive learning for AI-generated code.
 *
 * Commands available:
 * - temper_plan: Plan feature with blast radius analysis
 * - temper_build: Execute plan with TDD and quality gates
 * - temper_review: Code review with confidence scoring
 * - temper_check: Stack-aware validation pipeline
 * - temper_fix: Root cause analysis + structured bug fix
 * - temper_standards: Build team engineering standards
 * - temper_status: Quality metrics dashboard
 */

export const TemperPlugin: Plugin = async (_ctx) => {
  return {
    tool: {
      // ============================================================================
      // PLAN: Feature Planning with Impact Analysis
      // ============================================================================
      temper_plan: tool({
        description: `Transform feature request into implementation plan with blast radius analysis.

Usage:
- temper_plan({ feature: "add OAuth authentication" })
- temper_plan({ feature: "JIRA-123" })
- temper_plan({ feature: "#456" })
- temper_plan({ feature: "feature", mode: "full" })  // Force full spec-kit
- temper_plan({ feature: "feature", mode: "quick" }) // Force lightweight

Phases:
1. Detect input type (Jira/GitHub/description)
2. Auto-prime via codebase exploration
3. Research external docs if needed
4. Assess complexity + risk
5. Blast radius analysis
6. Clarify if ambiguous (max 2-3 questions)
7. Generate spec/plan/tasks to .temper/specs/{feature}/
8. Present for approval`,

        args: {
          feature: tool.schema.string().describe("Feature description, Jira ticket (JIRA-123), or GitHub issue (#123)"),
          mode: tool.schema.enum(["auto", "full", "quick"] as const).optional().default("auto").describe("Planning mode: auto (default), full (force spec-kit), quick (inline)"),
        },

        async execute(args: { feature: string; mode?: string }, context: ToolContext) {
          const { directory } = context
          return {
            instructions: `# Plan: Feature Planning with Impact Analysis

## Feature: ${args.feature}
${args.mode && args.mode !== "auto" ? `## Mode: ${args.mode}` : ""}

**Goal:** Transform feature request into implementation plan with blast radius analysis and risk assessment.

### Phase 0: Detect Input Type
- Jira ticket (e.g., BKNG-1234) → fetch from Jira API
- GitHub issue (e.g., #123) → fetch via gh issue view
- URL → fetch from appropriate source
- Otherwise → use as direct description

### Phase 1: Auto-Prime
Scan this project to build a reference map:
1. DETECT STACK (package.json, pom.xml, pyproject.toml, go.mod, Cargo.toml)
2. SCAN PROJECT STRUCTURE (top-level dirs, source roots)
3. MAP PATTERNS (controllers, services, repositories, tests)
4. FIND SIMILAR IMPLEMENTATIONS
5. CHECK FOR TEMPER CONFIG (.claude/temper.config, packs)

### Phase 2: Research (if needed)
Only if feature involves external libraries not in project.

### Phase 3: Assess Complexity
| Files | Level |
|-------|-------|
| <3 | Trivial → implement directly |
| 3-5 | Simple → inline plan |
| 5-10 | Medium → tasks.md + quickstart.md |
| 10+ | Complex → full spec/plan/tasks/quickstart |

### Phase 4: Blast Radius Analysis
- List all files to be changed
- Find importers/consumers for each
- Check test coverage for affected paths
- Flag contract changes (API, DB schema)

### Phase 5: Clarify (if ambiguous)
Max 2-3 questions. Skip if clear.

### Phase 6: Generate Artifacts
Create .temper/specs/{feature-slug}/:
- spec.md (requirements)
- plan.md (architecture, blast radius)
- tasks.md (ordered steps)
- quickstart.md (10-line summary)

### Phase 7: Present for Approval
Show plan summary, risk level, blast radius, file count.

Working directory: ${directory}
`
          }
        },
      }),

      // ============================================================================
      // BUILD: Execute Plan with Quality Gates
      // ============================================================================
      temper_build: tool({
        description: `Execute approved plan task by task with TDD and graduated quality gates.

Usage:
- temper_build({}) // Auto-detect active plan
- temper_build({ spec: "auth-feature" }) // Specify spec

Prerequisites:
- Approved plan exists (from temper_plan)
- OR user provides inline instructions for trivial tasks

Execution:
1. Load plan from .temper/specs/{feature}/tasks.md
2. Verify feature branch (create if on main)
3. For each task: test first (RED) → implement (GREEN) → validate
4. After all tasks: auto-chain → temper_review → temper_check
5. Report results, ask to commit`,

        args: {
          spec: tool.schema.string().optional().describe("Spec name to build (auto-detects if not provided)"),
        },

        async execute(args: { spec?: string }, context: ToolContext) {
          const { directory } = context
          return {
            instructions: `# Build: Execute Plan with Quality Gates

${args.spec ? `## Spec: ${args.spec}` : "## Spec: Auto-detect from .temper/specs/"}

**Goal:** Implement the approved plan, task by task, with TDD and graduated quality gates.

### Step 1: Load Plan
1. Check for active plan in .temper/specs/*/tasks.md
2. If multiple specs exist, ask user which to execute
3. Load tasks.md + quickstart.md
4. Read plan.md for architecture decisions
5. Read active pack rules from .claude/packs/

### Step 2: Verify Branch
1. Run: git branch --show-current
2. If on main/master: ask user to create feature branch
3. Suggest name: feature/{ticket}-{description}

### Step 3: Execute Tasks (in order)
For each task:
a. **Read context** - Read existing files, understand patterns
b. **Write test first** - If TDD pack enabled (RED phase)
c. **Implement** - Write minimal code to pass
d. **Validate** - Run test → GREEN, run validation
e. **Refactor** - Only if obvious, low-risk, all tests pass

### Step 4: Post-Implementation
1. Run full test suite → all must pass
2. Run temper_review → fix issues (max 2 loops)
3. Run temper_check → all levels must pass
4. Report results:
   "Feature complete. {X} files created, {Y} modified, {Z} tests added."
5. On approval → commit with conventional message

### Quality Gates
| Level | Behavior |
|-------|----------|
| SUGGEST | Non-blocking, logged only |
| WARN | Highlighted, developer decides |
| BLOCK | Must fix before proceeding |

### Error Recovery
- COMPILATION ERROR: Read full error → identify type → fix → retry (max 3)
- TEST FAILURE (new): Test may be wrong OR implementation wrong → investigate
- TEST FAILURE (existing): REGRESSION → your code broke something → fix your code
- STUCK: Re-read plan → re-read similar code → break down task

Working directory: ${directory}
`
          }
        },
      }),

      // ============================================================================
      // REVIEW: Confidence-Scored Code Review
      // ============================================================================
      temper_review: tool({
        description: `Review changes with parallel analysis, confidence scoring, and intent validation.

Usage:
- temper_review({}) // Review current changes

Execution:
1. Gather changed files + active pack rules + review memory
2. Analyze: backend/frontend/security concerns
3. Intent validation against linked issue (if any)
4. Filter by confidence threshold + review memory
5. Generate report to .temper/reviews/
6. Auto-fix high-priority issues (if enabled, max 2 loops)
7. Update metrics + review memory`,

        args: {
          files: tool.schema.array(tool.schema.string()).optional().describe("Specific files to review (defaults to changed files)"),
          threshold: tool.schema.number().min(0).max(1).optional().default(0.7).describe("Confidence threshold (0.0-1.0)"),
        },

        async execute(args: { files?: string[]; threshold?: number }, context: ToolContext) {
          const { directory } = context
          return {
            instructions: `# Review: Confidence-Scored Code Review

**Goal:** Review changes with confidence scoring and intent validation.

${args.files ? `## Files: ${args.files.join(", ")}` : "## Files: Auto-detect from git status"}
## Confidence Threshold: ${args.threshold ?? 0.7}

### Step 1: Gather Context
1. Get changed files from git
2. Load active pack rules from .claude/packs/
3. Load review memory from .temper/review-memory.json

### Step 2: Parallel Analysis
Analyze for:
- **Backend**: Business logic, data access, API contracts
- **Frontend**: Components, state management, UI patterns
- **Security**: OWASP Top 10, secrets, auth/authorization

### Step 3: Intent Validation
If linked issue exists, verify changes match stated requirements.

### Step 4: Filter by Confidence
- Score each finding (0.0-1.0)
- Suppress if in review memory (dismissed 5+ times)
- Only report findings above threshold

### Step 5: Generate Report
Write to .temper/reviews/{timestamp}.md:
- Summary
- High-priority findings
- Suggestions
- Metrics update

### Step 6: Auto-Fix (if enabled)
Fix high-priority issues automatically (max 2 loops).

### Step 7: Update Metrics
- Increment review count
- Update pattern frequency
- Store in .temper/metrics.json

Working directory: ${directory}
`
          }
        },
      }),

      // ============================================================================
      // CHECK: Validation Pipeline
      // ============================================================================
      temper_check: tool({
        description: `Auto-detect stack and run validation levels in order.

Usage:
- temper_check({}) // Run all levels
- temper_check({ level: 3 }) // Run up to level 3

Levels (stop on failure):
0. Environment — verify not production
1. Compile/Build
2. Unit Tests
3. Integration Tests (if configured)
4. Coverage (threshold from config)
5. Lint/Format
6. Type Check
7. Security (dependency scan)`,

        args: {
          level: tool.schema.number().min(0).max(7).optional().describe("Stop at this level (default: run all)"),
          fix: tool.schema.boolean().optional().default(false).describe("Auto-fix lint/format issues"),
        },

        async execute(args: { level?: number; fix?: boolean }, context: ToolContext) {
          const { directory } = context
          return {
            instructions: `# Check: Validation Pipeline

**Goal:** Auto-detect stack and run validation levels in order.

${args.level !== undefined ? `## Stop at Level: ${args.level}` : "## Run All Levels"}
${args.fix ? "## Auto-fix: Enabled" : ""}

### Stack Detection
Detect stack from project files:
- pom.xml → Spring Boot (mvn compile, mvn test)
- package.json + tsconfig.json → React/TypeScript (npm test, npm run build)
- package.json + express → Node/Express (npm test, npm run build)
- pyproject.toml + fastapi → FastAPI (pytest, ruff, mypy)
- go.mod → Go (go test, golangci-lint, go build)
- Cargo.toml → Rust (cargo test, cargo clippy, cargo build)

### Validation Levels (stop on failure)

**Level 0: Environment**
- Verify not production
- Check required tools installed

**Level 1: Compile/Build**
- Spring Boot: mvn compile
- TypeScript: tsc --noEmit or npm run build
- Python: python -m py_compile (or mypy)
- Go: go build ./...
- Rust: cargo build

**Level 2: Unit Tests**
- Run unit test suite
- All tests must pass

**Level 3: Integration Tests** (if configured)
- Run integration tests
- Check .claude/temper.config for integration test command

**Level 4: Coverage**
- Check coverage threshold from config
- Default: 80% for new code

**Level 5: Lint/Format**
- Run linter (eslint, ruff, golangci-lint, clippy)
${args.fix ? "- Auto-fix issues where possible" : ""}

**Level 6: Type Check**
- TypeScript: tsc --noEmit
- Python: mypy
- Go: go vet

**Level 7: Security**
- Run dependency scan (npm audit, pip-audit, etc.)
- Check for known vulnerabilities

### Output
Report results for each level:
✅ Level X: Passed
❌ Level X: Failed (details)

Working directory: ${directory}
`
          }
        },
      }),

      // ============================================================================
      // FIX: Root Cause Analysis + Structured Bug Fix
      // ============================================================================
      temper_fix: tool({
        description: `Find root cause, write regression test, implement minimal fix, validate.

Usage:
- temper_fix({ bug: "login fails with special characters" })
- temper_fix({ bug: "JIRA-456" })

Execution:
1. Detect input (Jira/GitHub/description)
2. RCA via exploration (search code, trace execution, check git history)
3. Write regression test → must FAIL (confirms bug)
4. Implement minimal fix → test must PASS
5. Run temper_check → all tests pass
6. Report + commit`,

        args: {
          bug: tool.schema.string().describe("Bug description or issue reference (JIRA-123, #456)"),
        },

        async execute(args: { bug: string }, context: ToolContext) {
          const { directory } = context
          return {
            instructions: `# Fix: RCA + Regression Test + Fix

## Bug: ${args.bug}

**Goal:** Find root cause, write regression test, implement minimal fix, validate.

### Step 1: Detect Input Type
- Jira ticket → fetch details
- GitHub issue → fetch via gh
- Description → use directly

### Step 2: Root Cause Analysis
1. Search code for relevant keywords
2. Trace execution path
3. Check git history for recent changes
4. Identify the failing component/line

Document findings:
- **Symptom**: What the user experiences
- **Root Cause**: The actual bug in code
- **Impact**: How many users/systems affected

### Step 3: Write Regression Test
1. Create test that reproduces the bug
2. Run test → must FAIL (confirms bug exists)
3. Test should cover the exact scenario

### Step 4: Implement Minimal Fix
1. Write smallest change that fixes the bug
2. Do NOT refactor or add features
3. Run regression test → must PASS

### Step 5: Validate
1. Run temper_check → all levels must pass
2. Run related unit tests
3. Verify no regressions in existing tests

### Step 6: Report & Commit
1. Document the fix
2. Commit with message:
   "fix: {brief description}

   Root cause: {explanation}
   Fix: {what was changed}

   Closes #{issue}"
3. Include co-authorship if applicable

Working directory: ${directory}
`
          }
        },
      }),

      // ============================================================================
      // STANDARDS: Interactive Standards Builder
      // ============================================================================
      temper_standards: tool({
        description: `Scan codebase for patterns, interview about conventions, generate company pack.

Usage:
- temper_standards({}) // Start interactive session

Execution:
1. Scan codebase (patterns, consistency, inconsistencies)
2. Interview developer (5-10 questions about conventions)
3. Generate .claude/packs/{company}/rules.md + preset
4. Validate against current codebase, set baseline`,

        args: {
          company: tool.schema.string().optional().describe("Company/team name for the pack"),
        },

        async execute(args: { company?: string }, context: ToolContext) {
          const { directory } = context
          return {
            instructions: `# Standards: Interactive Standards Builder

**Goal:** Scan codebase for patterns, interview about conventions, generate company pack + preset.

${args.company ? `## Company: ${args.company}` : "## Company: (ask user)"}

### Step 1: Scan Codebase
Analyze for:
- **Patterns**: Common coding patterns used
- **Consistency**: Are patterns followed consistently?
- **Inconsistencies**: Where do patterns diverge?
- **Test coverage**: What's tested? What's not?
- **Naming conventions**: Variable, function, class names
- **File organization**: Directory structure patterns

### Step 2: Interview Developer
Ask 5-10 questions about conventions:
- "I see methods typically have 15-20 lines. What's your preferred max?"
- "Error handling uses Result types. Should this be enforced?"
- "Tests use Given-When-Then. Is this a team standard?"
- "API responses use DTOs. Should this be a BLOCK rule?"

### Step 3: Generate Pack
Create .claude/packs/{company}/rules.md:

\`\`\`markdown
# {Company} Standards

## BLOCK
- [Mandatory rules from interview]

## WARN
- [Quality rules from interview]

## SUGGEST
- [Conventions from interview]
\`\`\`

### Step 4: Validate
1. Run pack against current codebase
2. Check for false positives
3. Set baseline (current issues are "known")
4. Store in .temper/baseline.json

### Step 5: Create Preset (optional)
If team has specific configuration:
\`\`\`yaml
# .claude/presets/{company}.yaml
stack: spring-boot
packs:
  - quality
  - tdd
  - security
  - {company}
\`\`\`

Working directory: ${directory}
`
          }
        },
      }),

      // ============================================================================
      // STATUS: Quality Metrics Dashboard
      // ============================================================================
      temper_status: tool({
        description: `Display metrics, trends, learning loop suggestions.

Usage:
- temper_status({}) // Show dashboard

Displays:
- Total reviews run
- Quality trend (improving/stable/declining)
- Technical debt score
- Top patterns detected
- Learning loop suggestions
- Active specs in progress`,

        args: {},

        async execute(_args: Record<string, never>, context: ToolContext) {
          const { directory } = context
          return {
            instructions: `# Status: Quality Metrics Dashboard

**Goal:** Display metrics, trends, learning loop suggestions.

### Read Data Sources
1. .temper/metrics.json (if exists)
2. .temper/review-memory.json (if exists)
3. .temper/specs/ (active specs)

### Display Dashboard

\`\`\`
╔═══════════════════════════════════════════════════════════════╗
║                     TEMPER METRICS DASHBOARD                   ║
╠═══════════════════════════════════════════════════════════════╣
║  Reviews Run:         {count}                                   ║
║  Quality Trend:       {improving/stable/declining} ↑/→/↓       ║
║  Tech Debt Score:     {score}/10                                ║
║  Active Specs:        {count}                                   ║
╠═══════════════════════════════════════════════════════════════╣
║  TOP PATTERNS DETECTED                                         ║
║  1. {pattern} - {count} occurrences                            ║
║  2. {pattern} - {count} occurrences                            ║
║  3. {pattern} - {count} occurrences                            ║
╠═══════════════════════════════════════════════════════════════╣
║  LEARNING LOOP                                                 ║
║  {suggestion for new rule based on pattern}                    ║
║  Run temper_standards to add as team rule                      ║
╚═══════════════════════════════════════════════════════════════╝
\`\`\`

### Pattern Detection → Rule Suggestion
If a pattern appears 3+ times:
- Suggest creating a team rule
- Show example of rule to add

### Active Specs
List any specs in .temper/specs/:
- {spec-name}: {status}
- {spec-name}: {status}

### Files to Read
- .temper/metrics.json
- .temper/review-memory.json
- .temper/specs/*/tasks.md

Working directory: ${directory}
`
          }
        },
      }),
    },
  }
}

export default TemperPlugin
