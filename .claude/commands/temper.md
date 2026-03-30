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

### $CLAUDE_PLUGIN_ROOT Resolution

All references use `$CLAUDE_PLUGIN_ROOT` to locate plugin files. Resolve it as follows:

1. If `$CLAUDE_PLUGIN_ROOT` is set and points to an existing directory → use it
2. If unset → walk up from the command file location looking for `.claude-plugin/manifest.json`
3. If still not found → fall back to `~/.claude/plugins/temper` (default install location)
4. If fallback doesn't exist → warn user: "Cannot locate Temper plugin. Set CLAUDE_PLUGIN_ROOT or reinstall."

The resolved path is used as `$CLAUDE_PLUGIN_ROOT` throughout this command.

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
2. Ask: "Retry / Change something / Save for later?"
3. Do NOT silently proceed to the next stage

---

## Stage Gates Use AskUserQuestion

At each stage gate, use `AskUserQuestion` with selectable options. Do NOT use `[Enter]` as a prompt.

```
AskUserQuestion:
  question: "What would you like to do with this {stage}?"
  options:
    - label: "Continue to {next_stage} (Recommended)"
      description: "Launches a new agent subprocess. Clean context with only {files} loaded."
    - label: "Change something first"
      description: "Type what you want to change. Edits are made, then gate re-appears."
    - label: "Save for later"
      description: "Save state and stop. Run /temper later to continue."
  multiSelect: false
```

### Gate Enforcement Rules

After handling a "Change something first" request, you **MUST** re-show the AskUserQuestion gate before proceeding. This is the most common bypass:

1. User selects "Change something first"
2. You ask what they want to change
3. User provides input (which may look like approval or contain "yes" / "go ahead")
4. You make the requested change
5. **STOP HERE** — re-show the AskUserQuestion gate with the same 3 options
6. Do NOT interpret the user's change input as approval to proceed to the next stage

The user must **explicitly select "Continue to {next_stage}"** from the gate to proceed.

---

## Stage 1: Planning

**Runs in:** Agent subprocess with full codebase access

### Launch Planning Agent

```
Use the Agent tool with this prompt:

"Execute /temper:plan for feature: $ARGUMENTS

Full methodology: Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/plan.md

CRITICAL: This agent runs in isolation. After planning:
1. Show the plan summary box (see below)
2. Do NOT show an AskUserQuestion gate — return the summary to the orchestrator
3. The orchestrator handles the gate decision

Return ONLY:
- Plan summary text (formatted box)
- Path to spec: .temper/specs/{feature-slug}/
- Complexity level: trivial/simple/medium/complex
- Risk level: low/medium/high"
```

### Plan Summary Format

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
└─────────────────────────────────────────────────────────────┘
```

### Stage Gate

Show the AskUserQuestion gate with:
- "Continue to Build (Recommended)" — launch BUILD agent
- "Change something first" — make changes, re-show gate
- "Save for later" — save state, stop

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
     "updated": "{ISO timestamp}"
   }
   ```
2. Proceed to Stage 2 (BUILD) — launches a new Agent subprocess

**on Change:**
1. Ask: "What would you like to change?"
2. User types their change request
3. Edit the plan files directly (intent.md, tasks.md, etc.)
4. Re-show the updated plan summary
5. **Re-show the AskUserQuestion gate** — do NOT skip to build

**on Save:**
1. Save state to `.temper/build-state.json`:
   ```json
   {
     "stage": "plan_complete",
     "spec": "{feature-slug}",
     "spec_path": ".temper/specs/{feature-slug}",
     "original_args": "$ARGUMENTS",
     "next_stage": "build",
     "artifacts": ["intent.md", "tasks.md"],
     "updated": "{ISO timestamp}"
   }
   ```
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
- "Change something first" — make changes, re-show gate
- "Save for later" — save state, stop

**on Continue:**
1. Save state to `.temper/build-state.json`
2. Proceed to Stage 3 (REVIEW) — launches a new Agent subprocess

**on Change:**
1. Ask: "What would you like to change?"
2. User types their change request
3. Make the change
4. Re-show the updated build summary
5. **Re-show the AskUserQuestion gate** — do NOT skip to review

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
│ WHAT WAS REVIEWED                                           │
│    Files: {N} changed files                                 │
│    Confidence: {X}%                                         │
│                                                             │
│ ISSUES FOUND                                                │
│    Critical: {N} | High: {N} | Medium: {N} | Low: {N}       │
│    Auto-fixable: {N}                                        │
│                                                             │
│ TOP ISSUES                                                  │
│    1. [{severity}] {file}:{line} — {one-line description}   │
│    2. [{severity}] {file}:{line} — {one-line description}  │
│                                                             │
│ SCENARIO COVERAGE                                           │
│    Covered: {X}/{Y} ({Z} automated, {W} manual)             │
│    ❌ {uncovered scenario name}                              │
└─────────────────────────────────────────────────────────────┘
```

### Stage Gate

Show the AskUserQuestion gate with:
- "Fix & continue to Check (Recommended)" — apply fixes, launch CHECK agent
- "Change something first" — make changes, re-show gate
- "Save for later" — skip fixes, save state

**on Continue:**
1. Apply auto-fixable issues (if any) directly — no subprocess needed for fixes
2. If fixes were applied: re-run a single review pass on the fixed files
   - If new issues found: show updated summary, ask user again (max 1 more loop)
   - If clean: proceed to step 3
3. Save state to `.temper/build-state.json`
4. Proceed to Stage 4 (CHECK) — launches a new Agent subprocess

**on Change:**
1. Ask: "What would you like to change?"
2. User types their change request
3. Make the change
4. Re-launch the REVIEW agent to get an updated review summary
5. Show the updated review summary
6. **Re-show the AskUserQuestion gate** — do NOT skip to check

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
│    Compile:   {status} {time}                               │
│    Tests:     {status} {time} — {N} passed                  │
│    Coverage:  {status} {X}% (threshold: {Y}%)               │
│    Scenarios: {status} {X}/{Y} covered (if intent.md)       │
│    Lint:      {status} {time}                               │
│    Security:  {status} {time}                               │
│                                                             │
│ Total: {time}                                               │
└─────────────────────────────────────────────────────────────┘
```

### Stage Gate

Show the AskUserQuestion gate with:
- "Commit (Recommended)" — commit with conventional message
- "Change something first" — make changes, re-run check
- "Save for later" — keep changes uncommitted

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

**on Change:**
1. Ask: "What would you like to change?"
2. User types their change request
3. Make the change
4. Re-launch the CHECK agent to re-validate
5. **Re-show the AskUserQuestion gate** — do NOT commit directly

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

Before showing the saved state, validate `.temper/build-state.json`:

1. **Parseable JSON** — if malformed, show error and ask user
2. **Valid stage** — must be one of: `plan_complete`, `build_complete`, `review_complete`, `check_complete`
3. **Spec directory exists** — `.temper/specs/{spec}/` must exist on disk
4. **Artifacts exist** — all files listed in `artifacts` array must exist
5. **Timestamp** — if `updated` > 30 days ago, warn user about staleness

If any check fails:
- Show what's wrong: "Saved state is invalid: {reason}"
- Ask user: "Start over (replan) / Delete saved state / Cancel?"

### Nested Invocation Protection

If `/temper "new feature"` is called while `.temper/build-state.json` already exists for a different feature:

```
┌─────────────────────────────────────────────────────────────┐
│ SAVED STATE FOUND                                           │
├─────────────────────────────────────────────────────────────┤
│ Feature: {name}                                             │
│    Stopped: After {stage}                                   │
│    Files: {N} changed                                       │
│                                                             │
│ Starting '{new feature}' will overwrite this session.       │
└─────────────────────────────────────────────────────────────┘
```

Use AskUserQuestion:
```
AskUserQuestion:
  question: "A saved session exists for '{existing feature}'. What would you like to do?"
  options:
    - label: "Resume existing session (Recommended)"
      description: "Continue from {next_stage} stage with the existing plan."
    - label: "Overwrite and start new"
      description: "Delete existing session, start planning '{new feature}' from scratch."
    - label: "Cancel"
      description: "Keep saved state, don't start anything."
  multiSelect: false
```

If `/temper` (no arguments) is called and `.temper/build-state.json` exists for the same feature:
```
AskUserQuestion:
  question: "Resume from where you left off?"
  options:
    - label: "Continue from {next_stage} (Recommended)"
      description: "Resume from checkpoint, launch {next_stage} agent."
    - label: "Start over (replan)"
      description: "Go back to PLAN, launch planning agent."
    - label: "Keep saved, don't resume"
      description: "Stop, keep state for later."
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
