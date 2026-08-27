# AGENTS.md

Guidance for AI coding agents working **on the Temper repository itself** — Codex,
Gemini CLI, Cursor, OpenCode, Antigravity, Copilot, and anything else that reads
`AGENTS.md`. Claude Code reads the same content from `.claude/CLAUDE.md`; keep the two
in agreement.

> **Scope.** This file configures work on *this repo*. It is not the thing you copy into
> a project that wants to *use* Temper — that is
> [`templates/AGENTS.temper.md`](templates/AGENTS.temper.md), and the install paths are
> in [`docs/agents.md`](docs/agents.md).

## What Temper is

An intent-gated SDLC for AI-generated code: `intent → plan → design? → build → review →
check → commit`. Its defining property is that **every gate verdict is computed by
`scripts/temper` from an evidence ledger, never asserted by a model**, and a native git
`pre-commit` hook blocks the commit while any gate is red.

## Commands

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

Under an agent with no slash commands, the same work is reachable through the `temper`
skill (`skills/temper/SKILL.md`), which is written to be self-sufficient.

## Layout

```
commands/     → slash commands (Markdown; the orchestration contracts)
agents/       → stage subprocess briefs, one per stage
reference/    → methodology, one file per stage + portability.md
packs/        → quality-pack rules
skills/       → skills (SKILL.md per directory) — the universal surface
scripts/temper→ the deterministic spine; gate logic lives HERE, never in a prompt
scripts/hooks/→ hook rules (Claude Code contract) + cursor-adapter.sh
templates/    → artifact templates + AGENTS.temper.md for consumers
evals/        → seeded-defect fixtures
docs/         → user documentation, incl. per-agent install guides
```

## Working on this repo

- **Test:** `bash scripts/tests/test-temper.sh` (must end `PASS: N  FAIL: 0`).
- **Validate:** `bash scripts/quality-check.sh`, `bash scripts/validate-plugin.sh`,
  `bash scripts/validate-docs.sh`, `bash scripts/validate-readme.sh`. All four run in
  CI via `.github/workflows/quality.yml`.

### Multi-agent: one source tree, many manifests

Temper ships manifests for several agents over **one** set of `commands/`, `agents/`,
and `skills/`. There is no generated export and there must never be one: Temper had a
generated `.cursor/` copy once, a generator bug froze it three majors behind, and it was
removed rather than keep misrepresenting what those users got (CHANGELOG v9.0.0).

| Surface | File |
|---|---|
| Claude Code | `.claude-plugin/{plugin,marketplace}.json`, `hooks/hooks.json` |
| Cursor | `.cursor-plugin/{plugin,marketplace}.json`, `hooks/cursor-hooks.json` |
| Codex | `.codex-plugin/plugin.json` |
| Antigravity | `.agents/plugins/marketplace.json` |
| OpenCode | `.opencode/skills` → symlink to `skills/` |
| Gemini CLI | `.gemini/commands/**.toml` — thin shims, no prompt bodies |
| Everything else | `skills/**/SKILL.md` via the `skills` CLI, `AGENTS.md` |
| Generic / folder discovery | `plugin.json` |

Consequences for any change you make:

1. **Adding a command** means adding it to `.claude-plugin/plugin.json`'s array **and**
   adding a `.gemini/commands/` shim. `validate-plugin.sh` fails if you forget either,
   and fails again if the shim's `description` drifts from the command's frontmatter.
2. **Adding a skill** means a `SKILL.md` with **both** `name:` and `description:` in its
   frontmatter. The `skills` CLI silently skips a skill missing either — a skipped skill
   looks identical to a working one until someone reports it missing.
3. **Adding an agent brief** means adding it to `.claude-plugin/plugin.json`'s `agents`
   array; the Cursor manifest covers `./agents/` wholesale and parity is asserted.
4. **Version stamps** are rewritten by `scripts/version-bump.sh` across every manifest.
   Never hand-edit one; `validate-plugin.sh` fails on any disagreement.
5. **Hook rules are written once**, against Claude Code's contract, in
   `scripts/hooks/*.sh`. `scripts/hooks/cursor-adapter.sh` translates for Cursor. Never
   write a second implementation of a rule.
6. **Capability limits get stated, never smoothed over.** They go in
   `reference/portability.md` and are repeated in the install docs. If an agent cannot
   enforce something, say so there rather than implying parity.

### Known mistakes

- A gate-mechanics change is a `scripts/temper` edit plus a `test-temper.sh` case — not
  a prompt edit. Gate logic never lives in a prompt.
- Hooks must fail **open** on every path except their one detected-violation path.
- Never re-add per-stage logic to `commands/temper.md` or `commands/fix.md`; it belongs
  in `agents/{stage}.md`, including the stage's return box. A brief must never point a
  clean-context subprocess at an orchestrator file.
- Never duplicate a prompt body into a per-agent file. Shims point at the one real file.

**Version:** 9.3.0 — see [`CHANGELOG.md`](CHANGELOG.md).
Config: `.claude/temper.config` · CLI: `scripts/temper --help` · Portability:
[`reference/portability.md`](reference/portability.md)
