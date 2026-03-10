---
description: "Code review with confidence scoring and review memory"
---

# Review: Confidence-Scored Code Review

**Goal:** Review changes with confidence scoring and intent validation.

## Execution

> **Full methodology:** See temper_review tool documentation

### Quick Reference
1. Gather changed files + active pack rules + review memory
2. Analyze: backend/frontend/security concerns
3. Intent validation against linked issue (if any)
4. Filter by confidence threshold + review memory
5. Generate report to `.temper/reviews/`
6. Auto-fix high-priority issues (if enabled, max 2 loops)
7. Update metrics + review memory

### Confidence Scoring

Each finding is scored 0.0-1.0:
- **0.9-1.0**: High confidence - certain issue
- **0.7-0.9**: Medium confidence - likely issue
- **0.5-0.7**: Low confidence - possible issue
- **<0.5**: Suppressed (below threshold)

Default threshold: 0.7

### Review Memory

Stored in `.temper/review-memory.json`:
- Tracks dismissed findings
- Auto-suppresses after 5 dismissals
- Prevents repeated noise

### Review Categories

1. **Backend**: Business logic, data access, API contracts
2. **Frontend**: Components, state management, UI patterns
3. **Security**: OWASP Top 10, secrets, auth/authorization

### Report Format

```markdown
# Review Report - {timestamp}

## Summary
- Files reviewed: {count}
- Findings: {high} high, {medium} medium, {low} low

## High Priority
1. [{confidence}] {finding}

## Suggestions
1. {suggestion}
```
