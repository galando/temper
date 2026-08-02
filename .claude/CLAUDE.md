# Temper

| Command | Purpose |
|---------|---------|
| `/temper` | Unified SDLC: plan → design → build → review → check |
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

<!-- TOKENOMICS:START -->
## Token Optimization Insights

_Last updated: 2026-07-31_

### Context Management
- Your context snowballs at **turn 28** on average (27% of sessions). Use `/compact` proactively after turn 26-28 on long sessions to prevent unbounded growth.
- Some sessions use significantly more tokens than others. Consider shorter, more focused sessions with clear goals.
- You read files you don't end up using. Use `Grep` first to locate relevant files before reading them — reduces unnecessary context by ~1%.
- You could benefit from subagents for parallel tasks. Consider splitting multi-file operations into parallel agent tasks.
- You receive verbose command output. Prefer `Grep`/`Read` tools over bash commands when searching files to reduce output tokens.

### Prompt Quality
- **7%** of your prompts are under 10 words. Include specific file paths, function names, and expected outcomes to reduce clarification rounds.

### Model Usage
- You use Opus/Claude for **3%** of simple tasks. Prefer **Sonnet** for editing, small fixes, and exploration tasks to reduce token usage by ~5x on those sessions.
<!-- TOKENOMICS:END -->
