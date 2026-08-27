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
anything is how that happens. There is no export here — the Cursor manifest points at
the same `commands/`, `agents/`, and `skills/` the Claude Code manifest does, and
`scripts/hooks/cursor-adapter.sh` translates one hook contract into the other.

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

| Pipeline step | Claude Code | Cursor | Any other agent |
|---|---|---|---|
| Run a stage in a clean context | `Agent` tool with `agents/{stage}.md` | subagent from the same `agents/{stage}.md` | run the brief inline, then summarize back to the box it defines and drop the working detail |
| Ask the human at a gate | `AskUserQuestion` | numbered options as plain text; stop and wait | numbered options as plain text; stop and wait |
| Pick a stage's model | `temper model {stage}` → `Agent(model:)` | `temper model {stage}`, mapped to the agent's own tier | ignore; the session's model runs it |

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

| Guarantee | Claude Code | Cursor | Any other agent |
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

## Files

| Surface | Claude Code | Cursor |
|---|---|---|
| Plugin manifest | `.claude-plugin/plugin.json` | `.cursor-plugin/plugin.json` |
| Marketplace manifest | `.claude-plugin/marketplace.json` | `.cursor-plugin/marketplace.json` |
| Plugin-level hooks | `hooks/hooks.json` | `hooks/cursor-hooks.json` |
| Hooks pack (opt-in) | `packs/hooks/settings.hooks.json` | `packs/hooks/cursor.hooks.json` |
| Commands / agents / skills / packs / reference / scripts | shared — one copy, no export | shared |

`scripts/validate-plugin.sh` asserts parity between the two manifests: every command,
agent, and skill the Claude manifest declares must be reachable through the Cursor
manifest's paths, and both must carry the same version. That check is what stops the
Cursor surface from silently falling behind again.

## Agents With No Plugin System

Codex, Gemini CLI, Aider, and anything else that reads `AGENTS.md` get Temper by
pointing at a checkout. `templates/AGENTS.temper.md` is the snippet to append to the
project's `AGENTS.md`; it names the checkout path, the commands, and the one setup step
(`bash <temper>/scripts/hooks/install.sh`) that makes the commit gate real. Everything
downstream — the CLI, the gates, the evidence ledger, the artifacts under
`.temper/specs/` — behaves identically, because none of it was ever agent-specific.
