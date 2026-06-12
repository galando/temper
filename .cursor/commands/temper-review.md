---
description: "Technical code review with confidence scoring, review memory, and intent validation"
---

# Review: Confidence-Scored Code Review

> open-code-review integration is Claude Code-only; see docs/recommended-setup.md

**Goal:** Review changes with parallel subagents, confidence scoring, and intent validation.

## Execution

> **Full methodology:** Loaded via the `temper-ref-review` rule

### Quick Reference

1. Gather changed files + active pack rules + review memory
2. Launch parallel review subagents (backend/frontend/security)
3. Structured intent validation: mechanical checks (scenario/code) + deferred (metric/manual)
4. Filter by confidence threshold + review memory
5. Generate report to `.temper/reviews/`
6. Auto-fix high-priority issues (if enabled, max 2 loops)
7. Update metrics + review memory

**Diff-aware: focuses on what changed, catches N+1 and performance issues**
