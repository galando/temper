---
description: "Code review with confidence scoring and review memory"
---

# Review: Confidence-Scored Code Review

**Goal:** Review changes with parallel subagents, confidence scoring, and intent validation.

## Execution

> **Full methodology:** Read `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/review.md`

### Quick Reference
1. Gather changed files + active pack rules + review memory
2. Launch parallel review subagents (backend/frontend/security)
3. Intent validation against linked issue (if any)
4. Filter by confidence threshold + review memory
5. Generate report to `.temper/reviews/`
6. Auto-fix high-priority issues (if enabled, max 2 loops)
7. Update metrics + review memory
