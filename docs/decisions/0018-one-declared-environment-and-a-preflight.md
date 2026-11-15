# ADR-0018: One declared environment for every command, and a preflight on the clean base

**Status:** Accepted
**Date:** 2026-11-15
**Supersedes:** (none)

## Context

In a measured run on a Java 24 Maven project, most of 2.8 hours of Build went to faults that existed before any agent
wrote code: a filtered `mvn verify` that could never meet a JaCoCo bundle rule, CLI gates and agents running under JDK 21
while the project needs `[24,)`, and a Maven check that skipped every `cd backend && mvn ...` line. Each fault showed up
only after agent work, and a gate call under the wrong JDK spent a task attempt and reset its work folder.

Two architectural gaps caused this: the CLI ran every command in whatever shell environment it inherited, and nothing ran
the plan's commands before Build.

## Decision

1. **A `setup:` block in `.claude/temper.config`** (`run`, `env`, `services`, `tools`) is the project's one declared
   environment. `run_env.run_cmd`, the one runner of every command the CLI runs, applies it: the credential filter first,
   then the block's variables (credential names left out), then the run line in the same shell, with a positive
   `temper-setup: OK` / `temper-setup: FAIL (exit N)` marker and exit 125 on failure. The same block is put into every
   agent prompt as one "Environment setup" line by `flow.plugin_line`. A missing block is exactly today's behaviour.
2. **A preflight at the plan gate** runs each Validate, Test, Integration and scenario Test command of the plan once, in
   a detached worktree of HEAD, and sorts each into passes, needs new code, environment fault or command fault, by
   positive patterns only. The two fault classes fail the plan gate with the real error. A time limit
   (`plan.preflight-timeout`, 300 s) and a skip with a recorded reason (`plan.preflight-skip`) bound it. It runs once
   per plan: the result is stored in `.temper/preflight.json` under a key of HEAD, the commands, the setup block and the
   time limit, and later plan gates read it while the key holds (`temper plan preflight` runs it again).
3. **An environment fault at a task gate** (one rule, `preflight.env_fault`) spends no attempt and resets nothing; the
   person is asked to check it again. A time-out there stays a fault of the code, as before: it spends the attempt.
4. **`temper doctor`** reports the toolchain, the block and the services, and writes nothing.

## Alternatives Considered

### Pass the setup to each caller
- **Pros:** each call site shows it applies the setup.
- **Cons:** nine call sites; one missed site runs a gate under the wrong toolchain, the original fault.
- **Why not chosen:** a single runner cannot miss one.

### Treat an unexplained failure on the clean base as a command fault
- **Pros:** catches base failures no pattern knows.
- **Cons:** the tests of new code fail on the base by design.
- **Why not chosen:** it would fail every plan whose Test commands name tests a task writes.

### Run the preflight in the project folder
- **Pros:** no worktree.
- **Cons:** build output lands in the tree, and uncommitted edits are not Build's base.
- **Why not chosen:** a dirty-folder pass can hide a Build failure.

## Consequences

### Positive
- Toolchain, coverage-rule and command-shape faults surface at the plan gate, with the real error, before Build.
- Agents and CLI commands share one declared environment.

### Negative
- The first plan gate of a plan on a committed project runs the plan's commands; a slow suite costs that time once per
  plan (or the person records a skip).
- Commands run before the person approves the plan.

### Neutral
- The skip key is protected by the mod's config rule; without the mod it is an ordinary file.

## References

- The preflight-env-contract run (its spec folder is run state, not in the repository)
- ADR-0013 (the CLI says what next)
