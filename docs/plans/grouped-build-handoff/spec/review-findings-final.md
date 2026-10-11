# Final Review findings (after loop 2) — fixed directly by user decision (loop budget spent)

## HIGH
- F1 scripts/temper:3036: R1 revert mode wipes a running sibling's uncommitted work that the agent commit swept in (git add -A); reproduced: sibling src/b.sh deleted. Revert in the index only (e.g. `git revert --no-commit` against the index, or rebuild the tree without the foreign commit's changes to paths the failing task does not own), then restore only the failing task's own declared paths and the undeclared paths it named; never touch a running sibling's declared paths in the working tree. Regression case: sibling with uncommitted work in its declared file; the failing task's agent commit sweeps it in; after the FAIL undo, the sibling's working-tree content is intact.

## MEDIUM
- F2 scripts/temper:2823: later_sibling checks every group; a task running in another group (G2) forces revert in G1 where reset is safe (reproduced). Scope the check to running siblings in the same group/worktree.
- F3 scripts/temper:3036: revert runs before restore; a file still dirty after the agent commit makes the revert fail and the group parks on attempt 1 (skipping the D-03 retry chain); the hand-revert hint it prints fails too (reproduced); no case. Restore (or stash the failing task's own dirty paths) before reverting, make the printed hint correct, add a case.
- F4 scripts/temper:2797: R2 excuses any change to a reopened path, not the revert content: a sibling edit of src/a.sh PASSes (reproduced); nothing stops a task agent running `temper group reopen`. Excuse only paths whose current content equals the content the reopen revert produced (compare blob hashes recorded at reopen time); and refuse `group reopen` while the calling context is a task agent if detectable, otherwise document that reopen is an orchestrator-only command and have the mod refuse `temper group reopen` from Bash during a grouped Build only if that is a simple pure-rule change (else note it).

## LOW
- F5 scripts/temper:325: TEMPER_LOCK_TEST_HOOK test seam in production: an env-named executable runs in the stale break, stdout not redirected, undocumented. Remove it and test the R7 window another way (e.g. a test-only wrapper that sources the lock functions, or a deterministic sequence of mkdir/rename in the test itself).
- F6 scripts/temper:333: R7 put-back: a waiter's mkdir during the aside window orphans the fresh lock (.lock.dead.PID), two holders; TOCTOU on mv. Close the window (e.g. break by renaming to a unique name and then re-checking ownership by token before deleting; if the token proves it was fresh, re-acquire through the normal path rather than putting back), with a case.
- F7 reference/plan.md:265: R4 dropped "file.": broken sentence.
