---
name: grill-me
description: "Socratic challenge mode — stress-test plans and designs with adversarial questions, one at a time"
---

# Grill Me

Interview the user relentlessly about a plan or design until reaching shared understanding. Walk down each branch of the decision tree, resolving dependencies between decisions one-by-one.

**This is NOT the walkthrough.** The walkthrough *explains* the plan. Grill Me *challenges* it.

| Property | Walkthrough | Grill Me |
|----------|-------------|----------|
| Purpose | Explain the plan to the user | Challenge the plan's assumptions |
| Direction | Temper → User (teaching) | Temper ↔ User (adversarial) |
| Questions | "Does this make sense?" | "What happens if X fails?" |
| Outcome | User understands plan | User discovers weaknesses |
| Mode | Sequential section presentation | One hard question at a time |

## Algorithm

### 1. Extract Claims

Read the plan/design document. Extract:

- **Claims** — explicit assertions ("This handles all error cases", "This is backward-compatible")
- **Assumptions** — unstated beliefs ("Users will have X", "External service is fast")
- **Dependencies** — things that must be true for the plan to work
- **Decisions** — architectural choices made (and alternatives rejected)
- **Gaps** — things not mentioned that should be

### 2. Generate Challenge Questions

For each extracted item, generate challenge questions targeting:

| Target | Question Pattern |
|--------|-----------------|
| Unstated assumptions | "What happens if {assumption} is false?" |
| Missing error paths | "What does {component} do when {dependency} fails?" |
| Alternatives not considered | "Why {this approach} instead of {alternative}?" |
| Scalability limits | "What happens at 10x/100x current {metric}?" |
| Dependency risks | "If {dependency} changes/breaks, what's the impact?" |
| Edge cases | "What about {edge case}?" |
| Hidden complexity | "What's the hardest part of implementing {this}?" |
| Success criteria gaps | "How would you verify {claim} actually works?" |
| Cross-cutting concerns | "How does this interact with {existing system}?" |
| Rollback | "If this fails in production, how do you roll back?" |

### 3. Present ONE Question at a Time

**CRITICAL:** Never ask multiple questions. One question, wait for response.

```
AskUserQuestion:
  question: "{challenge question}"
  options:
    - label: "Answer"
      description: "Provide your answer or reasoning."
    - label: "Update plan"
      description: "I want to revise the plan based on this question."
    - label: "Skip"
      description: "Skip this question, move to next."
    - label: "Done grilling"
      description: "End the session and return to the gate."
  multiSelect: false
```

### 4. Analyze Response

After each answer:

1. **If the answer reveals a weakness:** Note it as a finding. Offer to update the plan.
2. **If the answer is solid:** Acknowledge it, move to next question.
3. **If the answer raises new questions:** Ask a follow-up (still one at a time).
4. **If the user chooses "Update plan":** Apply the change to the plan/design file, then continue grilling.

### 5. Loop Until Done

Continue until:
- User types "Done grilling" or selects "Done grilling" option
- Maximum 10 questions reached
- 3 consecutive answers that reveal no weaknesses (the plan is solid)

### 6. Summary

After the loop ends:

```
GRILL ME — Summary
  Questions asked: {N}
  Weaknesses found: {N}
  Plan updates made: {N}

  Weaknesses:
    1. {description} — {how it was addressed}
    2. {description} — {still open}

  Plan updated: Yes/No
  Returning to {stage} gate...
```

## Integration with Temper

This skill is invoked from the Plan and Design stage gates in the `/temper` unified command. When the user selects "Grill Me" at a gate, the orchestrator invokes this skill with the current plan.md or design.md as input.

After the grill session ends, the user returns to the original stage gate (Plan or Design). If the plan was updated during grilling, the gate shows the updated summary.
