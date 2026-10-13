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
