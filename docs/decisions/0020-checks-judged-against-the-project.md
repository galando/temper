# ADR-0020: Checks judged against the project

**Status:** Accepted
**Date:** 2026-11-19
**Amends:** ADR-0018 (decision 2 is replaced, decision 3 is narrowed, decision 4 is corrected)

## Context

ADR-0018 put a preflight in the plan gate: each Validate and the Integration line ran on a throwaway worktree of HEAD,
and fifteen text patterns sorted each failure into an environment fault, a command fault or "needs new code". The
review of pull request 115 (`docs/plans/one-go/evidence/pr-env.md`) found that the gate then ran project commands
inside the planner's turn under one limit of 300 s for all, that 24 of 33 representative failures outside Maven matched
no pattern and passed silently, that its worktree was not the place Build runs in, and that a code bug which prints
`Connection refused` was held as a fault of the environment. The environment check and the baseline of WP20 now find a
missing tool, a wrong JDK or a service that is down from the project's own files, before any agent.

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

## Alternatives Considered

### Keep the patterns and add more
- **Pros:** a failure gets a class without a run of the suite.
- **Cons:** every stack needs its own list, and a list that misses a text passes the failure silently.
- **Why not chosen:** the exit code and the declared environment are known for every stack.

### Run the commands inside the plan gate, with a longer limit
- **Pros:** one call, one verdict.
- **Cons:** the planner waits on the suite in its own turn, and the gate is no longer static.
- **Why not chosen:** the baseline already runs in its own process at the place Build uses.

## Consequences

### Positive
- `temper gate plan` is static and fast; a slow Validate costs no planner time and is never an environment fault.
- A failed command is final only by the person's answer: "Run it again" runs it again after a repair.

### Negative
- A Validate that names no path and breaks on tests a later group changes still fails only at its first group gate.
- One more question id (`plan.command`) in the registry.
