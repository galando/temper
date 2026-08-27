# Temper

<!--
  Append this block to your project's AGENTS.md when your coding agent has no plugin
  system (Codex, Gemini CLI, Aider, and anything else that reads AGENTS.md).

  Agents WITH a plugin system should install the plugin instead — see
  docs/getting-started.md. Claude Code and Cursor both load Temper's commands, agents,
  and skills from their own manifests; this file is the fallback, not a second path.

  Replace <TEMPER> below with the absolute path to your Temper checkout, then delete
  this comment.
-->

This project uses **Temper** — an intent-gated SDLC where every stage gate verdict is
computed by a CLI, never asserted by you.

Temper is checked out at `<TEMPER>`. `$TEMPER` below means `<TEMPER>/scripts/temper`.

## One-time setup

Run these once per project, from the project root. Both are idempotent:

```bash
cp <TEMPER>/templates/temper.config.default .claude/temper.config   # if absent
<TEMPER>/scripts/temper init
bash <TEMPER>/scripts/hooks/install.sh
```

The third is the one that matters: it installs a native git `pre-commit` hook that
refuses a commit while any gate is FAIL and unoverridden. It is not an agent feature —
it fires on `git commit` from anywhere, and under an agent with no hook system it is
the **only** deterministic enforcement Temper has.

## Running the pipeline

The stages are `intent → plan → design? → build → review → check → commit`. Each stage
has a brief; read the brief, do exactly what it says, then run its gate:

| Stage | Read this brief | Then run |
|---|---|---|
| Intent | `<TEMPER>/agents/intent.md` | `$TEMPER gate intent --spec-path .temper/specs/{slug}` |
| Plan | `<TEMPER>/agents/plan.md` | `$TEMPER gate plan --spec-path .temper/specs/{slug}` |
| Design | `<TEMPER>/agents/design.md` | `$TEMPER gate design --spec-path .temper/specs/{slug}` |
| Build | `<TEMPER>/agents/build.md` | `$TEMPER gate build` |
| Review | `<TEMPER>/agents/review.md` | `$TEMPER gate review` |
| Check | `<TEMPER>/agents/check.md` | `$TEMPER gate check` |
| Commit | — | `$TEMPER gate commit` |

`<TEMPER>/commands/temper.md` is the orchestration contract: state transitions,
feedback loops, what each gate offers. Read it once at the start of a run.

For a bug fix, the sequence is `rca → fix → review → check` — `<TEMPER>/commands/fix.md`
and `<TEMPER>/agents/{rca,fix}.md`.

## Rules that hold regardless of agent

1. **Never assert a gate verdict.** Run `$TEMPER gate {stage}` and report what it
   printed. A verdict you narrate instead of computing is the failure mode Temper
   exists to prevent.
2. **Stop at every gate.** Print the verdict and the options, then wait for the human.
   Do not advance the pipeline on your own judgment — no `AskUserQuestion` tool is not
   the same as no gate.
3. **Record evidence as you go** (`$TEMPER evidence add`, `$TEMPER evidence run`). A
   stage with no evidence FAILs closed: nothing recorded means nothing verified.
4. **Never `git add -f`** over a project's `.gitignore`, and never edit
   `.temper/build-state.json` by hand — `$TEMPER state` owns it.
5. **Run each stage in a fresh session** where you can. The stage briefs assume a clean
   context; carrying the whole conversation through every stage is the degradation this
   setup accepts, not something to make worse.

`<TEMPER>/reference/portability.md` documents exactly what this fallback path gives up
against a plugin install, and why.
