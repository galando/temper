# Intent: {Feature Name}

**Author:** {the name the person gave, else: the person}
**Status:** {draft | accepted | completed}
**Created:** {date}
**Ticket:** {JIRA-XXX or #XXX or !XXX if linked}
**Complexity:** {trivial/simple/medium/complex}

---

## Intent (IDD)

### Problem

{Who is affected, current → desired behavior with one concrete example, why it
matters. Separate facts (measured, linked, stated) from assumptions (inferred).}

### Success Criteria

{Every criterion has a stable AC-NN id — never renumber. A dropped criterion moves
to ### Decisions, it is never deleted silently.}

- [ ] AC-01 [required]: {specific, measurable criterion} (source: {doc} §{section} | {TICKET})
  Why: {which business outcome, risk, or workflow this criterion serves}
  Validate: {scenario | code | metric | manual} — {details}
- [ ] AC-02 [optional]: {criterion} (proposed)
  Why: {which business outcome, risk, or workflow this criterion serves}
  Validate: manual — {details}
  Deferred: {reason and decision point}

### Constraints

{Each marked with where it came from — a source or a proposal.}

- {constraint 1} (source: {doc} §{section} | {TICKET})
- {constraint 2} (proposed)

### Scope and Non-goals

- In scope: {what this change touches}
- Out of scope: {what it explicitly does not touch}
- Must keep working: {existing behavior this must not break}

### Open Questions

{Each bullet labeled Blocking or Deferred. A question answered moves to
### Decisions and leaves this section — the two never hold the same question.}

- Blocking: {question, concrete} choices: {recommended answer} | {other answer} | {other answer}
- Deferred: {question}; consequence: {effect}; why work can proceed: {reason}; needed by: {when}.

### Assumptions

{What the intent assumes for the rules nobody was asked about (agents/intent.md, the rules checklist), one line each,
so the person can scan and correct them at the Intent gate.}

- {what is assumed} (because {why})

### Rules covered

{One line per item of the rules checklist (agents/intent.md): asked, assumed or not applicable. The Intent gate fails
a draft that leaves one out.}

- Who: {asked | assumed | not applicable} ({which question, or why})
- When: {asked | assumed | not applicable}
- How much: {asked | assumed | not applicable}
- Exempt: {asked | assumed | not applicable}
- States: {asked | assumed | not applicable}
- Where it shows: {asked | assumed | not applicable}
- Exceptions: {asked | assumed | not applicable} ({which: excluded, twice, at the edge, gone, someone else's, halfway})

### Decisions

{One row per question a human answered, written the moment the answer arrives.
This is the only record that survives a session: the Intent stage runs in a clean
context and reads only this file, so an answer not written here gets asked again.}

- {question} -> {answer} ({who decided}, {date})
- {a fact of the project, looked up} -> as the project holds it ({file}:{line})

---

## Scenarios (BDD)

{Ships empty. Plan writes one fenced ```gherkin block of four lines per scenario: the Scenario: line, one Then line
(the result its test checks), Covers: AC-NN and Test:. Test: is a scoped shell command that proves the scenario on the
merged tree and names the test the plan's task writes (for example `Test: pytest unit/test_cli.py::test_color -q`).
Do NOT write placeholder Scenario: blocks here: the check gate demands a passing test for every Scenario: line and
cannot tell a placeholder from a real one.}

## Source Traceability

### Context Sources

{Every source the request linked, recorded at capture time.}

- consulted: {source} — {what it contributed} ({retrieved date})
- unavailable: {source} — {why}
- none: description only — nothing linked
