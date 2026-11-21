---
description: "Run the project's validation pipeline (tests, build, lint, security)"
---

# Check: Stack-Aware Validation Pipeline

**Goal:** Run the project's real validation pipeline and record what happened — never
estimate a result. The check brief (`${CLAUDE_PLUGIN_ROOT}/agents/check.md`) carries the exact calls the gate needs
(`evidence run` for a test run; a coverage value recorded with `evidence add` is not read: coverage is what the CLI
measured); this doc is the methodology behind what to run and how to interpret it.

**Mode:** Check runs as a stage of `/temper`, in a clean subprocess with no `AskUserQuestion` gate:
return the summary, the orchestrator owns the gate and the commit. Load `.temper/specs/{feature}/review-context.json` if present.

## Step 1: Detect Stack

Detect the stack from the build file at the root: pom.xml Spring Boot, package.json Node, pyproject.toml Python, go.mod
Go, Cargo.toml Rust. A YAML preset file in the project's `.claude/presets` folder overrides auto-detected commands.

**Configured commands first.** Before using the table below, run
`${CLAUDE_PLUGIN_ROOT}/scripts/temper config get check.commands.test`, then the same call for
`check.commands.coverage`. A key that prints a command replaces the detected command for that level; a key that
prints nothing keeps stack detection.

| Manifest | Stack | test / lint / type / build |
|---|---|---|
| `pom.xml`/`build.gradle` | Java/Spring | `mvn(w) test` / — / — / `mvn(w) package` |
| `package.json` | Node | scripts.test / scripts.lint / `tsc --noEmit` / scripts.build |
| `pyproject.toml`/`setup.py` | Python | `pytest` / `ruff check .` / `mypy .` / `python -m build` |
| `go.mod` | Go | `go test ./...` / `golangci-lint run` / — / `go build ./...` |
| `Cargo.toml` | Rust | `cargo test` / `cargo clippy` / — / `cargo build` |

## Step 2: Validation Levels (in order; a BLOCK-level failure halts the pipeline)

WARN-level failures do not halt — continue to the next level and report at the end.
Skip a level cleanly (⏭️) when its tool isn't configured; never fail the pipeline for a
missing *optional* tool.

| # | Level | On failure | Skip when |
|---|---|---|---|
| 0 | Environment, decided from file names only: never open a `.env` file or read what one holds. It fails when the project's top folder holds a file named `.env.production` or `.env.prod` | STOP immediately; name the file name that stopped it, and say that renaming the file clears it when it is only a template | no such file name exists |
| 1 | Compile/build | STOP, show error, suggest fix | — |
| 2 | Unit tests | STOP, show failing names | — |
| 3 | Integration tests | STOP, show failing tests | none configured |
| 4 | Coverage, judged against the project (below) | the gate FAILs on a measured drop | never skipped: with no coverage tool the row is `not measured`, which fails nothing |
| 4.5 | **Scenario verification** — see below | BLOCK on FAIL, WARN on MISSING | no intent.md |
| 4.75 | Heuristic test-gap analysis | WARN | level 2 or 4.5 failed |
| 4.85 | API diff / contract check | WARN (BLOCK if breaking + consumer not updated) | no API files changed |
| 4.9 | Performance regression vs. baseline | BLOCK if >10% slower | no benchmarks configured |
| 5 | Lint/format | WARN | no linter |
| 6 | Type check | WARN | not applicable |
| 7 | Security (deps + SAST) | WARN medium / BLOCK critical CVE | no scanner |

### Level 4.5 — Scenario Verification (Live Execution)

This is the level that proves, per scenario, whether a real test exercises it — the
level that catches a scenario Build never implemented. It is the only level that
reads `intent.md` and checks behavior against what was promised.

1. Resolve `{spec}`: the `--spec-path` this run was given, else
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper state get spec_path`. Neither gives a spec path → SKIP
   this level entirely (never pick a spec folder by guessing).
2. Extract every `Scenario:` (name, its `Then` line and its `Test:` line) from `intent.md`.
3. Match each scenario to a test: the test its `Test:` line names → `[PROVEN]`; else MCP `query_graph_tool` by name
   annotation → `[PROVEN]`; else grep test files for the scenario name (snake_case/camelCase) → `[HEURISTIC]`; no match
   → UNMATCHED.
4. Run each matched test individually (`jest --testNamePattern`, `pytest ::test_name`,
   `mvn -Dtest=`, `go test -run`, `cargo test name --`, etc.) and capture PASS/FAIL/time
   — label `[PROVEN]`, real runner output.
5. Gate: FAIL → BLOCK. MISSING (no matching test) → WARN, but still name it — this is
   the exact gap `gate check`'s "scenarios traced to tests" requirement exists to catch;
   silently passing it defeats the whole level.
6. Optional: for security-critical scenarios that all pass, offer a 1-2 function mutation
   spot-check (flip one condition, confirm the test now fails, always restore the code).

### Levels 4.75 / 4.85 / 4.9 — heuristic depth checks (condensed)

All three are static analysis, not real mutation/contract/perf testing — say so in the
report, don't imply stronger guarantees than they give:

- **4.75 test-gap:** for each changed function with tests, classify STRONG (all
  branches/edges covered) / WEAK (happy-path only, name the missing cases: null,
  boundary, negative, empty, error path) / NO TEST. No test on security-critical code →
  BLOCK; zero coverage elsewhere → WARN. Write `.temper/test-gap-report.json`.
- **4.85 API diff:** for changed controller/route/DTO/shared-type files, diff old vs.
  new shape (ADDITIVE/MODIFIED/BREAKING), grep the tests, the frontend and the imports for consumers, and
  check whether each consumer was updated. Breaking + consumer not updated → BLOCK.
  Write `.temper/contract-map.json`.
- **4.9 performance:** run configured benchmarks, compare to
  `.temper/performance-baseline.json`. <5% slower: pass, update baseline. 5-10%: WARN.
  >10%: BLOCK, suggest investigation. >20% variance historically flaky → downgrade one
  level.

### Level 7 — Security

Dependency scan (`npm audit`, `pip-audit`, etc.) plus, if the semgrep MCP server is
available: `security_check` on changed files,
then `semgrep_scan_with_custom_rule` using the rules of the pack files your prompt lists on its `Packs:` line (the
CLI chose those of Check). Map error→CRITICAL(BLOCK), warning→HIGH(WARN), info→MEDIUM(WARN). SAST findings
bypass confidence filtering — always shown, labeled `[PROVEN]`. No semgrep → fall back to
the OWASP pattern-matching in `review.md` Step 2, labeled `[HEURISTIC]`.

## Step 3: Config Suggestions

If every level passed and files changed: generate up to 5 config suggestions
(confidence >= 0.6) comparing the diff against `CLAUDE.md`/`AGENTS.md`, write
`.temper/specs/{feature}/config-suggestions.json`, and show them at the Check gate for
Accept/Reject/Defer. Full methodology: `${CLAUDE_PLUGIN_ROOT}/reference/config-suggestions.md`. (They're
shown once at the gate — there's no separate re-offer queue.)

Every accepted suggestion is a permanent line in a file loaded on every future session,
so suggest one only when a *specific* thing went wrong that the config could have
prevented — not general good practice the model would apply anyway. If `CLAUDE.md` is
already long enough that you're hesitating, say so and suggest `/doctor` instead of
adding to it; see `${CLAUDE_PLUGIN_ROOT}/docs/context-hygiene.md`.

## Context Output

Write `check-context.json`:

```json
{
  "version": 1, "stage": "check", "timestamp": "{ISO timestamp}",
  "validation_results": { "compile": "pass|fail|skip", "tests": "pass|fail|skip",
    "coverage_pct": {N}, "lint": "pass|fail|skip", "security": "pass|fail|skip" },
  "scenario_verification": { "total": {N}, "passed": {N}, "failed": {N}, "missing": {N} },
  "test_failures": [ { "test_name": "", "error_message": "", "file": "", "line": 0,
    "scenario": "the intent.md scenario it maps to" } ]
}
```

## Feedback Loop to Build

When test failures exist in newly written code, write a targeted fix entry per failure
(test name, error, file:line, the `intent.md` scenario it maps to) to `check-context.json`.
A failed row of class `code` is repaired in the stage first (ADR 0021): the CLI's failed row is the
RED, a fresh Build agent fixes it, and the CLI commits it and runs the checks again. The CLI's Check
question then offers "Repair again" once, and "Loop back to Build" while the budget lasts; once it is
spent, it asks `run.budget`.

## Summary + Gate

The base summary box format is owned by the check brief (`${CLAUDE_PLUGIN_ROOT}/agents/check.md`) — render it, appending: a
Live Scenarios line (`{X}/{Y}: {P} pass / {F} fail / {M} missing`), Test Gaps / API
Diff / Perf sub-panel lines only when those levels ran, total time, and the scenario
verdict `{X}/{Y} behaviorally verified` (STRONG assertions count full, WEAK half —
quality-weighted, intentionally different from Build's binary pass/fail).

The gate question and the commit are the orchestrator's: `temper next --json` gives the question
and its options (a passed Check is the one Commit question; a failed one offers Repair again and the
loop back to Build while the budget allows, a skip with a reason, and Save for later). This stage never asks it.

## Error Interpretation

- **Compile:** read the full error (cascade errors are noise), name file:line and the fix.
- **Test failure:** distinguish a new test failing (incomplete implementation) from an
  existing one failing (regression — identify the likely causing change).
- **Coverage:** name the uncovered files/functions, prioritize recently-changed public
  methods; never suggest a trivial test just to move the number.
- **Lint/type:** group by violation type; offer auto-fix only if the tool supports it
  (`eslint --fix`, `ruff format`).
- **Security:** name the CVE, severity, affected dependency; suggest a version bump if
  one fixes it, else note it as an accepted risk with a workaround if one exists.
- **Missing tool:** skip that level, name the missing tool and point to its own install
  page (never print an install command), and never fail the whole pipeline for an
  optional tool. The one measurement the gate needs is the exception: a test run. When its tool is missing, say so
  in the summary, record nothing and estimate nothing: the gate fails on that row only, and its question offers **Run
  Check again**. The person installs the tool and picks it; the person never records a number by hand. A coverage
  that was not measured (no coverage tool, a coverage program that could not start, no base value) is the third
  state of its row, `not measured`: it fails nothing, passes nothing, and the commit card names it.

### The coverage rule (9.8.5)

`scripts/check_run.py` (`coverage_verdict`) judges coverage by one rule, in this order, decided by the CLI's own probe
and exit codes, never by output text:

1. The project's config holds `check.coverage-threshold`: the total must reach its value (rule `threshold`). The key
   counts only when the project's own config holds it; remove the line and coverage is judged against the project.
2. No coverage command for the stack, or the coverage program could not start (exit 127): `not measured`, with the
   hint of what to set.
3. No base value (the baseline's `coverage`, `.temper/evidence/baseline.json`, of a run on the run's base commit):
   `not measured`.
4. Line data and at least 10 changed executable lines: their share that ran must reach the base total, never more
   than 80 (rule `changed lines`). Line data comes from coverage.py's JSON, Go's profile and `lcov.info` of jest,
   vitest and c8.
5. Else the total may be at most 1 point below the base total (rule `total`).
6. Else `not measured`.

The planted bug score is no row of the gate: `temper check ahead`, beside Review, plants one small bug at a time in
the changed lines when three runs of the suite fit the budget, and writes `.temper/evidence/mutation.json`. The commit
card and the Check markers show it as information; it gates nothing and moves nothing. In a feature run it runs no
check: the store is warm from `integrate`, and the suite's time and result are the store's entry of the tree as it is;
with no entry nothing runs, and the file says why. In a fix run, which has no `integrate`, it first runs Check's
commands through the store.

## Maven

A Maven group validates with `mvn verify` run once with JaCoCo on, so the suite and its coverage come from one run. A task's tests run
only its declared test classes (`-Dtest=`, offline, `mvnd` when it is on PATH, else `mvn`), and GREEN needs a new surefire report for
each class (`scripts/maven_loop.py`). Check never runs a second full Maven pass for coverage.

## One suite run, with coverage

The suite runs once, in its coverage form, when Build ends: `temper integrate` (and, in a fix run, the Fix agent's
`temper check build-checks`) runs the owner's command, each scenario test and the locked acceptance tests into the
Build ledger (9.8.5, WP23). When the stack allows it, coverage is on in that same run; a second full run for coverage
is never made. Every run goes through the reuse store: on the tree `integrate` left, Check runs no command and records
the suite, coverage, scenario and acceptance rows as reused, with their key and tree. What Check still runs: a fix's
regression proof, the criteria validated by `code` or `metric`, a criterion the person confirms, and every command
again on a tree that changed after `integrate` (a repair at Review). With no suite in the config or `detect`, the plan's
`**Integration:**` line is Check's owner too. A group's check of the same text as the owner's
test command is the same key on the same content. On jest the coverage command is `npx jest`, not the project's `npm
test` script: a project whose test script does more than run jest sets `check.commands.test`. The coverage output goes under `.temper/check/` (`.temper/check/coverage.xml`,
`.temper/check/htmlcov/`), which the blast radius skips along with `.coverage`, `htmlcov/`, `.pytest_cache/` and
the other test caches. Task agents and the fix pass run scoped tests, never the full suite.
