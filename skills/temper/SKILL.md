---
name: temper
description: "Run the Temper intent-gated SDLC — intent → plan → design? → build → review → check → commit, with every gate verdict computed by the temper CLI instead of asserted by the model. Use when the user asks to run Temper, invokes /temper or /temper:fix, or wants a feature built behind quality gates. Works under any agent."
---

# Temper

Temper is an intent-gated SDLC for AI-generated code. Its defining property: **you
never decide whether a gate passed.** A bash CLI reads an evidence ledger and computes
PASS/FAIL per requirement, and a native git `pre-commit` hook refuses the commit while
any gate is red. Your job is to do each stage's work, record evidence, run the gate, and
stop for the human.

This skill is the entry point for agents that load Temper as a **skill** rather than a
plugin — Codex, OpenCode, Gemini CLI, Amp, Cline, Zed, and the rest of the roster the
`skills` CLI installs into. Under Claude Code or Cursor the `/temper` command does all
of this for you and you should use that instead.

---

## Step 0 — Find the CLI. Do not skip this.

**Temper without `scripts/temper` is not Temper.** The gates would become something you
assert, which is the exact failure this tool exists to prevent. Before anything else,
resolve the CLI:

1. `$CLAUDE_PLUGIN_ROOT` or `$CURSOR_PLUGIN_ROOT` set → `$ROOT/scripts/temper`.
2. This skill was installed from a full checkout → walk up from this file for the
   directory holding `commands/`, `agents/`, and `scripts/temper`.
3. A checkout exists somewhere known (`~/temper`, `~/.claude/plugins/temper`,
   `~/.cursor/plugins/temper`) → use it.
4. **None of the above** — a per-skill install copied only `skills/temper/`. Tell the
   user, in one line, that Temper's gates need the CLI, and give them the command:

   ```bash
   git clone https://github.com/galando/temper.git ~/temper
   ```

   Then use `~/temper/scripts/temper`. Do **not** proceed by grading yourself instead.

Once resolved, `temper root` prints the plugin root and `$TEMPER` below means that
CLI. Verify with `$TEMPER --help` before Stage 0.

**One-time project setup** (idempotent — run all three, skip what is already there):

```bash
cp <root>/templates/temper.config.default .claude/temper.config   # if absent
$TEMPER init
bash <root>/scripts/hooks/install.sh
```

The third is the one that matters under your agent. Most agents cannot block a tool
call; a git hook blocks every commit regardless of agent, so it is the only
deterministic enforcement you can count on. Say so if you have to skip it (not a git
repo yet), and install it on the next run.

---

## The pipeline

`intent → plan → design? → build → review → check → commit`. Each stage has a brief in
`<root>/agents/{stage}.md` and its methodology in `<root>/reference/{stage}.md`. Read
the brief, do what it says, record evidence, run the gate, stop.

| Stage | Brief | Gate |
|---|---|---|
| Intent | `agents/intent.md` | `$TEMPER gate intent --spec-path .temper/specs/{slug}` |
| Plan | `agents/plan.md` | `$TEMPER gate plan --spec-path .temper/specs/{slug}` |
| Design (medium/complex only) | `agents/design.md` | `$TEMPER gate design --spec-path .temper/specs/{slug}` |
| Build | `agents/build.md` | `$TEMPER gate build` |
| Review | `agents/review.md` | `$TEMPER gate review` |
| Check | `agents/check.md` | `$TEMPER gate check` |
| Commit | — | `$TEMPER gate commit` |

State lives in `.temper/build-state.json`, owned by `$TEMPER state` — never hand-write
it. Start a run with `$TEMPER state init {slug} --command temper`; advance after each
approved gate with `$TEMPER state advance {stage}_complete {next}`; clear it on commit.

`<root>/commands/temper.md` is the full orchestration contract — feedback loops, the
gate option set, resume, autonomy. Read it once at the start of a run. For a bug fix
the sequence is `rca → fix → review → check`: `commands/fix.md` and
`agents/{rca,fix}.md`.

**Intent first, always.** Everything downstream is derived from the intent, so a wrong
Problem statement multiplies into a wrong plan and a wrong build. Correcting it at the
intent gate costs words; correcting it after Plan costs the plan. The intent gate is
never skipped and never automated.

---

## Rules that hold under every agent

1. **Never assert a gate verdict.** Run `$TEMPER gate {stage}` and report exactly what
   it printed. A narrated verdict is the one thing Temper exists to prevent — if you
   cannot run the CLI, say so and stop rather than improvising a PASS.
2. **Stop at every gate.** Print the verdict and numbered options, then wait. Lacking a
   structured question tool is not the same as lacking a gate: plain text and a pause
   is the gate. Never advance on your own judgment.
3. **Record evidence as you go** (`$TEMPER evidence add`, `$TEMPER evidence run`). A
   stage with no evidence FAILs closed — nothing recorded means nothing verified. This
   is deliberate, not a bug to work around.
4. **A red gate is not yours to clear.** `$TEMPER override {stage} --reason "…"` is a
   human's decision; it records their git identity and stays visible in the final
   report. Never run it because it would unblock you.
5. **Never `git add -f`** over a project's `.gitignore`, and never edit
   `.temper/build-state.json`, `.temper/gates.json`, or `.temper/evidence/*` by hand.
6. **Run each stage in a fresh context** where your agent supports subagents — that is
   what the stage briefs assume. Where it does not, run stages as separate sessions
   rather than carrying one conversation through all of them. An inline run is a real
   degradation; treat it as one.

---

## What your agent may not be able to do

Temper's rules live once in `<root>/scripts/hooks/*.sh` and are wired per agent. Most
agents can block fewer events than Claude Code can — Cursor cannot refuse a `stop` or a
completed file edit, and an agent with no hook system refuses nothing. That changes what
is *enforced*, never what is *required*: every rule above still applies to you whether
or not something would catch you breaking it.

`<root>/reference/portability.md` has the full per-agent matrix. If your agent is not on
it, assume no hook enforcement, install the git `pre-commit` hook, and follow the rules
because they are the method — not because a script is watching.
