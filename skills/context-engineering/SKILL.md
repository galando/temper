---
name: context-engineering
description: "Hierarchical context loading for AI coding agents — load what you need, defer what you don't"
---

# Context Engineering

**Version:** 1.0.0
**Last Updated:** 2026-05-12

## Overview

Context engineering is the discipline of loading the right information, in the right order, at the right time. AI coding agents have finite context windows. Loading too much wastes tokens and dilutes attention. Loading too little causes hallucinations and missed dependencies.

This skill provides a **hierarchical loading strategy** that maximizes signal per token:

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
- When context feels stale (agent is repeating itself or missing obvious facts)

## Process

### Step 1: Determine Task Scope

Before loading anything, answer:

1. **What am I doing?** (fixing a bug, adding a feature, reviewing code)
2. **What files am I likely to touch?** (from tasks.md or plan.md)
3. **What do I already know?** (from current context or build-state.json)

This takes 10 seconds and prevents loading 80% of files you won't use.

### Step 2: Load Rules (always first)

Load in this order:
1. `.claude/temper.config` — enabled packs, stack, review settings
2. `.claude/packs/{enabled-pack}/rules.md` — only enabled packs
3. `.claude/packs/stacks/{detected-stack}.md` — stack-specific patterns (if exists)
4. `.claude/CLAUDE.md` — project conventions

**Budget:** ~200 lines total. If packs exceed this, load only the packs scoped to the current phase.

### Step 3: Load Architecture (if touching unfamiliar code)

1. Start with the file you need to change
2. Trace dependencies: what does it import? What imports it?
3. Stop at 2 hops — do not traverse the entire dependency graph
4. If `plan.md` exists: read the file list section only (not the full plan)

**Budget:** ~400 lines. Use `grep` to find imports, not `cat` to read entire files.

### Step 4: Load Source (only what's needed)

1. Read only files listed in tasks.md or plan.md
2. Read tests before implementation (TDD discipline)
3. Read error logs or test output if fixing a bug
4. Skip files you're not modifying and don't need to understand for the change

**Budget:** ~1000 lines. This is the bulk of your context. Be selective.

### Step 5: Load Errors (if fixing or debugging)

1. Test output from the last run
2. `check-context.json` or `review-context.json` (if resuming from feedback loop)
3. Git diff (if reviewing changes)
4. Runtime error logs or stack traces

**Budget:** ~200 lines. Only relevant failures, not full test suites.

### Step 6: Defer Everything Else

These are loaded ONLY when explicitly needed:
- Full file contents of files not being modified
- Historical git log beyond the last 5 commits
- Documentation for frameworks you're not currently using
- Design docs for features you're not currently building

## Constraint: Under 2K Lines Per Task

Total context loaded per task should stay under 2000 lines. This includes rules, architecture, source, and errors. If you're approaching this limit:

1. **Drop architecture** — you probably already understand the module boundaries
2. **Summarize source** — read the function signatures, skip the bodies
3. **Defer errors** — only load the specific test failure you're fixing

Why 2K? Larger contexts reduce attention density. The agent spends tokens processing information instead of acting on it. Smaller, focused contexts produce better results.

## Rationalizations

| Rationalization | Why It's Wrong |
|-----------------|----------------|
| "I need to read the whole codebase to understand the patterns" | No, you need to read 3-5 representative files. Patterns emerge quickly. |
| "More context means better decisions" | More context means more noise. The signal-to-noise ratio drops after 2K lines. |
| "I'll just load everything and filter later" | You can't "filter" context — it all consumes attention tokens whether you reference it or not. |
| "The file is short, I'll read it just in case" | 10 "short" files = 500 lines you didn't need. Read on demand, not preemptively. |
| "I need the full git history for context" | The last 5 commits tell you what changed. Full history is archaeology, not engineering. |

## Red Flags

Watch for these signs that your context strategy is failing:

- **Agent repeats itself** — too much context, not enough focus. Reduce.
- **Agent hallucinates APIs** — not enough source context. Load the actual module.
- **Agent misses obvious dependencies** — architecture context was skipped. Load the import graph.
- **Agent fixes symptoms, not root cause** — error context is incomplete. Load the full stack trace.
- **Task takes > 10 turns** — context is likely bloated. Compact and reload focused context.

## Verification

After loading context, verify:

1. **Can you name the 3-5 files you'll modify?** If not, scope is unclear.
2. **Can you describe the module boundary you're working within?** If not, load architecture.
3. **Do you know what tests exist for the code you're changing?** If not, load test files.
4. **Is your loaded context under 2000 lines?** If not, trim before proceeding.
