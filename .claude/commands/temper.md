---
description: "Unified SDLC command: plan → build → review → check with stage gates"
argument-hint: "<feature-description>"
---

# Temper: Unified SDLC Command

**Goal:** Execute the full SDLC flow (plan → build → review → check → commit) with stage gates and **real** context isolation via Agent subprocesses.

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
  │     ↓ returns: plan summary + spec path
  │     ↓ gate decision from user
  │
  ├── Agent subprocess → BUILD (loads tasks.md + intent.md only)
  │     ↓ returns: build summary + files changed
  │     ↓ gate decision from user
  │
  ├── Agent subprocess → REVIEW (loads changed files only)
  │     ↓ returns: review summary + issues
  │     ↓ gate decision from user
  │
  └── Agent subprocess → CHECK (runs validation pipeline)
        ↓ returns: check results
        ↓ gate decision from user → commit
```

**Why Agent subprocesses?** A self-directed prompt like "CLEAR ALL CONTEXT" is unenforceable — Claude cannot clear its own context window. Agent subprocesses start with genuinely clean context because they are separate invocations.

### State Management

The orchestrator tracks progress via `.temper/build-state.json`. **Resolve the spec path from this file before launching any agent.**

```json
{
  "stage": "plan_complete|build_complete|review_complete|check_complete",
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
  question: "What would you like to do?"
  options:
    - label: "Next step"
      description: "Continue to {next section name}."
    - label: "Ask a question"
      description: "Type your question about this section."
  multiSelect: false
```

- **"Ask a question"** (or "Other" with question text): Answer, then re-show the same section's gate
- **"Other" (change request)**: Edit plan files, show what changed, then re-show the same section's gate
- **"Next step"**: Advance to next section. After the last section, show the final walkthrough gate:

```
AskUserQuestion:
  question: "Walkthrough complete. What next?"
  options:
    - label: "Continue to Build (Recommended)"
      description: "Launch BUILD agent with clean context."
    - label: "Save for later"
      description: "Save state and stop."
  multiSelect: false
```

**"Other" (free-text change request)**: Edit plan files, show what changed, re-show this gate.

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

Show the AskUserQuestion gate with:
- "Continue to Review (Recommended)" — launch REVIEW agent
- "Save for later" — save state, stop
- **"Other" (built-in free-text)** — type a change request, edits are made, gate re-appears

**on Continue:**
1. Save state to `.temper/build-state.json`
2. Proceed to Stage 3 (REVIEW) — launches a new Agent subprocess

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

Show the AskUserQuestion gate with:
- "Fix all & continue to Check (Recommended)" — apply fixes for ALL issues (including low), launch CHECK agent
- "Save for later" — skip fixes, save state
- **"Other" (built-in free-text)** — type a change request, edits are made, gate re-appears

**on Continue:**
1. Apply ALL fixable issues (including low severity) directly — no subprocess needed for fixes
2. If fixes were applied: re-run a single review pass on the fixed files
   - If new issues found: show updated summary, ask user again (max 1 more loop)
   - If clean: proceed to step 3
3. Save state to `.temper/build-state.json`
4. Proceed to Stage 4 (CHECK) — launches a new Agent subprocess

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
3. Detect stack and run the full validation pipeline

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

Show the AskUserQuestion gate with:
- "Commit (Recommended)" — commit with conventional message
- "Save for later" — keep changes uncommitted
- **"Other" (built-in free-text)** — type a change request, edits are made, re-run check

**on Commit:**
```
1. Delete .temper/build-state.json (cleanup)
2. Mark spec as completed in intent.md
3. Commit with conventional message:
   {type}({scope}): {description}

   {Closes #{issue}}
   - {X} files changed, {Y} tests added

   Co-Authored-By: Claude <noreply@anthropic.com>

4. Report:
   "Committed: {hash}
    Branch: {branch}
    Ready to push?"
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

> Follow the shared pattern in `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/orchestrator-patterns.md` → "Resume Validation" section. Valid stages for this command: `plan_complete`, `build_complete`, `review_complete`, `check_complete`.

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
| PLAN → BUILD | New Agent subprocess | tasks.md + intent.md | ~5-10KB |
| BUILD → REVIEW | New Agent subprocess | changed files (git diff) | ~20-50KB |
| REVIEW → CHECK | New Agent subprocess | check.md + intent.md | ~5KB |
| CHECK → Commit | Direct (no subprocess) | Nothing | 0KB |

Each subprocess starts genuinely clean. No theater.

---

## Individual Commands Still Work

```
/temper:plan    → Just planning, stops at gate
/temper:build   → Just building, stops at gate
/temper:review  → Just review, stops at gate
/temper:check   → Just check, stops at gate
```

Use these when you want granular control. These do NOT use Agent subprocesses — they run directly in the current context.
