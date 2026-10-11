# Review findings, loop 2 (Opus re-review after loop 1 fixes)

## HIGH
- R1 scripts/temper:2973 (H2/A1 half fixed): an agent-made commit in the worktree FAILs attempt 1, but the FAIL restore touches working-tree paths only; the commit stays on the group branch, the retry's start_sha absorbs it and attempt 2 PASSes, so an undeclared file or a pending sibling's file reaches integrate (reproduced). On FAIL with a non-CLI commit, reset the group branch to the task's start_sha (only when no other CLI commit landed after it; otherwise revert exactly the foreign commits), and make the retry's start_sha the restored point; regression case: agent commit with an undeclared file, attempt 1 FAIL, attempt 2 must not PASS with that file present on the branch.

## MEDIUM
- R2 scripts/temper:2238: group reopen while a sibling runs: the revert sha is in cli_commits but its files count as undeclared for the sibling (the reopened task is pending), so the sibling FAILs and its M2 restore re-applies the reverted content; the code comment claims the opposite (reproduced). Exclude files of a CLI reopen revert from the sibling's changed set (they belong to the reopened task), fix the comment, add a case.
- R3 scripts/temper:2129: L4 reuses ANY existing temper/{slug}/{G} branch with no check that this run made it; after state clear/init a new run with the same slug starts on an abandoned run's commits and skips the deps merge (reproduced). Reuse only a branch recorded in this run's groups.json (same run, same base); otherwise refuse loudly as before, naming the stale branch and how to delete it.
- R4 reference/plan.md:266: still allows a wildcard in **File:** "when the files cannot be named in advance"; the grouped plan gate refuses every glob (H4). Make the doc say exact paths only in grouped mode.

## LOW
- R5 scripts/temper:2274: group reopen skips _plan_fresh; call it like the other grouped commands.
- R6 scripts/temper:814: state loop writes next_stage from an unvalidated <to>; validate <to> against the known stages.
- R7 scripts/temper:325: the stale break deletes the lock with no token check after its re-check; a release plus a fresh acquire in that window loses a fresh lock. Re-read the token after the re-check and delete only the stale owner's lock (rename-then-verify).
- R8 scripts/temper:341: the lock wait is about 2x TEMPER_LOCK_WAIT_S (python3 spawned per 20 ms sleep); compute the deadline from wall clock (date +%s or $SECONDS), not loop counts.
- R9 CHANGELOG.md:10 and design.md:469: the 9.7.0 entry omits the plan-changed and glob refusals and exact-path matching (and the loop-1 hardening: final-run rule, worktree commits counted, recorded CLI shas, locked atomic writes, reopen guards, state loop next_stage); design.md still cites gate plan "fresh" — align both with what was built.
