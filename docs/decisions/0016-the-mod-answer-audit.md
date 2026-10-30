# ADR-0016: The mod answer audit

**Status:** Accepted
**Date:** 2026-10-30
**Amends:** ADR-0012 (the person decides only in the question dialog), ADR-0013

## Context

Some CLI calls are the person's alone: leaving a stage, an override, a confirmation, accepting a covered task, opening a
small-change window, choosing a branch, answering the Context check. The mod lets such a call through only as the call a
person's answer maps to. The list of those calls grew by hand with each feature, and a call that was reachable from no
question, or from a question the view no longer held, went unnoticed.

## Decision

1. **Every person-only call is reachable only from the question `view.json` holds.** The mod counts an answer only when the
   header, the question and the label match what the CLI wrote for the step and run the view names, and only while the view still
   asks it.
2. **A test walks every question of every view fixture.** It answers each option through the mod's answer code and checks each
   call of the option against the mod's rule, so a new person-only call without a question fails the suite. A table maps each
   kind (plan review, task accept, task confirm, state set branch, adhoc open, overrides) to the question that allows it.
3. **A typed answer maps to a call with that text, quoted.** A subagent's question, and a question with prefilled answers, count
   for nothing.
4. **The mod still runs nothing and sets nothing.** It allows or refuses a call; it never makes one.

## Consequences

- A feature that adds a person-only call also adds its question to the fixtures and a row to the table, in the same change.
- The guard is not a sandbox (`docs/trust.md`): it stops a model from deciding for the person, not a person from running a call
  in a terminal.
