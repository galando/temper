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

Files to load at start:
1. `.temper/specs/{feature}/intent.md`
2. `.temper/specs/{feature}/plan.md`
3. `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/design.md` (this file)

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
    - label: "Save for later"
      description: "Save design and stop."
  multiSelect: false
```

| Response | Action |
|----------|--------|
| **Continue to Build** | Save design.md, proceed to build |
| **Save for later** | Save state, stop |
| **Other** (free-text) | Edit design, re-show gate |

### Skip Conditions

The Design stage is automatically skipped when:
- Feature complexity is Trivial or Simple
- `phases.design: false` in temper.config
- Plan only involves config changes or single-file modifications

When skipped, the orchestrator proceeds directly to Build.
