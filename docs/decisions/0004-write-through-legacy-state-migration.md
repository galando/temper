# ADR-0004: Legacy build-state values are migrated write-through, not mapped on read

**Status:** Proposed
**Date:** 2026-07-31
**Supersedes:** (none)

## Context

Removing the Eval stage (ADR-0003) leaves three kinds of stale artifact on existing
installs. Two are inert by construction:

- an `eval:` block in `.claude/temper.config` — `_cfg_get` returns the caller's default for
  an unknown key, and after `gate_eval()` is deleted nothing asks for `eval.*`;
- an `"eval"` key in `.temper/gates.json` — `gate_commit` iterates a fixed
  `stages_to_check` list, so unlisted keys are never visited.

The third is **not** inert. An in-flight v7.0.x run can leave `.temper/build-state.json`
holding `next_stage: "eval"` or `stage: "eval_complete"`, and those values are read and
acted on.

Two components read that file, and they sit on opposite sides of a hard boundary:

- `scripts/temper` (the spine) reads it via `cmd_state_get` / `cmd_state_advance` /
  `gate_commit`.
- `scripts/hooks/verify-tests-ran.sh` is a **native git pre-commit hook**. It parses the
  JSON with an inline `python3 -c` and cannot shell out to `scripts/temper` — the hook must
  work in repos where the plugin is not installed or not on PATH, and its degradation
  contract forbids introducing a new failure mode. It treats `check_complete` (and, today,
  `eval_complete`) as the green sentinel and blocks otherwise.

The release also drops `eval_complete` from that hook's green set.

## Decision

Forward-map legacy values **write-through**: a `_state_migrate_legacy` helper in
`scripts/temper` rewrites `.temper/build-state.json` in place, mapping
`next_stage: "eval" → "commit"` and `stage: "eval_complete" → "check_complete"`. It is
idempotent and is called before any state read or write and at the top of `temper gate`.

Three properties are load-bearing:

1. **Write-through, not in-memory.** The git hook reads the file directly and cannot call
   the CLI. A read-only map would leave the legacy value on disk forever, and every
   `git commit` for that user would be blocked with
   `BLOCK: latest Temper stage is 'eval_complete'`. Healing the file on the first CLI touch
   is the only mechanism that reaches both readers.
2. **Atomic write** — temp file plus `os.replace`. The existing JSON writers
   (`_json_set_path`, `_json_append`) open the target `"w"` and truncate, which is tolerable
   for a write the caller requested and can retry. It is not tolerable for a migration that
   runs unbidden on read: an interrupt would turn recoverable stale state into no state.
   Generalising atomicity to the other writers is out of scope.
3. **A `grep -q '"eval'` fast path** before spawning `python3`. `cmd_state_get` runs several
   times per gate; without the guard the migration would add ~40 ms to each call for a
   no-op. With it, the steady-state cost is one grep on a ~400-byte file.

Migration heals *persisted* values only. Because `STAGE_SEQ_TEMPER` loses `eval`,
`temper state advance eval_complete ...` fails loudly with an unknown-stage error. That is
correct: nothing should ever advance *into* a removed stage.

## Alternatives Considered

### Read-only forward map in `cmd_state_get`

- **Pros:** No writes from a read path. Trivially safe.
- **Cons:** The git hook never sees the mapped value, so an upgraded user sitting on
  `stage: "eval_complete"` is blocked at every `git commit` indefinitely.
- **Why not chosen:** It fixes the reader that could have called the CLI and misses the one
  that cannot — which is the only reader that actually blocks the user.

### Teach `verify-tests-ran.sh` to forward-map `eval_complete` itself

- **Pros:** Fixes the block at the point of failure, no state writes at all.
- **Cons:** Violates the release's explicit requirement that the hook no longer match
  `eval_complete` (a forward map *is* matching it), and duplicates stage vocabulary into a
  layer that is supposed to know nothing about it.
- **Why not chosen:** It would also give a deliberately fail-open hook write-adjacent
  knowledge of state it must only read.

### A one-shot `temper migrate` subcommand the user runs manually

- **Pros:** Explicit, auditable, no implicit writes.
- **Cons:** Requires the user to know they need it — and they find out by being blocked at
  commit, which is exactly the experience being avoided.
- **Why not chosen:** A migration nobody knows to run is not a migration.

## Consequences

### Positive
- Upgrading mid-run is transparent: the first `/temper` command or gate heals the state file.
- The pattern generalises — any future stage rename gets two lines in the same helper.
- Establishes the layer rule explicitly: **state-format changes are healed at the spine on
  write, never interpreted by hooks on read.**

### Negative
- A read path now writes. Mitigated by idempotence, the grep guard, and the atomic replace.
- **Residual edge case, accepted:** a user who upgrades and runs plain `git commit` before
  any `temper` command still gets exactly one `BLOCK: latest Temper stage is
  'eval_complete'`. The first CLI touch clears it. The CHANGELOG migration note names the
  remedy.

### Neutral
- Adds two spine test cases. Both must assert the **on-disk** value, not just stdout —
  asserting stdout alone would pass with a read-only map and miss the entire point.

## References

- `.temper/specs/opus5-speed-refresh/design.md` — "Compatibility Contract", Decision 8
- `scripts/hooks/verify-tests-ran.sh` — the degradation contract this decision preserves
- ADR-0003 — the stage removal that creates the legacy values
