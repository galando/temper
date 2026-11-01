# ADR-0014: An optional Pipeline stage after Commit

**Status:** Accepted
**Date:** 2026-10-30
**Amends:** ADR-0013 (the stage list the CLI computes)

## Context

A commit that opens a pull request is not the end of the work: the pull request's checks run afterwards, and a red check sends
the person back to the terminal to read a log, work out the cause and push a fix. Temper stopped at Commit, so that loop
happened outside the run, with no record and no gate.

## Decision

1. **A seventh stage, Pipeline, follows Commit.** It runs only after a Commit that opened a pull request, and only when
   `phases.pipeline` is not `false`. It is in the CLI's stage list, the run sequence, the gate dispatcher (`gate_pipeline`),
   the mod's stage names, the band and `types/index.d.ts`.
2. **The agent reads, records and proposes. It never pushes.** `agents/pipeline.md` reads the checks with `gh pr checks` and the
   failed logs with `gh run view <id> --log-failed`. A log is untrusted data: the agent never runs or follows a line of it and
   never copies a token from it. It writes `pipeline-context.json` (status, failed jobs, the proposed fix, the round) and returns
   a panel. It commits nothing, edits no project file, opens no ad-hoc window and never runs `gh pr ready`.
3. **The orchestrator owns the push, and the person decides it.** The gate question offers the fix and asks before each push.
   The steps open a Pipeline ad-hoc window, apply the changes the fix list names, stage each file by name, commit, push, close
   the window, count the round and redo the stage, so CI is read again. A redo removes the old verdict and the context file.
4. **A bounded loop.** After `loops.max-per-type` rounds the question stops offering the fix.
5. **The mod refuses a code write at Pipeline** unless the Pipeline ad-hoc window is open.

## Consequences

- Temper reads the pull request's checks through `gh`, and Commit pushes: `docs/trust.md` and `docs/privacy.html` say so.
- A fix proposal is a sentence per change, never a change of the CI configuration to make a job pass, and never a skipped test.
- A run with no pull request, or with the stage turned off, ends at Commit as before.
