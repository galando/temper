---
phases: [build, review, check, fix]
---

# TDD Pack

**Version:** 2.0.0
**Last Updated:** 2026-08-03

## Mandatory Rules (BLOCK if violated)
- Every new function/method must have a corresponding test
- Tests must be written BEFORE implementation (RED → GREEN → REFACTOR)
- Test names must describe the scenario being tested

## Quality Rules (WARN if violated)
- Tests should follow Given-When-Then structure
- Each test should verify one behavior
- Tests should be independent (no shared state between tests)
- Tests should be fast (unit tests < 100ms each)
- Mock external dependencies (APIs, databases, file system)

## Conventions (SUGGEST improvements)
- Use descriptive test names: `methodName_scenario_expectedResult`
- Group related tests in describe/context blocks
- Use test fixtures for complex setup

## TDD Workflow

**RED** — write the test first and watch it fail. Cover the happy path and at least one
error case. A test that passes before the implementation exists is a broken test, not a
head start: investigate it rather than proceeding. The RED run is recorded as gate
evidence (`temper evidence add`), so it has to actually happen.

**GREEN** — the minimal code that passes, in the shape the adjacent code already uses.
Extra utilities and speculative abstraction belong to a task that asked for them.

**REFACTOR** — only on green, only when the improvement is obvious and belongs to the
current task, and always re-run the full suite afterward.

## When intent.md Exists (Scenario-Driven TDD)

When `/temper:plan` generates an intent.md with Gherkin scenarios, the TDD cycle becomes scenario-driven:

| TDD Phase | Without intent.md | With intent.md |
|-----------|-------------------|----------------|
| **What to test** | Read task spec, identify public methods | Read Gherkin scenario from intent.md |
| **RED** | Write test for expected behavior | Write test mapped to scenario name |
| **GREEN** | Minimal implementation | Minimal implementation |
| **REFACTOR** | Clean up if safe | Clean up if safe |

The RED-GREEN-REFACTOR cycle is the same. The input changes:
- Test names reference the scenario name
- Given block becomes test setup
- When block becomes action under test
- Then block becomes assertions
- Scenario coverage gate enforces all scenarios have passing tests

Intent.md scenarios drive WHAT to test. TDD pack enforces HOW (discipline, conventions, structure).

## Test File Location by Stack

| Stack | Test Location | Naming Convention |
|-------|---------------|-------------------|
| Spring Boot | `src/test/java/{package}/` | `{Class}Test.java` |
| React/TS | Same dir or `__tests__/` | `{Component}.test.tsx` |
| Node/Jest | Same dir or `__tests__/` | `{module}.test.js` |
| Python/pytest | `tests/` | `test_{module}.py` |
| Go | Same package | `{file}_test.go` |
| Rust | Same dir or `tests/` | `#[test]` in source |
