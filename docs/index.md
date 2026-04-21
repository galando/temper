---
title: Home
nav_order: 1
---

# Temper

{: .fs-9 }

**Your AI writes fast. Temper makes it last.**
{: .fs-6 .fw-300 }

[![Version](https://img.shields.io/github/v/release/galando/temper?include_prereleases)](https://github.com/galando/temper/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

[Get started now](#quick-start){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[Why Temper?](why-temper.html){: .btn .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View on GitHub](https://github.com/galando/temper){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## The Problem

AI writes code fast. But "fast" without "right" creates bugs, technical debt, and features that miss the point.

Three questions every AI-generated feature should answer:

1. **Did we solve the problem?** (Intent)
2. **Does it do the right things?** (Behavior)
3. **Does the code work?** (Tests)

Most AI tools answer only the third. Temper answers all three — and now (v3.0.0) adds **security hot path detection, heuristic test gap analysis, API contract validation, and performance regression guards**.

## What's New in v3.0.0

A quality intelligence layer for review and check — zero new dependencies:

| Feature | What It Does |
|---------|-------------|
| **Security Hot Paths** | Classifies files by sensitivity (CRITICAL/HIGH/MEDIUM/LOW), traces call chains to entry points, elevates scrutiny automatically |
| **Diff-Aware Review** | Builds a risk fingerprint from changed regions, focuses 80% review attention on high-risk hunks |
| **Cross-File Consistency** | Detects pattern drift — new file uses `try/catch` but peers use `Result<>`? Flagged |
| **Test Gap Analysis** | Reads implementation + test code side-by-side, finds untested edge cases, BLOCKs on untested security code |
| **API Diff Review** | Detects API shape changes from git diff, greps for consumers, flags unverified breaking changes |
| **Performance Pattern Detection** | Scans for N+1 queries, missing pagination, sync I/O, inefficient data structures |

## IDD + BDD + TDD: Three Layers, One File

{: .important }
Temper is 100% markdown — no executables, no binaries, no external dependencies.

Temper combines three development methodologies in a single artifact called `intent.md`:

| Layer | Question | How Temper Does It |
|-------|----------|-------------------|
| **IDD** (Intent) | Did we solve the problem? | Success criteria with structured validation types |
| **BDD** (Behavior) | Does it do the right things? | Scenarios derived before architecture — they drive what gets built |
| **TDD** (Test) | Does the code work? | Tests written from scenarios — RED -> GREEN -> REFACTOR |

**Scenarios drive architecture.** Every planned file must trace to a behavior or infrastructure need. Success criteria are mechanically validated where possible.

## The Proof

**Before Temper:** You add user authentication. AI generates code. Tests pass. You deploy. Users report password resets don't work. The queue consumer crashed silently.

**After Temper:**

```
/temper "add password reset"
```

That's it. One command runs the full SDLC:

```
┌─────────────────────────────────────────────────────────────┐
│ 📋 PLAN COMPLETE — Add Password Reset                        │
├─────────────────────────────────────────────────────────────┤
│ 🎯 INTENT                                                   │
│    Problem: Users can't reset passwords without support     │
│    Success: Self-service reset in under 2 minutes           │
│    Scenarios: 5 (4 unit, 1 integration)                     │
│                                                             │
│ 📁 FILES: 3 create, 2 modify                                │
│ ⚡ RISK: Medium (touches auth layer)                        │
└─────────────────────────────────────────────────────────────┘

Diagram (architecture flow):

+--------+    +------------------+    +-------------+
|  User  +--->+ ResetController  +--->+ TokenService|
+--------+    +------------------+    +------+------+
                                             |  |
                                     +-------+  +-------+
                                     v                 v
                              +------------+    +-------------+
                              | (Database) |    | EmailService|
                              +------------+    +-------------+

> Walk through plan step by step? (or Continue to Build / Save for later)

> Walk through plan step by step

📋 Step 1/6 — Intent Deep Dive
   Problem: Users can't reset passwords without contacting support
   Success criteria:
     • Self-service reset in under 2 minutes (Validate: scenario)
     • Token expires after 15 minutes (Validate: code)
   [Next step / Other]

> Next step

📋 Step 2/6 — Diagram Walkthrough
   ...step by step through architecture...

> Next step

📋 Step 6/6 — Task Walkthrough
   Task 1: Create token model + migration [SEQUENTIAL]
   Task 2: Implement TokenService [SEQUENTIAL: after Task 1]
   ...

> Continue to Build

┌─────────────────────────────────────────────────────────────┐
│ 🔨 BUILD COMPLETE                                           │
├─────────────────────────────────────────────────────────────┤
│ ✅ Tasks: 5/5 completed                                     │
│ ✅ Tests: 5 added, all passing                              │
│ ✅ Coverage: 87% (threshold: 80%)                           │
│                                                             │
│ Continue to Review (Recommended)                            │
│ Save for later                                              │
└─────────────────────────────────────────────────────────────┘

> Continue to Review

┌─────────────────────────────────────────────────────────────┐
│ ALL CHECKS PASSED                                           │
├─────────────────────────────────────────────────────────────┤
│    Compile:    ✅ 2.3s                                       │
│    Tests:      ✅ 4.1s — 5 passed                            │
│    Coverage:   ✅ 87% (threshold: 80%)                        │
│    Test Gaps:  ✅ 78% (31/40 edge cases covered)                │
│    API Diff:   ✅ 3/3 consumers verified                      │
│    Perf:       ✅ 0 anti-patterns (baseline updated)            │
│    Security:   ✅ 0 hot path issues                           │
│                                                             │
│ Commit (Recommended)                                        │
│ Save for later                                              │
└─────────────────────────────────────────────────────────────┘

> Commit

✅ Committed: a1b2c3d
   Branch: feature/password-reset
   Ready to push?
```

The queue consumer issue? Blast radius flagged it. The missing rate limiting? Scenario coverage gate caught it.

## Commands

### Unified Command (Recommended)

```
/temper "add login feature"     # Full SDLC in one command
```

### Individual Commands

| Command | Purpose |
|---------|---------|
| [`/temper:plan`](commands.html#plan) | Blast radius + security hot paths + BDD scenarios + interactive walkthrough |
| [`/temper:build`](commands.html#build) | Scenario-driven TDD gates, resume from checkpoint |
| [`/temper:review`](commands.html#review) | Diff fingerprinting + security hot paths + intent validation + confidence scoring |
| [`/temper:check`](commands.html#check) | Stack validation + test gap analysis + contract checking + perf regression |
| [`/temper:fix`](commands.html#fix) | Multi-hypothesis root cause analysis |
| [`/temper:pack`](commands.html#pack) | Manage quality packs: view, toggle, create |
| [`/temper:status`](commands.html#status) | Quality metrics, hotspot tracking |

## Quick Start

```bash
/plugin marketplace add galando/temper
/plugin install temper

cd your-project

# Option 1: Unified command (recommended)
/temper "add login feature"

# Option 2: Individual commands (granular control)
/temper:plan "your feature"    # Scenarios + diagrams + blast radius + walkthrough
/temper:build                  # Scenario-driven TDD
/temper:review                 # Intent validation
```

## Next Steps

- [Why Temper?](why-temper.html) — Why "be careful" isn't enough
- [Getting Started Guide](getting-started.html) — Detailed installation and setup
- [Commands Reference](commands.html) — Full command documentation
- [Packs](packs.html) — Built-in and custom quality packs
- [Enterprise Setup](enterprise.html) — Deploy across your organization
- [DeepWiki](https://deepwiki.com/galando/temper) — AI-powered documentation
