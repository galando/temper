<!-- tasks.md is written in groups by default: Build runs each task as one slim task agent and gates once
per group. The block between the grouped-example markers is a complete example that passes `temper gate plan` (a selftest case runs
it). Details: reference/plan.md, "Grouped tasks". -->
<!-- grouped-example:begin -->
# Tasks: {Feature Name}

**Integration:** `{full suite command}`

## Group G1: {title}
**Depends:** none
**Validate:** `{group-level test command}`
**Interfaces:** `src/parser.sh` — `parse_main`
**Context:**
Only what a task agent in this group needs, in under 4096 bytes: the pack rules that
apply to this group (distilled; security rules always), the conventions to follow, the
interfaces it must keep. Not the whole plan.

### Task 1: {description}
**File:** `src/parser.sh`, `tests/parser_test.sh`
**Depends:** none
**Test:** `bash tests/parser_test.sh`
**Traced to:** Scenario: "scenario name"
- [ ] done

### Task 2: {description}
**File:** `src/report.sh`, `tests/report_test.sh`
**Depends:** Task 1
**Test:** `bash tests/report_test.sh`
**Traced to:** Scenario: "name1", "name2"
- [ ] done

## Group G2: {title}
**Depends:** G1
**Validate:** `{group-level test command}`
**Context:**
Distilled rules and conventions for G2.

### Task 3: {description}
**File:** `src/cli.sh`, `tests/cli_test.sh`
**Depends:** none
**Test:** `bash tests/cli_test.sh`
**Traced to:** Infrastructure: required by G1
- [ ] done
<!-- grouped-example:end -->

<!-- Per-task layout: only with `build.mode: per-task` in .claude/temper.config (the previous Build, one task
per launch on the build model). Write it INSTEAD of the grouped format above. Every task keeps its own
`- [ ]` box: `temper gate build` counts unticked boxes, so a task without one is never waited for. -->
<!-- per-task-example:begin -->
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
- [ ] done

### Task 2: {description} [SEQUENTIAL: after Task 1]

**Action:** CREATE / MODIFY
**File:** {file path}
**Traced to:** Scenario: "name1", "name2" | Infrastructure: required by {module}
**Test:** {test file path}
**Validate:** `{bash command}`
- [ ] done
<!-- per-task-example:end -->
