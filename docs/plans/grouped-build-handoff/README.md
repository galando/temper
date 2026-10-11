# Grouped Build (9.7.0): handoff to the next session

Working notes for finishing the grouped Build feature on branch `ccr-9154161b-pdiqc8`.
Delete this folder before the PR is merged.

## Where things stand

- The feature was built through the full `/temper` flow: Intent, Plan and Design on Opus,
  Build on Sonnet (one agent per task), Review on Opus, Check on Sonnet.
- Everything is committed and pushed on `ccr-9154161b-pdiqc8`. No PR merged.
- Last validation (Check stage): selftest 1440 pass / 0 fail, `claude plugin test .` 2663 pass /
  0 fail, `quality-check.sh` 8/8, `validate-directory.sh` OK, `validate-docs.sh` 9/9,
  `check-mod-calls.sh` OK.
- Not run: `npx -p typescript@5.6 tsc -p tsconfig.mod.json`. The mod types are not generated in
  the cloud container; CI (quality.yml) runs it on a pull request to `main`.
- Check gate: coverage cannot be measured for the Bash CLI (no coverage tool); it was handled by
  an override with that reason, approved by the user. Every other Check requirement passes,
  including AC-13 from a real grouped run on the final code (see "Sample run" below).

## The spec

The run's artifacts were under `.temper/specs/grouped-haiku-build/`, which this repository
ignores. Copies are in `spec/` here:

- `intent.md`: the problem, criteria AC-01 to AC-15 and decisions D-01 to D-08.
- `plan.md`, `design.md` (with "Resolutions (user at design gate)"), `tasks.md`.
- `review-findings-*.md`: every review round's findings, in order: loop1, loop2, final,
  focused, focused2 to focused5, d08.

## Decisions that shape the code

- D-01 max-blast-radius in grouped mode: per group at plan time; at the autonomy commit gate,
  changed files are compared with the declared files.
- D-02 Change at a group gate re-runs only the named tasks.
- D-03 a failing task retries on Haiku, escalates to Sonnet, then parks its group.
- D-04 the cost comparison is a follow-up, not a release blocker.
- D-07 every stage launch records its usage (`temper usage add`); `temper report` sums it.
- D-08 a commit made by a task agent is detected, the task FAILs and its group parks; nothing
  is undone automatically. A human removes the commit (the printed `git rebase --autostash`
  line) or accepts it (`group reopen --accept-foreign <sha> --reason ...`, guarded like an
  override). This replaced an automatic undo that eight review rounds kept finding new defects in.
- Stopping rule (recorded with D-08): fix what can give a wrong result in a normal run or weaken
  a gate; detect and stop agent misbehaviour instead of repairing it; document rare or contrived
  cases as known limits (CHANGELOG 9.7.0, "Known limits").

## Next steps for the new session

1. Open a PR from `ccr-9154161b-pdiqc8` to `main` if it is not open yet, and let CI run `tsc`.
2. Review the whole diff once, with fresh context (`/temper:review` or `/code-review`), judged by
   the stopping rule above. Earlier reviews were incremental; residue from patch-on-patch is likely
   in `scripts/temper` and in `scripts/selftest/temper-cases-5.sh` and `temper-cases-6.sh`.
3. Run a simplify pass on the grouped code in `scripts/temper`.
4. Decide on per-task worktrees. Most hard defects came from parallel tasks sharing one worktree
   per group (sibling interference, attribution, parking). One worktree per task would remove
   that class; weigh it against more merges.
5. Measure before investing more (AC-12): run one real feature in per-task mode and in grouped
   mode, compare `temper report --json` usage, wall time and Review findings
   (procedure in `docs/grouped-build.md`).
6. Remove this folder before merging.

## Numbers from this run

Usage as recorded by `temper report` (per-agent totals from Claude Code; the orchestrator
session itself is not counted): 49 agent launches, about 6.5M tokens. Opus 2.16M (Intent,
Plan, Design, nine Reviews), Sonnet 4.34M (Build tasks, review fixes, Check). Most of the cost
was the repeated review and fix rounds of the automatic undo, since removed by D-08.

Sample run (3 Haiku task agents, 2 groups, on the final code): see "Sample run" below.

## Sample run

A throwaway project with 2 groups and 3 small Bash tasks (add, subtract, then a report that
reuses them), run with `build.mode: grouped` on the final code. The orchestrator launched every
Haiku agent itself (nesting was not disabled; AC-13 asks for the orchestrator-launched path).

| Step | Result |
|---|---|
| G1: Task 1 and Task 2 in parallel on Haiku | RED then GREEN, task gates PASS on attempt 1 |
| G1 group gate, then G2 started from G1's work | PASS |
| G2: Task 3 on Haiku | RED then GREEN, task gate PASS on attempt 1 |
| `temper integrate`, then `temper gate build` | PASS, PASS |
| Haiku usage | 3 agents, 178,006 tokens (about 59K each), 34 to 53 s each, 0 escalations |

Most of each Haiku agent's tokens are the fixed cost of starting an agent, not Temper's brief.
Group wall times in `temper group report` include orchestrator idle time between steps.
