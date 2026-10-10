# ADR-0011: Grouped Build with CLI-scheduled task agents

**Status:** Accepted
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
5. **The group context lives in `tasks.md`**, as a `**Context:**` block under the group
   heading, not in a fourth spec file. The spec folder holds exactly `intent.md`,
   `tasks.md` and `plan.md`, and `temper gate plan` reads only those.
6. **Task agents never commit.** The CLI commits a task's declared paths at task-gate PASS.
   Parallel agents would race on `index.lock`, and a commit made inside a worktree sees no
   run state.
7. **Task model and write scope are CLI-resolved.** The task model comes from the agent
   brief frontmatter (`claude-haiku-5-5`), overridable in `.claude/temper.config`, through
   a separate resolver so `temper model --all` stays at eight lines when grouped mode is off.
   Declared-file overlap is rejected for any two tasks (or groups) not ordered by
   `Depends`, because a cross-group overlap is a guaranteed integration conflict.

### Intent decisions this ADR rests on

- **D-01** `autonomy.max-blast-radius` bounds each single group's declared files (Plan
  splits a larger group); the commit gate parks when files change outside the union of
  declared files. It is no longer compared with the feature total.
- **D-02** Change at a group gate records feedback and re-runs only the tasks it concerns,
  with the usual retry and escalation. Re-planning is a separate "Loop back to Plan".
- **D-03** A task that fails on Haiku, its Haiku retry and the Sonnet escalation stops its
  group and parks the run for a human, with every attempt recorded. Independent groups may
  finish first.
- **D-04** The AC-12 comparison run is a follow-up, not a 9.7.0 blocker. 9.7.0 ships grouped
  mode opt-in and experimental, with the measurement recording and procedure built in.
- **D-05** Nested subagents work by default but the user can turn them off, so the
  orchestrator launches every task agent (decision 1).
- **D-06** Size budgets: task brief 6144 bytes, group Context 4096, task block 1536, as
  constants in `scripts/temper`, tuned after the AC-12 comparison.
- **D-07** Usage is recorded for every agent launch in every stage and both Build modes
  (`temper usage add`; `temper report` shows per stage and per model). Numbers are the
  per-agent totals Claude Code returns, not split into input/output/cache; the orchestrator
  session's own usage is not recorded.

### Resolutions at the design gate (2026-10-10)

1. **Narrowed autonomy invariant.** Autonomy may let the CLI make local commits of a task's
   declared files on `temper/{slug}/{G}` group branches and the local `temper integrate`
   merge into the feature branch. It still never pushes, never merges to a remote, never
   re-plans, and never makes the final feature commit (it always parks). Recorded in
   `reference/autonomy.md`.
2. **Packs distilled into Context.** Plan must distil the pack rules that apply to each
   group into that group's Context block, security rules always. Review still checks the
   full packs.
3. **Task-scoped tests.** Each task declares its own scoped test command. The CLI runs it,
   records the output, and the task gate judges only that. Parallelism inside a group stays;
   the residual attribution risk (a sibling's unfinished edit) is documented in
   `docs/grouped-build.md`.

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
- For the first time, the CLI makes git commits and merges. The autonomy invariant is
  narrowed to allow exactly these local writes (Resolution 1).
- Tasks of one group that run at the same time share a worktree. One task's test run
  can see a sibling's unfinished edit; task-scoped tests limit but do not remove this.
- Haiku task agents see only distilled pack rules (Resolution 2).
- Grouped mode is experimental in 9.7.0: its cost and time saving is unmeasured (D-04).

### Neutral
- Merge commits run no pre-commit hook. The CLI's own ADR 0009 check before each merge
  takes its place.

## References

- ADR 0009 (build checkpoint commit carve-out)
- `.temper/specs/grouped-haiku-build/intent.md` D-01..D-07, `docs/grouped-build.md`
