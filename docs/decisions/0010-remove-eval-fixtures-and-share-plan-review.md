# ADR 0010: Remove the eval fixtures, share the plan review through a Claude artifact

Date: 2026-10-03, amended in 9.6.5 · Status: accepted · Applies to: `evals/`, `templates/plan-review.html`, `scripts/plan_review.py`

## Context

Two separate decisions landed in v9.5.0.

**Eval fixtures.** `evals/` held three seeded-defect projects plus a wiring smoke test,
run by a nightly and per-PR workflow that calls `claude -p`. The job needed a repository
setting that was never made, so the job concluded `skipped` on its latest nightly run and
could not gate a merge. Keeping a suite that never runs costs maintenance (validators,
docs, a marketing claim) and gives false assurance.

**Sharing the plan review.** The HTML plan review worked for one person on one machine.
Sharing it with a teammate had no route, and comments returned as a downloaded JSON file
the author had to place by hand. Downloads are also blocked inside the Claude artifact
viewer.

## Decision

1. Delete `evals/` and the `Eval Fixtures` workflow, and remove every validator check
   and doc claim that depended on them. Gate logic stays covered by
   `scripts/tests/test-temper.sh`; the wiring gap is enforced by the stage-gate Stop
   hook (ADR 0005), not by a live run.
2. Add **Share HTML review** at the Plan gate. It publishes the page as a Claude artifact
   with the `db` capability, so comments return through the shared store, with no manual
   file step. Without the Artifact tool the gate offers the local review (**Open HTML
   review**) instead.
3. Rendering moves out of the model and into `scripts/plan_review.py`, so escaping and
   section splitting are deterministic and tested.
4. Nothing is published without the user confirming where the plan goes.

## Why

- A free static host can show the page but cannot receive comments without a server.
  The artifact store is the only free option that closes the loop.
- Filling a 15KB template by hand in a prompt is slow and unsafe: plan text containing
  `</script>` would break the page. A script fixes both and can be tested.

## Consequences

- Temper has no behavioral regression suite for its own prompts. A future one should run
  in CI with nothing to configure, or run on demand only.
- Reviewers need Contributor access to an artifact to save comments; Viewers fall back to
  Copy comments.

## Amendment (9.6.5)

v9.5.0 also shipped a second sharing path for sessions without the Artifact tool: an
unlisted link made through a separate command line tool, with comments sent back by
paste. 9.6.5 removes it. Share HTML review now has one path, the Claude artifact, and a
session without the Artifact tool is offered the local review instead.
