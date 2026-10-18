# Temper

| Command | Purpose |
|---------|---------|
| `/temper` | Unified SDLC: intent → plan → design → build → review → check |
| `/temper:intent` | Capture an idea as a draft `intent.md` (build later) |
| `/temper:plan` | Plan with blast radius (a door into `/temper`) |
| `/temper:design` | System design, complex/medium features (a door into `/temper`) |
| `/temper:build` | TDD + quality gates (a door into `/temper`) |
| `/temper:review` | Confidence-scored review (a door into `/temper`) |
| `/temper:check` | Stack validation (a door into `/temper`) |
| `/temper:fix` | RCA + fix |
| `/temper:pack` | Manage quality packs |
| `/temper:status` | Quality + observability dashboard |
| `/temper:init` | Seed a project's `.claude/temper.config` (idempotent) |

**Autonomous Continuation (opt-in):** after approving the plan, `/temper` can run the
remaining stages unattended and park before commit. Armed at the plan gate (never at
invocation); never pushes/merges. With the `autonomy:` block absent or `enabled: false`,
every gate is the ordinary interactive one. Config: `.claude/temper.config` → `autonomy:`.

**The deterministic spine (v7):** every gate verdict is computed by `scripts/temper`
(`temper gate {stage}`) from an evidence ledger (`temper evidence add`), not asserted by
a model. `git commit` is blocked by a native pre-commit hook (and, with the guardrails pack,
an in-agent PreToolUse hook) whenever a gate is FAIL and unoverridden: see `packs/guardrails/rules.md`.

**One flow (ADR 0012, ADR 0013).** `temper next --json` (`scripts/flow.py`) says what comes next,
with each gate's exact question and options; `commands/temper.md` is a loop over it. The CLI writes
`.temper/view.json` after every change, the one file of the CLI's the mod reads. The person decides
each gate only in the `Temper gate` question, with the mod or without it, in every mode; the mod
counts an answer only on an exact match for the CLI's run and step, guards, and draws the run (its
bar decides nothing). The guard is not a sandbox (`docs/trust.md`). The stage commands above are
doors into `/temper`.

**Version:** 9.7.1 (history: `CHANGELOG.md`).
Config: `.claude/temper.config` | Docs: `reference/`
CLI reference: `scripts/temper --help` | Retired systems: `docs/history/`

**Developing temper (this repo):**
- Test: `bash scripts/selftest/test-temper.sh` (ends `PASS: N  FAIL: 0`); validators:
  `bash scripts/quality-check.sh` (also runs in CI via quality.yml).
- Directory readiness: `bash scripts/validate-directory.sh` (no raw HTML in the README, no
  assets folder path in text, no `options` key). Run it before any README or manifest change.
- The mod (pure rules, wiring, drawing) and its test suite: after any change to them run
  `claude plugin test .`, `tsc -p tsconfig.mod.json` (TypeScript 5.6, as CI runs it) and
  `bash scripts/check-mod-calls.sh`; the reviewed `$` calls live in that script.
- Layout: `commands/` (slash commands) · `agents/` (stage subprocess briefs) ·
  `reference/` (methodology) · `packs/` (rules) · `scripts/temper` (the deterministic
  spine — gate logic lives HERE, never in a prompt) · `scripts/guards/` ·
  `scripts/plan_review.py` (renders and merges the HTML plan review).
- Known mistakes: a gate-mechanics change is a `scripts/temper` edit + a
  `test-temper.sh` case, not a prompt edit; what comes next, a gate's options and the grouped
  Build loop are `scripts/flow.py` (a case in `temper-cases-8.sh`; regenerate
  `scripts/selftest/view-fixtures.ts` with `make-view-fixtures.sh` when the view changes), never
  a list in a page; hooks must fail OPEN except their one
  detected-violation path; never re-add per-stage logic to `commands/temper.md` or
  `commands/fix.md` — it belongs in that stage's own brief in `agents/` (including the
  stage's return box: a brief must never point a clean-context subprocess at an
  orchestrator file); new commands and agents must be listed in `.claude-plugin/plugin.json`;
  the person decides only in a question dialog, so never add a button that decides to the
  mod, and never give a stage command a flow of its own (it is a door into `/temper`).

<!-- Nothing follows. Do not add a generated advice section here: validate-docs.sh
     rejects the TOKENOMICS:START / TOKENOMICS:END markers (docs/history/tokenomics.md).
     Never write the markers' full comment syntax inside this comment; the embedded
     close-delimiter would end it early. -->
