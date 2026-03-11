---
title: Why Temper?
nav_order: 2
---

# Why Temper?

{: .fs-9 }

The question we hear most often:
{: .fs-6 .fw-300 }

> "Why not just tell Claude to be careful?"

---

## The Honest Answer

You can. And it helps. But it's not enough.

AI-generated code has **specific failure patterns** that "be careful" doesn't catch:

| Pattern | What happens | Why "be careful" misses it |
|---------|--------------|---------------------------|
| **Hallucinated APIs** | Method calls that don't exist | The AI is confident they do exist |
| **Over-engineering** | Unnecessary abstractions, premature generalization | Looks like "good design" |
| **Copy-paste drift** | Similar code blocks with subtle inconsistencies | Each block looks correct in isolation |
| **Incomplete error paths** | Happy path works, errors are placeholder | Hard to notice without explicit testing |
| **Missing integration** | New code not wired into routing/DI/config | The code itself is correct |
| **Stale patterns** | Using deprecated APIs when project migrated | AI trained on older examples |

These aren't sloppiness. They're **structural limitations** of how LLMs generate code.

## The Three Approaches

| | **AI Solo** | **AI + Temper** | **Traditional Review** |
|---|-------------|-----------------|------------------------|
| **Blast radius analysis** | None | ✅ Maps affected files, dependencies | Manual (error-prone) |
| **Test-first enforcement** | Hope AI remembers | ✅ RED-GREEN-REFACTOR gates | Code review comments |
| **Performance patterns** | Maybe catches obvious | ✅ N+1, unbounded results, sync I/O | Manual inspection |
| **Confidence scoring** | All findings equal | ✅ Filters by confidence threshold | Reviewer judgment |
| **False positive handling** | None | ✅ Review memory suppresses noise | Reviewer fatigue |
| **AI-specific patterns** | ❌ | ✅ Hallucinated APIs, over-engineering | ❌ |
| **Learning over time** | ❌ | ✅ Pattern detection, rule suggestions | ❌ |
| **Context footprint** | N/A | ~2KB always-on | Human reviewer time |

## Value by Audience

### Solo Developers

**The problem:** You ship fast. AI helps you ship faster. But bugs slip through, and you're the only one catching them.

**What Temper gives you:**
- **Confidence** that your AI-generated code actually works
- **Time back** from manual review and debugging
- **Learning** that adapts to your codebase patterns

```
Before: AI writes code → you manually test → bugs in production
After:  AI plans → tests first → implements → self-reviews → you ship
```

### Teams

**The problem:** Multiple developers + AI assistants = inconsistent patterns, knowledge silos, review bottlenecks.

**What Temper gives you:**
- **Shared standards** enforced automatically via custom packs
- **Consistent quality** regardless of who wrote the prompt
- **Hotspot tracking** to identify files that need attention
- **Learning loop** that captures team patterns

```
Before: Review backlog grows → reviewers get tired → issues slip through
After:  AI self-reviews → only high-confidence issues reach humans → faster reviews
```

### Organizations

**The problem:** Scaling AI adoption across teams requires governance, consistency, and measurable quality.

**What Temper gives you:**
- **Audit trail** — every plan, review, and fix is logged
- **Compliance** — BLOCK rules enforce organizational standards
- **Metrics** — coverage trends, issue density, learning progress
- **Debt tracking** — know where technical debt is accumulating

```
Before: AI adoption is chaotic → quality varies by team → leadership is nervous
After:  Consistent guardrails → measurable quality → confident scaling
```

## Real Findings Examples

Here's what Temper catches that a careful prompt can't:

### 1. N+1 Query in a Loop

```java
// The AI wrote this. Looks fine. But...
for (Order order : orders) {
    order.setCustomer(customerRepository.findById(order.getCustomerId()));
}
```

**What Temper catches:** "Loop making database call inside iteration. N+1 query pattern detected."

**Why "be careful" misses it:** The code is syntactically correct and handles the happy path. The performance issue only appears under load.

### 2. Hallucinated API

```typescript
// The AI thought this method existed. It doesn't.
const user = await UserService.fetchByEmail(email);
```

**What Temper catches:** "Method `fetchByEmail` not found in `UserService`. Available methods: `findById`, `findByUsername`, `list`."

**Why "be careful" misses it:** The AI is confident the method exists. Only validation against the actual codebase catches this.

### 3. Over-Engineering

```typescript
// The AI created a factory for something used exactly once
class UserValidatorFactory {
  create(): UserValidator { return new UserValidator(); }
}
```

**What Temper catches:** "Factory pattern for single-use class. Consider direct instantiation."

**Why "be careful" misses it:** The code follows "good design patterns." But patterns applied blindly become anti-patterns.

### 4. Missing Integration

```typescript
// New route handler exists, but never added to router
app.get('/users/:id', getUserHandler);  // Forgot to add this
```

**What Temper catches:** "Handler `getUserHandler` defined but not registered in routing."

**Why "be careful" misses it:** The code itself is correct. The bug is in the wiring.

## The Bottom Line

Temper isn't about making the AI "careful." It's about **structural guardrails** that catch the specific failure patterns of AI-generated code.

- **Blast radius analysis** ensures changes are understood before coding
- **TDD gates** ensure tests exist and pass before proceeding
- **Confidence scoring** separates signal from noise
- **Review memory** learns your codebase patterns
- **Hotspot tracking** shows where problems accumulate
- **Custom packs** let you encode team-specific standards that the AI automatically follows

The result: AI-generated code that's actually ready to ship.

---

## Next Steps

- [Getting Started Guide](getting-started) — Install and run your first check
- [Commands Reference](commands) — Full command documentation
- [Packs](packs) — Built-in and custom quality packs
