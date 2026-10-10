# ADR-0011: Grouped Build with CLI-scheduled task agents

**Status:** Proposed
**Date:** 2026-10-10
**Supersedes:** (none)

## Context

Build runs one task at a time today. Each launch runs on the session model with about
64 KB of context, and a human gate follows every task. Temper 9.7.0 adds an opt-in
`build.mode: grouped`. Plan writes tasks.md as groups of small tasks. Each task runs as
one launch of a slim Haiku agent, and the human reviews once per group. Several parts of
the design go beyond earlier Temper decisions: who schedules the agents, where parallel
work happens, and who commits and merges it. Full design:
`.temper/specs/grouped-haiku-build/design.md` (in the run's spec folder).

## Decision

1. **The orchestrator launches every task agent. The temper CLI decides the order.**
   `temper schedule` prints the ready set (dependencies met, group not parked, declared
   files disjoint from running tasks, `max-parallel`). The orchestrator launches every
   printed task in one turn, on the model the CLI printed. No agent launches another
   agent.
2. **The CLI manages one git worktree per group.** The worktree is
   `.claude/worktrees/temper-{slug}-{G}`, on branch `temper/{slug}/{G}`, based on the
   run's feature branch. The subagent `isolation: worktree` field is not used.
3. **The CLI makes the local commits and merges.** At a task-gate PASS the CLI makes a
   pathspec commit of the task's declared files on the group branch. `temper integrate`
   merges the group branches into the feature branch with `--no-ff`. Before every
   commit or merge, the CLI checks the ADR 0009 upstream-gate condition. Nothing is
   pushed. The final feature commit still goes through `temper gate commit` and a human.
4. **Every `.temper/` JSON write goes through a lock.** The lock is a `mkdir` lock
   (`.temper/.lock`). It is stale after 30 s and fails open after 10 s. Each write goes
   to a temp file and then `os.replace`. The lock is held only for writes, never while
   a test runs.

## Alternatives Considered

### A group agent that launches its own task agents
- **Pros:** shorter orchestrator loop; retries stay inside the group.
- **Cons:** the user can turn nesting off (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`).
  The group agent's context grows with every task result. Scheduling would move into a
  prompt.
- **Why not chosen:** AC-13 requires grouped mode to work with nesting off, and AC-03
  requires scheduling in the CLI.

### Subagent `isolation: worktree`
- **Pros:** no worktree code in the CLI.
- **Cons:** it branches from the default branch, makes one copy per task instead of
  per group, and blocks Bash commands in the main checkout.
- **Why not chosen:** task agents must run the temper CLI from the main checkout, and
  tasks in a group must share one tree.

### Task agents commit their own work
- **Pros:** the same habit as per-task mode.
- **Cons:** parallel agents in one worktree race on `index.lock`. A commit made in a
  worktree sees no run state, so the native hook does not gate it.
- **Why not chosen:** a CLI commit made after the CLI's own verdict is serialized and
  holds only declared files.

## Consequences

### Positive
- Scheduling, verdicts, retries and merges are deterministic and covered by selftest
  cases.
- A launch carries about 12 KB instead of about 64 KB. Independent work runs in
  parallel.

### Negative
- For the first time, the CLI makes git commits and merges. This sits in tension with
  the autonomy invariant "never commits, pushes, or merges", which a human must settle
  (design.md, Areas of Concern 1) before this ADR is Accepted.
- Tasks of one group that run at the same time share a worktree. One task's test run
  can see a sibling's unfinished edit (design.md, Areas of Concern 2 and 3).

### Neutral
- Merge commits run no pre-commit hook. The CLI's own ADR 0009 check before each merge
  takes its place.

## References

- ADR 0009 (build checkpoint commit carve-out)
- `.temper/specs/grouped-haiku-build/intent.md` D-01..D-06
