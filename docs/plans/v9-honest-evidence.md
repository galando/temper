# v9 — Honest Evidence

**Status:** Proposed
**Scope:** Three moves, shipped together as one major release.
**Rule for the release:** remove more than it adds.

---

## Why

Temper's pitch is "gate verdicts are computed, never asserted by a model" (README:67).
Today that is true of the arithmetic and false of the inputs:

- `temper evidence add` records whatever `--exit` / `--value` / `--scenario` the caller
  asserts. It never executes anything. A fully fabricated run — five `evidence add`
  calls, zero real commands — reaches `temper gate commit -> PASS`. (Reproduced.)
- The in-agent commit gate (`block-uncommitted-gate.sh`) is **not registered** in
  `hooks/hooks.json` on a default install; it lives only in the copy-paste template
  `packs/hooks/settings.hooks.json`, and the documented enable path does not exist in
  `commands/pack.md`.
- The native-hook install step in README fails verbatim in a user shell
  (`$CLAUDE_PLUGIN_ROOT` is unset there), and `docs/getting-started.md` never mentions
  the hook at all — so the documented onboarding never installs the headline feature.

The fix is mostly reconnection, not invention: v3.1.0 already ran each scenario's test
individually ("Live Execution", still described in `reference/check.md`), and v7 already
made blocking mechanical. The two halves were never wired together.

---

## Move 1 — Make it honest (correct)

1. **`temper evidence run`** — the CLI executes the command itself:

   ```
   temper evidence run --stage build --phase red [--claim C] [--scenario N] -- <command...>
   ```

   Records the *real* exit code, duration, and output hash; writes the row with a new
   label `VERIFIED` that `evidence add` can never emit. `gate_build` and `gate_check`
   require VERIFIED rows for their test-run requirements (escape hatch:
   `gates.require-verified: false`). Side benefit: agent prompts get *shorter* — one
   command replaces every "now record your exit code" instruction.

2. **Coverage parsed, not asserted.** Small stdlib parsers for `lcov.info`,
   `coverage.xml`, and `coverage-summary.json`; `--value` is derived from the artifact.
   `check.coverage-threshold: off` becomes a recorded waiver — today the gate FAILs
   unconditionally when no coverage row exists, which structurally pushes the model
   toward fabricating one.

3. **Verdicts bound to tree state.** Record `git rev-parse HEAD` plus a worktree diff
   hash when a verdict is written. `temper gate commit` FAILs with "re-run
   /temper:check (tree changed since verification)" on mismatch. No verdicts at all →
   "no active Temper run — commit allowed" (this also defuses the abandoned-run
   commit-block trap; `temper abandon` disarms the gate through the same mechanism).

4. **Register the in-agent hooks by default.** `PreToolUse` (Bash →
   `block-secrets.sh` + `block-uncommitted-gate.sh`; Edit/Write → `block-secrets.sh`)
   and the `PostToolUse` forbidden-imports check move into `hooks/hooks.json`. All are
   fail-open by contract, so default-shipping is safe. Broaden the commit matcher so
   `command git commit --no-verify` and friends don't slip past.

5. **Bug sweep** — each demonstrated during the audit, each lands with a
   `test-temper.sh` regression:
   - No file locking: concurrent `evidence add` loses rows (7 of 20 survived). One
     flock + tempfile/os.replace helper for every JSON write.
   - Keyword-collision: a scenario row whose claim contains "test" satisfies the
     "tests pass" requirement. Add a structured `--kind test|coverage|scenario|lint|scan`
     field; gates match on kind, never on claim text.
   - `_glob_touch_match` reduces `**/auth/**` to substring "auth" → autonomy parks on
     `src/oauth2/`. Use real fnmatch.
   - Blast radius counts Temper's own untracked state files. Exclude `.temper/` and
     `.claude/` via pathspec.
   - The instructed TDD red run (`--phase red --exit 1 --label PROVEN`) triggers a
     spurious downgrade WARN every cycle. Exempt red-phase rows from the nonzero-exit
     downgrade.
   - RED/GREEN is count-based with no ordering — green-then-red passes. Compare
     timestamps.
   - `cmd_report` and the coverage compare interpolate paths into python source
     (crashes on apostrophe paths). Argv transport only.
   - `state clear` leaves `pending-stage.json`, so the documented reset strands the
     Stop-hook debt. Clear it too.
   - CI: add shellcheck and a macOS runner (a bash-3.2 crash already shipped once).

---

## Move 2 — Make it lighter (efficient)

1. **Delete dead machinery:** the adaptive-learning pack/reference/status panels
   (nothing collects accept/dismiss; the repo's own memory is empty after two majors),
   `templates/spec.md` + `templates/quickstart.md` (forbidden by `reference/plan.md`),
   temper-core's retired `capabilities:` table and v4/v5 archaeology, and `models` from
   init.md's retired-keys list (the CLI reads it; the retirement notice is wrong).
2. **`/temper:fix` becomes a thin variant of the `/temper` orchestrator.** Split
   `reference/fix.md` per stage; stop both agents reading all ~5k tokens each.
   Measured: ~35k → ~21k instruction tokens per fix run (−40%).
3. **`reference/review.md` diet.** Move dedup/consensus/threshold arithmetic into a
   deterministic `temper review merge`; delete the OCR merge formulas. ~4.7k → ~2.5k
   tokens on the heaviest stage context, and review output stops varying with how the
   model approximates arithmetic.
4. **Fast lane.** `temper lane` classifies from measured blast radius and change type
   (docs-only, single-file, config) into full/standard/fast. Fast = plan-lite,
   single-context execution, merged review+check. The script decides the lane, so the
   short path cannot be rationalized into an escape hatch.
5. **Correct the README claims** ("~500 lines of shell" vs ~2,290 actual; the
   "never asserted" phrasing becomes true in this release) and extend
   `validate-docs.sh` with a retired-claims guard so drift cannot recur.

---

## Move 3 — Make it effortless (easy to adopt)

1. **Plugin install = fully working.** Default enforcement is the registered in-agent
   hook. There is no step two.
2. **`install.sh` is demoted to optional strict mode.** Rationale: Claude Code has no
   pre-commit event, so only a native git hook can block commits made *outside* the
   agent — but the agent is the thing worth blocking, and the in-agent hook covers it
   with zero setup. `/temper:init` offers strict mode as a yes/no question (never a
   copy-paste command). The installer fixes then apply only there: resolve the hooks
   dir via `git rev-parse --git-path hooks` (worktrees), vendor the scripts so plugin
   updates don't silently kill the hook, python3 fallback chain that degrades open.
3. **Every blocking surface names the way out.** House rule: every FAIL/BLOCK print
   ends with one "→ next:" line naming a runnable command with its resolved path.
   `temper abandon` becomes the discoverable reset.
4. **`temper init` writes `.temper/.gitignore`:** runtime state ignored, `specs/`
   committed (the durable, PR-reviewable artifact).
5. **Docs:** getting-started gains the install step, first-run expectations (Plan:
   4–8 min, ~$1–2, from the existing A/B data), and the CLI/ledger reference section
   that three files already point to but which doesn't exist. One real recorded run
   replaces the hand-drawn output boxes.

---

## Versioning: v9, not v8.1

This release changes gate semantics (VERIFIED required), removes config keys and
templates, changes the default enforcement posture, and restructures `/temper:fix`.
Under semver those are breaking changes — a major. Shipping them as one coherent major
with a migration section is more honest than three minors that each break a little.
v8.1 would only be defensible if `require-verified` defaulted to off — which would keep
the current dishonesty as the default and defeat the release's purpose.

The release also introduces a **stability contract** (`STABILITY.md`): config keys,
gate semantics, the evidence-ledger schema, and CLI commands are API; one-major
deprecation window; `temper config validate` warns on unknown or removed keys.

## Migration (v8 → v9)

- Existing runs: `temper state clear` on first v9 invocation (offered, not silent).
  Old evidence rows remain readable; gates simply don't count unverified rows toward
  VERIFIED requirements.
- Removed config keys warn once via `temper config validate`.
- Repos with the old native hook: `/temper:init` detects and refreshes it, or removes
  it when strict mode is declined.

## Acceptance criteria

- The fabrication repro (five fake `evidence add` calls, zero real commands) yields
  `temper gate commit -> FAIL` naming the unverified requirements.
- Seeded-defect fixtures still 3/3; a new clean fixture passes every gate; a new
  adversarial fixture (agent pressured to skip tests) is blocked.
- A `test-temper.sh` regression exists for every bug in Move 1.5; shellcheck and the
  macOS job are green.
- Measured instruction tokens: full run ≤ 30k, fix run ≤ 22k.
- Fresh install, zero setup steps: agent's `git commit` is blocked on a red gate.

## Deferred — each lands as its own release after v9

Parallel wave builds (per-ticket subagents, gates at wave boundaries), diff-scoped
mutation testing, an MCP surface, the public head-to-head benchmark, the
implement-spec integration, post-compaction re-anchoring. They all amplify the core,
so they wait until the core is honest.
