---
description: "Root cause analysis + structured fix"
argument-hint: "<bug-description-or-JIRA-123>"
---

# Fix: RCA → Fix → Review → Check

**Goal:** Investigate root cause, implement minimal fix, then **review** and **check** — the same full pipeline as `/temper` but with RCA replacing the PLAN stage.

## Usage

```
/temper:fix "users get 500 error on checkout"    # Start new fix
/temper:fix "JIRA-123"                            # Fix from Jira ticket
/temper:fix "#456"                                # Fix from GitHub issue
/temper:fix                                       # Resume saved fix
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

Each stage runs in an **isolated Agent subprocess** — genuine context clearing, not theater.

```
ORCHESTRATOR (this file)
  │
  ├── Agent subprocess → RCA (replaces PLAN)
  │     Multi-hypothesis root cause analysis
  │     ↓ returns: RCA summary box
  │     ↓ gate decision from user
  │
  ├── Agent subprocess → FIX (replaces BUILD)
  │     Regression test (RED) → minimal fix (GREEN) → blast radius
  │     ↓ returns: fix summary + files changed
  │     ↓ gate decision from user
  │
  ├── Agent subprocess → REVIEW (same as /temper)
  │     Confidence-scored review with pack rules
  │     ↓ returns: review summary + issues
  │     ↓ gate decision from user
  │
  └── Agent subprocess → CHECK (same as /temper)
        Full validation pipeline
        ↓ returns: check results
        ↓ gate decision from user → commit
```

### State Management

The orchestrator tracks progress via `.temper/build-state.json`. **Resolve the spec path from this file before launching any agent.**

```json
{
  "stage": "rca_complete|fix_complete|review_complete|check_complete",
  "spec": "{bug-slug}",
  "spec_path": ".temper/specs/{bug-slug}",
  "branch": "fix/{bug-slug}",
  "original_args": "{user's original bug description}",
  "next_stage": "fix|review|check|commit",
  "artifacts": ["rca.md"],
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

At each stage gate, use `AskUserQuestion` with selectable options. Do NOT use `[Enter]` as a prompt.

### Gate Options Pattern

Every stage gate uses exactly 2 explicit options plus the built-in "Other" free-text input:

```
AskUserQuestion:
  question: "What would you like to do with this {stage}?"
  options:
    - label: "Continue to {next_stage} (Recommended)"
      description: "Launches a new agent subprocess. Clean context."
    - label: "Save for later"
      description: "Save state and stop. Run /temper:fix later to continue."
  multiSelect: false
```

**Users type change requests directly via the "Other" option.** AskUserQuestion always provides an "Other" free-text input. When a user selects "Other" and types a change request:
1. Make the requested change
2. **STOP** — re-show the AskUserQuestion gate with the same options
3. Do NOT interpret the change input as approval to proceed

### Gate Enforcement Rules

After handling a change request (via "Other" free-text input), you **MUST** re-show the AskUserQuestion gate before proceeding:

1. User selects "Other" and types their change request (e.g., "investigate the auth module instead")
2. You make the requested change
3. **STOP HERE** — re-show the AskUserQuestion gate with the same 2 options
4. Do NOT interpret the user's change input as approval to proceed to the next stage

The user must **explicitly select "Continue to {next_stage}"** from the gate to proceed.

---

## Stage 1: RCA (Root Cause Analysis)

**Runs in:** Agent subprocess with full codebase access

### Launch RCA Agent

```
Use the Agent tool with this prompt:

"Execute root cause analysis for bug: $ARGUMENTS

Full methodology: Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/fix.md

CONTEXT: Load these first:
1. Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/fix.md for methodology
2. Load enabled packs from .claude/temper.config and stack-specific rules (Step 1.5)
3. Check if the bug violates any pack rules during RCA (e.g., security: was input validation skipped?)

ENFORCEMENT: Always follow the full RCA methodology. Always generate multi-hypothesis investigation (or skip condition with justification).

CRITICAL: This agent runs in isolation. After RCA:
1. Show the RCA summary box (see below)
2. Do NOT show an AskUserQuestion gate — return the summary to the orchestrator
3. The orchestrator handles the gate decision

Return ONLY:
- RCA summary text (formatted box)
- Root cause: {specific line, condition, why}
- Confidence: {HIGH/MEDIUM/LOW}
- Suggested fix: {1-2 sentence minimal fix}
- Fix location: {file:line}
- Test scenario: {scenario the regression test should exercise}
- Blast radius: {other code with same vulnerability}
- Related files: {files to read before fixing}"
```

### RCA Summary Format

```
┌─────────────────────────────────────────────────────────────┐
│ 🔍 RCA — {Bug Title}                                        │
├─────────────────────────────────────────────────────────────┤
│ ROOT CAUSE                                                   │
│    Bug:        {one-line description}                        │
│    Cause:      {specific: which line, which condition, why} │
│    Location:   {file:line}                                  │
│    Confidence: {HIGH/MEDIUM/LOW}                            │
│    Introduced: {commit hash + date, or "unknown"}           │
│                                                             │
│ CALL CHAIN                                                   │
│    {entry point} → {intermediate} → {failing function}     │
│                                                             │
│ BLAST RADIUS                                                 │
│    Impact:       {all users / specific flow / edge case}    │
│    Same bug in:  {other locations, or "none found"}        │
│                                                             │
│ SUGGESTED FIX                                                │
│    Approach: {1-2 sentence minimal fix}                     │
│    Fix at:   {file:line}                                    │
│    Test:     {scenario the regression test should exercise} │
│                                                             │
│ PACK RULES LOADED                                            │
│    {quality, tdd, security, git} + {stack-specific}        │
└─────────────────────────────────────────────────────────────┘
```

### Stage Gate

Show the AskUserQuestion gate with:
- "Proceed to Fix (Recommended)" — launch FIX agent
- "Save for later" — save state, stop
- **"Other" (built-in free-text)** — type a change request (e.g., "investigate auth module instead")

**on Continue:**
1. Save RCA results to `.temper/specs/{bug-slug}/rca.md` (create directory if needed)
2. Save state to `.temper/build-state.json`:
   ```json
   {
     "stage": "rca_complete",
     "spec": "{bug-slug}",
     "spec_path": ".temper/specs/{bug-slug}",
     "original_args": "$ARGUMENTS",
     "next_stage": "fix",
     "artifacts": ["rca.md"],
     "branch": "fix/{bug-slug}",
     "updated": "{ISO timestamp}"
   }
   ```
3. **Create fix branch** (if git pack is enabled):
   - Run: `git branch --show-current`
   - If on main/master: `git checkout -b fix/{bug-slug}`
   - Store branch name in build-state.json
4. Proceed to Stage 2 (FIX) — launches a new Agent subprocess

**on Change (via "Other" free-text input):**
1. User types their change request in the "Other" field (e.g., "investigate the auth module instead")
2. Re-launch the RCA agent with the updated direction
3. Show the updated RCA summary
4. **Re-show the AskUserQuestion gate** — do NOT skip to fix

**on Save:**
1. Save state to `.temper/build-state.json`
2. Report: "Saved. Run /temper:fix when ready to continue."

---

## Stage 2: Fix

**Runs in:** Agent subprocess with clean context — only RCA results + related files loaded

### Launch Fix Agent

Before launching, read `.temper/build-state.json` to get the `spec_path` and `spec` values.

```
Use the Agent tool with this prompt:

"Execute /temper:fix for bug: {spec from build-state.json}

Full methodology: Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/fix.md

CONTEXT: You are starting with a CLEAN context. Load these files first:
1. {spec_path}/rca.md (root cause analysis results)
2. Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/fix.md for methodology

Then execute the fix:
1. Load enabled packs and stack-specific rules (Step 1.5)
2. Write regression test — MUST FAIL (Step 3)
3. Validate fix approach against pack rules (Step 3.5)
4. Implement minimal fix — test MUST PASS (Step 4)
5. Blast radius check (Step 4.5)
6. Intent cross-reference (Step 4.75)
7. Simplify if code-simplifier available (Step 4.8)

CRITICAL: Do NOT show an AskUserQuestion gate at the end. Return the fix summary to the orchestrator.

Return ONLY:
- Fix summary text (formatted box)
- List of files changed
- Regression test name and result
- Blast radius results
- Any blockers or failures"
```

### Fix Summary Format

```
┌─────────────────────────────────────────────────────────────┐
│ 🔧 FIX — {Bug Title}                                        │
├─────────────────────────────────────────────────────────────┤
│ ROOT CAUSE                                                   │
│    {1-line root cause}                                      │
│                                                             │
│ FIX APPLIED                                                  │
│    Fix:         {1-line description}                        │
│    Confidence:  {HIGH/MEDIUM}                               │
│    Files:       {list}                                      │
│                                                             │
│ REGRESSION TEST                                              │
│    Test:   {test class}#{method}                            │
│    Status: ✅ PASS (was failing before fix)                 │
│                                                             │
│ BLAST RADIUS                                                 │
│    Consumers: {count} | Same-pattern: {fixed}/{found}      │
│    ✅ No breaking changes                                   │
│                                                             │
│ PACK VALIDATION                                              │
│    Rules: {security ✅, tdd ✅, quality ✅, {stack} ✅}     │
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
3. Re-show the updated fix summary
4. **Re-show the AskUserQuestion gate** — do NOT skip to review

**on Save:**
1. Save state to `.temper/build-state.json`:
   ```json
   {
     "stage": "fix_complete",
     "spec": "{bug-slug}",
     "spec_path": ".temper/specs/{bug-slug}",
     "original_args": "{from prior state}",
     "next_stage": "review",
     "artifacts": ["rca.md"],
     "updated": "{ISO timestamp}"
   }
   ```
2. Report: "Saved. Run /temper:fix when ready to continue."

---

## Stage 3: Reviewing

**Runs in:** Agent subprocess with clean context — only changed files loaded

### Launch Review Agent

Before launching, read `.temper/build-state.json` to get the `spec_path` and `spec` values.

```
Use the Agent tool with this prompt:

"Execute /temper:review for fix: {spec from build-state.json}

Full methodology: Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/review.md

CONTEXT: You are starting with a CLEAN context. Load these first:
1. Run: git diff --name-only (to get changed files)
2. Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/review.md for methodology
3. Read {spec_path}/rca.md (for root cause context)
4. Load enabled packs from .claude/temper.config and stack-specific rules (per review.md Step 1)

Then review all changed files using parallel subagents as described in the methodology.

Focus areas for FIX reviews:
- Fix correctness: does the fix address the root cause?
- Regression test quality: does the test prove the fix?
- Pack rule compliance: security, quality, stack patterns
- AI-code detection: hallucinated APIs, over-engineering, copy-paste drift

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
│ 🔍 REVIEW — Fix for {Bug Title}                             │
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
│    2. [{severity}] {file}:{line} — {one-line description}   │
│                                                             │
│ FIX-SPECIFIC CHECKS                                         │
│    Root cause addressed: ✅ / ❌                            │
│    Regression test quality: STRONG / WEAK / TRIVIAL        │
│    Pack violations: {none / listed}                         │
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
     "spec": "{bug-slug}",
     "spec_path": ".temper/specs/{bug-slug}",
     "original_args": "{from prior state}",
     "next_stage": "check",
     "artifacts": ["rca.md"],
     "updated": "{ISO timestamp}"
   }
   ```
2. Report: "Saved. Run /temper:fix when ready to continue."

---

## Stage 4: Checking

**Runs in:** Agent subprocess with clean context — only check.md + rca.md loaded

### Launch Check Agent

```
Use the Agent tool with this prompt:

"Execute /temper:check for project validation.

Full methodology: Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/check.md

CONTEXT: You are starting with a CLEAN context. Load these first:
1. Read $CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/check.md for methodology
2. Read {spec_path}/rca.md (for regression test context)
3. Detect stack and run the full validation pipeline

CRITICAL: Do NOT show an AskUserQuestion gate at the end. Return the check summary to the orchestrator.

Return ONLY:
- Check summary text (formatted box)
- Per-level results (pass/fail/skip)
- Any failures with suggested fixes"
```

### Check Summary Format

```
┌─────────────────────────────────────────────────────────────┐
│ ✅ CHECK — Fix for {Bug Title}                              │
├─────────────────────────────────────────────────────────────┤
│ WHAT WAS VALIDATED                                          │
│    Compile:   {status} {time}                               │
│    Tests:     {status} {time} — {N} passed                  │
│    Coverage:  {status} {X}% (threshold: {Y}%)               │
│    Lint:      {status} {time}                               │
│    Security:  {status} {time}                               │
│                                                             │
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
2. Commit with conventional message:
   fix({scope}): {description}

   Root cause: {explanation}
   Regression test: {test name}
   {Closes JIRA-123 / Fixes #456}

   Co-Authored-By: Claude <noreply@anthropic.com>

3. Report:
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
     "spec": "{bug-slug}",
     "spec_path": ".temper/specs/{bug-slug}",
     "original_args": "{from prior state}",
     "next_stage": "commit",
     "artifacts": ["rca.md"],
     "updated": "{ISO timestamp}"
   }
   ```
2. Report: "Saved. Run /temper:fix when ready to continue."

---

## Resume: `/temper:fix` (no arguments)

If you stopped earlier, run `/temper:fix` to continue.

### Resume Validation

Before showing the saved state, validate `.temper/build-state.json`:

1. **Parseable JSON** — if malformed, show error and ask user
2. **Valid stage** — must be one of: `rca_complete`, `fix_complete`, `review_complete`, `check_complete`
3. **Spec directory exists** — `.temper/specs/{spec}/` must exist on disk
4. **Artifacts exist** — all files listed in `artifacts` array must exist
5. **Timestamp** — if `updated` > 30 days ago, warn user about staleness

If any check fails:
- Show what's wrong: "Saved state is invalid: {reason}"
- Ask user: "Start over (re-investigate) / Delete saved state / Cancel?"

### Nested Invocation Protection

If `/temper:fix "new bug"` is called while `.temper/build-state.json` already exists for a different bug:

```
┌─────────────────────────────────────────────────────────────┐
│ SAVED STATE FOUND                                           │
├─────────────────────────────────────────────────────────────┤
│ Bug: {name}                                                 │
│    Stopped: After {stage}                                   │
│    Files: {N} changed                                       │
│                                                             │
│ Starting '{new bug}' will overwrite this session.           │
└─────────────────────────────────────────────────────────────┘
```

Use AskUserQuestion:
```
AskUserQuestion:
  question: "A saved session exists for '{existing bug}'. What would you like to do?"
  options:
    - label: "Resume existing session (Recommended)"
      description: "Continue from {next_stage} stage with the existing RCA."
    - label: "Overwrite and start new"
      description: "Delete existing session, start RCA for '{new bug}' from scratch."
  multiSelect: false
```

If `/temper:fix` (no arguments) is called and `.temper/build-state.json` exists for the same bug:
```
AskUserQuestion:
  question: "Resume from where you left off?"
  options:
    - label: "Continue from {next_stage} (Recommended)"
      description: "Resume from checkpoint, launch {next_stage} agent."
    - label: "Start over (re-investigate)"
      description: "Go back to RCA, launch root cause analysis agent."
  multiSelect: false
```

**Special case:** If resuming at `rca_complete`, re-display the RCA summary box (read `{spec_path}/rca.md`) before launching the FIX agent, so the user can re-evaluate the root cause.

---

## Context Efficiency

| Stage Transition | Method | Context Loaded | Size |
|-----------------|--------|----------------|------|
| RCA → FIX | New Agent subprocess | rca.md + related files | ~5-15KB |
| FIX → REVIEW | New Agent subprocess | changed files (git diff) | ~20-50KB |
| REVIEW → CHECK | New Agent subprocess | check.md | ~5KB |
| CHECK → Commit | Direct (no subprocess) | Nothing | 0KB |

Each subprocess starts genuinely clean. No theater.

---

## Individual Commands Still Work

```
/temper:plan    → Plan feature, stops at gate
/temper:build   → Build feature, stops at gate
/temper:review  → Review code, stops at gate
/temper:check   → Run validation, stops at gate
```

`/temper:fix` now follows the same orchestration pattern as `/temper`, giving fixes the full quality pipeline.
