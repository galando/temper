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

## Stage Gates: Simple Pattern

At each stage, the same question:

```
What next?
  [Enter] {continue}
  [c]     Change something first
  [s]     Save for later
```

| Option | What It Does |
|--------|--------------|
| **Enter** | Continue to next stage (clears context for efficiency) |
| **c** | Type what you want to change, Claude edits, re-ask |
| **s** | Save state, stop. Run `/temper` later to continue |

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
│   [Enter] Build it                                          │
│   [c]     Change something first                            │
│   [s]     Save for later                                    │
└─────────────────────────────────────────────────────────────┘
```

**on Enter (continue):**
```
✅ Continuing to BUILD...
🧹 Clearing context for efficiency.
📂 Loading: tasks.md + intent.md only

🔨 BUILD — {Feature Name}
...
```

**on c (change):**
```
> c

What would you like to change?

> Add rate limiting scenario

[Claude edits intent.md]

✅ Done.

What next?
  [Enter] Build it
  [c]     Change something first
  [s]     Save for later
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
│   [Enter] Review it                                          │
│   [c]     Change something first                             │
│   [s]     Save for later                                     │
└─────────────────────────────────────────────────────────────┘
```

**on Enter (continue):**
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
│   [Enter] Fix & continue                                     │
│   [c]     Change something first                             │
│   [s]     Save for later                                     │
└─────────────────────────────────────────────────────────────┘
```

**on Enter (fix & continue):**
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
│   [Enter] Commit                                             │
│   [c]     Change something first                             │
│   [s]     Save for later                                      │
└─────────────────────────────────────────────────────────────┘
```

**on Enter (commit):**
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
│   [Enter] Continue from {next_stage}                         │
│   [r]     Start over (replan)                                 │
│   [s]     Keep saved, don't resume                            │
└─────────────────────────────────────────────────────────────┘
```

| Option | What It Does |
|--------|--------------|
| **Enter** | Continue from where you stopped |
| **r** | Go back to PLAN stage, reload full context |
| **s** | Stop, keep state for later |

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
