# Check: Stack-Aware Validation

**Goal:** run the project's real validation and record what happened. Never estimate a
result; a number nobody measured is not a result.

## Step 1: Detect the stack

1. `.claude/temper.config`: `check.commands.test`, `check.commands.lint` and
   `check.commands.typecheck` replace detection for their level when set; `stack` names it.
2. Otherwise detect:

| Manifest | Stack | test / lint / types / build |
|---|---|---|
| `pom.xml`, `build.gradle` | Java | `mvn verify` with JaCoCo / none / none / `mvn package` |
| `package.json` | Node | scripts.test / scripts.lint / `tsc --noEmit` / scripts.build |
| `pyproject.toml`, `setup.py` | Python | `pytest --cov` / `ruff check .` / `mypy .` / none |
| `go.mod` | Go | `go test -cover ./...` / `golangci-lint run` / none / `go build ./...` |
| `Cargo.toml` | Rust | `cargo test` / `cargo clippy` / none / `cargo build` |

## Step 2: Levels, in order

A BLOCK failure stops the levels after it; a WARN failure is reported and the levels go on. A
level whose optional tool is missing is skipped and named, never failed.

| # | Level | On failure | Skip when |
|---|---|---|---|
| 0 | Environment: the top folder holds a file named `.env.production` or `.env.prod`, or `check.environment` is `production`. Never open a `.env` file. | stop and name it | `check.environment` is set to anything else |
| 1 | Compile or build | BLOCK | never |
| 2 | Tests, with coverage on in the same run | BLOCK | never |
| 3 | Coverage against `check.coverage-threshold` (default 80) | the checklist fails | never; with no coverage tool it fails until the tool is installed |
| 4 | Scenario verification (below) | BLOCK on a failing test, WARN on a missing one | no scenarios |
| 5 | Test gaps: per changed function, STRONG, WEAK (name the missing cases) or NO TEST | WARN; BLOCK for security code with no test | level 2 failed |
| 6 | API contract diff for changed routes and types | WARN; BLOCK when breaking with a consumer not updated | no API files changed |
| 7 | Lint | WARN | no linter |
| 8 | Type check | WARN | not applicable |
| 9 | Security: dependency audit (`npm audit`, `pip-audit`, ...) and semgrep when connected | WARN for medium, BLOCK for a critical CVE | no scanner |

Run the suite **once**, with coverage on in that run when the stack allows it (pytest `--cov`,
jest `--coverage`, JaCoCo with `mvn verify`). Write coverage output under `.temper/check/`.
Wait for every run in the foreground.

## Level 4: scenario verification

1. Take every `Scenario:` of `intent.md` with its `Test:` command.
2. Run each `Test:` command on its own and record a `scenario` row in `evidence.md`.
3. A scenario with no `Test:` line: grep the tests for its name; run the match. No match:
   record it as missing; never pass it silently.
4. Fill `intent.md`'s Scenario Coverage Checklist: `- [x] {Scenario} -> {test}` per passing
   scenario.

## Criteria

For each `[required]` criterion: `scenario` passes from its scenarios' rows; `code` passes from
a grep you ran and recorded; `metric` is deferred to after release and said so; `manual` waits
for the person to confirm it at the Check question. Never record a manual criterion yourself.

## Missing tools

When the tool for the tests or for coverage is missing, say which, point to its own install
page (never print an install command to run), and record nothing. The Coverage row fails, and
the Check question offers "Run Check again"; the person installs the tool and picks it. Nobody
types a number in by hand.

## Error interpretation

- Compile: read the whole error; the first one usually causes the rest. Name `file:line`.
- Test failure: a new test failing means unfinished work; an existing test failing is a
  regression, so name the likely change.
- Coverage: name the uncovered files and functions; never suggest a trivial test to move the
  number.
- Security: name the CVE, the severity and the dependency; suggest the version that fixes it.

## Writing check.md

Use the shape in `reference/run-state.md`: one row per level that ran, the scenario trace, the
criteria. For each test failure in new code, write a fix entry (test name, error, `file:line`,
the scenario it maps to): the fix pass reads them when the person loops back to Build.
