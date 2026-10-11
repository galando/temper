# Focused review of 26c972a (D-08), judged by the stopping rule

## Fix (in scope of the stopping rule)
- M1 HIGH scripts/temper:3198 (reproduced): when an agent's commit is detected at a SIBLING's gate (gate order in a batch is arbitrary), the sibling is blamed, the park prints --task <sibling>, and the real culprit stays running; after route (a) and the printed reopen, the culprit's gate PASSes on its pre-park RED/GREEN rows with its work gone. Fix: on a foreign-commit park, mark every running task of the group failed/pending (their attempt rows stale), list them all in the park message and the reopen hint, and make reopen accept them; a reopened task needs fresh RED/GREEN rows.
- M2 HIGH scripts/temper:2378 (reproduced): `group reopen --accept-foreign` writes an override inside the CLI without a human confirmation; confirm-override.sh and the mod's decision matching never see it. Fix: guard it like `temper override` (confirm-override.sh asks; the mod treats it as a decision needing the user's typed command), with cases.
- M3 MEDIUM scripts/temper:3147 (reproduced, NORMAL run): a D-03 park refuses the gate of a sibling that finished in the same batch; after reopen it stays running with no NEXT line and no route. Fix: the schedule (or the reopen output) must offer `task gate N` for such a running task, or reopen must reset it; add a case for the normal-run path.
- M4 MEDIUM scripts/temper:2274 (reproduced): the printed rebase refuses on unstaged changes; "(or a reset)" is unspecified. Fix: print exact, safe steps (stash with a name, rebase, stash pop; never reset --hard), run as written in a test with a dirty sibling file.
- M5 MEDIUM scripts/temper:2274 (reproduced): after an agent merge, running the printed lines replays the foreign commit under a new sha; reopen accepts; it can reach integrate. Fix: at reopen (and at integrate), every commit in the group's base..HEAD must be recorded by the CLI or accepted; otherwise refuse and name it. Correct the CHANGELOG known limit.
- M6 MEDIUM scripts/temper:2930 (reasoned): the verdict reads an env var TEMPER_OVERRIDES_FILE that nothing sets; remove it.

## Document as known limits (LOW)
- L1 foreigncheck treats a git error (worktree removed by hand) as off the branch.
- L2 one hint line per foreign sha, no cap.
- L3 accept rows recorded before the reopen revert commit; a rerun after its failure duplicates rows.
- L4 D-08 has no Gherkin scenario (covered by temper-cases-6.sh).
