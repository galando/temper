---
description: "Hierarchical context loading for AI coding agents — load what you need, defer what you don't"
---

# Context Engineering

**Version:** 1.0.0
**Last Updated:** 2026-05-12

## Overview

Context engineering is the discipline of loading the right information, in the right order, at the right time. Context loaded and never used still costs tokens and attention; context skipped and needed shows up as guessed APIs and missed dependencies.

This skill fixes the **loading order** for a Temper stage. How much to load is your judgment, sized to the change:

```
Priority 1: rules      → pack rules, stack conventions, guardrails
Priority 2: arch       → module boundaries, dependency graph, entry points
Priority 3: source     → specific files relevant to the current task
Priority 4: errors     → recent failures, test output, runtime errors
Priority 5: conversation → prior decisions, user intent, stakeholder context
```

## When to Use

- Start of every `/temper` stage (plan, design, build, review, check, fix)
- Before making changes to unfamiliar code
- When resuming a session from saved state

## Process

### Step 1: Determine Task Scope

Before loading anything, answer:

1. **What am I doing?** (fixing a bug, adding a feature, reviewing code)
2. **What files am I likely to touch?** (from tasks.md or plan.md)
3. **What do I already know?** (from current context or build-state.json)

### Step 2: Load Rules (always first)

Load in this order:
1. `.claude/temper.config` — enabled packs, stack, review settings
2. `.claude/packs/{enabled-pack}/rules.md` — only enabled packs, only those scoped to the current phase
3. `.claude/packs/stacks/{detected-stack}.md` — stack-specific patterns (if exists)
4. `.claude/CLAUDE.md` — project conventions

### Step 3: Load Architecture (if touching unfamiliar code)

1. Start with the file you need to change
2. Trace its imports and importers as far as the change's blast radius reaches; `grep`
   for imports rather than reading whole files to find them
3. If `plan.md` exists: read the file list section only (not the full plan)

### Step 4: Load Source (only what's needed)

1. Read only files listed in tasks.md or plan.md
2. Read tests before implementation (TDD discipline)
3. Read error logs or test output if fixing a bug
4. Skip files you're not modifying and don't need to understand for the change

### Step 5: Load Errors (if fixing or debugging)

1. Test output from the last run
2. `check-context.json` or `review-context.json` (if resuming from feedback loop)
3. Git diff (if reviewing changes)
4. Runtime error logs or stack traces

### Step 6: Defer Everything Else

Load these only when the task needs them:
- Full file contents of files not being modified
- Historical git log beyond the recent commits that touched the files in play
- Documentation for frameworks you're not currently using
- Design docs for features you're not currently building

## Red Flags

Signs that the loaded context does not match the task:

- **Agent hallucinates APIs** — not enough source context. Load the actual module.
- **Agent misses obvious dependencies** — architecture context was skipped. Load the import graph.
- **Agent fixes symptoms, not root cause** — error context is incomplete. Load the full stack trace.

## Verification

After loading context, verify:

1. **Can you name the files you'll modify?** If not, scope is unclear.
2. **Can you describe the module boundary you're working within?** If not, load architecture.
3. **Do you know what tests exist for the code you're changing?** If not, load test files.
