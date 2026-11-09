# Evidence: Temper beside the workflow tools people choose between

Checked on 2026-11-09 against each tool's own repository: Temper 9.8.3, Superpowers 7.0.2, Spec Kit (main),
OpenSpec 1.16.1 and BMAD Method (main, the v7 preview). Every cell about another tool comes from a file in that
tool's repository, listed under [Sources](#sources). "Not found" means its README, docs and source do not say it,
not that it is proven absent. If a cell is wrong, open an issue and it will be corrected.

## The difference in one paragraph

All five tools make a coding agent state what it will build before it builds it. The four others do that with
instructions: skills, prompts and commands the model is asked to follow, and a person who reads the result. Two of
them also check that the planning files are well formed. Temper adds a program between the model and the commit. A
small CLI records what ran (a failing test, a passing test, the suite, coverage) and computes each gate from that
record, and a failed gate blocks `git commit`. That check is what Temper adds, and it is also why a Temper run costs
more.

## Side by side

| | Temper | Superpowers | Spec Kit | OpenSpec | BMAD Method |
|---|---|---|---|---|---|
| **How a step is enforced** | A CLI computes each gate from recorded evidence. With the mod, an edit outside the current stage is refused. | Instructions. One hook loads a skill's text when a session starts; nothing refuses a tool call. | Instructions, plus a script that checks the planning files exist and `plan.md` is not empty. | Instructions, plus `openspec validate`, which checks the structure of specs and changes. | Instructions: skills with step files that tell the agent to halt at checkpoints. |
| **Who decides a step passed** | The CLI's verdict, then the person at each gate. An override needs a reason and is recorded. | The person approves the design. After that, the model's own statement. | The person, who reviews each result. | The person. `/opsx:verify` is advisory and does not block. | The person approves the plan. After that, model reviewers. |
| **Tests before code** | Computed: the Build gate needs a recorded failing run before a passing run. | Instructed. | Optional, instructed. | Not found in the core. | Instructed. |
| **Acceptance tests written from the spec, then protected** | Yes. Written before Build and locked by digest; Check fails when one changed. | Not found. | Not found. | Not found. | Acceptance criteria are frozen by instruction. Acceptance tests before code are in a separate module. |
| **A failed check blocks `git commit`** | Yes, by a git hook, on the run's branch. | No. | Not found. | Not built in. Its docs suggest wiring `validate` into a hook of your own. | Not found. |
| **Questions before planning** | A rules checklist (who, when, how much, what is exempt). The person clicks answers in Claude Code's question dialog. | In chat, one open question at a time. | A clarify command: up to five questions with options, in chat. | In chat, through its explore command. | In chat: numbered questions with options, on a drafted design. |
| **A lighter path for a small change** | Partly. Design runs only for medium and complex features, and `/temper:fix` is short. Every feature still passes every gate. | Yes. Small changes are agreed in chat. | An optional lean preset. | Yes. Lite mode is the default for most changes. | Yes. Small changes go straight to build. |
| **Coding agents supported** | Claude Code only. | 16 listed in its README. | 41 named integrations. | "30+ tools", by its README. | Any tool that supports skills; it names Claude Code and Codex. |
| **Install** | Two commands in Claude Code (one on 2.1.275 or later). Needs bash, git and python3. | One command, from Anthropic's official marketplace. | Two commands. Needs Python 3.11 or later and uv. | An install script or npm, then `openspec init`. npm needs Node.js 22.12 or later. | One `npx` command. Needs Node.js 20.12 or later, Python 3.10 or later and uv. |
| **Published numbers against a plain agent** | Yes: [the benchmark](bench-2026-11.md), with its losses. | None found. | None found. | None found. | None found. |
| **License** | MIT | MIT | MIT | MIT | MIT |

## Where the others are ahead

- **Reach.** Each of the four runs in many coding agents. Temper runs in Claude Code only.
- **Cost of a small change.** Superpowers, OpenSpec and BMAD Method shrink the process for a small change. Temper
  runs every gate for every feature: in its own benchmark a feature costs 3 to 13 times what plain Claude Code costs
  and takes 5 to 18 times as long.
- **Getting started.** Superpowers installs with one command from the marketplace Claude Code already knows.
- **Use.** All four have far more users, so far more people have found their rough edges.

## Where Temper is ahead

- **The model does not grade itself.** A gate is a program's verdict over recorded runs, never a sentence the model
  wrote. A skipped step shows as a failed row.
- **A red gate stops the commit.** No commit block was found in any of the four.
- **Acceptance tests are locked before Build.** A builder that edits one fails Check.
- **It publishes what it measured, including where it loses.** On a request that states every rule, plain Claude
  Code was as correct in that benchmark. Temper led on vague requests (98% of the person's rules met against 73%)
  and on the tests left behind (93% of planted bugs caught against 79%).

Two limits belong beside those claims. Temper is not a sandbox: [Trust](https://github.com/galando/temper/blob/main/docs/trust.md) lists what the guard does not
see. And its own benchmark found runs that left the script when the mod was not loaded (2 of 8 runs with the loop on
a smaller model), which is why the shipped loop stays on the larger one.

One outside comparison ran three of these tools on one task ([Fontoura, updated October 2026][fontoura]). In its
single run on Superpowers 7.0.0 the brainstorming step never ran, and it notes that OpenSpec's validate checks
structure, not approval. One run is an anecdote, not a rate; it shows what "instructions only" can mean.

## Which to choose

- **Choose Superpowers** for a method that works in most agents with one install and little ceremony.
- **Choose Spec Kit** when the team wants written specs as the shared artifact, across many agents.
- **Choose OpenSpec** for small, frequent changes to an existing code base.
- **Choose BMAD Method** for role based planning of a larger product.
- **Choose Temper** when a wrong guess is expensive: the request leaves rules out, the change touches money, access
  or data, or you need a record of who approved what, and you work in Claude Code.
- **Choose none of them** for a quick script or a one line fix. Plain Claude Code is as correct there and far cheaper.

## Sources

Temper: `scripts/temper` (the gates), [Trust](https://github.com/galando/temper/blob/main/docs/trust.md), [the benchmark](bench-2026-11.md).

Superpowers ([repository](https://github.com/obra/superpowers)):
[hooks](https://github.com/obra/superpowers/blob/main/hooks/hooks.json),
[brainstorming skill](https://github.com/obra/superpowers/blob/main/skills/brainstorming/SKILL.md),
[test driven development skill](https://github.com/obra/superpowers/blob/main/skills/test-driven-development/SKILL.md),
[README](https://github.com/obra/superpowers/blob/main/README.md).

Spec Kit ([repository](https://github.com/github/spec-kit)):
[prerequisite check](https://github.com/github/spec-kit/blob/main/scripts/bash/check-prerequisites.sh),
[tasks template](https://github.com/github/spec-kit/blob/main/templates/tasks-template.md),
[clarify](https://github.com/github/spec-kit/blob/main/docs/reference/agentic-sdd.md),
[integrations](https://github.com/github/spec-kit/blob/main/docs/integrations/index.md),
[lean preset](https://github.com/github/spec-kit/blob/main/presets/lean/README.md),
[README](https://github.com/github/spec-kit/blob/main/README.md).

OpenSpec ([repository](https://github.com/Fission-AI/OpenSpec)):
[CLI](https://github.com/Fission-AI/OpenSpec/blob/main/docs/cli.md),
[commands](https://github.com/Fission-AI/OpenSpec/blob/main/docs/commands.md),
[concepts](https://github.com/Fission-AI/OpenSpec/blob/main/docs/concepts.md),
[README](https://github.com/Fission-AI/OpenSpec/blob/main/README.md).

BMAD Method ([repository](https://github.com/bmad-code-org/BMAD-METHOD)):
[build workflow](https://github.com/bmad-code-org/BMAD-METHOD/blob/main/skills/bmad-build/workflow.md),
[implement step](https://github.com/bmad-code-org/BMAD-METHOD/blob/main/skills/bmad-build/step-03-implement.md),
[build a change](https://github.com/bmad-code-org/BMAD-METHOD/blob/main/docs/build/build-a-change.md),
[developer agent](https://github.com/bmad-code-org/BMAD-METHOD/blob/main/skills/bmad-agent-dev/SKILL.md),
[README](https://github.com/bmad-code-org/BMAD-METHOD/blob/main/README.md).
The BMAD Method cells describe its main branch, the v7 preview; its stable branch was checked only for hooks and
its test first wording.

[fontoura]: https://felipefontoura.com/articles/spec-driven-development-tools-compared/
