# ADR-0015: Draft pull requests, stacked by branch pointers

**Status:** Accepted
**Date:** 2026-10-30
**Amends:** ADR-0013 (the Commit question)

## Context

Commit made the commit and stopped. Opening the pull request was left to the person, and a run with several Build groups
produced one commit history that reviewers had to read whole.

## Decision

1. **Every pull request Temper opens is a draft.** `gh pr create` always carries `--draft`. Temper never runs `gh pr ready` and
   never removes the draft state. A guard (a test and the mod rule) fails on a `gh pr create` without `--draft` and on any
   `gh pr ready`.
2. **`reference/pr.md` is the only place Temper pushes or calls `gh`.** Its preconditions never fail the commit: with no `gh`,
   no login, no `origin` or no named branch, the commit is kept and the fallback commands are printed.
3. **A stacked pull request is one part per Build group, made by branch pointers.** Part k below N gets a branch
   `<branch>-part-<k>` at the merge commit that ended it; part N is the feature branch itself, so its tip is what Check proved.
   Part 1 targets the default branch and part k targets part k minus one. Every commit keeps the SHA Build gave it, and
   history is never rewritten. `scripts/pr_parts.py` cuts the parts at the `merge(<slug>): group G<n>` commits and folds a part
   whose change is only comments or blank lines into the next one.
4. **Temper opens the pull requests itself, and no outside skill is used.** At a passed Check the question offers **Commit and open
   PR** and, with two or more Build groups, **Commit and open stacked PRs**; `reference/pr.md` is what runs. It runs at Commit, not
   Review, because it creates the pull request.
5. **An armed run never pushes.** The options are not offered to it, and not to `/temper:fix`.

## Consequences

- A failed part stops the run of parts, reports the pull requests already open, and prints the commands for the rest.
