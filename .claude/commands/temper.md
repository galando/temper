---
description: "Unified SDLC command: plan → design → build → review → check with stage gates, feedback loops, and observability"
argument-hint: "<feature-description>"
---

# Temper: Unified SDLC Command (v4.4.1)

**Goal:** Execute the full SDLC flow (plan → design? → build → review → check → commit) with stage gates, feedback loops, context accumulation, observability, and **real** context isolation via Agent subprocesses.

## Usage

```
/temper "add login feature"    # Start new feature
/temper                         # Resume or continue
```

---

## Architecture: Agent Per Stage

### Shared Orchestrator Patterns

> **Reference:** `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/orchestrator-patterns.md`
>
> This command uses shared patterns for: $CLAUDE_PLUGIN_ROOT resolution, gate options, gate enforcement, resume validation, nested invocation protection, agent failure handling, and context efficiency. Read that file for the canonical definitions.

Each stage runs in an **isolated Agent subprocess**. This provides genuine context clearing — each stage starts with a clean context window containing only what it needs.

```
ORCHESTRATOR (this file)
  │
  ├── Agent subprocess → PLAN (full codebase exploration)
  │     ↓ returns: plan summary + spec path + complexity
  │     ↓ gate decision from user
  │
  ├── [OPTIONAL] Agent subprocess → DESIGN (if complex/medium + phases.design: true)
  │     ↓ returns: design summary + design.md
  │     ↓ gate decision from user
  │
  ├── Agent subprocess → BUILD (loads tasks.md + intent.md only)
  │     ↓ returns: build summary + files changed + build-context.json
  │     ↓ gate decision from user
  │     ↓ FEEDBACK: may loop back to PLAN (infeasible design)
  │
  ├── Agent subprocess → REVIEW (loads changed files only)
  │     ↓ returns: review summary + issues + review-context.json
  │     ↓ gate decision from user
  │     ↓ FEEDBACK: may loop back to BUILD (auto-fix loop)
  │
  └── Agent subprocess → CHECK (runs validation pipeline)
        ↓ returns: check results + check-context.json
        ↓ gate decision from user → commit
        ↓ FEEDBACK: may loop back to BUILD (test failure loop)
```

**Why Agent subprocesses?** A self-directed prompt like "CLEAR ALL CONTEXT" is unenforceable — Claude cannot clear its own context window. Agent subprocesses start with genuinely clean context because they are separate invocations.

### State Management

The orchestrator tracks progress via `.temper/build-state.json`. **Resolve the spec path from this file before launching any agent.**

```json
{
  "stage": "plan_complete|design_complete|build_complete|review_complete|check_complete",
  "spec": "{feature-slug}",
  "spec_path": ".temper/specs/{feature-slug}",
  "branch": "feature/{feature-slug}",
  "original_args": "{user's original feature description}",
  "next_stage": "build|review|check|commit",
  "artifacts": ["intent.md", "tasks.md"],
  "updated": "{ISO timestamp}"
}
```

On resume, validate `build-state.json`: parseable JSON, stage is valid, spec directory exists, listed artifacts exist. If invalid, ask user whether to start over.

### Agent Failure Handling

If an agent subprocess returns a failure or blocker:
1. Show the failure details to the user
2. Ask: "Retry / Save for later?" (user can type changes via "Other")
3. Do NOT silently proceed to the next stage

---

## Stage Gates Use AskUserQuestion

> **Gate patterns:** See `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/orchestrator-patterns.md` → "Gate Options Pattern" and "Gate Enforcement Rules" sections.

At each stage gate, use `AskUserQuestion` with selectable options. Do NOT use `[Enter]` as a prompt.

---

## Stage 1: Planning

**Runs in:** Agent subprocess with full codebase access

### Launch Planning Agent

```
Use the Agent tool with this prompt:

"Execute /temper:plan for feature: $ARGUMENTS

Full methodology: Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/plan.md

ENFORCEMENT: Always follow the full planning methodology regardless of complexity level. Always generate: intent.md, tasks.md, mermaid diagram in plan.md, blast radius analysis. No shortcuts.

MCP PRIORITY: If code-review-graph MCP tools are available, use them as the PRIMARY exploration method in Phase 1 (Auto-Prime). Call build_or_update_graph_tool, get_architecture_overview_tool, list_communities_tool, list_flows_tool, and semantic_search_nodes_tool BEFORE falling back to grep/read. These tools provide AST-level proven dependency analysis that is far superior to heuristic grep-based exploration.

DIAGRAM ENFORCEMENT: You MUST generate ASCII art diagrams using box-drawing characters (+, -, |, -->, etc.). Write BOTH mermaid source and ASCII art to plan.md. When returning the summary to the orchestrator, include ONLY the ASCII art version — NEVER return raw mermaid source code in the summary. The summary must be readable in a terminal without any rendering tool.

CRITICAL: This agent runs in isolation. After planning:
1. Show the plan summary box (see below)
2. Do NOT show an AskUserQuestion gate — return the summary to the orchestrator
3. The orchestrator handles the gate decision

Return ONLY:
- Plan summary text (formatted box + ASCII art diagram rendered below it — NOT raw mermaid source)
- Path to spec: .temper/specs/{feature-slug}/
- Complexity level: trivial/simple/medium/complex
- Risk level: low/medium/high"
```

### Plan Summary Format

**ENFORCEMENT:** The unified `/temper` command always follows the full planning guidelines regardless of complexity level. No shortcuts for Simple or Trivial features. Always generate: intent.md, tasks.md, mermaid diagram, blast radius, and present the full approval gate with walkthrough option.

```
┌─────────────────────────────────────────────────────────────┐
│ PLAN — {Feature Name}                                       │
├─────────────────────────────────────────────────────────────┤
│ INTENT (Why)                                                │
│    Problem: {one-line problem}                              │
│    Success: {success criteria 1}                            │
│             {success criteria 2}                            │
│                                                             │
│ PLAN (What & How)                                           │
│    Scenarios: {N} ({N} unit, {N} mock, {N} integration)     │
│    1. {scenario name}                                       │
│    2. {scenario name}                                       │
│    3. {scenario name}...                                    │
│                                                             │
│ ARCHITECTURE                                                │
│    Create: {N} files                                        │
│      • {file} — {purpose}                                   │
│    Modify: {N} files                                        │
│      • {file} — {change reason}                             │
│                                                             │
│ RISK: {Low/Medium/High} — {reason}                          │
│                                                             │
│ SECURITY (if hot paths found)                               │
│    {N} CRITICAL, {N} HIGH hot paths                         │
│    {top finding}                                            │
└─────────────────────────────────────────────────────────────┘

Diagram (rendered below summary box — MUST be ASCII art, NOT raw mermaid source):

{ASCII art diagram — generated using +---+ boxes, --> arrows, | walls. MUST be readable in terminal.}
```

**CRITICAL:** The diagram in the summary MUST be ASCII art (box-drawing characters). Do NOT output raw mermaid syntax like "flowchart TD", "subgraph", "A[B] --> C" — that is NOT readable in a terminal. Generate proper ASCII art with aligned boxes and arrows.

### Stage Gate

Show the AskUserQuestion gate with:
- "Continue to Build (Recommended)" — launch BUILD agent
- "Walk through plan step by step" — interactive walkthrough (see below)
- "Save for later" — save state, stop
- **"Other" (built-in free-text)** — type a change request, edits are made, gate re-appears

#### Step-by-Step Walkthrough

When the user selects "Walk through plan step by step", present the plan as an interactive, section-by-section flow. Read the plan files (intent.md, plan.md, tasks.md) from `.temper/specs/{feature-slug}/` to provide detailed content for each section.

**Walkthrough sections (presented one at a time):**

1. **Intent Deep Dive** — Full problem statement, all success criteria with validation methods, constraints, target users
2. **Diagram Walkthrough** — Show the ASCII art diagram (from plan.md), explain each node/edge, highlight what's new vs existing vs modified
3. **Scenario Review** — For each BDD scenario: show the Gherkin, explain why it exists (which blast radius risk or acceptance criterion it addresses)
4. **Architecture Details** — For each file to create/modify: what it does, which patterns it follows, which scenarios it traces to
5. **Blast Radius Review** — Each impacted consumer, whether tests exist, what regression guards are in place
6. **Task Walkthrough** — For each task: what it does, validation command, dependencies, parallel opportunities

**After each section, use AskUserQuestion:**

```
AskUserQuestion:
  question: "Plan walkthrough — {current section name}. What would you like to do?"
  options:
    - label: "Next step"
      description: "Continue to {next section name}."
    - label: "Skip to build"
      description: "Skip remaining sections, proceed to Build stage."
    - label: "Switch to design walkthrough"
      description: "Jump to the Design walkthrough (if design stage is active)."
  multiSelect: false
```

- **"Other"** (built-in free-text): Ask a question or request a change. Answer/edit, then re-show the same section's gate.
- **"Next step"**: Advance to next section. After the last section, show the final walkthrough gate (see below)
- **"Skip to build"**: Exit walkthrough immediately, save state, proceed to Build stage (same as "Continue to Build" from the main gate)
- **"Switch to design walkthrough"**: Begin the Design walkthrough from section 1. Only shown if `phases.design: true` and complexity is medium/complex. If design stage is not active, omit this option. The user can navigate back from Design walkthrough.

After the last section, show the final walkthrough gate:

```
AskUserQuestion:
  question: "Plan walkthrough complete. What next?"
  options:
    - label: "Continue to Build (Recommended)"
      description: "Launch BUILD agent with clean context."
    - label: "Switch to design walkthrough"
      description: "Jump to the Design walkthrough for cross-reference."
    - label: "Save for later"
      description: "Save state and stop."
  multiSelect: false
```

**"Other" (free-text change request)**: Edit plan files, show what changed, re-show this gate.

**on "Switch to design walkthrough"** (from either per-section or final gate): Begin the Design walkthrough (Stage 1.5 walkthrough steps), starting from section 1. Only available if `phases.design: true` and complexity is medium/complex. If design stage is not active, omit this option. The user can navigate back to Plan walkthrough from the Design walkthrough.

**on "Skip to build":** Save state and proceed to Build stage immediately — identical to selecting "Continue to Build" from the main Plan gate.

**Walkthrough edits propagate automatically.** The orchestrator edits plan files on disk directly. The BUILD agent subprocess reads these same files, so changes are reflected without any extra step.

**on Continue:**
1. Save state to `.temper/build-state.json`:
   ```json
   {
     "stage": "plan_complete",
     "spec": "{feature-slug}",
     "spec_path": ".temper/specs/{feature-slug}",
     "original_args": "$ARGUMENTS",
     "next_stage": "build",
     "artifacts": ["intent.md", "tasks.md"],
     "branch": "feature/{feature-slug}",
     "updated": "{ISO timestamp}"
   }
   ```
2. **Create feature branch** (if git pack is enabled):
   - Run: `git branch --show-current`
   - If on main/master: `git checkout -b feature/{feature-slug}`
   - Store branch name in build-state.json
3. Proceed to Stage 2 (BUILD) — launches a new Agent subprocess

**on Change (via "Other" free-text input):**
1. User types their change request in the "Other" field
2. Edit the plan files directly (intent.md, tasks.md, etc.)
3. Re-show the updated plan summary
4. **Re-show the AskUserQuestion gate** — do NOT skip to build

**on Save:**
1. Save state to `.temper/build-state.json`
2. Report: "Saved. Run /temper when ready to continue."

---

## Stage 1.5: Design (Optional — for complex/medium features)

**Runs in:** Agent subprocess with clean context — loads intent.md + plan.md

**When active:** `phases.design: true` in temper.config AND complexity is `medium` or `complex`.
**When skipped:** Automatically skipped for `simple` or `trivial` complexity, or when `phases.design: false`.

### Design Gate Decision

After Plan stage completes, check:
1. Read `.claude/temper.config` → `phases.design`
2. If `false`: skip to Stage 2 (BUILD) directly
3. If `true`: check the plan's complexity level
4. If complexity is `simple` or `trivial`: skip to Stage 2 (BUILD) directly
5. If complexity is `medium` or `complex`: launch Design agent

### Launch Design Agent

Before launching, read `.temper/build-state.json` to get the `spec_path` and `spec` values.

```
Use the Agent tool with this prompt:

"Execute /temper:design for feature: {spec from build-state.json}

Full methodology: Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/design.md

CONTEXT: You are starting with a CLEAN context. Load these files first:
1. {spec_path}/intent.md
2. {spec_path}/plan.md
3. Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/design.md for methodology

Then produce the system design as described in the methodology.

CRITICAL: Do NOT show an AskUserQuestion gate at the end. Return the design summary to the orchestrator.

Return ONLY:
- Design summary text (formatted box)
- Path to design.md artifact
- Key architectural decisions"
```

### Stage Gate

Show the AskUserQuestion gate with:
- "Continue to Build (Recommended)" — launch BUILD agent
- "Walk through design step by step" — interactive walkthrough (see below)
- "Save for later" — save state, stop
- **"Other" (built-in free-text)** — type a change request, edits are made, gate re-appears

#### Step-by-Step Walkthrough

When the user selects "Walk through design step by step", present the design as an interactive, section-by-section flow. Read the design files from `.temper/specs/{feature-slug}/` to provide detailed content for each section.

**Walkthrough sections (dynamic — only show sections present in design.md):**

Read `.temper/specs/{feature-slug}/design.md` and detect which sections exist. Present only sections that have content. The available sections:

1. **Architecture Overview** — System components, data flow diagram, what's new vs modified vs existing (always shown)
2. **API Contracts** — Request/response shapes, endpoint changes, backward compatibility notes (shown if design.md has API contract content)
3. **Database Changes** — Schema changes, migration strategy, impact on existing data (shown if design.md has database content)
4. **Integration Points** — External system connections, error handling strategy, retry/fallback logic (shown if design.md has integration content)
5. **Decision Log** — Each architectural decision with rationale and alternatives considered (always shown)

**After each section, use AskUserQuestion:**

```
AskUserQuestion:
  question: "Design walkthrough — {current section name}. What would you like to do?"
  options:
    - label: "Next step"
      description: "Continue to {next section name}."
    - label: "Skip to build"
      description: "Skip remaining sections, proceed to Build stage."
    - label: "Switch to plan walkthrough"
      description: "Jump to the Plan walkthrough."
  multiSelect: false
```

- **"Other"** (built-in free-text): Ask a question or request a change. Answer/edit, then re-show the same section's gate.
- **"Next step"**: Advance to next section. After the last section, show the final walkthrough gate (see below)
- **"Skip to build"**: Exit walkthrough immediately, save state, proceed to Build stage (same as "Continue to Build" from the main gate)
- **"Switch to plan walkthrough"**: Begin the Plan walkthrough from section 1. The user can navigate back from Plan walkthrough.

After the last section, show the final walkthrough gate:

```
AskUserQuestion:
  question: "Design walkthrough complete. What next?"
  options:
    - label: "Continue to Build (Recommended)"
      description: "Launch BUILD agent with clean context."
    - label: "Switch to plan walkthrough"
      description: "Jump to the Plan walkthrough for cross-reference."
    - label: "Save for later"
      description: "Save state and stop."
  multiSelect: false
```

**"Other" (free-text change request)**: Edit design files, show what changed, re-show this gate.

**on "Switch to plan walkthrough"** (from either per-section or final gate): Begin the Plan walkthrough (Stage 1 walkthrough steps), starting from section 1. The user can navigate back to Design walkthrough from the Plan walkthrough.

**on "Skip to build":** Save state and proceed to Build stage immediately — identical to selecting "Continue to Build" from the main Design gate.

**Walkthrough edits propagate automatically.** The orchestrator edits design files on disk directly. The BUILD agent subprocess reads these same files, so changes are reflected without any extra step.

**on Continue:**
1. Save state to `.temper/build-state.json` with `"stage": "design_complete"`
2. Proceed to Stage 2 (BUILD) — launches a new Agent subprocess

**on Change (via "Other" free-text input):**
1. User types their change request in the "Other" field
2. Edit the design files directly (design.md, etc.)
3. Re-show the updated design summary
4. **Re-show the AskUserQuestion gate** — do NOT skip to build

**on Save:**
1. Save state to `.temper/build-state.json`
2. Report: "Saved. Run /temper when ready to continue."

---

## Feedback Loops (v4.0.0)

> **Reference:** `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/orchestrator-patterns.md` → "Feedback Loop Patterns"

When `feedback.enabled: true` in temper.config, stages can loop back to upstream stages:

| Loop | Trigger | Max Iterations | Circuit Breaker |
|------|---------|---------------|-----------------|
| Review → Build | Auto-fixable issues found | 2 | Same issue twice = stop |
| Check → Build | Test failures in new code | 2 | Same test twice = stop |
| Build → Plan | Infeasible design discovered | 1 | Human-driven only |

### How Feedback Loops Actually Work (Runtime Instructions)

This is NOT pseudo-code. These are instructions Claude Code follows at runtime when orchestrating the `/temper` pipeline. Every step below uses real tools (Read, Write, Edit, AskUserQuestion, Agent).

#### Step 1: Check if feedback loops are enabled

After Review or Check agent returns, BEFORE showing the gate:
1. Read `.claude/temper.config` using the Read tool
2. Check if `feedback.enabled: true` — if false, skip to standard gate (no loop options)
3. Read `.temper/feedback-loops.json` using the Read tool — if file doesn't exist, create it with: `{"version":1,"active_loops":[],"history":[]}`

#### Step 2: Determine if loop should be offered

For **Review** stage: loop is possible if review found issues (critical + high > 0)
For **Check** stage: loop is possible if check found test failures (test_failures.length > 0)

If loop is possible, check eligibility by reading `.temper/feedback-loops.json`:
1. Find active loop with matching `from_stage` (review or check) in `active_loops` array
2. If no active loop exists → `can_loop: true`, `iteration: 0`
3. If active loop exists and `iteration < max_iterations` (from config, default 2) → `can_loop: true`, `iteration: current`
4. If active loop exists and `iteration >= max_iterations` → `can_loop: false`, reason: "Max iterations reached"
5. Check same-issue circuit breaker: compare current issues with `failure_context.issues` from previous loop. If same issue (same file:line + same description) appears → `can_loop: false`, reason: "Same issue found 2x consecutively — manual fix required"

#### Step 3: Show gate with or without loop option

If `can_loop: true`: show gate with "Loop back to Build" option included
If `can_loop: false`: show standard gate options only, and display the reason to the user

#### Step 4: On user selects "Loop back to Build"

Using the Write tool:
1. Write context file to spec directory:
   - Review loop: Write `{spec_path}/review-context.json` with the review findings schema
   - Check loop: Write `{spec_path}/check-context.json` with the test failures schema
2. Update `.temper/feedback-loops.json` using the Write tool:
   - If no active loop: append new entry to `active_loops` with `iteration: 1`
   - If active loop exists: increment `iteration` count, update `failure_context`
3. Save state to `.temper/build-state.json` with `next_stage: "build"`
4. Launch BUILD Agent subprocess — it loads the context file automatically (already in Build agent prompt at lines 484-485)

#### Step 5: On successful commit (after Check passes)

Using Bash tool:
1. `rm -f {spec_path}/review-context.json {spec_path}/check-context.json`
2. Read `.temper/feedback-loops.json`, move all `active_loops` to `history`, clear `active_loops`
3. Write updated feedback-loops.json
4. `rm -f .temper/build-state.json`

### Observability Tracking (v4.0.0)

When `observability.enabled: true` in temper.config, track per-stage metrics:

1. Before launching each Agent subprocess: record start timestamp
2. After each stage completes: record elapsed time, estimate tokens, count tool calls
3. Write metrics to `.temper/observability.json` after each stage
4. Show in `/temper:status` dashboard

---

## Stage 2: Building

**Runs in:** Agent subprocess with clean context — only tasks.md + intent.md loaded

### Launch Build Agent

Before launching, read `.temper/build-state.json` to get the `spec_path` and `spec` values.

```
Use the Agent tool with this prompt:

"Execute /temper:build for spec: {spec from build-state.json}

Full methodology: Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/build.md

CONTEXT: You are starting with a CLEAN context. Load these files first:
1. {spec_path}/tasks.md
2. {spec_path}/intent.md (if exists)
3. Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/build.md for methodology
4. Read {spec_path}/review-context.json (if exists — feedback from review loop)
5. Read {spec_path}/check-context.json (if exists — feedback from check loop)

Then execute all tasks in tasks.md using TDD discipline.

CRITICAL: Do NOT show an AskUserQuestion gate at the end. Return the build summary to the orchestrator.

Return ONLY:
- Build summary text (formatted box)
- List of files changed
- Test results (pass/fail counts)
- Any blockers or failures"
```

### Build Summary Format

```
┌─────────────────────────────────────────────────────────────┐
│ BUILD — {Feature Name}                                      │
├─────────────────────────────────────────────────────────────┤
│ WHAT WAS BUILT                                              │
│    Tasks: {N}/{N} completed                                 │
│    Tests: {N} added, all passing                            │
│    Files: {N} created, {N} modified                         │
│                                                             │
│ QUALITY                                                     │
│    Coverage: {X}% (threshold: {Y}%)                         │
│    All tests: PASS                                          │
│                                                             │
│ KEY CHANGES                                                 │
│    + {file} — {one-line description}                        │
│    ~ {file} — {one-line description}                        │
└─────────────────────────────────────────────────────────────┘
```

### Stage Gate

> **Feedback Loop Check:** Before showing gate, check if Build → Plan loop should be offered:
> 1. Use Read tool to check `.claude/temper.config` → verify `feedback.enabled: true`
> 2. Use Read tool to check `.temper/feedback-loops.json` for active loops with `from_stage: "build"`
> 3. If active loop exists and `iteration >= 1` → `can_loop: false` (human-driven, max 1 loop per cycle)
> 4. Otherwise → `can_loop: true`

Show the AskUserQuestion gate with:
- "Continue to Review (Recommended)" — launch REVIEW agent
- "Loop back to Plan (Revise plan)" — (shown ONLY if feedback.enabled AND can_loop) write build-context.json, update feedback-loops.json, launch PLAN agent
- "Save for later" — save state, stop
- **"Other" (built-in free-text)** — type a change request, edits are made, gate re-appears

**on Continue:**
1. Save state to `.temper/build-state.json`
2. Proceed to Stage 3 (REVIEW) — launches a new Agent subprocess

**on Loop back to Plan:**
1. Write `build-context.json` to spec directory with:
   ```json
   {
     "version": 1,
     "stage": "build",
     "timestamp": "{ISO timestamp}",
     "build_summary": {
       "tasks_completed": {N},
       "tasks_total": {N},
       "tests_added": {N},
       "files_changed": {N}
     },
     "failure_reason": "{why the plan needs revision — e.g. infeasible design, missing dependencies, architecture mismatch}",
     "blockers": ["{description of what couldn't be built}"],
     "partial_results": {
       "completed_files": ["{files that were successfully built}"],
       "failed_tasks": ["{tasks that couldn't be completed with current plan}"]
     }
   }
   ```
2. Create loop entry in `.temper/feedback-loops.json`:
   ```json
   {
     "id": "loop-build-{timestamp}",
     "from_stage": "build",
     "to_stage": "plan",
     "reason": "infeasible design discovered",
     "iteration": 1,
     "max_iterations": 1,
     "failure_context": {
       "blockers": ["{blocker descriptions}"]
     },
     "started": "{ISO timestamp}"
   }
   ```
3. Save state to `.temper/build-state.json` with `next_stage: "plan"`
4. Launch PLAN Agent subprocess with:
   ```
   "Execute /temper:plan for feature: {original_args from build-state.json}

   Full methodology: Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/plan.md

   CONTEXT: You are starting with a CLEAN context. Load these files first:
   1. {spec_path}/intent.md (original intent — may need revision)
   2. {spec_path}/build-context.json (contains what went wrong during build)
   3. Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/plan.md for methodology

   CRITICAL: This is a feedback loop re-entry from Build. The build-context.json describes what couldn't be built and why. Revise the plan to address these blockers.

   Return ONLY:
   - Plan summary text (formatted box + ASCII art diagram)
   - Path to spec: .temper/specs/{feature-slug}/
   - Complexity level: trivial/simple/medium/complex
   - Risk level: low/medium/high"
   ```

**on Change (via "Other" free-text input):**
1. User types their change request in the "Other" field
2. Make the change
3. Re-show the updated build summary
4. **Re-show the AskUserQuestion gate** — do NOT skip to review

**on Save:**
1. Save state to `.temper/build-state.json`:
   ```json
   {
     "stage": "build_complete",
     "spec": "{feature-slug}",
     "spec_path": ".temper/specs/{feature-slug}",
     "original_args": "{from prior state}",
     "next_stage": "review",
     "artifacts": ["intent.md", "tasks.md"],
     "updated": "{ISO timestamp}"
   }
   ```
2. Report: "Saved. Run /temper when ready to continue."

---

## Stage 3: Reviewing

**Runs in:** Agent subprocess with clean context — only changed files loaded

### Launch Review Agent

Before launching, read `.temper/build-state.json` to get the `spec_path` and `spec` values.

```
Use the Agent tool with this prompt:

"Execute /temper:review for feature: {spec from build-state.json}

Full methodology: Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/review.md

CONTEXT: You are starting with a CLEAN context. Load these first:
1. Run: git diff --name-only (to get changed files)
2. Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/review.md for methodology
3. Read {spec_path}/intent.md (for intent validation)
4. Read {spec_path}/build-context.json (if exists — build deviations and test results)

Then review all changed files using parallel subagents as described in the methodology.

CRITICAL: Do NOT show an AskUserQuestion gate at the end. Return the review summary to the orchestrator.

Return ONLY:
- Review summary text (formatted box)
- Issues found (by severity)
- Auto-fixable issues list
- Intent validation results"
```

### Review Summary Format

```
┌─────────────────────────────────────────────────────────────┐
│ REVIEW — {Feature Name}                                     │
├─────────────────────────────────────────────────────────────┤
│ DIFF FINGERPRINT                                            │
│    Files: {N} changed ({A} additions, {M} modifications)    │
│    Hunks: {N} ({L} logic, {S} structure, {T} test)          │
│    Security: {N} CRITICAL, {N} HIGH                         │
│                                                             │
│ ISSUES FOUND                                                │
│    Critical: {N} | High: {N} | Medium: {N} | Low: {N}      │
│    Auto-fixable: {N}                                        │
│                                                             │
│ SECURITY HOT PATHS                                          │
│    ⚠️  {File}.{function} — CRITICAL                        │
│       Reachable from {entry_point} ({exposure})             │
│    ✅ {File}.{function} — tests cover boundaries             │
│                                                             │
│ CROSS-FILE CONSISTENCY                                      │
│    ⚠️  {file} uses {new_pattern}, others use {old_pattern} │
│    ✅ All patterns consistent                               │
│                                                             │
│ PERFORMANCE PATTERNS                                        │
│    [HIGH] N+1 query — {file}:{line}                        │
│    [MEDIUM] Missing pagination — {endpoint}                │
│                                                             │
│ CONTRACT CHANGES (if API files changed)                     │
│    ❌ BREAKING: {endpoint} — {description}                  │
│    ✅ ADDITIVE: {endpoint} — backward compatible            │
│                                                             │
│ SCENARIO COVERAGE (from intent.md)                          │
│    Covered: {X}/{Y} ({Z} automated, {W} manual)             │
│    (X = STRONG + ½ WEAK per Step 3a labels)                │
│    ❌ {uncovered scenario name}                              │
│                                                             │
│ TOP ISSUES                                                  │
│    1. [{severity}] {file}:{line} — {one-line description}  │
│    2. [{severity}] {file}:{line} — {one-line description} │
│                                                             │
│ INTENT VERDICT (if intent.md exists)                        │
│    Problem: {one-line problem statement}                    │
│    Verdict: ✅ Intent satisfied / ⚠️ Partial / ❌ Not met    │
│    Evidence: {X}/{Y} scenarios substantively validated      │
│      (Y = total scenarios in intent.md, X = STRONG + ½ WEAK) │
│    Mutation spot-check: {N} PROVEN, {N} UNVERIFIED          │
│    Gaps:                                                    │
│      [assertion] {trivial/incomplete assertion gaps}        │
│      [mutation] {tests that didn't catch real mutations}    │
│      [drift] {implementation vs problem drift}              │
│      [coverage] {uncovered decision points}                 │
└─────────────────────────────────────────────────────────────┘
```

### Stage Gate

> **Feedback Loop Check:** Before showing gate, follow "How Feedback Loops Actually Work" section (Step 1-2):
> 1. Use Read tool to check `.claude/temper.config` → verify `feedback.enabled: true`
> 2. Use Read tool to check `.temper/feedback-loops.json` for active loops
> 3. If feedback enabled AND review found issues (critical + high > 0) AND eligible per Step 2: show loop option

Show the AskUserQuestion gate with:
- "Fix all & continue to Check (Recommended)" — apply fixes for ALL issues (including low), launch CHECK agent
- "Loop back to Build (Fix issues)" — (shown ONLY if feedback.enabled AND can_loop) write review-context.json, update feedback-loops.json, launch BUILD agent
- "Save for later" — skip fixes, save state
- **"Other" (built-in free-text)** — type a change request, edits are made, gate re-appears

**on Continue:**
1. Apply ALL fixable issues (including low severity) directly — no subprocess needed for fixes
2. If fixes were applied: re-run a single review pass on the fixed files
   - If new issues found: show updated summary, ask user again (max 1 more loop)
   - If clean: proceed to step 3
3. Save state to `.temper/build-state.json`
4. Proceed to Stage 4 (CHECK) — launches a new Agent subprocess

**on Loop back to Build:**
1. Write `review-context.json` to spec directory with:
   ```json
   {
     "version": 1,
     "stage": "review",
     "timestamp": "{ISO timestamp}",
     "findings_summary": {
       "critical": {N},
       "high": {N},
       "medium": {N},
       "low": {N},
       "auto_fixed": {N}
     },
     "intent_verdict": "satisfied|partial|not_met",
     "security_hot_paths": [],
     "contract_changes": [],
     "scenario_coverage": {
       "total": {N},
       "strong": {N},
       "weak": {N},
       "trivial": {N},
       "uncovered": {N}
     }
   }
   ```
2. Create or update loop entry in `.temper/feedback-loops.json`:
   ```json
   {
     "id": "loop-review-{timestamp}",
     "from_stage": "review",
     "to_stage": "build",
     "reason": "auto-fixable issues found",
     "iteration": {current_iteration + 1},
     "max_iterations": 2,
     "failure_context": {
       "issues": ["file:line — description"],
       "auto_fixable_count": {N}
     },
     "started": "{ISO timestamp}"
   }
   ```
3. Launch BUILD agent subprocess with:
   ```
   "Execute /temper:build for spec: {spec}

   Full methodology: Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/build.md

   CONTEXT: You are starting with a CLEAN context. Load these files first:
   1. {spec_path}/tasks.md
   2. {spec_path}/intent.md (if exists)
   3. {spec_path}/review-context.json (contains issues to fix)
   4. {spec_path}/check-context.json (if exists — previous check failures)

   CRITICAL: This is a feedback loop re-entry. The review-context.json contains issues that must be fixed.

   Return ONLY:
   - Build summary text (formatted box)
   - List of files changed
   - Test results (pass/fail counts)
   - Any blockers or failures"
   ```

**on Change (via "Other" free-text input):**
1. User types their change request in the "Other" field
2. Make the change
3. Re-launch the REVIEW agent to get an updated review summary
4. Show the updated review summary
5. **Re-show the AskUserQuestion gate** — do NOT skip to check

**on Save:**
1. Save state to `.temper/build-state.json`:
   ```json
   {
     "stage": "review_complete",
     "spec": "{feature-slug}",
     "spec_path": ".temper/specs/{feature-slug}",
     "original_args": "{from prior state}",
     "next_stage": "check",
     "artifacts": ["intent.md", "tasks.md"],
     "updated": "{ISO timestamp}"
   }
   ```
2. Report: "Saved. Run /temper when ready to continue."

---

## Stage 4: Checking

**Runs in:** Agent subprocess with clean context — only check.md + intent.md loaded

### Launch Check Agent

```
Use the Agent tool with this prompt:

"Execute /temper:check for project validation.

Full methodology: Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/check.md

CONTEXT: You are starting with a CLEAN context. Load these first:
1. Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/check.md for methodology
2. Read {spec_path}/intent.md (for scenario coverage validation, if exists)
3. Read {spec_path}/review-context.json (if exists — review findings for context)
4. Detect stack and run the full validation pipeline

CRITICAL: Do NOT show an AskUserQuestion gate at the end. Return the check summary to the orchestrator.

Return ONLY:
- Check summary text (formatted box)
- Per-level results (pass/fail/skip)
- Scenario coverage results (if intent.md exists)
- Any failures with suggested fixes"
```

### Check Summary Format

```
┌─────────────────────────────────────────────────────────────┐
│ CHECK — {Project Name}                                      │
├─────────────────────────────────────────────────────────────┤
│ WHAT WAS VALIDATED                                          │
│    Compile:    {status} {time}                               │
│    Tests:      {status} {time} — {N} passed                  │
│    Coverage:   {status} {X}% (threshold: {Y}%)               │
│    Scenarios:  {status} {X}/{Y} covered (if intent.md)       │
│    Test Gaps:  {status} {X}% ({N}/{N} functions analyzed)      │
│    API Diff:   {status} {N} changes ({N} consumers checked)    │
│    Perf:       {status} {N} regressions (if benchmarks)      │
│    Lint:       {status} {time}                               │
│    Security:   {status} {time}                               │
│                                                             │
│ Skipped: Integration (no tool configured)                   │
│ Total: {time}                                               │
└─────────────────────────────────────────────────────────────┘
```

### Stage Gate

> **Feedback Loop Check:** Before showing gate, follow "How Feedback Loops Actually Work" section (Step 1-2):
> 1. Use Read tool to check `.claude/temper.config` → verify `feedback.enabled: true`
> 2. Use Read tool to check `.temper/feedback-loops.json` for active loops
> 3. If feedback enabled AND check found test failures (test_failures.length > 0) AND eligible per Step 2: show loop option

Show the AskUserQuestion gate with:
- "Commit (Recommended)" — commit with conventional message
- "Loop back to Build (Fix tests)" — (shown ONLY if feedback.enabled AND can_loop) write check-context.json, update feedback-loops.json, launch BUILD agent
- "Save for later" — keep changes uncommitted
- **"Other" (built-in free-text)** — type a change request, edits are made, re-run check

**on Commit:**
```
1. Delete .temper/build-state.json (cleanup)
2. Delete context files from spec directory:
   - rm {spec_path}/review-context.json (if exists)
   - rm {spec_path}/check-context.json (if exists)
3. Reset feedback-loops.json:
   - Move all active_loops to history
   - Clear active_loops array
   - Keep last 10 loops in history (remove older)
4. Mark spec as completed in intent.md
5. Commit with conventional message:
   {type}({scope}): {description}

   {Closes #{issue}}
   - {X} files changed, {Y} tests added

   Co-Authored-By: Claude <noreply@anthropic.com>

6. Report:
   "Committed: {hash}
    Branch: {branch}
    Ready to push?"
```

**on Loop back to Build:**
1. Write `check-context.json` to spec directory with:
   ```json
   {
     "version": 1,
     "stage": "check",
     "timestamp": "{ISO timestamp}",
     "validation_results": {
       "compile": "pass|fail|skip",
       "tests": "pass|fail|skip",
       "coverage_pct": {N},
       "lint": "pass|fail|skip",
       "security": "pass|fail|skip"
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
         "scenario": "string"
       }
     ]
   }
   ```
2. Create or update loop entry in `.temper/feedback-loops.json`:
   ```json
   {
     "id": "loop-check-{timestamp}",
     "from_stage": "check",
     "to_stage": "build",
     "reason": "test failures found",
     "iteration": {current_iteration + 1},
     "max_iterations": 2,
     "failure_context": {
       "test_failures": ["test_name — error_message"],
       "failed_test_count": {N}
     },
     "started": "{ISO timestamp}"
   }
   ```
3. Launch BUILD agent subprocess with:
   ```
   "Execute /temper:build for spec: {spec}
   
   Full methodology: Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/build.md
   
   CONTEXT: You are starting with a CLEAN context. Load these files first:
   1. {spec_path}/tasks.md
   2. {spec_path}/intent.md (if exists)
   3. {spec_path}/check-context.json (contains test failures to fix)
   
   CRITICAL: This is a feedback loop re-entry. The check-context.json contains test failures that must be fixed.
   
   Return ONLY:
   - Build summary text (formatted box)
   - List of files changed
   - Test results (pass/fail counts)
   - Any blockers or failures"
   ```

**on Change (via "Other" free-text input):**
1. User types their change request in the "Other" field
2. Make the change
3. Re-launch the CHECK agent to re-validate
4. **Re-show the AskUserQuestion gate** — do NOT commit directly

**on Save:**
1. Save state to `.temper/build-state.json`:
   ```json
   {
     "stage": "check_complete",
     "spec": "{feature-slug}",
     "spec_path": ".temper/specs/{feature-slug}",
     "original_args": "{from prior state}",
     "next_stage": "commit",
     "artifacts": ["intent.md", "tasks.md"],
     "updated": "{ISO timestamp}"
   }
   ```
2. Report: "Saved. Run /temper when ready to continue."

---

## Resume: `/temper` (no arguments)

If you stopped earlier, run `/temper` to continue.

### Resume Validation

> Follow the shared pattern in `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/orchestrator-patterns.md` → "Resume Validation" section. Valid stages for this command: `plan_complete`, `design_complete`, `build_complete`, `review_complete`, `check_complete`.

### Nested Invocation Protection

If `/temper "new feature"` is called while `.temper/build-state.json` already exists for a different feature:

> Follow the shared pattern in `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/orchestrator-patterns.md` → "Nested Invocation Protection" section. Use "feature" in the display.

If `/temper` (no arguments) is called and `.temper/build-state.json` exists for the same feature:
```
AskUserQuestion:
  question: "Resume from where you left off?"
  options:
    - label: "Continue from {next_stage} (Recommended)"
      description: "Resume from checkpoint, launch {next_stage} agent."
    - label: "Start over (replan)"
      description: "Go back to PLAN, launch planning agent."
  multiSelect: false
```

---

## Context Efficiency

| Stage Transition | Method | Context Loaded | Size |
|-----------------|--------|----------------|------|
| PLAN → DESIGN | New Agent subprocess | intent.md + plan.md | ~5-10KB |
| PLAN → BUILD | New Agent subprocess | tasks.md + intent.md | ~5-10KB |
| DESIGN → BUILD | New Agent subprocess | tasks.md + intent.md + design.md | ~10-15KB |
| BUILD → REVIEW | New Agent subprocess | changed files (git diff) + build-context.json | ~20-50KB |
| REVIEW → CHECK | New Agent subprocess | check.md + intent.md + review-context.json | ~5-10KB |
| REVIEW → BUILD (feedback) | New Agent subprocess | tasks.md + review-context.json | ~10-15KB |
| CHECK → BUILD (feedback) | New Agent subprocess | tasks.md + check-context.json | ~10-15KB |
| BUILD → PLAN (feedback) | New Agent subprocess | intent.md + build-context.json | ~10-15KB |
| CHECK → Commit | Direct (no subprocess) | Nothing | 0KB |

Each subprocess starts genuinely clean. Context files accumulate in `.temper/specs/{feature}/` and are cleaned up on commit.

---

## Individual Commands Still Work

```
/temper:plan    → Just planning, stops at gate
/temper:design  → Just design (for complex features), stops at gate
/temper:build   → Just building, stops at gate
/temper:review  → Just review, stops at gate
/temper:check   → Just check, stops at gate
```

Use these when you want granular control. These do NOT use Agent subprocesses — they run directly in the current context.
