# Host capabilities for a cheaper, faster Temper (read-only map, 2026-11-15)

Method. The Claude Code docs map was truncated, so I fetched each page directly. Confidence tags: [doc] stated in a fetched page (URL given); [inferred] my reading; [not found] the fetched text does not say. Some pages were long and were read in part (noted where it matters). Local files read: /home/user/temper/docs/mod.md (lines 20-26, 141, 149) and /home/user/temper/types/index.d.ts (lines 1-57). No file was written; the scratch clone rule did not apply because nothing ran.

## 1. Subagents

- Frontmatter model and effort. `model` takes sonnet, opus, haiku, fable, a full ID, or inherit; `effort` takes low, medium, high, xhigh or max and overrides the session effort [doc https://code.claude.com/docs/en/sub-agents.md, Supported frontmatter fields].
- Per-launch override. The Agent tool takes a per-invocation `model` alias (not a full ID or inherit) and, from v2.1.292, an `effort`. Order: per-invocation, frontmatter, CLAUDE_CODE_SUBAGENT_MODEL, parent model [doc sub-agents.md, Choose a model]. CLAUDE_CODE_SUBAGENT_MODEL_FORCE overrides the field for every subagent, forks included [doc sub-agents.md, Choose a model; Fork].
- Mods can also choose the model at spawn: a mod's agent.spawn hook replaces the first source [doc https://code.claude.com/docs/en/agent-teams.md, Specify teammates and models; https://code.claude.com/docs/en/plugins/mods/reference.md, agent.spawn].
- Effort trap. A subagent with no effort of its own runs at the session level only if it is on the main model. On another model "that level doesn't apply" [doc https://code.claude.com/docs/en/model-config.md, Effort level of subagents and teammates]. A Haiku subagent therefore gets Haiku's own default unless its definition sets effort.
- Starting context. Fresh window. System prompt is the agent's own prompt plus environment details, not Claude Code's system prompt. CLAUDE.md loads, except for the built-in Explore and Plan agents, which also skip the git status snapshot. Custom agents can set `omitClaudeMd: true`. The parent conversation is not inherited [doc sub-agents.md, What loads at startup].
- Cache. A subagent's first request does not read the parent's cache; it warms its own. Subagent requests get the 5-minute TTL by default, even on a subscription; `subagentPromptCacheTtl` or frontmatter `experimental.cacheTtl` changes it [doc https://code.claude.com/docs/en/prompt-caching.md, Subagents and the cache; Which TTL each request gets].
- Parallel limits. 20 concurrently running subagents by default; the 21st fails with "Concurrent subagent limit reached". `CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` raises it (v2.1.217+). No cap on total launches. Nesting depth defaults to 3 (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`). A fork takes a slot; a resume skips the check [doc sub-agents.md, Concurrent subagent limit].
- Workflow agents: 16 concurrent by default (`CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS`, 1 to 256); 1,000 agents per run; 4,096 items per parallel() or pipeline() call [doc https://code.claude.com/docs/en/workflows.md, Behavior and limits].
- Background or foreground. Foreground blocks the main conversation and passes permission prompts through. Background runs concurrently and its prompts surface in the main session. "A subagent that Claude spawns from your main conversation starts in the background" by default [doc sub-agents.md, Run subagents in foreground or background]. The page also says `CLAUDE_CODE_FORK_SUBAGENT=0` makes Claude wait; the exact default for a plain Agent call is not spelled out in what I read [inferred].
- Fork. Inherits the full conversation: same system prompt, tools, model and history. Its first request reads the parent's cache, so a fork costs less than a fresh subagent for the same context. Forks cannot spawn forks. `isolation: "worktree"` is available [doc sub-agents.md, Fork the current conversation; How forks differ]. A dollar figure beyond cache reuse: [not found].
- Explore and Plan are one-shot and return no agent ID, so they cannot be resumed [doc sub-agents.md, Resume subagents].

## 2. Continuing a subagent

- Yes. SendMessage sends to the agent ID or name. A resumed subagent "retain[s] its full conversation history". SendMessage does not need agent teams [doc sub-agents.md, Resume subagents].
- The resumed run's first request "can keep reading the prompt cache the original run warmed", still within the subagent's 5-minute TTL [doc prompt-caching.md, Other requests can also read...].
- A mod's agent.spawn hook fires on resume (v2.1.299+), with `e.resume` set, and can refuse it with `{ deny: reason }` [doc https://code.claude.com/docs/en/plugins/mods/reference.md, agent.spawn].
- From a plugin command: [inferred] the tool is in the main session's toolset. I found no plugin-specific page for it.

## 3. AskUserQuestion

- Each call: 1 to 4 questions; each question 2 to 4 options; `header` at most 12 characters; `multiSelect`; an "Other" free-text row [doc https://code.claude.com/docs/en/agent-sdk/user-input.md, Question format; Limitations].
- Several questions in one call return one answers map (question text to label) [doc user-input.md, Return answers]. That they show as one dialog is [inferred].
- Option previews: TypeScript SDK only, set by `toolConfig.askUserQuestion.previewFormat` (markdown or html). CLI preview: [not found].
- NOT available in subagents spawned via the Agent tool [doc user-input.md, Limitations]. Gates therefore stay in the main session.
- Unanswered: waits by default. `askUserQuestionTimeout` (60s, 5m, 10m) submits the selected options and tells Claude the user may be away. The timer does not run in background sessions, in screen-reader mode or under Remote Control [doc https://code.claude.com/docs/en/tools-reference.md, AskUserQuestion tool behavior].
- `--permission-prompts none` removes AskUserQuestion [doc https://code.claude.com/docs/en/headless.md, Turn off permission prompts in unattended runs].

## 4. Hooks and the mod surface

- Events (from a summarised extraction of https://code.claude.com/docs/en/hooks.md, truncated at 100000 of 293529 chars, so verify exact names): SessionStart, Setup, UserPromptSubmit, UserPromptExpansion, PreToolUse, PermissionRequest, PermissionDenied, PostToolUse, PostToolUseFailure, PostToolBatch, Notification, MessageDisplay, SubagentStart, SubagentStop, TaskCreated, TaskCompleted, Stop, StopFailure, TeammateIdle, InstructionsLoaded, ConfigChange, CwdChanged, DirectoryAdded, FileChanged, WorktreeCreate, WorktreeRemove, PreCompact, PostCompact, PreModelSwitch, PostModelSwitch, Elicitation, ElicitationResult, SessionEnd.
- Blocking per the extraction: UserPromptSubmit; PreToolUse (deny, ask, defer; `updatedInput` used in the costs example, https://code.claude.com/docs/en/costs.md, Offload processing to hooks); PostToolBatch (stops the loop before the next model call); SubagentStop (prevents the stop); Stop (keeps going); TaskCreated and TaskCompleted; TeammateIdle; ConfigChange; PreCompact; PreModelSwitch.
- Handler types: command, http, mcp_tool, prompt (30 s default), agent (experimental, 60 s default).
- Plugins: hooks in hooks/hooks.json, merged with user and project hooks, using ${CLAUDE_PLUGIN_ROOT} [doc https://code.claude.com/docs/en/hooks.md, Plugins, as extracted].
- Mods (early access; /home/user/temper/docs/mod.md:149 says so): a plugin ships a JS module listed in hooks/hooks.json `modules`. Events: turn.step (per-request `model` and `effort` via next({...e, model})), agent.spawn (choose a model, or deny), tool.call (deny, result or next), tool.check (allow, ask or deny), config.set, settings.read, prompt.*, ui.*, telemetry.*. Methods: $.agent (register, spawn, list), $.model.complete (maxTokens default 1024, up to 64000), $.tool, $.session [doc https://code.claude.com/docs/en/plugins/mods/reference.md, Files; Events; Limits].
- Mod surface in this repo (verified): /home/user/temper/types/index.d.ts:14-39 defines TemperView (stages, wait, next, groups) and :55 defines the plugin state. The mod reads the CLI's view.json and keeps no state of its own (docs/mod.md:28-30).

## 5. Workflows

- Plugin workflows: a script in `workflows/` at the plugin root (or the `workflows` manifest field). Runs as `/<plugin>:<name>` [doc https://code.claude.com/docs/en/workflows.md, Distribute a workflow in a plugin].
- Script API: agent() spawns one subagent (options include schema, stallMs, label; resolves to null on stop or an unrecoverable error); pipeline() and parallel() fan out; phase(), log(), args. No filesystem or shell access from the script itself; no module imports; Date.now() and Math.random() throw so relaunches repeat [doc workflows.md, What the saved script looks like; Behavior and limits; Edit a saved script].
- No mid-run user input. A run pauses only for permission prompts and usage-limit waits. "For sign-off between stages, run each stage as its own workflow" [doc workflows.md, Behavior and limits]. This is the key constraint for Temper's gates.
- Launch: a Workflow tool call. Interactive sessions show an approval with "Yes, and don't ask again for <name>" for bundled, saved or plugin workflows. In claude -p and the SDK there is no prompt; add `Workflow` or `Workflow(<name>)` to the allow rules, use auto mode, bypass mode, or a PreToolUse allow hook [doc workflows.md, Approve the plan before it runs].
- Whether a slash command starts a run without a model turn: [not found].
- Models per agent: "Claude Code picks each workflow agent's model in the same order it uses for subagents" [doc workflows.md, Cost]. Effort per agent: [not found].
- Resume: relaunch replays from saved results. Completed agents return their result unless the script changed before them. A failed agent reruns, and so does every agent the script starts after it. Missing results give "nothing to resume" [doc workflows.md, Resume after a pause].
- Fan-out cache: agents share a prefix when model, effort level, agent type, tools, output schema and working directory all match. The runtime holds the others up to 5 s (`CLAUDE_CODE_WORKFLOW_PREFIX_STAGGER_MS`) so they read the first agent's cache [doc workflows.md, Prompt caching in a fan-out]. Per-task worktrees (different cwd) would break the match [inferred from the cwd condition].
- Availability: all paid plans with API access, and Bedrock, Google Cloud's Agent Platform and Foundry. On Pro, turn on in /config. `disableWorkflows` and CLAUDE_CODE_DISABLE_WORKFLOWS turn it off [doc workflows.md, intro; Turn workflows off].
- Cost signal: a "Large workflow" warning above 25 agents or a projected 1.5M tokens. The size guideline default is medium, or small on Pro [doc workflows.md, Cost; Set a size guideline].

## 6. Headless and SDK

- claude -p flags confirmed in the fetched text: --allowedTools, --permission-mode, --output-format json|stream-json, --json-schema, --bare, --agents, --plugin-dir, --mcp-config, --settings, --append-system-prompt, --max-budget-usd, --permission-prompts none, --continue, --resume. --effort appears in the docs as `claude --effort ultracode` [doc https://code.claude.com/docs/en/headless.md; workflows.md, Have Claude write a workflow]. `/model sonnet` and `/effort` work in -p [doc headless.md, Customize the system prompt note]. CLAUDE_CODE_EFFORT_LEVEL is documented [doc model-config.md]. --model: [not verified; the CLI reference was not fetched].
- JSON output carries `total_cost_usd` and a per-model cost breakdown [doc headless.md, Pipe data through Claude].
- Parallel stage agents from a CLI: [inferred] run N `claude -p` processes in parallel, each with its own model and effort. Each is a separate session with its own cache. Use --agents or --plugin-dir to load definitions.
- --bare skips hooks, plugins, CLAUDE.md, auto memory and MCP unless flagged. Hooks do not run even when loaded by flag: "Hooks still don't run in bare mode when you pass them with --settings, or in the hooks/hooks.json ... of a plugin you load with a flag" [doc headless.md, Start faster with bare mode]. A driver that uses --bare loses the mod's guards.
- Agent SDK: AgentDefinition takes description, tools, disallowedTools, prompt, model, mcpServers, skills, maxTurns, autoCompactWindow, background, omitClaudeMd, memory, effort (low to max, or a number), permissionMode [doc https://code.claude.com/docs/en/agent-sdk/typescript.md, AgentDefinition]. canUseTool gates tool calls. A PreToolUse hook returning defer lets the process exit and resume later from the persisted session [doc https://code.claude.com/docs/en/agent-sdk/user-input.md, Handle tool approval requests].
- Mod in -p (verified in the repo): with enforcement on, a run stops at the first gate, and the mod draws nothing (/home/user/temper/docs/mod.md:141).

## 7. Skills, commands and agents: context cost

- Descriptions of every skill in the listing enter context every turn. "Every skill in the skill listing adds to your context on every turn, whether or not Claude ever uses it" [doc https://code.claude.com/docs/en/skills.md, Find unused skills].
- Description plus when_to_use is cut at 1,536 characters in the listing [doc skills.md, Frontmatter reference].
- `disable-model-invocation: true` removes the description from context; the full skill loads when invoked [doc skills.md, Control who invokes a skill].
- Bodies load only when invoked and stay for the session. After compaction the first 5,000 tokens of each invoked skill are kept, with a combined 25,000-token budget [doc skills.md, Skill content lifecycle, as extracted].
- Subagent descriptions: keep the combined set within a 15,000-token description budget [doc sub-agents.md, best practices].
- Plugin skills are namespaced `/plugin:skill`. `skillOverrides` does not apply to them [doc skills.md, Choose where skills load; Resolve skills that share a name].
- context: fork runs the skill in a new subagent of type `agent`, with `model` setting that subagent's model; it does not see the conversation [doc skills.md, Run skills in a subagent].
- Enabling a plugin's skills, commands, agents or hooks does not invalidate the cache; they are appended. MCP server changes do [doc https://code.claude.com/docs/en/prompt-caching.md, Enabling or disabling a plugin].

## 8. Current models and prices

Source: https://platform.claude.com/docs/en/about-claude/pricing (table; USD per million tokens).

| Model | Base input | 5m write | 1h write | Cache read | Output |
|---|---|---|---|---|---|
| Haiku 5.5 (prompt up to 100K) | $0.10 | $0.125 | $0.20 | $0.01 | $0.50 |
| Haiku 5.5 (prompt over 100K) | $0.50 | $0.625 | $1 | $0.05 | $2.50 |
| Sonnet 5.5 | $2 | $2.50 | $4 | $0.10 | $10 |
| Sonnet 5 | $2 | $2.50 | $4 | $0.20 | $10 |
| Opus 5.5 | $4 | $5 | $8 | $0.20 | $20 |
| Opus 5, 4.8, 4.7, 4.6, 4.5 | $5 | $6.25 | $10 | $0.50 | $25 |
| Fable 5.2 | $8 | $10 | $16 | $0.20 | $40 |
| Fable 5.1 | $10 | $12.50 | $20 | $0.25 | $50 |

- Context: all Claude 5 models and Fable have 1M input tokens and 128K max output [doc https://platform.claude.com/docs/en/about-claude/models/overview]. The 1M window has no premium beyond 200K, except that Haiku 5.5 costs more above 100K prompt tokens [doc https://code.claude.com/docs/en/model-config.md, Context windows].
- Batch: 50% off. Data residency: inference_geo "us" is 1.1x [doc pricing; models overview].
- Ratios computed from the table: Haiku 5.5 input and output are 1/20 of Sonnet 5.5; Opus 5.5 is 2x Sonnet 5.5 and 0.8x Opus 5 at $5/$25; Fable 5.2 is 2x Opus 5.5.
- Effort levels: low, medium, high, xhigh, max. Fable, Opus 5.5, Sonnet 5.5 and Haiku 5.5 support all five [doc model-config.md, Adjust effort level]. "ultracode" is a setting that plans a workflow per task, not a level [doc workflows.md].
- Thinking is always on for Fable, Opus 5.5, Sonnet 5.5 and Haiku 5.5 and cannot be turned off. Thinking tokens bill as output [doc https://code.claude.com/docs/en/costs.md, Adjust extended thinking].
- Output tokens per effort level: [not found]. The docs say lower effort is faster and cheaper but give no token counts.
- Default effort, a conflict between two docs: model-config says Fable 5.2, Opus 5.5, Sonnet 5.5 and Haiku 5.5 default to medium. The models overview table says Fable 5.2 high, Opus 5.5 medium, Sonnet 5.5 high, Haiku 5.5 medium. Verify before relying on either.

## 9. Prompt caching rules that matter for many short agents

- Minimum cacheable prompt: 512 tokens on Fable 5.x, Opus 5.5, Sonnet 5.5 and Haiku 5.5 (Sonnet 5 needs 1,024; Haiku 4.5 needs 4,096). Shorter prompts are not cached, and no error is returned [doc https://platform.claude.com/docs/en/build-with-claude/prompt-caching.md, Minimum cacheable prompt length]. Whether a Claude Code agent's prefix (with tool definitions) clears 512 tokens: [inferred yes; not measured].
- Multipliers: 5m write 1.25x; 1h write 2x; read 0.1x; read 0.05x on Opus 5.5 and Sonnet 5.5; read 0.025x on Fable 5.x [doc platform prompt-caching.md, TTL and multipliers; pricing footnotes].
- TTL: default 5 minutes, refreshed free on each hit; a 1h option via `cache_control` ttl [doc platform prompt-caching.md].
- Claude Code: the main conversation gets 1h only on a subscription within plan usage; on API keys, usage credits or cloud providers it is 5m. promptCacheTtl or CLAUDE_CODE_PROMPT_CACHE_TTL sets it. Subagents and workflows default to 5m [doc https://code.claude.com/docs/en/prompt-caching.md, Cache lifetime; Which TTL each request gets]. Break-even: a 1h write costs 1.6x a 5m write (2 / 1.25), so 1h pays only when reads follow the write after the 5m window [computed].
- Prefix order: tools, then system, then messages. A change at one level invalidates it and every later level. Hits need identical content up to the breakpoint [doc platform prompt-caching.md, Prefix matching].
- What breaks it (platform table): changing tool definitions invalidates all three levels. The web-search toggle, speed setting, tool_choice and images invalidate system and messages but not tools. Thinking parameters and effort are model-specific [doc platform prompt-caching.md, table; reading: a check mark means that level is kept].
- Claude Code specifics: each model has its own cache, so a /model switch or a skill with a model field costs a full miss; changing effort keeps the cache on Opus 5.5, Sonnet 5.5, Haiku 5.5 and Fable 5.1+ with an API key or subscription [doc https://code.claude.com/docs/en/prompt-caching.md, Switching models; Changing effort level]. CLAUDE.md edits do not apply mid-session. Compaction rewrites the conversation layer.
- Limits: 4 explicit breakpoints per request; the lookback is 20 blocks [doc platform prompt-caching.md, Breakpoints].
- Scope: caches are isolated per organization, and per workspace on the API and Foundry (per organization on Google managed and Bedrock) [doc platform prompt-caching.md, Sharing]. In Claude Code the cache is effectively per machine and directory, because the system prompt embeds the auto memory path and a working-directory announcement [doc https://code.claude.com/docs/en/prompt-caching.md, Cache scope].
- Fan-out sharing requires the same model, effort, agent type, tools, output schema and working directory [doc workflows.md, Prompt caching in a fan-out].

## What this means for Temper (cost, time, questions, loops)

1. Cost. The largest levers the host offers are per-stage model and effort (frontmatter or per launch; Haiku 5.5 at 1/20 of Sonnet's price for prompts up to 100K), continuing a subagent instead of starting a new one (SendMessage), and keeping the shared prefix identical across fan-out agents.
2. Time. A plugin workflow removes model relays between steps and runs up to 16 agents at once; a resume replays completed agents from saved results.
3. Questions. AskUserQuestion takes up to 4 questions per call. Batch the gates that happen together. The host cannot ask from a subagent or from inside a workflow.
4. Loops. Stop, SubagentStop, PostToolBatch and TaskCompleted hooks, plus the agent.spawn resume deny, can bound loop-backs without a model's decision.

## Open items (not determined)

- Whether a /plugin:name workflow starts without a model turn: [not found].
- Whether agent() takes effort per call: [not found].
- Default effort conflict between model-config and the models overview (section 8).
- Whether --model is a claude -p flag: [not verified].
- Full hook event schemas and sync or async classes: the hooks page was read in part.
- Whether a plain Agent call (non-fork) waits or runs in background by default: [inferred; the docs point both ways].
- Dollar cost of a fork beyond cache reuse: [not found].
- Whether a worktree (different cwd) breaks prefix sharing for Agent-tool subagents: the cwd condition is documented for workflows only.
