---
name: grill-me
description: "Socratic challenge mode: stress-test plans and designs with adversarial questions, asked in rounds"
---

# Grill Me

Interview the user about a plan or design until you reach a shared understanding. Walk down each branch of the decision
tree, settling the decisions others depend on first.

> **Credit:** adapted from Matt's [Grill Me skill](https://www.aihero.dev/skills-grill-me) (AI Hero), with thanks.

**This is NOT the walkthrough.** The walkthrough *explains* the plan. Grill Me *challenges* it.

| Property | Walkthrough | Grill Me |
|----------|-------------|----------|
| Purpose | Explain the plan to the user | Challenge the plan's assumptions |
| Direction | Temper → User (teaching) | Temper ↔ User (adversarial) |
| Outcome | User understands plan | User discovers weaknesses |
| Mode | Sequential section presentation | Rounds of up to four hard questions |

## Algorithm

### 1. Extract Claims

Read the plan or design. Extract the **claims** it makes, the **assumptions** it leaves unstated, the **dependencies**
that must hold, the **decisions** it took (and the alternatives it rejected), and the **gaps**: what it should mention
and does not.

### 2. Generate Challenge Questions

| Target | Question Pattern |
|--------|-----------------|
| Unstated assumptions | "What happens if {assumption} is false?" |
| Missing error paths | "What does {component} do when {dependency} fails?" |
| Alternatives not considered | "Why {this approach} instead of {alternative}?" |
| Scalability limits | "What happens at 10x/100x current {metric}?" |
| Edge cases | "What about {edge case}?" |
| Success criteria gaps | "How would you verify {claim} actually works?" |
| Rollback | "If this fails in production, how do you roll back?" |

A fact about the project (a caller, a version, what a file holds) is looked up in the code, never asked.

### 3. Ask in Rounds

A round is one `AskUserQuestion` call with up to 4 questions (the tool takes no more). A question enters a round only
when every decision it depends on is settled; one that depends on an open answer waits for the next round.

Each question carries two or three concrete answers, and the first option is the recommended answer: the one you would
pick, marked `(Recommended)`. The person can always write their own answer instead.

```
AskUserQuestion:
  questions:
    - question: "{challenge question}"
      options:
        - label: "{the answer you would pick} (Recommended)"
          description: "{what it settles, and what it costs}"
        - label: "{another concrete answer}"
          description: "{what it settles, and what it costs}"
      multiSelect: false
    - ...up to 4 questions in all
```

`Update plan` and `Done grilling` stay in reach in every round: a round of up to three questions adds a last one,
"Next?", with the options `Next round`, `Update plan` and `Done grilling`; in a round of four the person writes either
as the own answer of any question.

### 4. Analyze the Round

For each answer of the round:

1. **It reveals a weakness:** note it as a finding and offer to update the plan.
2. **It is solid:** acknowledge it.
3. **It raises a new question:** put it in the next round.
4. **The user chose `Update plan`:** apply the change to the plan or design file, then go on with the next round.

A question the person skipped in a round is not asked again in the same session; the summary lists it as still open.

### 5. Loop Until Done

Continue until the user chooses `Done grilling`, or 10 questions have been asked, in at most 4 rounds, or a round
revealed no weakness (the plan is solid).

### 6. Summary

```
GRILL ME — Summary
  Questions asked: {N} in {R} rounds
  Weaknesses found: {N}
  Plan updates made: {N}

  Weaknesses:
    1. {description} — {how it was addressed}
    2. {description} — {still open}

  Skipped, still open:
    - {question}

  Plan updated: Yes/No
  Returning to {stage} gate...
```

## Integration with Temper

The gates of `/temper` offer Grill Me; when the user picks it, the orchestrator invokes this skill with the stage's
file as input. When the session ends, the user returns to the same gate, and a plan updated during the session shows
in the gate's summary.
