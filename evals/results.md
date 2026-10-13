# Measurement results

Every row is one real run, scored by `evals/score.py` from what the run left. A run that did not
happen has no row. How each kind of run is made, and what each column means: `evals/README.md`.

- **Fixed at end:** the fixture's hidden test passes on the project as the run left it.
- **Review:** a Review ledger row names the planted defect (the severity it gave).
- **Check:** the Check verdict, and whether a failed row names the defect (only counted when
  Check recorded a green test run of its own).
- **Gates:** `Temper gate` questions asked, CLI moves made, and moves made with no gate answer
  since the move before (an armed run's own moves are not counted).
- **Tokens and cost:** Claude Code's own totals for the session (all models, subagents included),
  and its list price estimate in US dollars. **Main loop** is the part of those tokens spent by
  the conversation that runs `/temper` itself, not by the stage agents (from the transcripts).

| Date | Plugin | Fixture | Run | Fixed at end | Review | Check | Gates | Tokens | Main loop | Cost | Minutes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-13 | 806849a | orders | baseline, unattended Review and Check | no | yes (high) | FAIL, names it | not measured | 36 in, 47176 cache write, 766875 cache read, 4594 out | n/a | 0.31 | 1.0 |
| 2026-10-13 | 806849a | reset | baseline, unattended Review and Check | no | yes (high) | FAIL, names it | not measured | 26 in, 45949 cache write, 527514 cache read, 4023 out | n/a | 0.28 | 0.8 |
| 2026-10-13 | 806849a | search | baseline, unattended Review and Check | no | yes (high) | PASS, does not name it | not measured | 38 in, 50645 cache write, 834489 cache read, 4817 out | n/a | 0.33 | 1.0 |
| 2026-10-13 | cb275b6 | jokes | baseline A: interactive, grouped Build, dialogs relayed; Intent named the defect in a Blocking question | yes | no | PASS, does not name it | 5 asked, 4 moves, 0 without an answer | 6898 in, 247458 cache write, 4338193 cache read, 35211 out | 88 in, 81896 cache write, 2574617 cache read, 8536 out | 1.70 | 20.9 |
| 2026-10-13 | 2c449fa | jokes | baseline B: interactive, per task Build, dialogs relayed; the person kept all_jokes as is; worker restart after Intent, so cost and minutes cover the second process only | no | yes (low) | PASS, does not name it | 5 asked, 4 moves, 0 without an answer | 10263 in, 179568 cache write, 3792547 cache read, 21974 out | 78 in, 53799 cache write, 2600398 cache read, 7237 out | 1.38 | 9.2 |
| 2026-10-13 | f7d11c6 | jokes | final: interactive, grouped Build with Haiku, dialogs relayed, auto permission mode; Intent named the defect in a Blocking question; worker restart at the Intent question, resumed with /temper:temper | yes | no | PASS, does not name it | 5 asked, 4 moves, 0 without an answer | 4874 in, 193391 cache write, 3602834 cache read, 30255 out | 104 in, 92381 cache write, 2323336 cache read, 7208 out | 1.33 | 28.5 |
| 2026-10-13 | eda1da7 | orders | final, unattended Review and Check | no | yes (critical) | FAIL, names it | not measured | 22 in, 44197 cache write, 438788 cache read, 3127 out | n/a | 0.25 | 0.8 |
| 2026-10-13 | 4c18907 | reset | final, unattended Review and Check | no | yes (high) | FAIL, names it | not measured | 32 in, 50495 cache write, 686397 cache read, 4717 out | n/a | 0.32 | 1.1 |
| 2026-10-13 | 4c18907 | search | final, unattended Review and Check | no | yes (critical) | PASS, does not name it | not measured | 28 in, 48161 cache write, 589302 cache read, 3896 out | n/a | 0.29 | 0.9 |
