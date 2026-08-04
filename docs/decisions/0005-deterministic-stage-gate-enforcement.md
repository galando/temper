# 0005 — Deterministic stage-gate enforcement for standalone commands

**Status:** accepted (v8.0.0, pre-release)
**Drivers:** live wiring measurement; v8's core determinism claim

## Context

v8's headline contract is that every gate verdict is computed by `scripts/temper` from
an evidence ledger, never asserted by a model. The unified `/temper` orchestrator holds
that contract structurally — it runs `temper gate {stage}` itself at every boundary.
The standalone commands (`/temper:plan`, `:build`, `:review`, `:check`) did not: their
prompts *instructed* the model to call the CLI, and whether it happened was the model's
choice.

Running `evals/run-wiring-smoke.sh` live (it had not been re-run for the v8
verification) measured how often that choice went the right way at the v8 head
(`28c7b1b`), n=3: **wired 1 of 3 runs.** In the two failures, Plan never called
`temper state set complexity` or `temper gate plan`, and Build wrote **no evidence file
at all** — leaving `temper gate commit` unable to see that either stage happened. A
session that skips the CLI is indistinguishable from a repo that never ran Temper, so
the commit gate correctly (and silently) degrades to a no-op.

A first remedy moved the gate call into each command's numbered step list instead of a
trailing section the model never reached. Sampled n=3 it went 3/3 against baseline's
1/3 — but that is p = 0.20 (one-tailed Fisher), and no prompt change can turn "the model
usually complies" into a guarantee. Prompt position shifts the failure rate; it cannot
zero it.

## Decision

Enforce the contract in the hook layer, the same place the commit gate already lives:

- **`scripts/hooks/stage-marker.sh`** (UserPromptSubmit): when the submitted prompt
  invokes a standalone stage command, record the owed gate in
  `.temper/pending-stage.json`.
- **`scripts/hooks/verify-stage-gate.sh`** (Stop): while a marker is pending and
  `.temper/gates.json` has no verdict for that stage, refuse to end the session
  (exit 2) with instructions to record evidence and run the gate. **Any verdict
  satisfies it, PASS or FAIL** — the guarantee is that `temper gate <stage>` ran, not
  that it succeeded. Each firing appends to `.temper/hooks.log`.

Shipped two ways: plugin-level `hooks/hooks.json` (fires for `--plugin-dir` and
marketplace installs with no settings merge) and the hooks pack's
`settings.hooks.json` (projects using the pack's copy-paste path).

The numbered-step prompt fix is kept as defense-in-depth — it makes the first attempt
more likely to be right, so the hook rarely has to fire.

Scope: `/temper` (unified) is not marked — its orchestrator owns the gates and a
session legitimately ends at any human gate. `/temper:fix` is not marked — an RCA-only
session can legitimately end before build evidence exists.

## Degradation contract

Consistent with every hook in the pack — exactly one fail-closed path:

- No marker, verdict present, python3 absent, marker unreadable → exit 0.
- Loop guards, both fail-open: after 2 refusals (counted in the marker), and when the
  harness reports `stop_hook_active` while our counter never moved (the marker isn't
  persisting — don't loop on a broken counter).
- The single block: a standalone stage session trying to end with no gate verdict.

## Evidence

- Unit: 15 cases in `scripts/tests/test-temper.sh` (marker detection and non-detection,
  block/clear/loop-guard paths, corrupt inputs, FAIL-verdict acceptance, a live
  `temper gate plan` round-trip, and a pinned regression for the argv-vs-stdin bug).
- Probe: a throwaway plugin confirmed empirically that plugin `hooks/hooks.json` fires
  in `claude -p` mode and that UserPromptSubmit's input field is `prompt`. (Both points
  contradicted a docs-derived answer; the probe is authoritative.)
- Live end-to-end: `claude -p "/temper:plan ..."` on the wiring-smoke fixture with the
  plugin loaded. `.temper/hooks.log` shows the mechanism catching the real failure mode
  in the wild:

  ```
  18:53:55Z verify-stage-gate blocked stop (stage=plan, no verdict)
  18:54:05Z verify-stage-gate cleared (verdict recorded)
  ```

  The model attempted to end without running the gate, was blocked, ran
  `temper gate plan` (verdict FAIL — a trivial-tier plan has no artifacts by design,
  and FAIL satisfies the guarantee), and only then was allowed to finish.

## Alternatives rejected

- **Prompt repositioning alone** — measured insufficient class of fix (above).
- **Native git hook** — fires at commit, far too late: the defect is the *absence* of
  session-time evidence, which the commit gate cannot distinguish from "not a Temper
  run".
- **Blocking on PASS rather than any verdict** — would turn a legitimate interactive
  FAIL (user chooses "Save for later") into an unfinishable session.
