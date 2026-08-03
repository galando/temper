---
description: "Run the project's validation pipeline (tests, build, lint, security)"
---

# Check: Stack-Aware Validation Pipeline

**Goal:** Run the project's real validation pipeline and record what happened — never
estimate a result. `agents/check.md` carries the exact `temper evidence add` invocations
the gate needs; this doc is the methodology behind what to run and how to interpret it.

**Modes:** Standalone (`/temper:check`) runs in the current context, own gate. Agent
subprocess (from `/temper`) starts clean, no AskUserQuestion gate — return the summary,
the orchestrator owns it. Load `.temper/specs/{feature}/review-context.json` if present.

## Step 1: Detect Stack

Apply the temper-core skill's detection order. A company preset (`.claude/temper.config`
/ `.claude/presets/*.yaml`) overrides auto-detected commands.

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
| 0 | Environment — no `.env*` looks like production | STOP immediately | no `.env*` files |
| 1 | Compile/build | STOP, show error, suggest fix | — |
| 2 | Unit tests | STOP, show failing names | — |
| 3 | Integration tests | STOP, show failing tests | none configured |
| 4 | Coverage vs. `check.coverage-threshold` (default 80) | WARN | no coverage tool |
| 4.5 | **Scenario verification** — see below | BLOCK on FAIL, WARN on MISSING | no intent.md |
| 4.75 | Heuristic test-gap analysis | WARN | level 2 or 4.5 failed |
| 4.85 | API diff / contract check | WARN (BLOCK if breaking + consumer not updated) | no API files changed |
| 4.9 | Performance regression vs. baseline | BLOCK if >10% slower | no benchmarks configured |
| 5 | Lint/format | WARN | no linter |
| 6 | Type check | WARN | not applicable |
| 7 | Security (deps + SAST) | WARN medium / BLOCK critical CVE | no scanner |

### Level 4.5 — Scenario Verification (Live Execution)

This is the level the README's rate-limiting story depends on — it is the only level
that reads `intent.md` and proves, per scenario, whether a real test exercises it.

1. Resolve `{spec}`: from `build-state.json` if present, else the most-recently-modified
   dir under `.temper/specs/`. No specs found → SKIP this level entirely.
2. Extract every `Scenario:` (name + Given/When/Then) from `intent.md`.
3. Match each scenario to a test: MCP `query_graph_tool` by name annotation → `[PROVEN]`;
   else grep test files for the scenario name (snake_case/camelCase) → `[HEURISTIC]`; no
   match → UNMATCHED. `check.live-scenarios` (`prompt`|`always`|`never`, default
   `prompt`) controls whether to ask before running matched tests for real; `never` falls
   back to heuristic-only.
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
  new shape (ADDITIVE/MODIFIED/BREAKING), grep tests/frontend/imports for consumers, and
  check whether each consumer was updated. Breaking + consumer not updated → BLOCK.
  Write `.temper/contract-map.json`.
- **4.9 performance:** run configured benchmarks, compare to
  `.temper/performance-baseline.json`. <5% slower: pass, update baseline. 5-10%: WARN.
  >10%: BLOCK, suggest investigation. >20% variance historically flaky → downgrade one
  level.

### Level 7 — Security

Dependency scan (`npm audit`, `pip-audit`, etc.) plus, if the semgrep MCP server is
available and `tools.mode` isn't `heuristic-only`: `security_check` on changed files,
then `semgrep_scan_with_custom_rule` using each enabled pack's rules (read the enabled
packs' `rules.md` — project `.claude/packs/` shadows global `~/.claude/packs/` shadows
built-in `$CLAUDE_PLUGIN_ROOT/packs/`; keep rules whose `phases` is `all` or contains
`check`). Map error→CRITICAL(BLOCK), warning→HIGH(WARN), info→MEDIUM(WARN). SAST findings
bypass confidence filtering — always shown, labeled `[PROVEN]`. No semgrep → fall back to
the OWASP pattern-matching in `review.md` Step 2, labeled `[HEURISTIC]`.

## Step 3: Debt Tracking + Config Suggestions

If `debt-tracking: true`: append coverage %, test count, and lint-violation count to
`.temper/metrics.json` history arrays (full debt analysis is `/temper:status`'s job, not
Check's — don't slow the pipeline down repeating it here).

If every level passed and files changed: generate up to 5 config suggestions
(confidence >= 0.6) comparing the diff against `CLAUDE.md`/`AGENTS.md`, write
`.temper/specs/{feature}/config-suggestions.json`, queue them in
`learning.json.suggestion_queue` (`type: config-update`). Full methodology:
`reference/config-suggestions.md`. Shown to the user at the Check gate.

Every accepted suggestion is a permanent line in a file loaded on every future session,
so suggest one only when a *specific* thing went wrong that the config could have
prevented — not general good practice the model would apply anyway. If `CLAUDE.md` is
already long enough that you're hesitating, say so and suggest `/doctor` instead of
adding to it; see `docs/context-hygiene.md`.

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

When `feedback.enabled: true` and test failures exist in newly written code: build a
targeted fix task per failure (test name, error, file:line, the `intent.md` scenario it
maps to), offer "Loop back to Build" while `iteration < loops.max-per-type` (default 2).
At the budget, stop and show remaining failures — offer "Save for later" instead. The
same test failing across 2 consecutive loops stops immediately rather than looping again
(`.temper/feedback-loops.json` tracks the counter).

## Summary + Gate

```
+-----------------------------------------------------------+
| CHECK — {Project Name}                                    |
+-----------------------------------------------------------+
| Compile {status}  Tests {status} {N} passed  Coverage {X}% |
| Live Scenarios {X}/{Y} ({P} pass / {F} fail / {M} missing)  |
| Lint {status}  Security {status}   Total: {time}            |
| (Test Gaps / API Diff / Perf sub-panels only when they ran) |
| Scenario verdict: {X}/{Y} behaviorally verified             |
|   (STRONG assertions count full, WEAK count half — this is |
|    quality-weighted and intentionally differs from Build's |
|    binary pass/fail)                                        |
+-----------------------------------------------------------+
```

`AskUserQuestion`: "Commit (Recommended)" / "Save for later" (+ "Loop back to Build" from
the orchestrator when the feedback conditions above are met). A change typed via "Other"
is never approval to commit — make the edit, re-run validation from the first level that
had failed (skip already-passed levels), re-show this same gate.

**On Commit:** delete `.temper/build-state.json`; if `intent.md` exists add `**Status:**
completed` + `**Completed:** {date}` to its header; commit with a conventional message
naming files changed / tests added. **On Save:** write `build-state.json` with `stage:
check_complete`, `next_stage: commit`, report "Run /temper when ready to continue."

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
- **Missing tool:** skip that level, note the install command — never fail the whole
  pipeline for an optional tool.
