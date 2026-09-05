# Temper

| Command | Purpose |
|---------|---------|
| `/temper` | Unified SDLC: intent → plan → design → build → review → check |
| `/temper:intent` | Capture an idea as a draft `intent.md` (build later) |
| `/temper:plan` | Plan with blast radius |
| `/temper:design` | System design (complex/medium features) |
| `/temper:build` | TDD + quality gates |
| `/temper:review` | Confidence-scored review |
| `/temper:check` | Stack validation |
| `/temper:fix` | RCA + fix |
| `/temper:pack` | Manage quality packs |
| `/temper:status` | Quality + observability dashboard |
| `/temper:init` | Seed a project's `.claude/temper.config` (idempotent) |

**Autonomous Continuation (opt-in):** after approving the plan, `/temper` can run the
remaining stages unattended and park before commit. Armed at the plan gate (never at
invocation); never pushes/merges. With the `autonomy:` block absent or `enabled: false`,
every gate is the ordinary interactive one. Config: `.claude/temper.config` → `autonomy:`.

**v7 — the deterministic spine:** every gate verdict is computed by `scripts/temper`
(`temper gate {stage}`) from an evidence ledger (`temper evidence add`), not asserted by
a model. `git commit` is blocked by a native pre-commit hook + an in-agent PreToolUse
hook whenever a gate is FAIL and unoverridden — see `packs/hooks/rules.md`.

**Version:** 9.3.0 — see `CHANGELOG.md` for history.
Config: `.claude/temper.config` | Docs: `$CLAUDE_PLUGIN_ROOT/reference/`
CLI reference: `scripts/temper --help` | Retired systems: `$CLAUDE_PLUGIN_ROOT/docs/history/`

**Developing temper (this repo):**
- Test: `bash scripts/tests/test-temper.sh` (ends `PASS: N  FAIL: 0`); validators:
  `bash scripts/quality-check.sh` (also runs in CI via quality.yml).
- Layout: `commands/` (slash commands) · `agents/` (stage subprocess briefs) ·
  `reference/` (methodology) · `packs/` (rules) · `scripts/temper` (the deterministic
  spine — gate logic lives HERE, never in a prompt) · `scripts/hooks/` · `evals/`
  (seeded-defect fixtures).
- Known mistakes: a gate-mechanics change is a `scripts/temper` edit + a
  `test-temper.sh` case, not a prompt edit; hooks must fail OPEN except their one
  detected-violation path; never re-add per-stage logic to `commands/temper.md` or
  `commands/fix.md` — it belongs in `agents/{stage}.md` (including the stage's return
  box: a brief must never point a clean-context subprocess at an orchestrator file);
  new commands and agents must be listed in `.claude-plugin/plugin.json`.

<!-- Nothing follows. Do not add a generated advice section here: validate-docs.sh
     rejects the TOKENOMICS:START / TOKENOMICS:END markers (docs/history/tokenomics.md).
     Never write the markers' full comment syntax inside this comment; the embedded
     close-delimiter would end it early. -->

