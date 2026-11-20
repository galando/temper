# ADR-0021: A finding is repaired in its stage

**Status:** Accepted
**Date:** 2026-11-19
**Amends:** ADR-0009 (a second carve out of the commit gate), ADR-0011 (resolution 1: the commits the CLI makes in a run
that goes on by itself), ADR-0013 (the flow's own action at Review and Check)

## Context

Before this record a blocking finding of Review, or a failed row of Check, went back to Build: a step back that wiped
the ledgers of the stages after it, a fix pass that had to write a failing test whatever the finding was, and a second
full Review of the whole change. In a run that goes on by itself the rule took that step back once. The measured runs
paid a Build and a Review round for a finding of one line, and a finding of a name or a comment was forced to fake a
failing test. Anyone could also mark a finding resolved with any text in the place of a commit (WP18 closed that hole,
and until this record no commit was ever one `evidence resolve` takes).

## Decision

1. **A finding is repaired in its stage.** One High or critical finding of Review, or one failed row of Check whose
   failure record has the class `code`, is repaired where it was found, as the CLI's own action, in every mode:
   `temper repair start --stage review|check` opens a window when every condition of `can_start`
   (`scripts/repair_ops.py`) holds, a fresh Build agent fixes and commits nothing, `temper repair commit` makes the
   CLI's commit and runs `integrate` and `gate build` (at Check also `check run`) on the new tree, and a reader that did
   not write the fix rechecks the diff (the section `Re-check:` of `agents/review.md`). A diff over 300 changed lines,
   or one that touches a file no finding names, gets a full Review in the place of the recheck.
2. **Only the CLI resolves a finding, for its own repair commit.** `temper repair close` resolves a finding when a
   `recheck #<id>: fixed` row was written after the commit and after the recheck's launch mark (`temper repair mark`),
   the recheck completed, the checks passed on the repair tree, and, for a finding marked `proof: test`, the CLI ran a
   RED before the fix and a GREEN after it on unchanged test files. `evidence resolve` takes a commit only when the run
   state records it as a repair and a recheck row follows it, and a hand call takes only a finding `repair close`
   resolved. No model calls it.
3. **A repair that made things worse is reverted.** A row that passed before fails after, the open blocking findings
   are not fewer, the recheck names a new blocking finding, or the recheck did not complete: the CLI commits the tree
   Review read again, through the same carve out, and the run asks `repair.stop`, which names what broke.
4. **Never by rule.** A contested or accepted finding, a file outside the plan, the spec folder, the config, the git
   folder, a locked acceptance test, a dependency manifest or lockfile, a CI file, a sensitive path or a plan that
   touches one (risk H), an unfinished Review, an environment fault, a check that was not measured, a criterion only the
   person can confirm, an acceptance test the triage does not blame on the code, a skipped stage, a fix run, and a diff
   that removes test lines. Each is a question, or a recorded stop in a run that goes on by itself.
5. **The budget.** One repair by rule a stage, counted in the one budget of ADR-0019, and one more on the person's
   click (Repair again); then the option is gone. With the budget spent the question still offers Accept a finding,
   Override and continue, Loop back to Build and Save for later. The loop back stays the way out and is never taken by
   rule.
6. **A verdict is of the tree it judged.** The commit gate's row `checked tree` passes a Review verdict of an older tree
   only when the difference is repair commits the CLI recorded, whose checks ran again and whose recheck completed.

7. **A plan fault a narrow change repairs costs no replan (WP25).** `temper plan amend task N --add-file F` is the
   amendment by rule: it only adds to a task a file another task of its own group declares, and that task to its
   Depends line, and it is no person only call, because its whole effect is bounded by the CLI (blocker B3 of the red
   team). `temper plan patch` stays the person's: every command line, and every file outside the approved set (`task N
   --add-file F`). Both run the plan gate's static rows on the result and refuse a row it newly fails, spend one repeat,
   append to `.temper/evidence/amendments.json` and move `plan_hash`; neither writes the approved record. Neither
   ledger row claims who called: only the mod checks the click (`docs/trust.md`). A full replan keeps the built tasks
   whose approved fields did not change (`temper group keep`).

## Amendments

- **ADR-0009** gains a second carve out of the commit gate: the row `repair commit` passes the one commit of a repair
  window when its token is set, HEAD is the token's parent, the staged tree is the token's tree, the run is at Review
  or Check on its own branch and every staged file is approved or a test. It never applies to the final commit:
  `repair start` refuses at the commit stage, so no token exists there. The carve out lives in the CLI, which the
  installed hook calls, so a hook installed by 9.8.4 or by the base gets it with no new install.
- **ADR-0011 resolution 1**: in a run that goes on by itself the CLI makes, besides its group and checkpoint commits,
  the commit of a repair in the stage and the commit that reverts it.
- **ADR-0013**: at Review and Check the flow's own `auto` action `repair start` comes before the rule's move and before
  the question. ADR-0012 point 3 still holds for a step back: going back clears what is redone.

## Alternatives Considered

### Keep the loop back to Build
- **Pros:** one path for every fix; the second Review reads everything again.
- **Cons:** a Build and a Review round for a finding of one line, and a failing test forced where none fits.
- **Why not chosen:** the measured runs paid for it, and the narrow recheck with the CLI's own runs covers the change.

### Let the fixer resolve its own finding
- **Pros:** no recheck launch.
- **Cons:** the writer judges its own fix.
- **Why not chosen:** rule 8: a reader that did not write the fix confirms it, after the CLI's checks passed.

## Consequences

- A repaired finding costs no dialog: the run still asks twice.
- The recheck reads the diff, not the code around it: a defect outside the changed lines is caught only by the CLI's
  runs. A project with a thin suite gets less than a second full Review gave; the fall back to a full Review stays for
  a large diff.
- The CLI cannot tell the fixer and the reader apart; the order of the rows (after the commit and after the launch
  mark) stands in for it.
