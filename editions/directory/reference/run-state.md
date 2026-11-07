# Run State: the Files Temper Keeps

In this edition there is no CLI. The run lives in plain files under the project's `.temper/`
folder, written by Claude with the Write and Edit tools. Every stage agent starts with a clean
context and reads only these files, so anything not written here is lost between stages.

Nothing in this edition checks these files mechanically. They are a record the person can read
and correct, not a ledger a program verifies. The full edition (on GitHub, `galando/temper`)
computes every verdict with its CLI from an evidence ledger and blocks `git commit` with a hook.

## Layout

```
.temper/
  run.json                  the active run; absent means no run is active
  lessons.md                one entry per fix, read first by every root cause analysis
  review-memory.json        finding patterns (optional)
  metrics.json              review and check counts over time (optional)
  specs/{slug}/
    intent.md               problem, criteria, scenarios (Intent and Plan)
    plan.md                 architecture, blast radius, files (Plan)
    tasks.md                grouped tasks with cases (Plan)
    design.md               medium and complex runs only (Design)
    rca.md                  fix runs only (RCA)
    evidence.md             every command a stage ran, with its real exit code
    review.md               findings with severity, confidence and status (Review)
    check.md                validation results and scenario trace (Check)
    state.json              the stage, the gates and the person's decisions
```

A slug is letters, digits, `.`, `_` or `-`, starts with a letter or digit, and has no `..`
or `/`. A ticket key keeps its case: `PROJ-123-login`.

## run.json

```json
{ "slug": "PROJ-123-login", "command": "temper", "started": "2026-11-07T10:00:00Z" }
```

`command` is `temper` or `fix`. Write it when a run starts; delete it when the run ends
(after the commit, or when the person chooses "Start over" or "Discard the run").

## state.json

```json
{
  "version": 1,
  "edition": "markdown",
  "slug": "PROJ-123-login",
  "feature": "the feature as the person typed it",
  "command": "temper",
  "stage": "intent",
  "tier": null,
  "risk": null,
  "branch": "temper/PROJ-123-login",
  "base_sha": "the commit the run started from",
  "loops": { "review": 0, "check": 0, "plan": 0 },
  "gates": {
    "intent": { "checklist": "PASS", "decision": "Continue to Plan", "reason": null, "at": "ISO time" }
  },
  "drift": [ { "path": "src/x.py", "decision": "add", "why": "..." } ],
  "history": [ { "at": "ISO time", "event": "Plan approved by the person" } ]
}
```

- `stage` is one of `intent`, `plan`, `design`, `build`, `review`, `check`, `commit` (and
  `rca`, `fix` in a fix run). It moves only after the person's answer at that stage's gate.
- `checklist` is what the stage's checklist (`reference/gates.md`) showed: `PASS` or `FAIL`.
- `decision` is the option label the person chose, word for word. `reason` is their reason when
  the option asks for one (an override, an accepted finding).
- `loops` counts each loop back. The budget is `loops.max-per-type` in `.claude/temper.config`,
  default 2.

## evidence.md

One row per command a stage really ran. The exit code is copied from the tool result, never
estimated, never reconstructed afterwards.

```markdown
# Evidence: {slug}

| Time | Stage | Phase | Claim | Command | Exit | Note |
|------|-------|-------|-------|---------|------|------|
| 10:42 | build | red | Task 1 tests | `pytest tests/test_parser.py -q` | 1 | AssertionError: expected [] |
| 10:45 | build | green | Task 1 tests | `pytest tests/test_parser.py -q` | 0 | 3 passed |
| 11:02 | check | suite | tests and coverage | `pytest --cov=src -q` | 0 | 41 passed, 87% |
```

Phases: `red`, `green` and `scenario` (Build), `regression` (Fix), `suite`, `coverage`,
`lint`, `types`, `security` and `scenario` (Check), `note` for a message the person typed at a
question. A row is never edited or deleted; a newer row wins.

## review.md

```markdown
# Review: {slug}

**Files reviewed:** {N}   **Intent:** satisfied | partial | not_met
**Review completed:** {ISO time}

| # | Severity | Confidence | Where | Finding | Status |
|---|----------|------------|-------|---------|--------|
| 1 | high | 0.85 | src/api.py:42 | user id taken from the body, not the session | open |
```

Status is `open`, `fixed` (the fix pass fixed and tested it), `accepted: {the person's reason}`
or `contested: {file:line and the quoted text}`. Only the person accepts a finding.

## check.md

```markdown
# Check: {slug}

| Level | Command | Exit | Result |
|-------|---------|------|--------|
| tests | `pytest --cov=src -q` | 0 | 41 passed |
| coverage | same run | 0 | 87% (threshold 80%) |

## Scenarios
- [x] {scenario name} -> tests/test_api.py::test_name (exit 0)
- [ ] {scenario name} -> no test found

## Criteria
- AC-01: pass ({evidence row})
- AC-03: manual, the person confirms at the Check question
```

## Configuration

`.claude/temper.config` (YAML) is optional. The keys this edition reads:

```yaml
stack: auto
packs: [quality, tdd, security, git, performance]
review:
  block-on: [critical]          # severities that fail the Review checklist
  confidence-threshold: 0.7
check:
  coverage-threshold: 80
  commands:                     # optional, replaces stack detection
    test: ""
    lint: ""
    typecheck: ""
phases:
  design: true                  # Design runs for medium and complex runs
loops:
  max-per-type: 2
```
