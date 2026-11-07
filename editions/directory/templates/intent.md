# Intent: {Feature Name}

**Author:** {the name the person gave, else: the person}
**Status:** {draft | accepted | completed}
**Created:** {date}
**Ticket:** {JIRA-XXX or #XXX, if one was linked}
**Reviewer:** {a name, only when the request names one}
**Complexity:** {trivial | simple | medium | complex}

---

## Intent (IDD)

### Problem

{Who is affected, current behavior and desired behavior with one concrete example, why it
matters. Keep facts (measured, linked, stated) apart from assumptions (inferred).}

### Success Criteria

{Every criterion has a stable AC-NN id; never renumber. A dropped criterion moves to
Decisions with the reason; it is never deleted silently.}

- [ ] AC-01 [required]: {specific, measurable criterion} (source: {doc or ticket})
  Why: {which business outcome, risk, or workflow this criterion serves}
  Validate: {scenario | code | metric | manual}: {details}
- [ ] AC-02 [optional]: {criterion} (proposed)
  Why: {which business outcome, risk, or workflow this criterion serves}
  Validate: manual: {details}

### Constraints

- {constraint} (source: {doc or ticket})
- {constraint} (proposed)

### Scope and Non-goals

- In scope: {what this change touches}
- Out of scope: {what it does not touch}
- Must keep working: {existing behavior this must not break}

### Target Users

- {user}: {what they do with this} → {what happens next}

### Open Questions

{Each bullet is labeled Blocking or Deferred. An answered question moves to Decisions.}

- Blocking: {concrete question} choices: {recommended answer} | {other answer} | {other answer}
- Deferred: {question}; consequence: {effect}; why work can go on: {reason}; needed by: {when}.

### Assumptions

- {what is assumed} (because {why})

### Rules covered

- Who: {asked | assumed | not applicable} ({which question, or why})
- When: {asked | assumed | not applicable}
- How much: {asked | assumed | not applicable}
- Exempt: {asked | assumed | not applicable}
- States: {asked | assumed | not applicable}
- Where it shows: {asked | assumed | not applicable}
- Exceptions: {asked | assumed | not applicable} ({which: twice, at the edge, gone, someone else's, halfway})

### Decisions

{One row per question a person answered, written the moment the answer arrives. Stage
agents start with a clean context and read only this file, so an answer not written here
is asked again.}

- {question} -> {answer} ({who decided}, {date})

---

## Scenarios (BDD)

{Empty until Plan fills it. Never write a placeholder Scenario block here: the Check
checklist needs a passing test for every Scenario line.}

## Scenario Coverage Checklist

{Empty until Check fills it: one `- [x] {Scenario} -> {test name}` line per verified scenario.}

## Source Traceability

### Context Sources

- consulted: {source}: {what it contributed} ({retrieved date})
- unavailable: {source}: {why}
- none: description only, nothing linked
