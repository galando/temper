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

Release engineers and the CI pipeline read Temper's gate results. Today they have
two choices. `temper report` prints a table for people. `.temper/gates.json` holds
internal state, keyed by stage. A CI step must parse that file and copy the verdict
logic. One pipeline greps `gates.json` for `"verdict": "FAIL"` next to `"check"`.
That grep breaks when the state schema gains a field. We want one stable JSON
output for the current run. A machine must be able to read it without knowing
Temper's internals.

Facts: `temper report --json` prints `gates.json` as it is (the internal shape).
Assumption: CI users want one row for each requirement, not only one verdict for
each stage. The first CI user will confirm this.

### Success Criteria

- [ ] AC-01 [required]: `temper report --ci` prints one JSON document. Its top level is
  a flat array. Each stage is one object with `stage`, `verdict`, and a
  `requirements[]` array of `{name, pass, detail}` (source: the CI guide §3 | PROJ-1187)
  Why: CI steps are the main users. Without a stable shape, each user must build
  its own parser, and it breaks when internals change.
  Validate: scenario — covered by "CI JSON shape is stable across a run"
- [ ] AC-02 [optional]: The JSON may list override rows, with the approver name, for
  each overridden stage (source: the CI guide §4)
  Why: an audit trail in the CI output shows an overridden FAIL at the place where
  people decide to merge.
  Validate: manual — read the output of a run with one recorded override
  Deferred: needs the audit-compliance sign-off. Decide at the plan gate.
- [ ] AC-03 [required]: The JSON output is the same for the same ledger, byte for byte
  (proposed)
  Why: CI caches and diffs compare the output, so random order causes false alarms.
  Validate: scenario — covered by "Same ledger gives the same bytes"

### Constraints

- The command makes no network call and uses only the standard library (source: the temper CLI header contract)
- The internal schema of `.temper/gates.json` does not change (source: CHANGELOG compatibility note | PROJ-1187)
- The output has no color codes and no progress text (proposed)

### Scope and Non-goals

- In scope: the `temper report` subcommand, its output contract, tests in the CLI's test suite
- Out of scope: HTML output, upload of the report, the write path of gates.json
- Must keep working: `temper report` (human table) and `temper report --json` (gates.json as it is)

### Business Outcome

Teams use Temper's gate in CI without wrapper scripts. We measure this as the
number of downstream repos that read `--ci` output (owner: Dana, reviewed each quarter).

### Target Users

- Release engineer: adds one `temper report --ci` line to the pipeline → the CI step fails the build on any FAIL requirement, with no parsing of internals
- Reviewer: opens the CI job log → sees pass or fail rows for every stage of the run

### Open Questions

- Blocking: does `--ci` exit non-zero when any stage FAILs, or does `gate` alone own the exit code; consequence: pipelines that use the exit code need a wrapper if we choose wrong; owner: Marco.
- Deferred: does the array include stages with no verdict yet; consequence: users must handle missing stages either way; why work can proceed: the shape does not change, so we can omit missing stages now and add them later; needed by: before the first outside user.

### Decisions

- Include `requirements[]` for each stage or only verdicts? -> a verdict plus the full requirements array for each stage (Dana Okafor, 2026-09-29)
- The CI guide says override rows "may" appear. Is that required or optional? -> optional. We keep the source word in AC-02 (Marco Reyes, 2026-09-29)

---

## Scenarios (BDD)

## Scenario Coverage Checklist

## Source Traceability

### Context Sources

- consulted: PROJ-1187 — the linked issue: current timeouts and support quotes (retrieved 2026-09-18)
