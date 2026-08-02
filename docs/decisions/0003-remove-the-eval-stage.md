# ADR-0003: Remove the Eval stage from the /temper pipeline

**Status:** Proposed
**Date:** 2026-07-31
**Supersedes:** (none)

## Context

`/temper` shipped a seventh pipeline stage, Eval, between Check and the commit gate. It
cost a `gate_eval()` branch in `scripts/temper`, an agent (`agents/eval.md`), a command
(`commands/eval.md`), a 232-line reference doc, a 5.5 KB skill (`skills/eval-judge/`), a
JSON template (`templates/evalset.json`), a config block, four generated `.cursor/`
artifacts and eight assertions in `scripts/tests/test-temper.sh`.

What it produced was an LM-judge aggregate score compared against a threshold. No other
gate consumed it, no feedback loop acted on it, and in practice the score was read and
ignored. Meanwhile the same repo carries `evals/` — a seeded-defect regression harness that
runs in CI and is genuinely load-bearing. The name collision routinely caused the two to be
confused.

Separately, the Opus 5 prompt refresh (`.temper/specs/opus5-speed-refresh`) set a target of
cutting the prompt surface by ≥35%. Every byte of the Eval stage counted against it.

## Decision

Delete the Eval stage entirely — the gate, the agent, the command, the reference doc, the
skill, the template and the `eval:` config block — rather than disabling it by default.
`temper gate eval` becomes a usage error; `temper gate check` advances straight to the
commit gate; `STAGES` and `STAGE_SEQ_TEMPER` lose the token.

`evals/` — `run-all.sh`, `run-fixture.sh`, `run-wiring-smoke.sh` and `fixtures/` — is
explicitly **not** part of this decision and must remain byte-identical. It is the only
behavioral verifier for the prompt-shortening work happening in the same release.

Backward compatibility is by omission where the artifact is inert, and by migration where
it is not (see ADR-0004): a stale `eval:` block in a user's config is never read because
`_cfg_get` returns the caller's default for unknown keys; a stale `"eval"` key in
`.temper/gates.json` is never visited because `gate_commit` iterates a fixed
`stages_to_check` list.

## Alternatives Considered

### Flip `eval.enabled` to `false` in the config template, keep the code

- **Pros:** Reversible in one line. No test churn. No risk to `gate commit`.
- **Cons:** Leaves ~10 KB of reference doc, a 5.5 KB skill, an agent, a command and a
  template on disk — all still loaded by `generate-cursor.sh`, still asserted by
  `validate-plugin.sh`, still counted against the 35% reduction target, and still
  discoverable as `/temper:eval` in the command list.
- **Why not chosen:** A disabled stage is still a stage the reader has to understand and
  the maintainer has to keep passing CI. It directly contradicts the size goal that
  motivated the release.

### Keep Eval but fold it into the Check gate

- **Pros:** Preserves the LM-judge signal without a seventh stage.
- **Cons:** Puts a non-deterministic model score inside a gate whose whole value is that
  its verdict is computed, not asserted. Check's verdict would stop being reproducible.
- **Why not chosen:** It inverts the v7 deterministic-spine principle.

## Consequences

### Positive
- Six-stage pipeline: plan → design → build → review → check → commit.
- ~18 KB of prompt surface and one gate branch removed.
- The `/temper:eval` vs `evals/` name collision disappears.

### Negative
- **Breaking change for v7.0.1 users** — a shipped stage and a shipped config key are
  removed. This is a MAJOR bump (v8.0.0) with a CHANGELOG migration note, not a patch.
- Any team that had wired the LM-judge score into their own reporting loses it with no
  replacement.

### Neutral
- The four generated `.cursor/` eval artifacts need no explicit delete: `generate-cursor.sh`
  does `rm -rf` on the output directory before rebuilding. The *assertions* in
  `validate-plugin.sh:222-234` do need removing, in the same commit.
  *(Moot as of v8.0.0: Cursor support and its generator were removed later in the same
  release. Left as written — this records the decision as it was made.)*

## References

- `.temper/specs/opus5-speed-refresh/intent.md` — SC3
- `.temper/specs/opus5-speed-refresh/design.md` — Workstream A
- ADR-0004 — the state-migration half of the compatibility story
