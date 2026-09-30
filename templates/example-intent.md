# Intent: Export Gate Ledger as CI-Readable JSON

**Author:** Dana Okafor <dana.okafor@example.com>
**Status:** draft
**Created:** 2026-09-29
**Ticket:** PROJ-1187
**Reviewer:** Marco Reyes <marco.reyes@example.com> (EM)
**Complexity:** medium

---

## Intent (IDD)

### Problem

Release engineers and the CI pipeline consume Temper's gate results, but today the
only renderings are `temper report` (human table) and `.temper/gates.json`
(internal state keyed by stage). A CI step that wants "did every gate pass, and
which requirement failed" must parse the internal file and re-implement verdict
logic. Concretely: a pipeline step that wants to fail the build when the check
gate FAILs currently greps `gates.json` for `"verdict": "FAIL"` next to
`"check"` — which breaks the moment the state schema gains a field. Desired:
one stable, documented JSON rendering of the current run's ledger that a machine
can consume without knowing Temper's internals.

Facts: `temper report --json` outputs `gates.json` verbatim (internal shape).
Assumption: CI consumers want per-requirement rows, not only per-stage verdicts —
to be confirmed by the first consumer.

### Success Criteria

- [ ] AC-01 [required]: `temper report --ci` emits a stable JSON document whose
  top level is a flat array, one object per stage with `stage`, `verdict`, and a
  `requirements[]` array of `{name, pass, detail}` (source: docs/ci-guide.md §3 | PROJ-1187)
  Why: CI steps are the primary consumer; without a stable machine shape every
  consumer re-derives it and breaks on internal changes.
  Validate: scenario — covered by "CI JSON shape is stable across a run"
- [ ] AC-02 [optional]: the JSON includes override rows with approver identity
  for any overridden stage (proposed)
  Why: an audit trail in CI output makes an overridden FAIL visible where the
  merge decision is actually made.
  Validate: manual — inspect output on a run with one override recorded
  Deferred: needs the audit-compliance sign-off; decide at the plan gate.

### Constraints

- JSON output must be producible with no network access and stdlib only (source: scripts/temper header contract)
- No change to `.temper/gates.json`'s internal schema (source: CHANGELOG compatibility note | PROJ-1187)
- Output must be deterministic — same ledger, byte-identical JSON (proposed)

### Scope and Non-goals

- In scope: `temper report` subcommand, its output contract, tests in scripts/tests/test-temper.sh
- Out of scope: HTML renderings, remote/upload of the report, the gates.json write path
- Must keep working: `temper report` (human table) and `temper report --json` (verbatim gates.json)

### Business Outcome

Teams adopt Temper's gate in CI without wrapper scripts; measurable as the count
of downstream repos consuming `--ci` output (owner: Dana, reviewed quarterly).

### Target Users

- Release engineer: pastes one `temper report --ci` line into the pipeline → the CI step fails the build on any FAIL requirement without parsing internals
- Reviewer: opens the CI job log → sees per-requirement pass/fail rows for every stage of the run

### Open Questions

- Blocking: does `--ci` exit nonzero when any stage FAILs, or is exit code owned by `gate` alone; consequence: pipelines that rely on exit code would need a wrapper if we choose wrong; owner: Marco.
- Deferred: should the array include stages with no verdict yet; consequence: consumers must handle absent stages either way; why work can proceed: shape is unaffected, absent stages can be omitted now and added compatibly; needed by: before the first external consumer.

### Decisions

- Include `requirements[]` per stage or only verdicts? -> per-stage verdict plus full requirements array (Dana Okafor, 2026-09-29)

---

## Scenarios (BDD)

## Scenario Coverage Checklist

## Source Traceability

### Context Sources

- consulted: PROJ-1187 — the linked issue: current timeouts and support quotes (retrieved 2026-09-18)
