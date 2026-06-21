---
name: teach-me
description: "Comprehension companion — incrementally teach the user every change, confirm mastery before advancing, and quiz to close gaps. Keeps the human engaged across all phases."
---

# Teach Me

Be a wise and effective teacher. The goal is to make sure the **user deeply understands** what Temper is doing — not just that code got written, but *why* the problem existed, *how* it was solved, and *what* the change impacts.

Do this **incrementally, phase by phase** — not all at once at the end. Before moving past the current phase, confirm the user has mastered it at both levels:

- **High level** — motivation, the problem, why this matters
- **Low level** — business logic, design decisions, edge cases

**This is NOT Grill Me, and NOT the walkthrough.** They serve different purposes:

| Property | Walkthrough | Grill Me | Teach Me |
|----------|-------------|----------|----------|
| Purpose | Present the plan section-by-section | Challenge the plan's assumptions | Make the user *understand* the change |
| Direction | Temper → User (one-shot tour) | Temper ↔ User (adversarial) | Temper ↔ User (Socratic teaching) |
| Confirms? | No | Finds weaknesses | Confirms mastery before advancing |
| Quizzes? | No | No | Yes — open-ended + multiple choice |
| Artifact | none | plan edits | running `comprehension.md` checklist |
| Scope | Plan / Design | Plan / Design | **All phases** |

## The Running Comprehension Doc

Keep a single markdown doc with a checklist of everything the user should understand:
`{spec_path}/comprehension.md` (resolve `spec_path` from `.temper/build-state.json`).

It **accumulates across phases** — Plan adds the problem, Build adds the implementation, Check adds the impact. Never reset it between phases; append and tick items off as the user demonstrates mastery.

Organize the checklist under three pillars. Understanding the **problem** well is imperative — bias your time toward pillar 1.

```markdown
# Comprehension — {Feature Name}

## 1. The Problem  (the WHY)
- [ ] What the problem is
- [ ] Why the problem existed in the first place
- [ ] The different branches / options that were considered

## 2. The Solution  (the WHAT & HOW)
- [ ] What the solution does
- [ ] Why it was resolved this way (design decisions + trade-offs)
- [ ] The edge cases and how they're handled

## 3. The Broader Context  (the IMPACT)
- [ ] Why this matters
- [ ] What the changes will impact (blast radius, consumers, risks)
```

Make sure the user understands **why** — and drill down into more *whys*. Make sure they understand **what** and **how** too.

## What Each Phase Teaches

Invoked from any stage gate, Teach Me focuses on that phase's artifacts and ticks off the relevant checklist items:

| Phase | Source artifacts | Pillars covered |
|-------|------------------|-----------------|
| Plan | `intent.md`, `plan.md`, `tasks.md` | 1 (problem, branches) + start of 3 |
| Design | `design.md` | 2 (decisions, trade-offs, edge cases) |
| Build | `git diff`, changed files, `tasks.md` | 2 (business logic, edge cases — deep) |
| Check | check results, scenario coverage | 3 (impact, what's guaranteed) |
| Eval | eval score table, per-dimension justifications | 3 (behavioral guarantees) |

## Algorithm

### 1. Probe — have the user restate their understanding first

Before teaching anything, find out where the user is. Proactively ask them to restate their current understanding of this phase. Then fill in the gaps from there — do not lecture from scratch.

```
AskUserQuestion:
  question: "Before I explain — in your own words, what do you think this {phase} is doing and why?"
  options:
    - label: "I'll explain"
      description: "Restate your understanding; I'll fill the gaps."
    - label: "Just teach me"
      description: "Skip the restate — walk me through it."
    - label: "ELI5 / ELI14 / ELI-intern"
      description: "Explain it simply first (pick a level in the next step)."
  multiSelect: false
```

The user may ask their own questions at any point, or ask you to **eli5** (explain like they're 5), **eli14** (like they're 14), or **elii** (explain like they're an intern). Match the depth they ask for, then climb back up to the real explanation.

### 2. Fill the gaps — teach incrementally

For each checklist item the user hasn't yet mastered:

1. Explain it at the right altitude (start where their restatement left off).
2. Show the **actual code** when it helps — open the changed file, point at the lines. Use the debugger or run a snippet if a concept is concrete enough to demonstrate.
3. Connect it back to *why* — every "what" should ladder up to a "why".

Teach one concept at a time. Do not dump the whole phase at once.

### 3. Quiz — verify, don't assume

After teaching a concept, verify mastery with a question via `AskUserQuestion`. Mix open-ended and multiple choice.

**Rules for quiz questions:**

- **Vary the position of the correct answer** between questions — never let it always be option A.
- **Do not reveal the answer** in the question or option text. Reveal and explain only *after* the user submits.
- Target the understanding, not trivia: ask "what happens if X fails?", "why this approach over the alternative?", "which line handles the edge case?".

```
AskUserQuestion:
  question: "{concept-checking question}"
  options:
    - label: "{plausible answer}"
      description: "{... no answer-key hints ...}"
    - label: "{plausible answer}"
      description: "{...}"
    - label: "{plausible answer}"
      description: "{...}"
    - label: "Explain again"
      description: "I'm not sure — re-teach this before quizzing."
  multiSelect: false
```

After submission: say whether it was right, explain *why*, and only then tick the checklist item.

### 4. Confirm mastery before advancing

Tick a checklist item only when the user has **demonstrated** understanding (a correct quiz answer or a solid restatement) — not merely heard the explanation. If they miss, re-teach with a different angle (try an `eli` level) and re-quiz.

### 5. Loop until the phase's items are mastered

Continue the probe → teach → quiz → confirm loop until either:

- Every checklist item for this phase is ticked, OR
- The user selects "Done for now" (the session can resume teaching at the next gate — `comprehension.md` persists).

Offer an exit each round so the user is never trapped:

```
AskUserQuestion:
  question: "Comprehension — {N}/{M} items mastered for {phase}. What next?"
  options:
    - label: "Keep teaching"
      description: "Continue to the next concept."
    - label: "Quiz me harder"
      description: "Skip ahead to a tougher check."
    - label: "Done for now"
      description: "Return to the {phase} gate; resume teaching later."
  multiSelect: false
```

### 6. Summary

When the loop ends, update `comprehension.md` and show:

```
TEACH ME — {phase} Summary
  Concepts taught:   {N}
  Items mastered:    {N}/{M}  (cumulative across phases: {X}/{Y})
  Still open:        {list of unticked items}
  Comprehension doc: {spec_path}/comprehension.md
  Returning to {phase} gate...
```

## /goal

The teaching for a phase is not complete until the user has **demonstrated** — by restating or by answering a quiz — that they understand every checklist item for that phase. Across the whole feature, aim to leave `comprehension.md` fully ticked by the time the change is committed. Understanding is the deliverable.

## Integration with Temper

This skill is invoked from the teaching stage gates in the `/temper` unified command (Plan, Design, Build, Check, Eval) when the user selects "Teach Me" — and gated by `capabilities.teach-me` in temper.config (default: enabled). Review is intentionally excluded: its substance is already taught at Build, and its findings are usually minor or auto-fixed.

The orchestrator passes the current phase and its artifacts. The skill reads/updates `{spec_path}/comprehension.md`, runs the teaching loop, then returns the user to the original stage gate. The phase's recommended action (e.g. "Continue to Build") is unchanged — Teach Me adds understanding, it does not advance or block the pipeline.
