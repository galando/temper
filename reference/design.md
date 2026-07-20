---
description: "System design exploration for complex features (optional stage)"
---

# Design: System Design Phase

**Goal:** Produce system design artifacts for complex/medium features. Skipped for simple/trivial features.

**When active:** `phases.design: true` in temper.config AND feature complexity >= medium.

## Execution

### Context Loading

This stage may run in two modes:
- **Standalone** (`/temper:design`) — runs in current context, handles its own gate
- **Agent subprocess** (from `/temper`) — starts with CLEAN context, only loads what's listed below

**Subprocess mode override:** When running as an Agent subprocess, do NOT show AskUserQuestion gates or clear context. Return the design summary to the orchestrator. The orchestrator handles all gate decisions and context transitions.

In both modes, the design methodology is identical.

**Context loading strategy:** Apply the context-engineering skill for hierarchical loading (rules -> arch -> source -> errors, under 2K lines/task). The file list below specifies WHAT to load; the skill specifies HOW and WHEN.

Files to load at start:
1. `.temper/specs/{feature}/intent.md`
2. `.temper/specs/{feature}/plan.md`
3. `$CLAUDE_PLUGIN_ROOT/reference/design.md` (this file)
4. Read active pack rules via the cached manifest, phase-filtered for `design` — see
   `reference/pack.md` "Cached Pack Manifest" + "Phase Scoping" for the full mechanism;
   read stack-specific rules from `.claude/packs/stacks/{detected-stack}.md` if present.

### Step 1: Analyze Plan

Read intent.md and plan.md to understand:
- Feature scope and success criteria
- Planned file changes
- Risk level and complexity

### Step 2: System Design Exploration

For MEDIUM complexity features:
- Identify the primary system components involved
- Map data flow between components
- Define key interfaces

For COMPLEX complexity features:
- Full system architecture diagram
- API contract definitions (request/response shapes)
- Database schema changes (if applicable)
- Integration points with external systems
- Error handling strategy

### Step 3: Generate Design Artifacts

Write `.temper/specs/{feature}/design.md` using the template from `$CLAUDE_PLUGIN_ROOT/templates/design.md`.

### Step 4: Design Summary

```
+--------------------------------------------------------------+
| DESIGN -- {Feature Name}                                     |
+--------------------------------------------------------------+
| SYSTEM ARCHITECTURE                                          |
|    Components: {N} new, {N} modified, {N} existing          |
|    Data flow: {brief description}                            |
|                                                              |
| API CONTRACTS (if applicable)                                |
|    + POST /api/{endpoint} -- {request shape} -> {response}   |
|    ~ GET /api/{endpoint} -- {change description}             |
|                                                              |
| DATABASE CHANGES (if applicable)                             |
|    + {table} -- {columns}                                    |
|    ~ {table} -- {change}                                     |
|                                                              |
| INTEGRATION POINTS                                           |
|    {external system} -- {how it connects}                    |
|                                                              |
| DECISION LOG                                                 |
|    1. {decision} -- {rationale}                              |
+--------------------------------------------------------------+
```

### Stage Gate

Use AskUserQuestion with these options:

```
AskUserQuestion:
  question: "What next?"
  options:
    - label: "Continue to Build (Recommended)"
      description: "Proceed to build with the approved design."
    - label: "Walk through design step by step"
      description: "Interactive walkthrough of design decisions."
    - label: "Save for later"
      description: "Save design and stop."
  multiSelect: false
```

| Response | Action |
|----------|--------|
| **Continue to Build** | Save design.md, proceed to build |
| **Walk through design** | Interactive section-by-section review (see below) |
| **Save for later** | Save state, stop |
| **Other** (free-text) | Edit design, re-show gate |

#### Step-by-Step Walkthrough

When the user selects "Walk through design step by step", present the design as an interactive, section-by-section flow.

**Walkthrough sections (dynamic — only show sections present in design.md):**

Read `design.md` and detect which sections exist. Present only sections that have content. The available sections:

1. **Architecture Overview** — System components, data flow diagram, what's new vs modified vs existing (always shown)
2. **API Contracts** — Request/response shapes, endpoint changes, backward compatibility notes (shown if design.md has API contract content)
3. **Database Changes** — Schema changes, migration strategy, impact on existing data (shown if design.md has database content)
4. **Integration Points** — External system connections, error handling strategy, retry/fallback logic (shown if design.md has integration content)
5. **Decision Log** — Each architectural decision with rationale and alternatives considered (always shown)

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
- **"Other" (change request)**: Edit design files, show what changed, then re-show the same section's gate
- **"Next step"**: Advance to next section. After the last section, show the final walkthrough gate:

```
AskUserQuestion:
  question: "Walkthrough complete. What next?"
  options:
    - label: "Continue to Build (Recommended)"
      description: "Proceed to build with the approved design."
    - label: "Save for later"
      description: "Save design and stop."
  multiSelect: false
```

**"Other" (free-text change request)**: Edit design files, show what changed, re-show this gate.

### ADR Generation

After design.md is generated, check if the design contains **architectural decisions** that warrant an Architectural Decision Record (ADR). ADRs persist decisions for future reference and prevent "why did we do it this way?" confusion.

**When to generate an ADR (only for architectural decisions):**
- Database schema or storage technology choice (Postgres vs Redis, SQL vs NoSQL)
- Framework or library selection for a new capability (auth, caching, messaging)
- API contract design (REST vs GraphQL, versioning strategy)
- Infrastructure or deployment architecture changes
- Security architecture decisions (auth flow, encryption strategy)
- Integration with external systems (payment provider, email service)

**When NOT to generate an ADR (styling/implementation details):**
- UI styling decisions (colors, fonts, layout)
- Variable naming or code organization
- Choice of utility function or helper library
- Test structure or naming conventions

**Procedure:**

1. After design.md is written, scan for architectural decisions
2. For each qualifying decision, generate `docs/decisions/NNNN-{slug}.md`:
   - `NNNN` = sequential number (check existing ADRs for next number, start at 0001)
   - `{slug}` = kebab-case summary of the decision
   - Use template from `$CLAUDE_PLUGIN_ROOT/templates/adr.md`
3. Fill in: Status (Proposed), Date, Context, Decision, Alternatives Considered, Consequences
4. Never delete ADRs — supersede via new ADRs with "Supersedes: ADR-{NNNN}" reference
5. If no architectural decisions found, skip ADR generation entirely

**Example ADR filenames:**
- `docs/decisions/0001-use-postgres-over-mongodb.md`
- `docs/decisions/0002-rest-api-with-versioning.md`
- `docs/decisions/0003-jwt-auth-with-refresh-tokens.md`

### Skip Conditions

The Design stage is automatically skipped when:
- Feature complexity is Trivial or Simple
- `phases.design: false` in temper.config
- Plan only involves config changes or single-file modifications

When skipped, the orchestrator proceeds directly to Build.
