# ADR-0015: Draft pull requests, stacked by branch pointers, and the optional readiness skill

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
4. **The review-readiness skill is optional and never vendored.** When a skill named `review-readiness` is available, the pull
   request options run its Steps 1 to 5 once per part, and stop before the step that would mark the request ready. It runs at
   Commit, not Review, because it creates the pull request. When it is absent, the question offers to install it or to skip it
   with a reason, and Temper's own steps run.
5. **An armed run never pushes.** The options are not offered to it, and not to `/temper:fix`.

## Consequences

- The CLI cannot read the home folder, so it does not look for the skill there: the orchestrator passes
  `--skill review-readiness` to `temper next` when the session lists it, and the project's own `.claude/skills` folder is also
  read. `next` and the view are built by one function, so they cannot disagree.
- A failed part stops the run of parts, reports the pull requests already open, and prints the commands for the rest.
