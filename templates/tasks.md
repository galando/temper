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
**Cases:**
- `parse "a,b"` returns two items, `a` and `b`
- an empty input returns no items
- an unclosed quote fails with the message `unclosed quote`
**Traced to:** Scenario: "scenario name"
- [ ] done

### Task 2: {description}
**File:** `src/report.sh`, `tests/report_test.sh`
**Depends:** Task 1
**Test:** `bash tests/report_test.sh`
**Cases:**
- one parsed item prints one report line
- no items prints `nothing to report` and exits 0
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
**Cases:**
- `cli --help` prints the usage and exits 0
- an unknown flag prints the usage and exits 2
**Traced to:** Infrastructure: required by G1
- [ ] done
<!-- grouped-example:end -->
