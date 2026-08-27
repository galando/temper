---
title: Agent Support
nav_order: 3
---

# Agent Support

Temper's spine is a bash CLI (`scripts/temper`) and a native git `pre-commit` hook.
Neither belongs to any one agent, so what differs between tools is only how they load
commands and skills — and how much a hook is allowed to refuse.

Every route below serves the **same** `commands/`, `agents/`, and `skills/`. There is no
generated export anywhere in this page.

## Fastest path — any agent, one command

The open [`skills` CLI](https://github.com/vercel-labs/skills) installs into ~77 agents
(OpenCode, Amp, Cline, Zed, Warp, Copilot, Kimi, Augment, Replit, Aider, and more):

```bash
npx skills add galando/temper            # install Temper's skills
npx skills add galando/temper --list     # browse first
```

{: .warning }
**A skills install gives you the method, not the CLI.** A per-skill install copies only
`skills/<name>/` — not `scripts/temper`. Temper's whole point is that gate verdicts are
*computed*, so `skills/temper/SKILL.md` opens by locating the CLI and refuses to run the
pipeline without it. Clone the repo (`git clone https://github.com/galando/temper.git
~/temper`) and the skill will find it.

## Native integrations

### Claude Code

```bash
/plugin marketplace add galando/temper
/plugin install temper
```

Or from the terminal: `claude plugin marketplace add galando/temper` then
`claude plugin install temper@temper`. Local development:
`claude --plugin-dir /path/to/temper`.

Everything works here: commands, per-stage subagents, skills, and both hook layers.

### Cursor

```bash
git clone https://github.com/galando/temper.git
ln -sfn "$(pwd)/temper" ~/.cursor/plugins/local/temper
```

Reload Cursor, then run `/temper "…"`. Cursor loads `commands/`, `agents/`, `skills/`,
and `hooks/cursor-hooks.json` from `.cursor-plugin/plugin.json`.
`scripts/hooks/cursor-adapter.sh` translates Cursor's hook contract onto the same rule
scripts Claude Code uses — no rule is implemented twice. Two Cursor events (`stop`,
`afterFileEdit`) cannot refuse anything, so two guards there are advisory; see the
matrix below.

### Codex

```bash
codex plugin marketplace add galando/temper
codex plugin add temper@temper
```

Codex reads `skills/` directly through `.codex-plugin/plugin.json`. Invoke with `@` —
e.g. `@temper` — then follow the skill.

### Antigravity CLI (`agy`)

```bash
agy plugin install https://github.com/galando/temper.git
```

Or from a local clone: `agy plugin install ./temper`. Skills and agent briefs are
discovered from the plugin root via `.agents/plugins/marketplace.json`.

### Gemini CLI

Temper's slash commands are wired natively as `.gemini/commands/**.toml`:

```bash
git clone https://github.com/galando/temper.git
cp -r temper/.gemini/commands/* ~/.gemini/commands/
```

You get `/temper`, `/temper:plan`, `/temper:build`, and the rest. Each `.toml` is a
**shim** — it points the agent at `commands/*.md` in your checkout rather than restating
the contract, so there is no second copy of a prompt to drift.

### OpenCode

```bash
npx skills add galando/temper -a opencode
```

OpenCode also discovers `.opencode/skills` (a symlink to `skills/`) inside a checkout.
Since OpenCode has no slash commands, drive the pipeline through the `temper` skill.

### Anything that reads AGENTS.md

Append the snippet to your project's `AGENTS.md` and point it at a checkout:

```bash
git clone https://github.com/galando/temper.git ~/temper
cat ~/temper/templates/AGENTS.temper.md >> /path/to/your/project/AGENTS.md
```

Replace the `<TEMPER>` placeholder with your checkout path.

## Then, in your project

Under Claude Code and Cursor, your first `/temper "…"` sets everything up. Everywhere
else, run the setup once per project:

```bash
cp ~/temper/templates/temper.config.default .claude/temper.config
~/temper/scripts/temper init
bash ~/temper/scripts/hooks/install.sh      # the commit gate — do not skip this
```

## What each agent actually enforces

The pipeline, the CLI, the gate verdicts, and the committed artifact chain are identical
everywhere. What differs is which lifecycle events an agent lets a hook *refuse*:

| | Claude Code | Cursor | Codex · Gemini · OpenCode · Antigravity · others |
|---|---|---|---|
| Commands | native | native | Gemini native; elsewhere via the `temper` skill |
| Stage briefs, skills, packs, artifacts | yes | yes | yes |
| `temper gate` verdicts + evidence ledger | yes | yes | yes |
| **Commit gate on `git commit`** (native git hook) | **enforced** | **enforced** | **enforced** |
| In-agent commit gate + secret scan on shell commands | blocks | denies | — |
| Override confirmation | asks | asks | — |
| Pre-edit guards (protected paths, regression-test protection) | blocks | not available | — |
| Stage-gate debt at end of session | blocks | advisory | — |
| Isolated per-stage context | subagent | subagent | inline or per-session (degraded) |

The bold row is the one that carries the weight. The gate that physically stops a red
commit is a git `pre-commit` hook — it knows nothing about agents, so it fires from an
agent, a terminal, or an IDE button. Under an agent with no hook system it is the *only*
deterministic enforcement there is, which is why `bash scripts/hooks/install.sh` is the
step this page refuses to soften.

Full detail, including why Cursor's `stop` and `afterFileEdit` hooks can only advise:
[`reference/portability.md`](https://github.com/galando/temper/blob/main/reference/portability.md).

## Next

- [Getting Started](getting-started) — the pipeline itself, stage by stage
- [Commands](commands) · [Packs](packs) · [Recommended Setup](recommended-setup)
