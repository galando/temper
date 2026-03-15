# Tasks: {Feature Name}

## Prerequisites

- [ ] Read {file1}
- [ ] Read {file2}

## Tasks

### Task 1: {description} [SEQUENTIAL]

**Action:** CREATE / MODIFY
**File:** {file path}
**Traced to:** Scenario: "scenario name"
**Test:** {test file path}
**Validate:** `{bash command}`
**Notes:** {gotchas, patterns to follow}

### Task 2: {description} [SEQUENTIAL: after Task 1]

**Action:** CREATE / MODIFY
**File:** {file path}
**Traced to:** Scenario: "name1", "name2" | Infrastructure: required by {module}
**Test:** {test file path}
**Validate:** `{bash command}`
