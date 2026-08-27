---
description: "Running Temper under agents other than Claude Code — plugin root resolution, capability fallbacks, and the honest support matrix"
---

# Portability

Temper's spine is a bash CLI and a git hook; neither belongs to any one agent. What
*is* agent-specific is the thin layer above it — how a plugin is installed, how a stage
runs in its own context, how a gate asks a human, and which lifecycle events a hook can
actually block. This file is the single definition of that layer. Every command and
agent brief points here rather than restating it.

**The rule this file exists to enforce:** one source tree, one implementation of every
rule, and a translator where a contract differs. Temper shipped a generated `.cursor/`
export once (v5.1–v9.0.0); a generator bug froze it three majors behind and it was
removed rather than keep misrepresenting what Cursor users got. A second copy of
anything is how that happens.

So: every manifest in this repo points at the same `commands/`, `agents/`, and
`skills/`; `scripts/hooks/cursor-adapter.sh` translates one hook contract into another
rather than duplicating a rule; and the Gemini CLI command files are *shims* that read
`commands/*.md` rather than restating it. Nothing here is generated, and
`validate-plugin.sh` fails the build if any of that stops being true.

---

## Plugin Root Resolution

Prompts refer to the plugin's install directory constantly — `reference/*.md`,
`packs/*/rules.md`, `scripts/temper`. Agents name it differently, and some don't name
it at all. Resolve in this order and use the result wherever a Temper file writes
`$CLAUDE_PLUGIN_ROOT`:

1. `$CLAUDE_PLUGIN_ROOT` — set by Claude Code.
2. `$CURSOR_PLUGIN_ROOT` — set by Cursor.
3. Walk up from the file you're reading until you find a directory holding
   `commands/`, `agents/`, and `scripts/temper`.
4. The default install paths: `~/.claude/plugins/temper`, `~/.cursor/plugins/temper`,
   `~/.cursor/plugins/local/temper`.
5. Still nothing → say "Cannot locate the Temper plugin. Set `CLAUDE_PLUGIN_ROOT` or
   `CURSOR_PLUGIN_ROOT`, or reinstall." and stop. Do not guess a path.

`scripts/temper root` implements exactly this and prints the answer — it resolves from
its own location first, so it works when invoked by absolute path with no environment
at all. Once you can run the CLI, `$(temper root)` is the value; the chain above is for
finding the CLI in the first place.

## Capability Fallbacks

Three things the pipeline does are named after Claude Code tools. Each has a defined
fallback; nothing in the pipeline is skipped because a tool is missing.

| Pipeline step | Claude Code | Cursor / Antigravity | Codex, Gemini CLI, OpenCode, any other |
|---|---|---|---|
| Run a stage in a clean context | `Agent` tool with `agents/{stage}.md` | subagent from the same `agents/{stage}.md` | run the brief inline, then summarize back to the box it defines and drop the working detail — or better, run the stage as its own session |
| Ask the human at a gate | `AskUserQuestion` | numbered options as plain text; stop and wait | numbered options as plain text; stop and wait |
| Pick a stage's model | `temper model {stage}` → `Agent(model:)` | `temper model {stage}`, mapped to the agent's own tier | ignore; the session's model runs it |
| Invoke a stage | `/temper:{stage}` | `/temper:{stage}` | `/temper:{stage}` under Gemini CLI; elsewhere the `temper` skill |

**Inline stages are a real degradation, not an equivalent.** The isolated subprocess is
what makes a stage's context genuinely clean — an inline run carries the orchestrator's
conversation with it, which is the failure mode `agents/*.md` exists to prevent. Under
an agent with no subagents, prefer running each stage as its own `/temper:{stage}`
invocation in a fresh session over running the whole pipeline inline in one.

**A gate is never skipped for lack of `AskUserQuestion`.** The gate is `temper gate
{stage}` — a CLI call whose verdict lands in `.temper/gates.json` — plus a human
decision. Print the verdict, print the options, stop. The pipeline does not advance on
the model's own say-so under any agent.

## Hook Enforcement, By Agent

Temper's rules live once in `scripts/hooks/*.sh`, written against Claude Code's hook
contract (Claude-shaped JSON on stdin, exit 2 = block).
`scripts/hooks/cursor-adapter.sh` translates Cursor's payloads in and Cursor's JSON
responses out. What differs is not the rule but *which lifecycle events an agent lets a
hook refuse*:

| Guarantee | Claude Code | Cursor | Codex, Gemini CLI, OpenCode, Antigravity, others |
|---|---|---|---|
| **Commit gate on `git commit`** (native git `pre-commit`, `scripts/hooks/install.sh`) | enforced | **enforced** | **enforced** |
| In-agent commit gate (`block-uncommitted-gate.sh`) | `PreToolUse:Bash` → blocks | `beforeShellExecution` → denies | — |
| Secret scan on shell commands | `PreToolUse:Bash` → blocks | `beforeShellExecution` → denies | — |
| Override confirmation (`confirm-override.sh`) | `PreToolUse:Bash` → asks | `beforeShellExecution` → asks | — |
| Pre-edit guards (secrets, protected paths, regression-test write protection) | `PreToolUse:Edit\|Write` → blocks | **not available** — Cursor has no pre-edit event | — |
| Post-edit formatter (`run-formatter.sh`) | `PostToolUse` | `afterFileEdit` | — |
| Forbidden-import check | `PostToolUse` → blocks | `afterFileEdit` → **advisory only** | — |
| Standalone-stage gate debt (`verify-stage-gate.sh`) | `Stop` → blocks | `stop` → **advisory only** | — |

Cursor's `stop` and `afterFileEdit` responses are `void` by Cursor's own contract — a
hook cannot refuse either event. The adapter reports those verdicts on stderr and
appends them to `.temper/hooks.log` instead of pretending they blocked.

**The headline guarantee survives everywhere.** The gate that physically stops a red
commit is a native git `pre-commit` hook installed by `scripts/hooks/install.sh`. It
knows nothing about agents, so it fires on `git commit` from an agent, a terminal, or
an IDE button, under every row of that table — including the "any other agent" column,
where it is the *only* deterministic enforcement and therefore the install step that
matters most.

## The Roster

Temper reaches an agent by one of four routes. Every route serves the **same**
`commands/`, `agents/`, and `skills/` — there is no export anywhere in this table.

| Route | Agents | Surface |
|---|---|---|
| Native plugin | Claude Code, Cursor, Codex, Antigravity | `.claude-plugin/`, `.cursor-plugin/`, `.codex-plugin/`, `.agents/plugins/` |
| Native commands | Gemini CLI | `.gemini/commands/**.toml` — thin shims pointing at `commands/*.md` |
| Skills install | ~77 agents via the [`skills` CLI](https://github.com/vercel-labs/skills) — OpenCode, Amp, Cline, Zed, Warp, Copilot, Kimi, Augment, Replit, and the rest | `skills/**/SKILL.md`, entry point `skills/temper/SKILL.md` |
| Instruction file | anything that reads `AGENTS.md` | `templates/AGENTS.temper.md` |

`npx skills add galando/temper` is the one command that covers the third row. It reads
`skills/**/SKILL.md` and installs into whichever agents it finds. Two consequences bind
every skill in this repo:

- **`name:` and `description:` are both required** in the frontmatter. The CLI *silently
  skips* a skill missing either — no error, the skill simply never appears. Three of
  Temper's skills shipped without `name:` until v9.3.0 and were invisible to that route.
- **A per-skill install copies only `skills/<name>/`** — not `scripts/`, not
  `reference/`, not `commands/`. `skills/temper/SKILL.md` therefore opens by resolving
  or cloning the CLI, and refuses to run the pipeline without it. That refusal is the
  point: Temper whose gates are model-asserted is not Temper.

### Per-agent surfaces

| Surface | Claude Code | Cursor | Codex | Antigravity | Gemini CLI | OpenCode / skills CLI |
|---|---|---|---|---|---|---|
| Plugin manifest | `.claude-plugin/plugin.json` | `.cursor-plugin/plugin.json` | `.codex-plugin/plugin.json` | `.agents/plugins/marketplace.json` | — | — |
| Marketplace | `.claude-plugin/marketplace.json` | `.cursor-plugin/marketplace.json` | same `plugin.json` | same file | — | — |
| Commands | `commands/*.md` | `commands/*.md` | via skill | via skill | `.gemini/commands/**.toml` | via skill |
| Skills | `skills/` | `skills/` | `skills/` | `skills/` | via skill | `skills/`, `.opencode/skills` symlink |
| Hooks | `hooks/hooks.json` + `packs/hooks/settings.hooks.json` | `hooks/cursor-hooks.json` + `packs/hooks/cursor.hooks.json` | — | — | — | — |
| Generic manifest | — | — | — | `plugin.json` | — | — |

Commands, agents, skills, packs, reference, and scripts are shared by every column. One
copy, no export.

## Agents With No Hook System

Most of the roster is here: Codex, Gemini CLI, OpenCode, Antigravity, Aider, Copilot,
Zed, Warp, and the rest. They load Temper's skills and (where they have them) commands,
run the CLI, and record evidence exactly as Claude Code does — because none of that was
ever agent-specific. What they do not have is anything that can refuse a tool call.

That changes what is *enforced*, never what is *required*. Two things carry the weight
there:

1. **The native git `pre-commit` hook** (`scripts/hooks/install.sh`). It is the only
   deterministic enforcement available, and it is complete for the thing that matters
   most — a red commit. Install it; the docs never soften this step.
2. **`skills/temper/SKILL.md`'s rules section**, which states the invariants as method
   rather than as things a script will catch: never assert a verdict, stop at every
   gate, record evidence, an override is a human's decision.

`templates/AGENTS.temper.md` is the snippet to append to a consuming project's
`AGENTS.md` when the agent has no plugin or skill system at all — it names the checkout
path, the stage briefs, the gate commands, and the same rules.
