# Temper

| Command | Purpose |
|---------|---------|
| `/temper` | Unified SDLC: plan → design → build → review → check |
| `/temper:plan` | Plan with blast radius |
| `/temper:design` | System design (complex/medium features) |
| `/temper:build` | TDD + quality gates |
| `/temper:review` | Confidence-scored review |
| `/temper:check` | Stack validation |
| `/temper:eval` | Behavioral verification (LM-judge + trajectory) |
| `/temper:fix` | RCA + fix |
| `/temper:pack` | Manage quality packs |
| `/temper:status` | Quality + observability dashboard |
| `/temper:init` | Seed a project's `.claude/temper.config` (idempotent) |

**Autonomous Continuation (opt-in):** after approving the plan, `/temper` can run the
remaining stages unattended and park before commit. Armed at the plan gate (never at
invocation); never pushes/merges; byte-identical to v5.9.0 when the `autonomy:` block is
absent or `enabled: false`. Config: `.claude/temper.config` → `autonomy:`.

**Version:** 6.0.1 — see `CHANGELOG.md` for history.
Config: `.claude/temper.config` | Docs: `$CLAUDE_PLUGIN_ROOT/reference/`
Token efficiency tips: `$CLAUDE_PLUGIN_ROOT/reference/tokenomics.md`
