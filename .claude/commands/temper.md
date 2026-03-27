---
description: "Unified SDLC command: plan → build → review → check with stage gates"
argument-hint: "<feature-description>"
---

# Temper: Unified SDLC Command

**Goal:** Execute the full SDLC flow (plan → build → review → check → commit) with stage gates and context clearing.

## Usage

```
/temper "add login feature"    # Start new feature
/temper                         # Resume or continue
```

---

## ⚠️ CRITICAL RULES (read these first)

### Rule 1: Context Clearing Is MANDATORY

When transitioning between stages, you **MUST** clear context. This is not optional. Execute these steps IN ORDER:

1. **Save state** to `.temper/build-state.json`
2. **Signal transition** — show the "Continuing to..." message
3. **Load ONLY the files needed** for the next stage (see Context Efficiency table below)
4. **Do NOT carry forward** files, analysis, or artifacts from the previous stage

If you skip context clearing, you will carry stale context that wastes tokens and causes hallucination.

### Rule 2: Stage Gates Use AskUserQuestion

At each stage gate, use the `AskUserQuestion` tool with **selectable options**. Do NOT use `[Enter]` as a prompt — Claude Code requires the user to select an option from a list.

```
AskUserQuestion:
  question: "What next?"
  options:
    - label: "Continue to {next_stage} (Recommended)"
      description: "Context will be cleared. Only {files for next stage} loaded."
    - label: "Change something first"
      description: "Type what you want to change. Claude edits, then re-asks."
    - label: "Save for later"
      description: "Save state and stop. Run /temper later to continue."
  multiSelect: false
```

---

## Stage 1: Planning

**Loads:** Full codebase (via Explore subagent) — temporary

**Summary:**
```
┌─────────────────────────────────────────────────────────────┐
│ 📋 PLAN — {Feature Name}                                   │
├─────────────────────────────────────────────────────────────┤
│ 🎯 INTENT (Why)                                             │
│    Problem: {one-line problem}                             │
│    Success: {success criteria 1}                           │
│             {success criteria 2}                           │
│                                                             │
│ 📝 PLAN (What & How)                                        │
│    Scenarios: {N} ({N} unit, {N} mock, {N} integration)   │
│    1. {scenario name}                                      │
│    2. {scenario name}                                      │
│    3. {scenario name}...                                   │
│                                                             │
│ 📁 ARCHITECTURE                                             │
│    Create: {N} files                                       │
│      • {file} — {purpose}                                   │
│      • {file} — {purpose}                                   │
│    Modify: {N} files                                       │
│      • {file} — {change reason}                             │
│      • {file} — {change reason}                             │
│                                                             │
│ ⚡ RISK: {Low/Medium/High} — {reason}                       │
└─────────────────────────────────────────────────────────────┘
```

**Stage Gate:** Use AskUserQuestion:
- "Continue to Build (Recommended)" — proceed to BUILD
- "Change something first" — user types change, Claude edits, re-ask
- "Save for later" — save state, stop

**on Continue:**
1. Save state to `.temper/build-state.json`
2. Signal: `"✅ Continuing to BUILD... 🧹 Clearing context. Loading: tasks.md + intent.md only"`
3. **CLEAR ALL CONTEXT** — do not carry any files, analysis, or artifacts from planning
4. Load ONLY: `.temper/specs/{feature}/tasks.md` + `.temper/specs/{feature}/intent.md`
5. Proceed to BUILD

**on Change:**
1. Ask: "What would you like to change?"
2. User types their change request
3. Claude edits intent.md
4. Re-show summary
5. Re-show AskUserQuestion with same options

---

## Stage 2: Building

**Loads:** tasks.md + intent.md only (~5-10KB)

**Summary:**
```
┌─────────────────────────────────────────────────────────────┐
│ 🔨 BUILD — {Feature Name}                                  │
├─────────────────────────────────────────────────────────────┤
│ ✅ WHAT WAS BUILT                                            │
│    Tasks: {N}/{N} completed                                 │
│    Tests: {N} added, all passing                            │
│    Files: {N} created, {N} modified                         │
│                                                             │
│ 📊 QUALITY                                                   │
│    Coverage: {X}% (threshold: {Y}%)                         │
│    All tests: PASS                                           │
│                                                             │
│ 📁 KEY CHANGES                                               │
│    + {file} — {one-line description}                         │
│    + {file} — {one-line description}                         │
│    ~ {file} — {one-line description}                         │
└─────────────────────────────────────────────────────────────┘
```

**Stage Gate:** Use AskUserQuestion:
- "Continue to Review (Recommended)" — proceed to REVIEW
- "Change something first" — user types change, Claude edits, re-ask
- "Save for later" — save state, stop

**on Continue:**
1. Save state to `.temper/build-state.json`
2. Signal: `"✅ Continuing to REVIEW... 🧹 Clearing context. Loading: changed files only"`
3. **CLEAR ALL CONTEXT** — do not carry tasks.md, intent.md, or any build artifacts
4. Load ONLY: changed files (`git diff --name-only`)
5. Proceed to REVIEW

---

## Stage 3: Reviewing

**Loads:** Changed files only (~20-50KB)

**Summary:**
```
┌─────────────────────────────────────────────────────────────┐
│ 🔍 REVIEW — {Feature Name}                                 │
├─────────────────────────────────────────────────────────────┤
│ ✅ WHAT WAS REVIEWED                                         │
│    Files: {N} changed files                                 │
│    Confidence: {X}%                                         │
│                                                             │
│ 📊 ISSUES FOUND                                              │
│    Critical: {N} | High: {N} | Medium: {N} | Low: {N}       │
│    Auto-fixable: {N}                                        │
│                                                             │
│ 🔧 TOP ISSUES                                                │
│    1. [{severity}] {file}:{line} — {one-line description}   │
│    2. [{severity}] {file}:{line} — {one-line description}   │
└─────────────────────────────────────────────────────────────┘
```

**Stage Gate:** Use AskUserQuestion:
- "Fix & continue to Check (Recommended)" — apply fixes, proceed
- "Change something first" — user types change, Claude edits, re-ask
- "Save for later" — skip fixes, save state

**on Continue:**
1. If auto-fixable issues exist: apply fixes
2. Re-run review (1 more loop max)
3. If clean:
   - Signal: `"✅ Continuing to CHECK... 🧹 Clearing context."`
   - **CLEAR ALL CONTEXT** — no file loading needed
   - Proceed to CHECK

---

## Stage 4: Checking

**Loads:** Nothing new (0KB)

**Summary:**
```
┌─────────────────────────────────────────────────────────────┐
│ ✅ CHECK — {Project Name}                                   │
├─────────────────────────────────────────────────────────────┤
│ ✅ WHAT WAS VALIDATED                                        │
│    Compile:   ✅ {time}                                     │
│    Tests:     ✅ {time} — {N} passed                         │
│    Coverage:  ✅ {X}% (threshold: {Y}%)                     │
│    Lint:      ✅ {time}                                     │
│    Security:  ✅ {time} — 0 vulnerabilities                │
│                                                             │
│ ⏱️  Total: {time}                                            │
└─────────────────────────────────────────────────────────────┘
```

**Stage Gate:** Use AskUserQuestion:
- "Commit (Recommended)" — commit with conventional message
- "Change something first" — user types change, re-run validation
- "Save for later" — keep changes uncommitted

**on Continue:**
```
✅ Committing...

{type}({scope}): {description}

{Closes #{issue}}
- {X} files changed, {Y} tests added

Co-Authored-By: Claude <noreply@anthropic.com>

✅ Committed: {hash}
   Branch: {branch}
   Ready to push?
```

---

## Resume: `/temper` (no arguments)

If you stopped earlier, run `/temper` to continue:

```
┌─────────────────────────────────────────────────────────────┐
│ 🔄 SAVED STATE FOUND                                         │
├─────────────────────────────────────────────────────────────┤
│ 📁 Feature: {name}                                          │
│    Stopped: After {stage}                                   │
│    Files: {N} changed                                        │
└─────────────────────────────────────────────────────────────┘
```

**Stage Gate:** Use AskUserQuestion:
- "Continue from {next_stage} (Recommended)" — resume from checkpoint
- "Start over (replan)" — go back to PLAN, reload full context
- "Keep saved, don't resume" — stop, keep state for later

---

## Context Efficiency

| Stage Transition | Clear | Then Load Only | Size |
|-----------------|-------|----------------|------|
| PLAN → BUILD | ✅ All context | tasks.md + intent.md | ~5-10KB |
| BUILD → REVIEW | ✅ All context | changed files (git diff) | ~20-50KB |
| REVIEW → CHECK | ✅ All context | Nothing | 0KB |
| CHECK → Commit | ✅ All context | Nothing | 0KB |

**Context clearing is MANDATORY.** The table above shows exactly what to load at each transition. Load nothing else.

---

## Individual Commands Still Work

```
/temper:plan    → Just planning, stops at gate
/temper:build   → Just building, stops at gate
/temper:review  → Just review, stops at gate
/temper:check   → Just check, stops at gate
```

Use these when you want granular control.
