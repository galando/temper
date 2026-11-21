# ADR-0020: Checks judged against the project

**Status:** Accepted
**Date:** 2026-11-19
**Amends:** ADR-0018 (decision 2 is replaced, decision 3 is narrowed, decision 4 is corrected)

## Context

ADR-0018 put a preflight in the plan gate: each Validate and the Integration line ran on a throwaway worktree of HEAD,
and fifteen text patterns sorted each failure into an environment fault, a command fault or "needs new code". The review
of pull request 115 (`pr-env.md`, a working paper of the build that is not kept in the tree) found that the gate then
ran project commands inside the planner's turn under one limit of 300 s for all, that 24 of 33 representative failures
outside Maven matched no pattern and passed silently, that its worktree was not the place Build runs in, and that a code
bug which prints `Connection refused` was held as a fault of the environment. The environment check and the baseline of
WP20 now find a missing tool, a wrong JDK or a service that is down from the project's own files, before any agent.

## Decision

1. **Replaces ADR-0018 decision 2.** The plan gate runs no project command. After the planner returned, the CLI runs
   each group's Validate and the Integration line once on the current code (`temper baseline plan`), in the baseline's
   worktree, in a process of its own, each under the limit Build gives it. A text equal to the suite the baseline ran,
   a command that names a file a task creates, and every task and scenario Test are left out. The exit code alone
   decides: 0 passes, 124 is a time out, 125 and a program that does not resolve are the environment's, any other exit
   fails (or fails like the base, when the base is red). A failure or a time out is the person's question
   `plan.command`: more time, another command, a revised plan or a skip with a reason (an override `plan-command`).
2. **Narrows ADR-0018 decision 3.** An environment fault at a task gate needs one of three sure signs: the setup line
   failed, exit 127 for a program the command starts, or a service of `setup.services` that does not answer right after
   the run. No output text counts beyond those; a time out stays the code's.
3. **Corrects ADR-0018 decision 4.** `temper doctor` reads, and with `--propose --write --expect <hash>` writes the block
   the person chose at the question that showed it whole. No command is run to check a block (the store of blocks
   tried goes), and no agent drafts one: the environment agent and its brief are removed.
4. **A check is judged against the project (9.8.5, the checks of WP19).** A gate row is passed, failed or not
   measured: a row the CLI could not measure has `pass` null and `state: not measured`, is printed `[?]`, is named on
   the commit card, and is never read as passed or failed; it fails nothing, and the run moves on. Coverage is one row,
   `coverage`, judged by one rule (`scripts/check_run.py coverage-verdict`): the key `check.coverage-threshold` only
   when the project's config holds it; no coverage command, a coverage program that could not start, or no base value
   is not measured; with line data and ten or more changed executable lines, their share that ran must reach the base
   total (at most 80); else the total may be at most 1 point below the base total. The planted bug score is no row: it
   is information on the commit card, and the threshold key and its default of 80 are gone.
5. **The environment check and the baseline come first (9.8.5, WP20).** A run's first step is the CLI's own
   `temper baseline start`: the tools and services the project's files and the config name are checked in under 5 s,
   then the project's own suite runs once on the current code, in a detached worktree, in its own process, and
   `.temper/evidence/baseline.json` says green, red or unknown. A fault or a red base is one question, `base.red`,
   before any agent, and after the approval no new task agent is launched on it. Every time limit is the larger of its
   default and three times the base's time of the same suite; a first time out of a group's check runs again with
   twice the limit, as the CLI's own call.

## Alternatives Considered

### Keep the patterns and add more
- **Pros:** a failure gets a class without a run of the suite.
- **Cons:** every stack needs its own list, and a list that misses a text passes the failure silently.
- **Why not chosen:** the exit code and the declared environment are known for every stack.

### A fixed coverage floor and a fixed time limit
- **Pros:** one number a team can read in the config.
- **Cons:** a project below the floor fails every run it did not cause, and a slow suite times out on its own base.
- **Why not chosen:** the project's own base is the one measure that fits every project.

### Run the commands inside the plan gate, with a longer limit
- **Pros:** one call, one verdict.
- **Cons:** the planner waits on the suite in its own turn, and the gate is no longer static.
- **Why not chosen:** the baseline already runs in its own process at the place Build uses.

## Consequences

### Positive
- `temper gate plan` is static and fast; a slow Validate costs no planner time and is never an environment fault.
- A failed command is final only by the person's answer: "Run it again" runs it again after a repair.
- A missing coverage tool is not measured, never failed and never passed, and a fault of the environment is named
  before any agent is paid for.

### Negative
- A Validate that names no path and breaks on tests a later group changes still fails only at its first group gate.
- One more question id (`plan.command`) in the registry, and `base.red` beside it.
- The baseline runs the suite once more per run, on the current code, before any agent.
