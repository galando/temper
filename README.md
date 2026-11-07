# Temper (Markdown edition)

Intent before code. Temper walks Claude Code through one flow for every change: Intent, Plan,
Design (for medium and complex work), Build, Review, Check, then a commit. Each stage ends at a
question you answer, and nothing moves on without your answer.

This is the Markdown edition: every file in it is a prompt, a reference page or a template.
The gates are checklists Claude applies by reading files and then asks you about. No program
computes them, and nothing blocks a commit. The full edition, with the CLI that computes every
verdict from an evidence ledger, the native commit hook and the Claude Code mod, is at
https://github.com/galando/temper.

The flow: Intent → Plan → Design (optional) → Build → Review → Check → Commit.

## Install

From the Claude Code plugin directory: run `/plugin`, find Temper, and install it.

Then, in your project:

```text
/temper:init
/temper:temper "describe the feature"
```

## Commands

| Command | What it does |
|---|---|
| `/temper:temper` | The one flow: intent, plan, design, build, review, check, commit |
| `/temper:intent` | Capture an idea as a draft `intent.md`, to build later |
| `/temper:plan` | A door into `/temper:temper`: starts a run (Intent first) or takes up the active one |
| `/temper:design` | A door into `/temper:temper` at Design |
| `/temper:build` | A door into `/temper:temper` at Build |
| `/temper:review` | A door into `/temper:temper` at Review |
| `/temper:check` | A door into `/temper:temper` at Check |
| `/temper:fix` | Root cause analysis, a regression test first, the smallest fix, then Review and Check |
| `/temper:status` | The active run, the gate decisions, findings, review memory and trends |
| `/temper:init` | Seed `.claude/temper.config` and the `.temper/` folder |

The stage commands are doors: they start or take up the one run at their stage and never have a
flow of their own.

## How it works

- **Intent** writes `intent.md`: the problem, success criteria with stable `AC-NN` ids, each
  with why it matters and how it is validated, constraints, and the open questions you answer
  by clicking.
- **Plan** explores the code, measures the blast radius, derives BDD scenarios from it, and
  writes `plan.md` and grouped `tasks.md`, each task with its files, its test command and its
  cases.
- **Design** runs for complex work (and medium work at high risk) and flags every area of
  concern for you to decide.
- **Build** goes test first: a failing test on an assertion, then the least code that passes,
  each run written with its real exit code to `evidence.md`. A file outside the plan waits for
  your answer.
- **Review** is confidence scored, never filters out a security finding, and checks the code
  against the intent.
- **Check** runs the real build, tests with coverage, each scenario's test, lint, types and a
  security scan.
- **Commit** happens only after you choose it. Temper never pushes and never merges.

Each stage runs as its own agent with a clean context and reads only the files the run keeps
under `.temper/specs/{slug}/`. Those files are the record of the change and are meant to be
committed with it.

## Differences from the full edition

| | Full edition | Markdown edition |
|---|---|---|
| Gate verdicts | computed by the `temper` CLI from an evidence ledger | a checklist Claude applies, shown to you |
| Commit gate | a native git pre-commit hook refuses a commit while a gate is red | none; Claude commits only after you choose Commit |
| Evidence | the CLI runs and records each test command | Claude writes each command and its exit code to `evidence.md` |
| Grouped Build | task agents in separate worktrees, merged and gated by the CLI | one Build agent per group, in the working tree |
| The mod | a phase band, a pane and write guards in Claude Code | none |
| Fresh plan review, HTML plan review, autonomous Build | yes | not included |
| `/temper:pack` and the guardrails pack | yes (the guardrails pack is hook based) | not included; the other packs are |

Nothing in this edition is enforced deterministically. It carries the same method and the same
questions, and it relies on Claude following them and on you reading what each stage shows. When
you need the guarantees, use the full edition.

## Packs

Built-in rule packs: `quality`, `tdd`, `security`, `git`, `performance`, `api-design` and
`architecture-depth`, plus stack notes for Spring Boot, Node with Express, React with
TypeScript, FastAPI, Go and Rust. Enable them in `.claude/temper.config`; a project copy in
`.claude/packs/{name}/rules.md` takes precedence.

## Skills

`temper-core`, `context-engineering`, `source-driven-development`, `grill-me` and `teach-me`.

## License

MIT, see `LICENSE`.
