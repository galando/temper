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

## Stage Gates: AskUserQuestion Pattern

At each stage, use the AskUserQuestion tool with these options:

```
Question: "What next?"
  Option 1: "Continue to {next_stage}" (Recommended)
  Option 2: "Change something first"
  Option 3: "Save for later"
```

**Implementation (use AskUserQuestion tool):**

```
AskUserQuestion:
  question: "What next?"
  options:
    - label: "Continue to {next_stage} (Recommended)"
      description: "Proceed to next stage. Context will be cleared for efficiency."
    - label: "Change something first"
      description: "Type what you want to change. Claude edits, then re-asks."
    - label: "Save for later"
      description: "Save state and stop. Run /temper later to continue."
  multiSelect: false
```

| Selection | What It Does |
|-----------|--------------|
| **Continue** (first option) | Continue to next stage (clears context for efficiency) |
| **Change something** | User types what to change via "Other", Claude edits, re-ask |
| **Save for later** | Save state, stop. Run `/temper` later to continue |

**IMPORTANT:** Do NOT use `[Enter]` as a prompt — Claude Code's AskUserQuestion requires the user to select an option. Always provide explicit selectable options.

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
│                                                             │
│ What next?                                                  │
│   ▸ Continue to Build (Recommended)                         │
│     Change something first                                  │
│     Save for later                                          │
└─────────────────────────────────────────────────────────────┘
```

**on Continue (first option):**
```
✅ Continuing to BUILD...
🧹 Clearing context for efficiency.
📂 Loading: tasks.md + intent.md only

🔨 BUILD — {Feature Name}
...
```

**on Change something (second option):**
```
> User selects "Change something first"

What would you like to change?

> Add rate limiting scenario

[Claude edits intent.md]

✅ Done.

[Re-shows AskUserQuestion with same options]
```

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
│                                                             │
│ What next?                                                  │
│   ▸ Continue to Review (Recommended)                          │
│     Change something first                                    │
│     Save for later                                            │
└─────────────────────────────────────────────────────────────┘
```

**on Continue (first option):**
```
✅ Continuing to REVIEW...
🧹 Clearing context for efficiency.
📂 Loading: changed files only

🔍 REVIEW...
```

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
│                                                             │
│ What next?                                                  │
│   ▸ Fix & continue to Check (Recommended)                     │
│     Change something first                                    │
│     Save for later                                            │
└─────────────────────────────────────────────────────────────┘
```

**on Continue (first option — fix & continue):**
- If auto-fixable issues exist: apply fixes
- Re-run review (1 more loop max)
- If clean: proceed to CHECK

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
│                                                             │
│ What next?                                                  │
│   ▸ Commit (Recommended)                                      │
│     Change something first                                    │
│     Save for later                                            │
└─────────────────────────────────────────────────────────────┘
```

**on Continue (first option — commit):**
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
│                                                             │
│ What next?                                                  │
│   ▸ Continue from {next_stage} (Recommended)                  │
│     Start over (replan)                                        │
│     Keep saved, don't resume                                   │
└─────────────────────────────────────────────────────────────┘
```

| Option | What It Does |
|--------|--------------|
| **Continue** (first option) | Continue from where you stopped |
| **Start over** | Go back to PLAN stage, reload full context |
| **Keep saved** | Stop, keep state for later |

---

## Context Efficiency

| Stage | What's Loaded | Size |
|-------|---------------|------|
| PLAN | Full codebase (via subagent) | Large (temp) |
| BUILD | tasks.md + intent.md | ~5-10KB |
| REVIEW | Changed files only | ~20-50KB |
| CHECK | Nothing new | 0KB |

**Every "Continue" clears context** — keeps the flow efficient.

---

## Individual Commands Still Work

```
/temper:plan    → Just planning, stops at gate
/temper:build   → Just building, stops at gate
/temper:review  → Just review, stops at gate
/temper:check   → Just check, stops at gate
```

Use these when you want granular control.
