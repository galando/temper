---
description: "Unified SDLC command: plan → design → build → review → check with stage gates, feedback loops, and observability"
argument-hint: "<feature-description>"
---

# Temper: Unified SDLC Command (v5.7.0)

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
> **Read that file once, now.** It holds the canonical definitions for: $CLAUDE_PLUGIN_ROOT resolution, single-read contract, build-state schema + save-state pattern, stage agent launch template, gate options, gate enforcement, resume validation, nested invocation protection, agent failure handling, context-file schemas, feedback-loop schemas, and context efficiency. Every `→ pattern` reference below points into that already-loaded file — do not re-read it.

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
        ↓ gate decision from user
        ↓ FEEDBACK: may loop back to BUILD (test failure loop)
  │
  └── [OPTIONAL] Agent subprocess → EVAL (if eval.enabled: true AND evalset.json exists)
        ↓ returns: score table + eval-context.json
        ↓ gate decision from user → commit
        ↓ FEEDBACK: may loop back to BUILD (block-on dimension failed)
```

**Why Agent subprocesses?** A self-directed prompt like "CLEAR ALL CONTEXT" is unenforceable — Claude cannot clear its own context window. Agent subprocesses start with genuinely clean context because they are separate invocations.

### State Management

State is tracked in `.temper/build-state.json` — schema and save-state rules in
orchestrator-patterns.md → "Build State Schema". For `/temper`: stages
`plan_complete | design_complete | build_complete | review_complete | check_complete | eval_complete`,
branch `feature/{slug}`, artifacts `intent.md` + `tasks.md`. **Resolve the spec path
from this file before launching any agent.** On resume, validate per
orchestrator-patterns.md → "Resume Validation".

### Agent Failure Handling

→ orchestrator-patterns.md → "Agent Failure Handling".

### Model Routing Resolution (v5.6.0)

Before launching ANY stage Agent, resolve the `model` param per the Model Routing
Resolution block in orchestrator-patterns.md. Summary (first-match-wins):

1. Read `.claude/temper.config` → `models` block.
2. If `models.enabled` is false OR the `models` block is absent:
   - **Emit NO `model` param on the Agent launch** — inherit the session model.
   - This is byte-identical to v5.5.0 behavior (GRACEFUL DEGRADATION CONTRACT).
3. Else if `models.respect-user-override: true` AND the user has explicitly set a model
   for this session/stage:
   - Keep the user's model; record `model_source: "user-override"` in observability.json.
4. Else: resolve `tier = models.routing.{stage}`, then map to the Agent `model` param by
   stripping the `tier-` prefix and looking up `models.tiers.{tier}`:
   - `tier-frontier` → `models.tiers.frontier` (shipped default: `opus`)
   - `tier-standard` → `models.tiers.standard` (shipped default: `sonnet`)
   - `tier-fast` → `models.tiers.fast` (shipped default: `haiku`)
   - Editing `models.tiers.{tier}` in temper.config changes what runs — routing honors it.
   - Emit `model: <mapped>` on the Agent launch; record `model_source: "routing"`.

Each of the 6 launch templates below carries a `[MODEL: …]` delta line. Fill it from this
resolution. The override-check (step 3) MUST precede the routing resolution (step 4).

**Review escalation (Deliverable 1.2):** the Review stage launches on its routed tier
(`tier-fast` by default). Findings tagged with any `models.escalate-on` value
(`architecture-finding`, `correctness-risk`) are re-judged on `tier-frontier`, reusing the
existing confidence-scoring path in `reference/review.md`. Record the escalation as a
`retries` bump or sub-stage entry in observability.json.

---

## Stage Gates Use AskUserQuestion

> **Gate patterns:** See `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/orchestrator-patterns.md` → "Gate Options Pattern" and "Gate Enforcement Rules" sections.

At each stage gate, use `AskUserQuestion` with selectable options. Do NOT use `[Enter]` as a prompt.

---

## Teach Me (Comprehension Companion) — shared handler (v5.7.0)

> **Capability:** `capabilities.teach-me` in temper.config (default: enabled).
> **Skill:** `$CLAUDE_PLUGIN_ROOT/.claude/skills/teach-me/SKILL.md`

Every stage gate below (Plan, Design, Build, Check, Eval) offers a **"Teach Me (Quiz me until I get it)"** option. Its purpose is to keep the human engaged with — and in genuine command of — every change Temper makes, phase by phase. It teaches the current phase, quizzes for mastery, and returns to the same gate. It NEVER advances or blocks the pipeline. (Review is intentionally excluded: its substance — the diff and its rationale — is already taught at Build, and its findings are usually minor or auto-fixed.)

**Shared `on Teach Me` handler** (each gate references this with its own `stage` + artifacts):

1. Read `.claude/temper.config` → verify `capabilities.teach-me` is not `false` (default: enabled). If `false`, this option is not shown.
2. Resolve `spec_path` from `.temper/build-state.json`.
3. Read (or create) the running checklist `{spec_path}/comprehension.md` (three pillars: Problem / Solution / Impact — schema in the teach-me skill). It **accumulates across phases** — never reset it; append and tick items off.
4. Load this stage's artifacts:
   - **Plan** → `intent.md`, `plan.md`, `tasks.md`
   - **Design** → `design.md`
   - **Build** → `git diff` + changed files + `tasks.md`
   - **Check** → the check results + scenario coverage
   - **Eval** → the eval score table + per-dimension justifications
5. Invoke the **teach-me** skill: probe (have the user restate first) → teach the gaps incrementally with real code → quiz via `AskUserQuestion` (vary the correct-answer position; never reveal the answer until the user submits) → confirm mastery before ticking each item. Honor `eli5`/`eli14`/`elii` depth requests.
6. On exit (all phase items mastered, or user selects "Done for now"): write the updated `comprehension.md`, show the Teach Me summary box.
7. **Re-show this same AskUserQuestion gate** — do NOT advance to the next stage.

---

## Stage 1: Planning

**Runs in:** Agent subprocess with full codebase access

### Launch Planning Agent

```
Use the Agent tool with this prompt:
[MODEL: models.routing.plan -> tier-frontier -> model: opus (or inherit session if models disabled; respect user-override)]

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
│ DECISIONS                                                   │
│    {N} load-bearing — {chosen} (not {rejected})            │
│    {chosen} (not {rejected})...                            │
│    (show up to 3 one-liners; append "+{N} more" if more;   │
│     literal "none" when no load-bearing decision exists)   │
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
- "Grill Me (Challenge the plan)" — (shown ONLY if capabilities.grill-me is not false) invoke grill-me skill with plan.md, Socratic Q&A loop that stress-tests assumptions, returns to this gate after
- "Teach Me (Quiz me until I get it)" — (shown ONLY if capabilities.teach-me is not false) invoke teach-me skill for the Plan phase (intent/plan/tasks), teach + quiz to mastery, returns to this gate after
- "Open HTML review" — (shown ONLY if capabilities.html-review is not false) generate and open interactive HTML plan review in browser (see HTML Review section below)
- "Save for later" — save state, stop
- **"Other" (built-in free-text)** — type a change request, edits are made, gate re-appears

**on Grill Me (Plan):**
1. Read `.claude/temper.config` → verify `capabilities.grill-me` is not `false` (default: enabled)
2. Read `.temper/specs/{feature-slug}/plan.md` and `.temper/specs/{feature-slug}/intent.md`
3. Enter Socratic one-question-at-a-time challenge loop (max 10 questions):
   - Extract claims, assumptions, dependencies, decisions from the plan
   - Generate challenge questions targeting unstated assumptions, missing error paths, alternatives, scalability
   - Present ONE question via AskUserQuestion, wait for response
   - If user selects "Update plan": edit plan files, continue grilling
   - If user selects "Done grilling": exit loop
4. Show grill summary (questions asked, weaknesses found, updates made)
5. If plan was updated: re-show the updated plan summary
6. **Re-show this AskUserQuestion gate** — do NOT skip to build

**on Teach Me (Plan):** → run the shared `on Teach Me` handler with `stage: plan` (artifacts: intent.md, plan.md, tasks.md). Then **re-show this AskUserQuestion gate** — do NOT skip to build.

**on Open HTML review:**
1. Read `.claude/temper.config` → verify `capabilities.html-review` is not `false` (default: enabled)
2. Generate HTML review file (see plan.md Phase 6.5):
   a. Read `templates/plan-review.html` from `$CLAUDE_PLUGIN_ROOT/templates/`
   b. Read `.temper/specs/{feature-slug}/plan.md` — split into sections
   c. Read `.temper/specs/{feature-slug}/tasks.md` — split into sections
   d. Build sections JSON array
   e. Replace template placeholders
   f. Write to `.temper/specs/{feature-slug}/review.html`
3. Open the file in the default browser: `open .temper/specs/{feature-slug}/review.html` (macOS) or `xdg-open` (Linux)
4. Show message: "HTML review opened in browser. Add comments and click 'Done Reviewing'. When finished, place the downloaded review-comments.json in .temper/specs/{feature-slug}/ and return here."
5. Wait for user to confirm they're done (via AskUserQuestion)
6. Check for `.temper/specs/{feature-slug}/review-comments.json`:
   - If exists: read and apply comments to plan artifacts (see below)
   - If not: "No comments file found. Continue without applying changes."
7. **Re-show this AskUserQuestion gate** — do NOT skip to build

**Applying HTML review comments:**
When review-comments.json exists:
1. Parse the JSON file
2. For each comment:
   - `task-change` → find matching section in tasks.md by `target` name, apply the change
   - `scenario-change` → find matching scenario in intent.md, apply the change
   - `plan-change` → find matching section in plan.md, apply the change
   - `general-note` → add to build-state.json as context note
3. Show what changed: "Applied {N} comments: {N} task changes, {N} plan changes, {N} notes"
4. Update plan summary if any plan artifacts were modified

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
1. Save state (orchestrator-patterns.md → "Save State Pattern", `stage: plan_complete`, `next_stage: build`).
2. **Create feature branch** (if git pack is enabled):
   - Run: `git branch --show-current`
   - If on main/master: `git checkout -b feature/{feature-slug}`
   - Store branch name in build-state.json
3. Proceed to Stage 2 (BUILD) — launches a new Agent subprocess

**on Change (via "Other"):** Edit the plan files (intent.md, tasks.md), re-show the updated plan summary, then re-show this gate. Enforcement: orchestrator-patterns.md → "Gate Enforcement Rules".

**on Save:** Save state (orchestrator-patterns.md → "Save State Pattern", `stage: plan_complete`).

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
[MODEL: models.routing.design -> tier-frontier -> model: opus (or inherit session if models disabled; respect user-override)]

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
- "Grill Me (Challenge the design)" — (shown ONLY if capabilities.grill-me is not false) invoke grill-me skill with design.md, Socratic Q&A loop targeting architectural decisions, returns to this gate after
- "Teach Me (Quiz me until I get it)" — (shown ONLY if capabilities.teach-me is not false) invoke teach-me skill for the Design phase (decisions, trade-offs, edge cases), teach + quiz to mastery, returns to this gate after
- "Save for later" — save state, stop
- **"Other" (built-in free-text)** — type a change request, edits are made, gate re-appears

**on Grill Me (Design):**
1. Read `.claude/temper.config` → verify `capabilities.grill-me` is not `false` (default: enabled)
2. Read `.temper/specs/{feature-slug}/design.md`
3. Enter Socratic one-question-at-a-time challenge loop targeting architectural decisions, trade-offs, alternatives (max 10 questions)
4. Show grill summary
5. If design was updated: re-show the updated design summary
6. **Re-show this AskUserQuestion gate** — do NOT skip to build

**on Teach Me (Design):** → run the shared `on Teach Me` handler with `stage: design` (artifact: design.md). Then **re-show this AskUserQuestion gate** — do NOT skip to build.

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

**on Change (via "Other"):** Edit the design files (design.md), re-show the updated design summary, then re-show this gate. Enforcement: orchestrator-patterns.md → "Gate Enforcement Rules".

**on Save:** Save state (orchestrator-patterns.md → "Save State Pattern", `stage: design_complete`).

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

### Observability Tracking (v5.6.0 — v2 capture)

When `observability.enabled: true` in temper.config, track per-stage metrics. The capture
schema is **version 2** (see orchestrator-patterns.md → "Observability.json v2 Schema").

1. Before launching each Agent subprocess: record `ts_start` (ISO8601, measured).
2. After each stage completes: record `ts_end`, then populate the per-stage entry:
   - `model_tier`: the tier resolved for this stage (tier-frontier/standard/fast), or the
     session tier if models disabled.
   - `model_source`: `routing` | `user-override` | `inherited` (per Model Routing Resolution).
   - `tokens`: `{input, input_source, output, output_source}` — prefer **measured** from
     harness-reported usage; fall back to **estimated** and flag the source. NEVER present
     an estimate as measured.
   - `latency_ms`: `{value, source}` — `ts_end - ts_start`, `source: "measured"`.
   - `tool_calls`: `{value, source}` — count of tool invocations, `source: "measured"`.
   - `cost_usd`: `{value, source}` — computed from `pricing.md[tier]` (see cost formula
     in orchestrator-patterns.md); `source: "pricing"` (derived, not billed).
   - `retries`: `{value, source}` — stage re-launches (feedback loops, escalations).
   - `eval_score`: `{value, source}` — pulled from `eval-context.json` for the eval stage;
     `null` otherwise.
3. Write `version: 2` to `.temper/observability.json` after each stage; accumulate stages[].
4. Recompute `totals` (tokens sum, cost_usd sum, latency_ms sum) on each write.
5. Show in `/temper:status` dashboard (economics panel — Deliverable 4).

**Source provenance (extends G-5, v5.3.0):** EVERY numeric value written to
`.temper/observability.json` MUST carry a sibling `source` field
(`measured` | `estimated` | `user-override` | `pricing`). The G-5 rule is preserved and
extended: do not emit a metric without a `source` field. The `/temper:status` dashboard
surfaces the source alongside the value (e.g. "tokens: 12.4k (estimated)", "cost: $0.04 (pricing)").

**Graceful degradation:** when `models.enabled` is false/absent, still capture v2 telemetry
but set `model_tier` to the inherited session tier and `model_source: "inherited"`. The
schema is v2 in both modes; only the routing provenance differs.

### Drift Detection (v5.6.0 — Deliverable 3)

After writing each stage's v2 entry to `.temper/observability.json`, extend
`.temper/metrics.json` with drift baselines and flags (additive — existing keys preserved).
Schema: orchestrator-patterns.md → "metrics.json Drift Baseline Schema".

1. Append the stage's `tool_calls`, `retries`, `latency_ms`, and `eval_score` (where
   available) to `metrics.json stage_baseline[stage][metric]` (rolling window, last K=10 runs).
2. Compute rolling mean and population stddev over the baseline history.
3. If `abs(value - mean) / stddev > drift-threshold` (from `temper.config models.drift-threshold`,
   default 2), append a `drift_flags[]` entry:
   ```
   { "stage": ..., "metric": ..., "value": ..., "baseline_mean": ..., "baseline_stddev": ...,
     "std_devs": ..., "threshold": ..., "severity": "SUGGEST", "direction": "high|low",
     "ts": "{ISO8601}", "source": "measured" }
   ```
4. Also flag a downward eval-score trend: if the last K eval_scores are monotonically
   decreasing, append a `drift_flags[]` entry at `severity: "SUGGEST"`.

**Drift flags NEVER auto-block a stage gate.** They are SUGGEST-level only (Temper gate
vocabulary) and surfaced in `/temper:status` for human review. Skip the stddev check when
the baseline has fewer than 3 samples (not enough signal).

---

## Stage 2: Building

**Runs in:** Agent subprocess with clean context — only tasks.md + intent.md loaded

### Launch Build Agent

Before launching, read `.temper/build-state.json` to get the `spec_path` and `spec` values.

```
Use the Agent tool with this prompt:
[MODEL: models.routing.build -> tier-standard -> model: sonnet (or inherit session if models disabled; respect user-override)]

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
- "Teach Me (Quiz me until I get it)" — (shown ONLY if capabilities.teach-me is not false) invoke teach-me skill for the Build phase (the diff, business logic, edge cases), teach + quiz to mastery, returns to this gate after
- "Loop back to Plan (Revise plan)" — (shown ONLY if feedback.enabled AND can_loop) write build-context.json, update feedback-loops.json, launch PLAN agent
- "Save for later" — save state, stop
- **"Other" (built-in free-text)** — type a change request, edits are made, gate re-appears

**on Continue:**
1. Save state to `.temper/build-state.json`
2. Proceed to Stage 3 (REVIEW) — launches a new Agent subprocess

**on Teach Me (Build):** → run the shared `on Teach Me` handler with `stage: build` (artifacts: git diff + changed files + tasks.md). Then **re-show this AskUserQuestion gate** — do NOT skip to review.

**on Loop back to Plan:**
1. Write `build-context.json` (schema: orchestrator-patterns.md → "Context File Schemas") with this stage's `failure_reason`, `blockers`, and `partial_results` (completed_files, failed_tasks).
2. Create a loop entry in `.temper/feedback-loops.json` (schema: orchestrator-patterns.md → "Feedback Registry") with `from_stage: build`, `to_stage: plan`, `reason: "infeasible design discovered"`, `iteration: 1`, `max_iterations: 1`.
3. Save state with `next_stage: "plan"`.
4. Re-launch the PLAN agent (Stage 1 "Launch Planning Agent" template) with `original_args` from build-state.json, adding to its CONTEXT list: `{spec_path}/build-context.json` (what went wrong) and the note: "Feedback re-entry from Build — revise the plan to address these blockers."

**on Change (via "Other"):** Make the change, re-show the updated build summary, then re-show this gate. Enforcement: orchestrator-patterns.md → "Gate Enforcement Rules".

**on Save:** Save state (orchestrator-patterns.md → "Save State Pattern", `stage: build_complete`, `next_stage: review`).

---

## Stage 3: Reviewing

**Runs in:** Agent subprocess with clean context — only changed files loaded

### Launch Review Agent

Before launching, read `.temper/build-state.json` to get the `spec_path` and `spec` values.

```
Use the Agent tool with this prompt:
[MODEL: models.routing.review -> tier-fast -> model: haiku (or inherit session if models disabled; respect user-override). Findings tagged architecture-finding/correctness-risk (models.escalate-on) are re-judged on tier-frontier (model: opus), reusing review.md confidence path.]

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
- "Architecture Depth Review" — (shown ONLY if capabilities.architecture-depth is not false) run module-depth analysis on changed files, add findings to review summary, return to gate
- "Loop back to Build (Fix issues)" — (shown ONLY if feedback.enabled AND can_loop) write review-context.json, update feedback-loops.json, launch BUILD agent
- "Save for later" — skip fixes, save state
- **"Other" (built-in free-text)** — type a change request, edits are made, gate re-appears

**on Architecture Depth Review:**
1. Read `.claude/temper.config` → verify `capabilities.architecture-depth` is not `false` (default: enabled)
2. Read `CONTEXT.md` (if exists) and `docs/adr/` (if exists) for domain context
3. Run the 5-dimension architecture depth analysis (seams, adapters, locality, leverage, deletion test) on changed files
4. Add findings with `[ARCH-DEPTH]` prefix to the review summary
5. Show updated review summary with architecture depth findings
6. **Re-show the AskUserQuestion gate** — do NOT skip to check

**on Continue:**
1. Apply ALL fixable issues (including low severity) directly — no subprocess needed for fixes
2. If fixes were applied: re-run a single review pass on the fixed files
   - If new issues found: show updated summary, ask user again (max 1 more loop)
   - If clean: proceed to step 3
3. Save state to `.temper/build-state.json`
4. Proceed to Stage 4 (CHECK) — launches a new Agent subprocess

**on Loop back to Build:**
1. Write `review-context.json` (schema: orchestrator-patterns.md → "Context File Schemas") with this review's `findings_summary`, `intent_verdict`, and `scenario_coverage`.
2. Create/update the loop entry in `.temper/feedback-loops.json` (schema: orchestrator-patterns.md → "Feedback Registry") with `from_stage: review`, `to_stage: build`, `reason: "auto-fixable issues found"`, `iteration: {current + 1}`, `max_iterations: 2`.
3. Re-launch the BUILD agent (Stage 2 "Launch Build Agent" template) — it already loads `review-context.json` from its CONTEXT list; this is a feedback re-entry, so the issues there must be fixed.

**on Change (via "Other"):** Make the change, re-launch the REVIEW agent for an updated summary, then re-show this gate. Enforcement: orchestrator-patterns.md → "Gate Enforcement Rules".

**on Save:** Save state (orchestrator-patterns.md → "Save State Pattern", `stage: review_complete`, `next_stage: check`).

---

## Stage 4: Checking

**Runs in:** Agent subprocess with clean context — only check.md + intent.md loaded

### Launch Check Agent

```
Use the Agent tool with this prompt:
[MODEL: models.routing.check -> tier-fast -> model: haiku (or inherit session if models disabled; respect user-override)]

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
- "Review config suggestions" — (shown ONLY if capabilities.config-suggestions is not false AND .temper/specs/{feature}/config-suggestions.json exists) show CLAUDE.md/AGENTS.md suggestions for accept/reject/defer
- "Teach Me (Quiz me until I get it)" — (shown ONLY if capabilities.teach-me is not false) invoke teach-me skill for the Check phase (validation results, scenario coverage, what's now guaranteed), teach + quiz to mastery, returns to this gate after
- "Loop back to Build (Fix tests)" — (shown ONLY if feedback.enabled AND can_loop) write check-context.json, update feedback-loops.json, launch BUILD agent
- "Save for later" — keep changes uncommitted
- **"Other" (built-in free-text)** — type a change request, edits are made, re-run check

**Config Suggestions Flow (before Commit gate):**
After Check agent returns and before showing the gate:
1. Read `.claude/temper.config` → verify `capabilities.config-suggestions` is not `false` (default: enabled)
2. If all validation passed: trigger config suggestions generation (see check.md Step 3.6)
3. If suggestions were generated: show them before the Commit gate

**on Review config suggestions:**
1. Read `.temper/specs/{feature}/config-suggestions.json`
2. Show each suggestion with:
   - Category and description
   - Suggested text to add to CLAUDE.md/AGENTS.md
   - Confidence score
3. For each suggestion, ask user: Accept / Reject / Defer
4. **Accepted:** Write the suggested text to CLAUDE.md or AGENTS.md (target from suggestion)
5. **Rejected:** Update learning.json suggestion_queue with status "rejected", increment dismissal count
6. **Deferred:** Keep in suggestion_queue with status "deferred"
7. After all suggestions reviewed: **Re-show this AskUserQuestion gate**

**on Teach Me (Check):** → run the shared `on Teach Me` handler with `stage: check` (artifacts: the check results, scenario coverage). This is the last chance to close any remaining `comprehension.md` items before commit — aim to leave the checklist fully ticked. Then **re-show this AskUserQuestion gate** — do NOT commit directly.

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
1. Write `check-context.json` (schema: orchestrator-patterns.md → "Context File Schemas") with this run's `validation_results`, `scenario_verification`, and `test_failures`.
2. Create/update the loop entry in `.temper/feedback-loops.json` (schema: orchestrator-patterns.md → "Feedback Registry") with `from_stage: check`, `to_stage: build`, `reason: "test failures found"`, `iteration: {current + 1}`, `max_iterations: 2`.
3. Re-launch the BUILD agent (Stage 2 "Launch Build Agent" template) — it already loads `check-context.json` from its CONTEXT list; this is a feedback re-entry, so the test failures there must be fixed.

**on Change (via "Other"):** Make the change, re-launch the CHECK agent to re-validate, then re-show this gate (do NOT commit directly). Enforcement: orchestrator-patterns.md → "Gate Enforcement Rules".

**on Save:** Save state (orchestrator-patterns.md → "Save State Pattern", `stage: check_complete`, `next_stage: eval`).

---

## Stage 4.5: Eval (Behavioral Verification)

**Runs in:** Agent subprocess with clean context — only eval.md + evalset.json + build-state.json + observability.json loaded

> **Graceful degradation (default-on):** This stage is skipped with a one-line notice — and no subprocess is spawned — when EITHER:
> 1. `.claude/temper.config` → `eval.enabled` is `false`, OR
> 2. No `evalset.json` exists at `{spec_path}/evals/evalset.json` (and none was authored at plan time).
>
> A skip is never an error. The pipeline proceeds to commit unchanged.

### Skip Check (before launching the agent)

1. Read `.claude/temper.config` → resolve `eval.enabled` (default: `true` if absent). If `false`: emit `Eval: disabled in config — skipping`, proceed to Commit.
2. Check `{spec_path}/evals/evalset.json` (and `{spec_path}/evalset.json`) exist. If neither: emit `Eval: no evalset found — skipping`, proceed to Commit.
3. Otherwise: launch the Eval agent below.

### Launch Eval Agent

```
Use the Agent tool with this prompt:
[MODEL: models.routing.eval -> tier-fast -> model: haiku (or inherit session if models disabled; respect user-override; the eval-judge skill already consumes eval.judge-model: tier-fast)]

"Execute /temper:eval for the current spec.

Full methodology: Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/eval.md

CONTEXT: You are starting with a CLEAN context. Load these first:
1. Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/eval.md for methodology
2. Read {spec_path}/evals/evalset.json (the rubric + cases)
3. Read {spec_path}/intent.md (intent, if exists)
4. Read .temper/build-state.json + .temper/observability.json (for trajectory mode)
5. Dispatch the eval-judge skill ($CLAUDE_PLUGIN_ROOT/.claude/skills/eval-judge/SKILL.md) on the
   configured judge-model tier; fall back to deterministic checks if unavailable.

CRITICAL: Do NOT show an AskUserQuestion gate at the end. Return the eval summary to the orchestrator.

Return ONLY:
- Eval summary text (score table per the Eval Summary Format below: legend, ARTIFACT/PROCESS
  grouping, per-row recommended action, partial-aggregate caveat when dims unscored)
- Per-dimension scores + categories + justifications + recommended actions
- Aggregate, aggregate_basis (scored|full), scored_weight
- Path to results file: {spec_path}/evals/results/results-{timestamp}.json
- Whether the eval passed/failed and which (if any) block-on dimension failed"
```

### Eval Summary Format

> **Render rules (see `reference/eval.md` → "Reading the Score Table"):** print the legend
> once above the table; group rows under ARTIFACT then PROCESS headers (never interleave);
> annotate every row below `pass_threshold` with its recommended action; when any dimension
> is unscored, print the partial-aggregate caveat in place of the plain Aggregate line.

```
How to read this: 0–1 scale, {pass_threshold} to pass. Low ARTIFACT-scores mean fix the code;
                   low PROCESS-scores mean the run was messy.

┌─────────────────────────────────────────────────────────────┐
│ EVAL — {Feature Name}                                       │
├─────────────────────────────────────────────────────────────┤
│ RESULTS (mode: {output|trajectory})   Judge: {model|fallback}│
│                                                             │
│ ARTIFACT — fix the code                                     │
│    task_success:     {score}   {PASS/FAIL}  {action?}       │
│    hallucination:    {score}   (invert)     {action?}       │
│    response_quality: {score|unscored}       {action?}       │
│                                                             │
│ PROCESS — fix the run                                       │
│    tool_use_quality: {score|unscored}       {action?}       │
│    trajectory:       {score|unscored}       {action?}       │
│                                                             │
│ {Aggregate line — see below}                                │
│ Results: evals/results/results-{ts}.json                    │
└─────────────────────────────────────────────────────────────┘
```

**`{action?}` placeholder (only on rows below `pass_threshold`):**
- artifact-category low → `→ Re-run (code defect)`
- any `block-on` dim low → `→ Re-run (block-on failed)`
- process-category low, NOT block-on → `→ accept (process noise)`
- `unscored` → `— unscored`
- rows at/above threshold → blank

**Aggregate line — choose one:**
- All dims scored: `Aggregate: {score}   Threshold: {pass_threshold}   {PASS}`
- Any dim unscored: `⚠ Aggregate {score} over {scored}/{total} scored dims ({names} unscored) — partial.   Threshold: {pass_threshold}   {PASS}`

### Stage Gate

Show the AskUserQuestion gate with:
- "Continue to Commit (Recommended)" — proceed to commit (Stage 4's on-Commit flow)
- "View results" — show `evals/results/results-{ts}.json`, then re-show this gate
- "Teach Me (Quiz me until I get it)" — (shown ONLY if capabilities.teach-me is not false) invoke teach-me skill for the Eval phase (score table, per-dimension justifications, what passed/failed and why), teach + quiz to mastery, returns to this gate after
- "Re-run (loop to Build)" — (shown ONLY if a `block-on` dimension failed AND `feedback.enabled`) write `eval-context.json`, launch BUILD agent (feedback re-entry)
- "Save for later" — save state, stop
- **"Other" (built-in free-text)** — type a change request, edits are made, re-run Eval, re-show gate

**on Teach Me (Eval):** → run the shared `on Teach Me` handler with `stage: eval` (artifacts: the eval score table, per-dimension justifications). Then **re-show this AskUserQuestion gate** — do NOT proceed to commit.

**on Continue to Commit:** Write `eval-context.json` (schema: orchestrator-patterns.md → "Context File Schemas") with aggregate + per-dimension scores + block-on status. Proceed to the Stage 4 "on Commit" flow.

**on Re-run (Eval→Build feedback):**
1. Write `eval-context.json` with the failing dimensions + the `block-on` reason.
2. Create/update the loop entry in `.temper/feedback-loops.json` with `from_stage: eval`, `to_stage: build`, `reason: "eval block-on dimension failed"`, `iteration: {current + 1}`, `max_iterations` from `feedback.max-loops`.
3. Re-launch the BUILD agent — it loads `eval-context.json` as a feedback re-entry.

**on Save:** Save state (orchestrator-patterns.md → "Save State Pattern", `stage: eval_complete`, `next_stage: commit`).

---

## Resume: `/temper` (no arguments)

If you stopped earlier, run `/temper` to continue.

### Resume Validation

> Follow the shared pattern in `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/orchestrator-patterns.md` → "Resume Validation" section. Valid stages for this command: `plan_complete`, `design_complete`, `build_complete`, `review_complete`, `check_complete`, `eval_complete`.

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
