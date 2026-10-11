# Focused review of 7c148ab (F1-F7 fix)

- G1 HIGH scripts/temper:2766: the undo skips a path a later commit changed again; when a sibling starts after the agent commit and passes, its commit keeps the agent's edit, so the foreign line stays on the branch while the sha is recorded as reverted (reproduced; 915e51f's git revert removed it). Breaks invariant (b).
- G2 MEDIUM scripts/temper:3112: the park hint stashes with no pop, so the running sibling's file goes missing, and the hand revert is not recorded by the CLI, so the sibling then FAILs as foreign (reproduced).
- G3 MEDIUM scripts/temper:2764: two git processes per path under the lock; 1000 paths took 5.7 s; a few thousand pass the 10 s wait or the 30 s stale break. Batch with ls-files -s -z + update-index --index-info.
- G4 LOW scripts/temper:2760: the undo exits 0 and records the shas while foreign content stays: non-UTF-8 names (replace decode), a file turned into a directory, an empty write-tree (reproduced).
- G5 LOW scripts/temper:329: the window between the age check and mv is still open; a lock re-taken there is deleted, so two holders exist (reproduced); the comment and CHANGELOG say no second holder.
- G6 LOW CHANGELOG.md:65: claim (b) has no exception, but by the F1 design an agent edit to a running sibling's file lands with that sibling's commit; document it or warn naming those paths.
- Also: plain index.lock contention can park a group (the reset needs the lock).
