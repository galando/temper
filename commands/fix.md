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

> **Shared patterns:** `$CLAUDE_PLUGIN_ROOT/reference/orchestrator-patterns.md`
> **Read that file once, now.** Canonical definitions for: $CLAUDE_PLUGIN_ROOT resolution, build-state schema + save-state pattern, gate enforcement, resume validation, nested invocation protection, and context efficiency. Every `→ pattern` reference below points into that already-loaded file — do not re-read it.
>
> **`$TEMPER` below means `$CLAUDE_PLUGIN_ROOT/scripts/temper`.** The commit hook
> (`scripts/hooks/install.sh`) runs `temper gate commit` on **every** `git commit`,
> regardless of which command produced it — so this file records evidence and runs the
> same gates as `/temper` (Fix maps onto the `build` gate: a regression test is exactly a
> RED-then-GREEN pair; Review and Check are the literal same stages, sharing
> `reference/review.md` / `reference/check.md`). Skipping this would leave every
> `/temper:fix` commit wrongly blocked (missing evidence fails closed, by design).

Each stage runs in an **isolated Agent subprocess** — genuine context clearing, not theater.

### Active Skills

- **Context Engineering** — load hierarchical context at stage start (rules → arch → source → errors, under 2K lines/task)
- **Temper Core** — stack detection, pack resolution, quality gates
- **Source-Driven Development** — before writing framework-specific code in the FIX stage: detect installed version → fetch current docs → cite sources → surface API conflicts

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

State is tracked in `.temper/build-state.json` — schema and save-state rules in
orchestrator-patterns.md → "Build State Schema". For `/temper:fix`: stages
`rca_complete | fix_complete | review_complete | check_complete`, branch `fix/{slug}`,
artifact `rca.md`. **Resolve the spec path from this file before launching any agent.**

---

## Stage 1: RCA (Root Cause Analysis)

**Runs in:** Agent subprocess with full codebase access

### Launch RCA Agent

```
Use the Agent tool with this prompt:

"Execute root cause analysis for bug: $ARGUMENTS

Full methodology: Read $CLAUDE_PLUGIN_ROOT/reference/fix.md

CONTEXT: Load these first:
1. Read $CLAUDE_PLUGIN_ROOT/reference/fix.md for methodology
2. Load enabled packs from .claude/temper.config and stack-specific rules
3. Check if the bug violates any pack rules during RCA (e.g., security: was input validation skipped?)
4. If code-review-graph MCP server is available: use query_graph_tool for call chain tracing (callers + callees of suspected function) — [PROVEN] results. Fallback to grep-based tracing if unavailable.

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
2. `$TEMPER state init {bug-slug} --command fix` (first time only — this also sets branch
   `fix/{bug-slug}`), else `$TEMPER state advance rca_complete fix`.
3. **Create fix branch** (if git pack is enabled):
   - Run: `git branch --show-current`
   - If on main/master: `git checkout -b fix/{bug-slug}`
4. Proceed to Stage 2 (FIX) — launches a new Agent subprocess

**on Change (via "Other"):** Re-launch the RCA agent with the updated direction (e.g. "investigate the auth module instead"), show the updated RCA summary, then re-show this gate. Enforcement: orchestrator-patterns.md → "Gate Enforcement Rules".

**on Save:** Save state (orchestrator-patterns.md → "Save State Pattern", `stage: rca_complete`).

---

## Stage 2: Fix

**Runs in:** Agent subprocess with clean context — only RCA results + related files loaded

### Launch Fix Agent

Before launching, read `.temper/build-state.json` to get the `spec_path` and `spec` values.

```
Use the Agent tool with this prompt:

"Execute /temper:fix for bug: {spec from build-state.json}

Full methodology: Read $CLAUDE_PLUGIN_ROOT/reference/fix.md
Follow all steps in fix.md — read it first and execute in order.

CONTEXT: You are starting with a CLEAN context. Load these files first:
1. {spec_path}/rca.md (root cause analysis results)
2. Read $CLAUDE_PLUGIN_ROOT/reference/fix.md for methodology
3. If code-review-graph MCP server is available: use get_impact_radius_tool for blast radius check — [PROVEN] results. Fallback to grep-based detection if unavailable.

Then execute the fix methodology. Make sure to include:
- Loading enabled packs and stack-specific rules
- Writing a regression test that MUST FAIL before the fix
- Validating the fix approach against pack rules before implementing
- Implementing the minimal fix (test MUST PASS)
- Blast radius check
- Intent cross-reference (if active intent.md exists)
- Simplification (if code-simplifier agent is available)

Record the regression test as build evidence — this is what `temper gate build` checks:
  $CLAUDE_PLUGIN_ROOT/scripts/temper evidence add --stage build --claim 'regression test' \
    --cmd '<test command>' --exit 1 --phase red --label PROVEN     # failing, before the fix
  $CLAUDE_PLUGIN_ROOT/scripts/temper evidence add --stage build --claim 'regression test' \
    --cmd '<test command>' --exit 0 --phase green --label PROVEN   # passing, after the fix

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

Run `$TEMPER gate build` (checks the RED-then-GREEN regression-test evidence above; the
"no unchecked tasks" requirement is skipped automatically — fixes have no `tasks.md`).

Show the AskUserQuestion gate with:
- **On PASS:** "Continue to Review (Recommended)" — launch REVIEW agent
- **On FAIL:** "Override and continue" (`$TEMPER override build --reason "..."`) or fix it
  and re-run the gate
- "Save for later" — save state, stop
- **"Other" (built-in free-text)** — type a change request, edits are made, gate re-appears

**on Continue:**
1. `$TEMPER state advance fix_complete review`
2. Proceed to Stage 3 (REVIEW) — launches a new Agent subprocess

**on Change (via "Other"):** Make the change, re-show the updated fix summary, then re-show this gate. Enforcement: orchestrator-patterns.md → "Gate Enforcement Rules".

**on Save:** Save state (orchestrator-patterns.md → "Save State Pattern", `stage: fix_complete`, `next_stage: review`).

---

## Stage 3: Reviewing

**Runs in:** Agent subprocess with clean context — only changed files loaded

### Launch Review Agent

Before launching, read `.temper/build-state.json` to get the `spec_path` and `spec` values.

```
Use the Agent tool with this prompt:

"Execute /temper:review for fix: {spec from build-state.json}

Full methodology: Read $CLAUDE_PLUGIN_ROOT/reference/review.md

CONTEXT: You are starting with a CLEAN context. Load these first:
1. Run: git diff --name-only (to get changed files)
2. Read $CLAUDE_PLUGIN_ROOT/reference/review.md for methodology
3. Read {spec_path}/rca.md (for root cause context)
4. Load enabled packs from .claude/temper.config and stack-specific rules

Then review all changed files using parallel subagents as described in the methodology.

Focus areas for FIX reviews:
- Fix correctness: does the fix address the root cause?
- Regression test quality: does the test prove the fix?
- Pack rule compliance: security, quality, stack patterns
- AI-code detection: hallucinated APIs, over-engineering, copy-paste drift

Record every finding you keep open (per `reference/review.md`'s severity taxonomy) —
this is what `temper gate review` checks:
  $CLAUDE_PLUGIN_ROOT/scripts/temper evidence add --stage review \
    --claim '<one-line finding>' --severity critical|high|medium|low --label HEURISTIC

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

Run `$TEMPER gate review` (zero open findings at or above `review.block-on`).

Show the AskUserQuestion gate with:
- **On FAIL:** "Fix all & continue to Check (Recommended)" — apply fixes for ALL open
  findings directly (no subprocess), then re-run `temper gate review`; if it's still FAIL
  after one fix pass, offer "Override and continue" instead of looping indefinitely
- **On PASS:** "Continue to Check (Recommended)"
- "Save for later" — skip fixes, save state
- **"Other" (built-in free-text)** — type a change request, edits are made, gate re-appears

**on Continue:**
1. `$TEMPER state advance review_complete check`
2. Proceed to Stage 4 (CHECK) — launches a new Agent subprocess

**on Change (via "Other"):** Make the change, re-launch the REVIEW agent for an updated summary, then re-show this gate. Enforcement: orchestrator-patterns.md → "Gate Enforcement Rules".

**on Save:** Save state (orchestrator-patterns.md → "Save State Pattern", `stage: review_complete`, `next_stage: check`).

---

## Stage 4: Checking

**Runs in:** Agent subprocess with clean context — only check.md + rca.md loaded

### Launch Check Agent

```
Use the Agent tool with this prompt:

"Execute /temper:check for project validation.

Full methodology: Read $CLAUDE_PLUGIN_ROOT/reference/check.md

CONTEXT: You are starting with a CLEAN context. Load these first:
1. Read $CLAUDE_PLUGIN_ROOT/reference/check.md for methodology
2. Read {spec_path}/rca.md (for regression test context)
3. Detect stack and run the full validation pipeline

Record what you ran — this is what `temper gate check` checks:
  $CLAUDE_PLUGIN_ROOT/scripts/temper evidence add --stage check --claim 'tests' \
    --cmd '<test command>' --exit <code> --label PROVEN
  $CLAUDE_PLUGIN_ROOT/scripts/temper evidence add --stage check --claim 'coverage' \
    --cmd '<coverage command>' --exit <code> --value <parsed %> \
    --artifact <path to the report> --label PROVEN

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

Run `$TEMPER gate check`, then `$TEMPER gate commit` (aggregates build/review/check —
Fix has no `plan` gate, `temper gate commit` only requires the gates a `fix` run
actually produced).

Show the AskUserQuestion gate with:
- **On PASS:** "Commit (Recommended)" — commit with conventional message
- **On FAIL:** show `$TEMPER report`; "Override and commit" (`$TEMPER override <stage>
  --reason "..."`, re-run `temper gate commit`) or "Save for later"
- **"Other" (built-in free-text)** — type a change request, edits are made, re-run check

**on Commit:**
```
1. git add -A && git commit -m "fix({scope}): {description}

   Root cause: {explanation}
   Regression test: {test name}
   {Closes JIRA-123 / Fixes #456}

   Co-Authored-By: Claude <noreply@anthropic.com>"
2. $TEMPER state clear
3. Report:
   "Committed: {hash}
    Branch: {branch}
    Ready to push?"
```

**on Change (via "Other"):** Make the change, re-launch the CHECK agent to re-validate, then re-show this gate (do NOT commit directly). Enforcement: orchestrator-patterns.md → "Gate Enforcement Rules".

**on Save:** Save state (orchestrator-patterns.md → "Save State Pattern", `stage: check_complete`, `next_stage: commit`).

---

## Resume: `/temper:fix` (no arguments)

If you stopped earlier, run `/temper:fix` to continue.

> **Resume validation:** Follow the shared pattern in `$CLAUDE_PLUGIN_ROOT/reference/orchestrator-patterns.md` → "Resume Validation" section. Valid stages for this command: `rca_complete`, `fix_complete`, `review_complete`, `check_complete`.

### Nested Invocation Protection

> Follow the shared pattern in `$CLAUDE_PLUGIN_ROOT/reference/orchestrator-patterns.md` → "Nested Invocation Protection" section. Use "bug" instead of "feature" in the display.

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

> See shared table in `$CLAUDE_PLUGIN_ROOT/reference/orchestrator-patterns.md` → "Context Efficiency Table". Fix command uses `fix/{bug-slug}` branches and `rca.md` as the primary artifact.

---

## Individual Commands Still Work

```
/temper:plan    → Plan feature, stops at gate
/temper:build   → Build feature, stops at gate
/temper:review  → Review code, stops at gate
/temper:check   → Run validation, stops at gate
```

`/temper:fix` now follows the same orchestration pattern as `/temper`, giving fixes the full quality pipeline.
