# Temper

| Command | Purpose |
|---------|---------|
| `/temper` | Unified SDLC: plan → design → build → review → check |
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

**Version:** 8.0.0 — see `CHANGELOG.md` for history.
Config: `.claude/temper.config` | Docs: `$CLAUDE_PLUGIN_ROOT/reference/`
CLI reference: `scripts/temper --help` | Retired systems: `$CLAUDE_PLUGIN_ROOT/reference/tokenomics.md`

<!-- Nothing follows. A generated "Token Optimization Insights" section, delimited by
     TOKENOMICS:START / TOKENOMICS:END markers, used to be re-injected here every
     session; it was standing advice that cost more than it saved and duplicated
     judgment the model already applies. Tokenomics is a retired system — see
     reference/tokenomics.md. validate-docs.sh fails if it returns. Do not quote the
     literal marker syntax in this comment: the embedded close-delimiter ends the
     comment early and the rest renders as visible context. -->

