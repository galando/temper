# Temper

| Command | Purpose |
|---------|---------|
| `/temper:plan` | Plan with blast radius |
| `/temper:build` | TDD + quality gates |
| `/temper:review` | Confidence-scored review |
| `/temper:check` | Stack validation |
| `/temper:fix` | RCA + fix |
| `/temper:pack` | Manage quality packs |
| `/temper:status` | Quality dashboard |

Config: `.claude/temper.config` | Docs: `$CLAUDE_PLUGIN_ROOT/.claude-plugin/reference/`

<!-- TOKENOMICS:START -->
## Token Optimization Insights

_Last updated: 2026-04-01_

### Context Management
- You read files you don't end up using. Use `Grep` first to locate relevant files before reading them — reduces unnecessary context by ~3%.
- Your context snowballs at **turn 7** on average (15% of sessions). Use `/compact` proactively after turn 5-7 on long sessions to prevent unbounded growth.
- You could benefit from subagents for parallel tasks. Consider splitting multi-file operations into parallel agent tasks.
- You receive verbose command output. Prefer `Grep`/`Read` tools over bash commands when searching files to reduce output tokens.
- CLAUDE.md instructions may be adding overhead (~0% of session tokens). Keep instructions concise and remove redundant entries.

### Prompt Quality
- **15%** of your prompts are under 10 words. Include specific file paths, function names, and expected outcomes to reduce clarification rounds.

### Model Usage
- You use Opus/Claude for **1%** of simple tasks. Prefer **Sonnet** for editing, small fixes, and exploration tasks to reduce token usage by ~5x on those sessions.
- MCP server(s) **some servers** are loaded but never used. Consider removing them to reduce per-session overhead.
<!-- TOKENOMICS:END -->
