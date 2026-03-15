# Intent: {Feature Name}

**Created:** {date}
**Ticket:** {JIRA-XXX or #XXX if linked}
**Complexity:** {trivial/simple/medium/complex}

---

## Intent (IDD)

### Problem

{What problem are we solving? For whom? Why is this needed?}

### Success Criteria

{Measurable outcomes - not just "tests pass"}

- [ ] {criterion 1: specific, measurable}
  Validate: {scenario | code | metric | manual} — {details}
- [ ] {criterion 2: specific, measurable}
  Validate: {scenario | code | metric | manual} — {details}
- [ ] {criterion 3: specific, measurable}
  Validate: {scenario | code | metric | manual} — {details}

### Constraints

{Technical or business limitations that must be respected}

- {constraint 1}
- {constraint 2}

### Target Users

{Who benefits from this feature?}

- {user type 1}: {how they benefit}
- {user type 2}: {how they benefit}

---

## Scenarios (BDD)

### Feature: {Feature Name}

#### Happy Path

```gherkin
Scenario: {scenario name}
  Given {initial context/preconditions}
  When {action taken}
  Then {expected outcome}
  Note: {testing approach - unit/integration/mock/manual}
```

```gherkin
Scenario: {scenario name}
  Given {initial context/preconditions}
  When {action taken}
  Then {expected outcome}
  Note: {testing approach - unit/integration/mock/manual}
```

#### Error Paths

```gherkin
Scenario: {error scenario name}
  Given {initial context/preconditions}
  When {action that triggers error}
  Then {expected error handling}
  Note: {testing approach - unit/integration/mock/manual}
```

#### Edge Cases

```gherkin
Scenario: {edge case name}
  Given {unusual but valid preconditions}
  When {action taken}
  Then {expected outcome}
  Note: {testing approach - unit/integration/mock/manual}
```

---

## Scenario Coverage Checklist

After implementation, verify each scenario has a passing test:

- [ ] {Scenario 1} → {test name}
- [ ] {Scenario 2} → {test name}
- [ ] {Scenario 3} → {test name}
