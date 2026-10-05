# ADR 0010: Remove the eval fixtures, share the plan review through artifacts or a secret Gist

Date: 2026-10-03 · Status: accepted · Applies to: `evals/`, `templates/plan-review.html`, `scripts/plan_review.py`

## Context

Two separate decisions landed in v9.5.0.

**Eval fixtures.** `evals/` held three seeded-defect projects plus a wiring smoke test,
run by a nightly and per-PR workflow that calls `claude -p`. The job is gated on an
`ANTHROPIC_API_KEY` repository secret. The secret was never set, so the job concluded
`skipped` on its latest nightly run and could not gate a merge. Keeping a suite that
never runs costs maintenance (validators, docs, a marketing claim) and gives false
assurance.

**Sharing the plan review.** The HTML plan review worked for one person on one machine.
Sharing it with a teammate had no route, and comments returned as a downloaded JSON file
the author had to place by hand. Downloads are also blocked inside the Claude artifact
viewer.

## Decision

1. Delete `evals/` and the `Eval Fixtures` workflow, and remove every validator check
   and doc claim that depended on them. Gate logic stays covered by
   `scripts/tests/test-temper.sh`; the wiring gap is enforced by the stage-gate Stop
   hook (ADR 0005), not by a live run.
2. Add **Share HTML review** at the Plan gate with two paths, chosen by the session:
   - **Artifact** (preferred): publish with the `db` capability so comments return
     through the shared store, with no manual file step.
   - **Secret Gist** (fallback): free and needs only `gh`, rendered through
     gist.githack.com. Comments return by copy and paste.
3. Rendering moves out of the model and into `scripts/plan_review.py`, so escaping and
   section splitting are deterministic and tested.
4. Nothing is published without the user confirming where the plan goes.

## Why

- A free static host can show the page but cannot receive comments without a server.
  The artifact store is the only free option that closes the loop, which is why it is
  preferred and why the Gist path stays a paste based fallback.
- A secret Gist is unlisted, not private. The flow says so and offers to delete the Gist
  after the comments are applied.
- Filling a 15KB template by hand in a prompt is slow and unsafe: plan text containing
  `</script>` would break the page. A script fixes both and can be tested.

## Consequences

- Temper has no behavioral regression suite for its own prompts. A future one should be
  runnable without a secret in CI, or run on demand only.
- The gist.githack.com link format was not exercised from the build environment (its
  network policy blocks the host); the flow tells the user how to get a working link if
  the constructed one does not render.
- Reviewers need Contributor access to an artifact to save comments; Viewers fall back to
  Copy comments.
