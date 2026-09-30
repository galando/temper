# ADR 0009: Build checkpoint commit carve-out

Date: 2026-09-29 · Status: accepted · Applies to: `temper gate commit` (scripts/temper)

## Context

Build runs one task per checkpoint: the moment a scenario's test goes GREEN, the
task commits (`feat({slug}): {scenario} [AC-NN]`). Those checkpoint commits land
while `next_stage` is still `build` — before Review and Check have run — so the
full commit gate (which demands review + check verdicts) would block every one
of them, making the checkpoint loop impossible.

The artifact-only carve-out does not cover them: a checkpoint commit stages
source files, not `.temper/specs/` artifacts.

## Decision

`temper gate commit` short-circuits to a single `build checkpoint commit`
requirement **only when every one of these holds**:

1. `next_stage == build` (the run is mid-Build),
2. the run's `command` is `temper` (never `fix`),
3. the current git branch equals the run's branch, and
4. every upstream gate Build owes is satisfied — plan; intent when
   `intent.md` exists; design when `design.md` exists ("satisfied" = PASS
   verdict or a recorded human override).

Then:

- last build test evidence row matching GREEN with exit 0 → PASS this one
  requirement and return;
- last such row RED (nonzero exit) → FAIL, naming the claim;
- no test rows at all → fall through to the full commit gate.

The final completion commit still faces every gate: by then `next_stage` is
past `build`, so the carve-out does not apply.

## Why these conditions

- **Branch match** — a commit on another branch (a human's quick fix) never
  rides a mid-Build carve-out.
- **Upstream gates satisfied** — the checkpoint is *downstream progress* on a
  run whose intent/plan verdicts already exist; it never substitutes for them.
- **GREEN evidence** — the carve-out says "the work committed so far is green",
  which is exactly what the RED→GREEN discipline proves per scenario.
- **temper, not fix** — /temper:fix has its own sequence and gates Fix as
  `build`; its commits follow the existing fix gate path.

## Consequences

- Review and Check still gate the final commit; the carve-out only admits
  incremental, green, task-scoped commits inside an active Build.
- `base_sha` (recorded before Build starts) is what downstream readers use to
  see checkpoint-committed files in the diff — see the Build stage brief.
