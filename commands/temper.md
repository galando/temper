---
description: "Unified SDLC command: intent → plan → design? → build → review → check → commit, gated by the temper CLI"
argument-hint: "<feature-description>"
---

# Temper: Unified SDLC Command

**FIRST OUTPUT (do this before reading anything else).** Look at your system prompt now for a line that starts with `Temper enforcement:`. If there is none, your very first line of text in this reply must be exactly: `Temper enforcement is off here (no mods support); continuing with prompt based phases.` If the line reads `Temper enforcement: off (UI only)`, the Temper mod is loaded and the user turned enforcement off, so your very first line must be exactly: `Temper enforcement is off (turned off by the user); continuing with prompt based phases.` Then carry on as written below. Never treat either case as an error, and say it only once per conversation. If the line reads `Temper enforcement: active`, say nothing about it. You state this once, here in the main conversation: a stage subprocess never has that line in its system prompt, so its brief says nothing about enforcement, and you never ask a stage to say it. Wherever this file says **With the mod**, it means the system prompt has a `Temper enforcement:` line, either `active` or `off (UI only)`: the mod is loaded and draws the run either way, and turning enforcement off only stops the mod from refusing tool calls. With the mod or without it, and in every mode, the person decides only in a question dialog (the `Temper gate` question at every gate): the mod has no button that decides, and it reads the person's answer from the dialog's result.

**Goal:** Run intent → plan → design? → build → review+check → commit with a human gate
at every stage (or, if armed, unattended past the plan gate). Every gate verdict is
computed by the `temper` CLI from an evidence ledger — never asserted by a model. The
Intent gate comes first because intent errors are the most expensive kind: correcting
the Problem statement costs words at the intent gate and costs the whole plan after it.

## Usage

```
/temper "add login feature"    # Start new feature
/temper                        # Resume or continue
```

---

## Reserved first words

When the first word of the arguments is one of these, handle it here and do not start a
run. With the mod, the mod already answered the words that only show something. A word
that names a move (`approve`, `next`, `back`, `override`, `accept`, `drift`) is the
person's wish, not yet their decision: the person decides in the question dialog, so ask
it, with the move they typed as its first option, and go on only on their answer. This is
the same with the mod and without it. Any other first word is a feature description.

| Word | What to do |
|---|---|
| `status` | Print `${CLAUDE_PLUGIN_ROOT}/scripts/temper status` and `${CLAUDE_PLUGIN_ROOT}/scripts/temper state get next_stage`. |
| `timeline` / `report` | Print `${CLAUDE_PLUGIN_ROOT}/scripts/temper report`. |
| `help` | List these words with their one line meanings. |
| `approve` / `next` | Ask the current gate's `Temper gate` question (see Gates; run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate {stage}` first when the stage has no verdict yet), with its Continue option first. On "Continue to {next}", do that stage's On Continue steps. |
| `back <stage> <reason>` | With no reason, refuse: "A step back needs a reason. Use /temper:temper back <stage> <reason>." Else ask the `Temper gate` question with the option `Loop back to {Stage}: {reason}` first, the reason as the person typed it. On that answer, do what Feedback Loops says. |
| `override <reason>` | With no reason, refuse: "Override needs a reason. Use /temper:temper override <reason>." Else ask the `Temper gate` question with the option `Override and continue: {reason}` first. On that answer, run `${CLAUDE_PLUGIN_ROOT}/scripts/temper override {stage} --reason "{reason}"`, then that stage's On Continue steps. |
| `accept <id> <reason>` | At Review only. With no reason, refuse. Else ask the `Temper gate` question with the option `Accept finding {id}: {reason}` first. On that answer, run `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence accept --stage review --id {id} --reason "{reason}"`, run the gate again and ask it again. |
| `drift <path> <add\|revert\|allow>` | In Build only: ask the `Scope drift` question for that file (see Stage 2), with the named choice first, and carry out the answer as that section says. |
| `pause` / `resume` | `pause`: stop at the next gate and wait for the person. `resume`: the same as `/temper` with no arguments (see Resume). |
| `pr` | Write a pull request description from `${CLAUDE_PLUGIN_ROOT}/scripts/temper report`: overrides, accepted findings and drift decisions with their reasons. |
| `discuss <text>` | Treat the text as the person's message at the current gate: answer it, and if it asks for a change, make the change, run the gate again, then wait (see Gates). It never advances a stage. |
| `mode`, `enforcement`, `pane`, `play` | These belong to the Temper mod. Without it, say they are not available here. The game needs the mod. |

---

## Architecture

Each stage runs in an **isolated Agent subprocess** — genuine context clearing, not a
self-directed "clear your context" instruction (which is unenforceable). What each stage
must do lives in exactly one place, its stage brief:

- Intent: `${CLAUDE_PLUGIN_ROOT}/agents/intent.md`
- Plan: `${CLAUDE_PLUGIN_ROOT}/agents/plan.md`
- Design: `${CLAUDE_PLUGIN_ROOT}/agents/design.md`
- Build: `${CLAUDE_PLUGIN_ROOT}/agents/build.md`
- Review: `${CLAUDE_PLUGIN_ROOT}/agents/review.md`
- Check: `${CLAUDE_PLUGIN_ROOT}/agents/check.md`

A brief's frontmatter declares its default model; its body names the reference file
with the stage's methodology, tells it which `temper` commands to run, and defines the
summary box it returns. This file does not repeat that contract per stage — read the
brief once when you launch it, and print the box the agent returns verbatim rather
than reconstructing it.

```
ORCHESTRATOR (this file)
  |
  +-- Agent(intent brief)  -> intent gate -> CLI gate intent (the fail-fast gate)
  +-- Agent(plan brief)    -> plan gate   -> CLI gate plan
  +-- Agent(design brief)  -> design gate -> CLI gate design (medium/complex only)
  +-- Agent(build brief)   -> build gate  -> CLI gate build
  +-- Agent(review brief)  -> review gate -> CLI gate review
  +-- Agent(check brief)   -> check gate  -> CLI gate check
  |
  +-- CLI gate commit -> commit
```

**Paths.** Claude Code wrote the plugin's absolute folder in place of the
CLAUDE_PLUGIN_ROOT variable when it loaded this file, so every plugin path here is
already a real path. The Bash tool does not set that variable: run each command with
the path exactly as this file shows it. A reference page you read with the Read tool
(`${CLAUDE_PLUGIN_ROOT}/reference/plan-review.md`, `${CLAUDE_PLUGIN_ROOT}/reference/plan.md`,
`${CLAUDE_PLUGIN_ROOT}/reference/autonomy.md` and the others) is not filled in: there
the CLAUDE_PLUGIN_ROOT variable means the folder that holds
${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off). Write
that folder out in full in every command you run from such a page, never the variable
itself, which the Bash tool would leave empty. The details are in
`${CLAUDE_PLUGIN_ROOT}/reference/orchestrator-patterns.md` under "The plugin folder".
Plugin files are always written out in full in this file, and the temper CLI is
`${CLAUDE_PLUGIN_ROOT}/scripts/temper`. Every other path (`.temper/`, the spec files,
`.claude/temper.config`, `CLAUDE.md`, `AGENTS.md`, the files being built) is in the
user's project, the current directory. Nothing in a run writes into the plugin folder,
unless the project is the plugin folder itself (developing Temper on its own
repository: a git checkout whose top folder is the plugin folder; an installed copy is
never a project, and the CLI refuses it).

**Plugin folder line.** Every stage launch prompt below carries this line, word for word,
so the stage knows the folder that its brief and the reference pages mean:
`Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder.`

## Models

Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper model --all` **once**, at the same time as the first state call, and keep
its output for the run. It prints one `stage=model` line per stage, resolving a project's
optional `models:` config override against the `model:` line in that stage's brief (the
files listed under Architecture). The
stage launches below say `model: {plan}`, `{build}` and so on — substitute the value for
that stage from this output verbatim. Don't re-run it per stage, and don't infer a model
from anywhere else: this command is the only thing that knows whether the project
overrode one.

## First-run bootstrap

Before Stage 1, ensure the project is set up — **per piece, not all-or-nothing**, so a
partially-set-up project (config copied but no git hook, `.temper/` present but no
config) still ends up with every piece. All three steps are idempotent, so this is
safe to run every time; do the ones that are missing, silently skip the ones already
in place.

When any piece is missing, check the project folder first, before writing anything:
when it is the home folder, stop and say in one line that the home folder holds Claude
Code's own files and is never a project, so run `/temper` from a project folder. Then
run `${CLAUDE_PLUGIN_ROOT}/scripts/temper status`; when it prints a line that starts
with `FAIL: run temper from a project folder` (the home folder, an installed copy of
the plugin, or a folder inside the plugin folder), stop and show that line. Any other
result, `FAIL: no intent.md to report on` among them, means go on:

1. **Config** — if `.claude/temper.config` is absent, copy the default template
   `${CLAUDE_PLUGIN_ROOT}/templates/temper.config.default` to `.claude/temper.config`.
2. **Scaffold** — run `${CLAUDE_PLUGIN_ROOT}/scripts/temper init` (idempotent).
3. **Commit gate** — this is the headline guarantee, and the easiest to leave missing.
   Ask git which file it runs as the pre-commit hook:
   `git rev-parse --git-path hooks/pre-commit` prints it. When the repository's
   `core.hooksPath` points at Temper's folder, that file is the kept Temper hook,
   `temper-gate/pre-commit` in the repository's git folder (the folder
   `git rev-parse --git-common-dir` names, which every worktree of the repository
   shares); otherwise it is a file in git's own hooks folder or in the folder another
   tool set (husky, lefthook). Never test a fixed path under `.git`: in a linked
   worktree or a submodule `.git` is a file, so such a path never exists there. The
   gate is in place when that file's path ends in `/temper-gate/pre-commit`, its second
   line starts with `# Temper native pre-commit hook`, and the CLI path written in it
   still exists (a plugin upgrade moves the plugin folder, and a hook whose CLI path no
   longer exists fails open silently). After the repository is moved or renamed,
   `core.hooksPath` still names the old place, git runs no pre-commit hook, and that
   file is missing, so this check fails and the installer points it at the new place.
   Otherwise run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/guards/install.sh"`. It writes the kept hook
   with the current plugin paths and never writes into a folder named `hooks`: not
   git's own hooks folder, not the folder `git rev-parse --git-path hooks` names, and
   not a `core.hooksPath` folder of another tool. It only reads the hooks there. Its
   other writes are `git config --local core.hooksPath` set to the kept hook's folder,
   and, only when the user's hook holds the line Temper 9.6.5 printed, the file
   `temper-pre-commit` in the git folder. Read its result:
   - Exit 0 → in place. It installed the hook and pointed `core.hooksPath` at its
     folder, found it already installed (or updated its plugin paths), or found that
     the user's own pre-commit hook calls the Temper hook (its line says so, and that
     nothing else was written), which counts as already in place. Carry each `Note:`
     and `Warning:` line it printed into the one-line note. After a warning about a
     `pre-commit.bak.<timestamp>` file an older version set aside, give its restore
     steps and show the line it printed for it in a fenced code block.
   - "FAIL: not inside a git repository" → say so in one line and continue (config +
     scaffold still done); the gate installs on the next run after `git init`.
   - Any other non-zero exit → the commit gate is not installed. It refuses when git's
     own hooks folder holds hooks that git would stop running if `core.hooksPath`
     pointed at Temper's folder (a `commit-msg`, git-lfs's `pre-push`, the pre-commit
     framework's or lefthook's hooks, or a `pre-commit.bak.<timestamp>` an older
     version left; an older Temper `pre-commit` does not count), when
     `core.hooksPath` names another tool's folder (husky's `.husky/_`, lefthook, a
     team folder), and when it names Temper's older folder and that folder holds
     other hooks git runs (git-lfs writes its hooks there), unless the pre-commit
     hook there already calls the Temper hook;
     when the `pre-commit` in Temper's own folder is not Temper's (a hook tool such as
     lefthook wrote it there; the installer never writes over it, and its hint says how
     to move it out); when the user's hook holds the Temper line after an `exit` or `exec` line; when
     the repository, or a place it would write once symlinks are followed, lies inside
     the plugin's own folder; and when a folder or file it needs cannot be made. It
     ignores GIT_DIR, GIT_WORK_TREE and GIT_CONFIG. Say in one line that the commit
     gate is not installed and why (its FAIL reason; with no FAIL line, show its whole
     output in a fenced code block). When it printed "The Temper hook is kept in
     {file}", name that file: the Temper hook it kept in the repository's git folder,
     never committed, and the only thing it wrote; otherwise it wrote nothing. Then
     show the lines it printed between its BEGIN and END lines, verbatim, in a fenced
     code block (one line that runs the kept hook, or, when it refused before it knew
     the git folder, the Temper hook's own lines in a subshell, so that their exits end
     only the subshell), then each `Warning:` line it printed (a hook an older version
     set aside, or a `pre-commit` from an older Temper that git still runs, with its
     stale plugin path), then its `Hint:` line as it printed it (where the line goes:
     `.husky/pre-commit`, the entry of a local hook of the pre-commit framework, a
     command in `lefthook.yml`, the start or the end of the user's own hook, or, for a
     hook from an older Temper, in place of all of its lines), and continue.

If a step ran, print a one-line "Set up." note naming what was done; if everything was
already in place, continue into Plan silently. This per-piece check is what makes
install two `/plugin` commands then just `/temper "…"` — and what stops a config that
arrived some other way (a copied `.claude/`, a re-run that failed mid-way) from
running the pipeline with no commit gate.

## State

`${CLAUDE_PLUGIN_ROOT}/scripts/temper state` owns `.temper/build-state.json` — never hand-write it. When a step calls
for more than one `${CLAUDE_PLUGIN_ROOT}/scripts/temper` invocation in a row (state/evidence calls only, never `gate`),
batch them into a single Bash tool call, one shell command per line — they're sequential
anyway, and it's one round-trip instead of several. When the CLI exits 3, it refused
because a path it keeps run state in is a symlink (the `.temper` folder, its evidence,
specs or archive folder, one of its state or evidence files, or the active run's spec
folder or its `gate-ledger.json`), so no write can follow a link out of the project:
stop, show its one-line reason, and wait for the user. While a run is active, the
commit hooks block every commit until the link is gone. Never remove, replace or follow
the link yourself.

- **Start:** before `state init`, look for a matching committed draft: list the
  folders in the project's `.temper/specs` folder, and if one of them already holds an
  `intent.md` for this feature, reuse that folder's name as the slug in place of a new
  one — the Intent stage then refines the committed draft in place rather than creating
  a sibling. Carry the draft's `**Ticket:**` header forward on pickup. The slug passed
  to `state init` is letters (either case), digits, '.', '_' or '-', starts with a
  letter or digit, and has no '..' or '/' (the CLI refuses anything else). A ticket key
  prefix keeps its case as typed (`{KEY}-{slug}`, for example `PROJ-123-login`). Then
  `${CLAUDE_PLUGIN_ROOT}/scripts/temper state init {slug} --command temper` (creates it,
  `stage: started`, branch `feature/{slug}`).
- **Advance:** after each gate's "Continue", `${CLAUDE_PLUGIN_ROOT}/scripts/temper state advance {stage}_complete {next}`.
- **Resume:** if `.temper/build-state.json` exists, read `${CLAUDE_PLUGIN_ROOT}/scripts/temper state get spec_path`
  and `${CLAUDE_PLUGIN_ROOT}/scripts/temper state get stage` to find where you left off. If it exists for a
  **different** feature than `$ARGUMENTS`, ask the user: resume the existing one, or
  overwrite and start fresh (`${CLAUDE_PLUGIN_ROOT}/scripts/temper state clear` then re-init).
- **With the mod**: the CLI state is the truth for where the run is.
  Never run `state init`, `state clear`, `state archive` or `state loop` on your own while a run is
  active (with enforcement active, the mod refuses them without the person's answer). The one
  exception is the `state clear` of the TRIVIAL exit in Stage 0, which the mod allows. If Resume
  Validation fails or the state looks wrong, show what is wrong in one line and ask with
  `AskUserQuestion`, header `Temper resume`: "Start over" / "Cancel" (the person's
  "Start over" answer lets one reset through; see Resume Validation). Never choose
  Start over yourself. The person's answer counts at the step the run is at: when a call it
  allows (`state advance`, `state loop`, `override`) is refused or fails with no effect, run it once
  more, and if it fails again, say so in one line and ask the gate question again.
- **On commit:** `${CLAUDE_PLUGIN_ROOT}/scripts/temper state clear` (evidence, gates, loop counters — spec artifacts
  under `.temper/specs/` are untouched, they're the permanent record).

## Gates

Every stage gate follows the same shape. After a stage Agent returns:

1. Print the summary box it returned, verbatim (each agent brief defines its format —
   not restated here).
2. Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate {stage}`. It prints PASS/FAIL with each requirement's status and
   writes the verdict to `.temper/gates.json`.
   **Blocking questions first, in every stage:** when the run's `intent.md` holds a `Blocking:` Open Question (Intent
   writes them; Plan and Design add theirs there), ask them in ONE `AskUserQuestion` call
   before anything else, one question each (four at most per call; ask the rest in a second
   call), the question's choices as the options with the recommended one first, three at most
   (a question holds four options; any other choice stays open through "Other"), plus a last
   option "Carry forward". Write each answer into intent.md's `### Decisions` and
   take the question out of Open Questions, then run the gate again. A `Deferred:` question is
   carried forward without asking. Never list Blocking questions as text for the person to
   answer by typing.
3. Ask the gate with `AskUserQuestion`, header `Temper gate`. This is the same in every setup:
   with the mod or without it, in every mode. With the mod, the mod reads the person's answer
   from the dialog's result and lets through only what that answer allows, at the step the run
   is at. After the answer: "Continue to {next}": do that stage's On Continue steps as written.
   "Save for later": the run is saved; stop. "Loop back to {upstream stage}": do what Feedback
   Loops says. "Override and continue": run
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper override {stage} --reason "<the reason>"`, then that
   stage's On Continue steps. A loop back and an override need the person's reason. When the
   answer carries none (no text typed after the choice in "Other", and no note), ask once more
   with the header `Temper gate` and the question `Loop back to {upstream stage}. What is the
   reason?` (options "The check found a real problem" / "Cancel") or `Override and continue.
   What is the reason?` (options "I accept the risk" / "It is not a real issue" / "Cancel"). The
   person's answer is the reason; "Cancel" shows the gate again. This reason question holds for
   every question with the header `Temper gate`, wherever a page asks one (the Build loop's
   group and completion gates, a parked group, the Commit gate FAIL): a move that needs a
   reason ("Loop back to ...", "Override and continue", "Override and commit", "Keep the
   agent's commits", "Accept finding {id}") and came without one gets the question `{that
   move}. What is the reason?` with fitting options and "Cancel". Any other answer typed in
   "Other", or a message the person writes at a gate, is a change request or a question:
   answer it; if it asks for a change, make the change, run the gate again and ask again.
   The options:
   - **On PASS:** `"Continue to {next} (Recommended)"` / `"Save for later"` / free-text
     `"Other"` for a change request (make the edit, re-run the gate, re-show).
   - **On FAIL:** `"Loop back to {upstream stage}"` (if `feedback.enabled` and the loop
     budget allows — see Feedback Loops) / `"Override and continue"` (records
     `${CLAUDE_PLUGIN_ROOT}/scripts/temper override {stage} --reason "<what the user typed>"`, which stays visible in
     the final report — it does not erase the FAIL) / `"Save for later"`.
4. Autonomous mode replaces step 3 — see Autonomous Continuation below.

Every gate also offers, unconditionally (no config toggle): **"Grill Me"** (skill
`grill-me`), **"Teach Me"** (skill `teach-me`), and at Plan: **"Walk through step by
step"**, **"Open HTML review"** and **"Share HTML review"**. Each returns to the same
gate — none advance or block the pipeline. A question holds four options at most (plus
"Other"): when a gate has more, keep three on the first question, the moves first and the
recommended one at the top (Continue to, Loop back to, Accept a finding, Override and
continue, Run ... again), and make the fourth **"More options"**. When the person picks it, ask
a second question with the same header in its own `AskUserQuestion` call, with the rest, four at
most, "Save for later" among them when it did not fit, and "Start over" (see Resume). A move
chosen there is the person's answer; any other option runs and then shows the gate again.

Never re-derive gate logic here or in a stage prompt. Gate mechanics live only in the
temper CLI and its tests, never in a prompt.

## Feedback Loops

When a gate FAILs and the user selects "Loop back":

1. `${CLAUDE_PLUGIN_ROOT}/scripts/temper state loop {from} {to} --reason "<why>"` — this enforces
   `loops.max-per-type` (default 2), prints `BLOCKED` (exit 1) once the budget is spent,
   and otherwise moves the run back to `{to}`: it sets `next_stage`, and clears the
   evidence, the verdicts and the skips of `{to}` and every stage after it, so nothing
   from the stage being redone survives to count at the next gate. Run nothing else to
   move the run. If blocked, do not offer the loop option again this run; fall through
   to Override / Save.
2. Re-launch the upstream stage's Agent (same template as its first launch), adding one
   line to its prompt: *"Feedback re-entry: {reason}. Fix this, then continue."* For grouped
   Build that is the fix pass in `${CLAUDE_PLUGIN_ROOT}/reference/build-groups.md`, not the group loop.
3. When it returns, re-run the downstream gate that triggered the loop.

**With the mod** a loop moves the run, and only the person decides that: the person's
"Loop back to {stage}" answer, with a reason, to the `Temper gate` question is the loop.
Run step 1 at once (the mod lets that one `state loop` through for the answer). When it
prints `BLOCKED`, say so in one line and ask the gate question again with "Override and
continue" and "Save for later". Never call `state loop` on your own; with enforcement
active, the mod refuses it without the person's answer. An armed autonomous run is the one
exception: it loops Review or Check back to Build by itself (see
`${CLAUDE_PLUGIN_ROOT}/reference/autonomy.md`).

That's the whole mechanism: a loop is a normal stage re-launch. Build→Plan is the one
exception: it's human-driven only (max 1 per run, no circuit breaker) because it means
the plan itself was wrong, not the implementation.

## Autonomous Continuation

Opt-in. `autonomy.enabled: false` or the block absent (default) → this feature does not
exist for the run: don't read anything, every gate is the ordinary interactive one
above. When `autonomy.enabled: true`, read `${CLAUDE_PLUGIN_ROOT}/reference/autonomy.md` **once, at the plan
gate on PASS** — its arming point, never at invocation or mid-run — and follow it for
every post-plan gate. Two invariants, restated here because they bound the whole
feature: autonomy never pushes, merges to a remote or makes the final feature commit
(PASS or FAIL at commit, it always parks; besides its `wip:` stage checkpoints, the only commits it
allows are grouped Build's local task commits and the local `temper integrate` merge, both made by the CLI), and
the Intent gate is always interactive.

---

## Stage 0: Intent (the fail-fast gate)

Why this is its own gate: **everything downstream is derived from the intent** — a
wrong Problem or a missing criterion multiplies into wrong scenarios, a wrong plan,
and a wrong build. The intent is the cheapest artifact in the run, so the human
corrects it FIRST, before the expensive exploration/architecture work spends anything.

Launch:

```
Use the Agent tool, model: {intent}, prompt:
"Follow ${CLAUDE_PLUGIN_ROOT}/agents/intent.md exactly. Feature: $ARGUMENTS.
Spec path: {what ${CLAUDE_PLUGIN_ROOT}/scripts/temper state get spec_path prints}.
Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder."
```

After it returns, record its usage once: `${CLAUDE_PLUGIN_ROOT}/scripts/temper usage add --stage intent --model {intent} --tokens {subagent tokens} --ms {duration ms}` (the numbers the Agent result reports; omit a flag the result does not give).

The agent returns `READY` (intent.md written, or an existing draft refined) or
`TRIVIAL` (a typo/one-liner with no product problem to state — nothing written).
**On TRIVIAL:** the change exits the gated pipeline honestly instead of limping
through gates built for artifacts it doesn't have (`gate plan` would FAIL forever on
"artifacts exist" with nothing fixable). Tell the user in one line ("trivial — handling
directly, no pipeline"), run `${CLAUDE_PLUGIN_ROOT}/scripts/temper state clear`, make the change directly, run the
project's tests, and commit normally: with no active run state,
`${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit` degrades open by design, so the
commit hook doesn't block a run that never gated. That `state clear` is allowed even
with the mod and enforcement active, but only for a run that never left Intent:
no stage has completed and the next stage is still Intent, no gate holds a verdict, no
override is recorded, the spec folder holds none of `intent.md`, `plan.md`, `tasks.md`
and `design.md`, and the run never moved (its step is still 0). A
TRIVIAL return wrote nothing, so such a run has nothing to lose. Run it at once, before
anything writes a file in the spec folder. If mid-change it turns out NOT to be
trivial, stop and restart `/temper` properly.

Gate: `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate intent` (Problem stated, >=1 criterion, Status header). Options:
**"Continue to Plan (Recommended)"** / Grill Me / Teach Me / "Save for later" / Other
(a correction — edit intent.md, re-run the gate, re-show; this is the whole point of
the gate: intent corrections here cost words, the same correction after Plan costs the
plan). Open Questions come FIRST, asked as the Gates section says (Blocking questions
first). An intent accepted with open questions records that choice.

**On Continue:** flip intent.md's header `Status: draft → accepted` and add
`**Accepted-by:** {git config user.name} <{user.email}>` — this human Continue is the
acceptance the artifact records. Commit the accepted intent in two separate Bash calls
(`git add .temper/specs/{slug}/`, then `git commit -m "docs(intent): accept {slug}"` —
separate calls so the in-agent commit-gate hook sees it staged; artifact-only commits
pass the fence; skip with a one-line note if the project gitignores `.temper/specs/`).
Then `${CLAUDE_PLUGIN_ROOT}/scripts/temper state advance intent_complete plan` and launch Stage 1.

The Intent gate is **always interactive** — autonomy is armed later, at the plan gate,
never here: no unattended run starts without a human having accepted the intent.

---

## Stage 1: Plan

Launch:

```
Use the Agent tool, model: {plan}, prompt:
"Follow ${CLAUDE_PLUGIN_ROOT}/agents/plan.md exactly. Feature: $ARGUMENTS.
Spec path: {what ${CLAUDE_PLUGIN_ROOT}/scripts/temper state get spec_path prints}. The accepted intent.md there is your
input — derive scenarios and architecture from it; refine it only with a stated
reason.
Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder."
```

After it returns, record its usage once: `${CLAUDE_PLUGIN_ROOT}/scripts/temper usage add --stage plan --model {plan} --tokens {subagent tokens} --ms {duration ms}` (the numbers the Agent result reports; omit a flag the result does not give).

Gate: `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate plan` — see `${CLAUDE_PLUGIN_ROOT}/reference/plan.md` → "Approval" for
the walkthrough mechanics. **"Open HTML review"** and **"Share HTML review"** (in addition
to that file's options): follow `${CLAUDE_PLUGIN_ROOT}/reference/plan-review.md` —
`${CLAUDE_PLUGIN_ROOT}/scripts/plan_review.py` renders the page, sharing publishes it as a Claude artifact only after the user confirms where it goes (without the `Artifact` tool, offer Open HTML review instead), and
the comments come back as `review-comments.json` to apply (task-change /
scenario-change / plan-change / general-note, mapped to its artifact).

**On Continue:** `${CLAUDE_PLUGIN_ROOT}/scripts/temper state advance plan_complete design-or-build` (pick `design` if
`phases.design: true` and complexity is medium/complex, else `build`). (Intent
acceptance — the Status flip and `Accepted-by:` — already happened at the Intent gate;
this gate approves the *plan*.) Create the feature branch if not already on it
(`git checkout -b feature/{slug}`), then **commit the approved plan artifacts** in two
separate Bash calls, staging first: `git add .temper/specs/{slug}/`, then
`git commit -m "docs(plan): approve plan — {slug}"`. They must be separate calls, not
`add && commit`: the in-agent commit-gate hook runs `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit` at the moment
the `git commit` call is submitted, and the artifact-only carve-out that lets this
commit through mid-pipeline inspects the *already-staged* set — so the `git add` has to
have run in a prior call. (Skip both with a one-line note if the project gitignores `.temper/specs/`
— never `git add -f`.) This gives the diff a committed baseline to be reviewed
against. Then launch that stage.

**On PASS at the plan gate, before showing options:** if `autonomy.enabled: true`, read
`${CLAUDE_PLUGIN_ROOT}/reference/autonomy.md` now and offer the arming choice it describes instead of a
single "Continue" option. Ask it with `AskUserQuestion`, header `Temper gate`, as every gate:
either answer is the person's approval of the plan. On "Autonomous", arm the run first
(`${CLAUDE_PLUGIN_ROOT}/scripts/temper state set run_mode autonomous`), then do the On
Continue steps: with the mod, the arming call is allowed only while the run is still at Plan.

---

## Stage 1.5: Design (medium/complex only)

Skip straight to Build when `phases.design: false`, or complexity is trivial/simple.

Launch:

```
Use the Agent tool, model: {design}, prompt:
"Follow ${CLAUDE_PLUGIN_ROOT}/agents/design.md exactly. Spec: {spec_path from state}.
Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder."
```

After it returns, record its usage once: `${CLAUDE_PLUGIN_ROOT}/scripts/temper usage add --stage design --model {design} --tokens {subagent tokens} --ms {duration ms}` (the numbers the Agent result reports; omit a flag the result does not give).

Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate design` (one requirement: design.md carries an Areas of Concern
section — flagged conflicts with owners, or an explicit "None flagged — why"; design
*quality* still shows up in whether Build can execute it and what Review finds). Gate
options: Continue / Grill Me / Teach Me / "Walk through step by step" (same shape as
Plan's — architecture overview, API contracts, database changes, integration points,
decision log; only sections `design.md` actually has) / Save / Other. On FAIL: "Loop back
to Plan" (`state loop design plan`, then Plan again) /
"Override and continue" (`${CLAUDE_PLUGIN_ROOT}/scripts/temper override design --reason "<the reason>"`) / "Save for
later". The Gates section says how each is asked.

**On Continue:** `${CLAUDE_PLUGIN_ROOT}/scripts/temper state advance design_complete build`, launch Build.

---

## Stage 2: Build (in groups by default)

Read `${CLAUDE_PLUGIN_ROOT}/reference/build-groups.md` once and
run its loop: the base sha, one worktree per group, every ready task launched in one turn on
the task model the schedule prints, `temper task gate` after each, one human gate per group,
`temper integrate`, then the Build completion gate. Its "Fix pass" section is what a Review or
Check loop back to Build launches. **On Continue** at the completion gate:
`${CLAUDE_PLUGIN_ROOT}/scripts/temper state advance build_complete review`, launch Stage 3.

**Scope drift (the fix pass).** Print every panel the Build brief (`agents/build.md`) returns
verbatim. **If it has a `DRIFT` section**, ask the person about each row before the checkpoint or
fix-pass gate, with and without the mod, and in autonomous mode too (a drift is never
answered for the person). One `AskUserQuestion` per row: header `Scope drift`; the question's
first line `Outside the plan: {path}`, then `Why: {why}` and `Change: {change}` from the row;
options **"Add to plan"** (the file becomes part of the plan), **"Revert"** (the task goes on
without it) and **"Allow once"** (only this change; the why is recorded as the reason). Record
each answer with
`${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence add --stage build --phase feedback --claim "drift {path}: {choice}: {why}"`;
for "Add to plan", also add the file to `plan.md`'s Files to Modify table. Then relaunch **the
same task** (or the same fix pass) with one `Drift decision: {path}: {add|revert|allow-once}`
line per answer. A typed answer instead of an option is a change request: handle it like
"Change". In grouped Build a task agent never drifts: the task gate fails any file outside
its declared files.

---

## Stage 3: Review

Launch:

```
Use the Agent tool, model: {review}, prompt:
"Follow ${CLAUDE_PLUGIN_ROOT}/agents/review.md exactly. Spec: {spec_path from state}.
Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder."
```

After it returns, record its usage once: `${CLAUDE_PLUGIN_ROOT}/scripts/temper usage add --stage review --model {review} --tokens {subagent tokens} --ms {duration ms}` (the numbers the Agent result reports; omit a flag the result does not give).

Gate: `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate review` (zero open findings at or above `review.block-on`). On FAIL
the options are "Loop back to Build (Recommended)" / "Accept a finding" / "Override and continue" / "Save for later".
"Accept a finding" asks a second question with the same header: one option per open finding, `Accept finding {id}`
with its claim as the description (three at most; the rest through "Other"), then the reason question
`Accept finding {id}. What is the reason?` (options "It is not a real issue" / "I accept the risk" / "Cancel"). With
the reason, run `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence accept --stage review --id {id} --reason "<the reason>"`,
run the gate again and show it again. An
**"Architecture Depth Review"** option is also always available — runs the 5-dimension
module-depth analysis (seams, adapters, locality, leverage, deletion test) on changed
files and folds `[ARCH-DEPTH]` findings into the summary before re-showing the gate.

**On Continue:** `${CLAUDE_PLUGIN_ROOT}/scripts/temper state advance review_complete check`, launch Check.

---

## Stage 4: Check

Launch:

```
Use the Agent tool, model: {check}, prompt:
"Follow ${CLAUDE_PLUGIN_ROOT}/agents/check.md exactly. Spec: {spec_path from state}.
Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder."
```

After it returns, record its usage once: `${CLAUDE_PLUGIN_ROOT}/scripts/temper usage add --stage check --model {check} --tokens {subagent tokens} --ms {duration ms}` (the numbers the Agent result reports; omit a flag the result does not give).

Gate: `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate check` (tests pass, coverage >= threshold, every `intent.md` scenario
traced to a test by name — the requirement that catches a scenario Build never
implemented). On a clean pass, Check may also have written `{spec_path}/config-suggestions.json`
— if present, offer a **"Review config suggestions"** option before Continue: show each,
Accept (write it into the project's CLAUDE.md/AGENTS.md) / Reject / Defer, then re-show the gate.

On PASS the gate question is the Commit question, asked once, with the header `Temper gate`:
**"Commit (Recommended)"** / "Save for later" (plus "Review config suggestions" when the file
is there). "Commit" is this gate's Continue: do the On Continue step below, then the Commit
section, and do not ask the Commit question there again.

**On Continue:** `${CLAUDE_PLUGIN_ROOT}/scripts/temper state advance check_complete commit`, proceed to Commit.

---

## Commit

Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit`. It aggregates every upstream gate's last verdict (PASS or
overridden), and — only when `run_mode == autonomous` — blast radius and park-on-touch.

- **PASS (interactive):** ask with `AskUserQuestion`, header `Temper gate`: "Commit" / "Save
  for later" / "Other", unless the person already chose "Commit" at the Check gate (then go on
  at once). The mod never clears or archives the state itself, so you do every step below, in
  order, ending with `state clear`.
  On Commit: set `intent.md`'s header to `**Status:** completed` + `**Completed:**
  {date}` — the orchestrator owns the terminal state flip (the Check subprocess never
  gates, so the orchestrator must). If `build-context.json` recorded
  deviations from the plan (unplanned files, approach changes), write them into
  `plan.md` as a `## Deviations` section — the committed plan describes what was
  actually built. Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper state archive`: it writes the run's decision record to
  `.temper/specs/{slug}/gate-ledger.json` (verdicts, overrides with approver,
  evidence counts) **without touching the live state**, so the pre-commit gate still
  verifies for real. Then stage the diff **and the spec artifacts**
  (`.temper/specs/{slug}/` — intent.md, tasks.md, plan.md, design.md,
  gate-ledger.json as present): the committed artifact chain is the audit trail —
  what was asked for, what was planned, what the gates verified, and the diff that
  answers them, in one commit. If the project gitignores `.temper/specs/` that's its
  explicit choice — never `git add -f` over it; note once that the artifacts stay
  local-only. Then `git commit` (a conventional-commit message summarizing the
  feature), then `${CLAUDE_PLUGIN_ROOT}/scripts/temper state clear`.
- **PASS (autonomous):** never auto-commits — park with a `SHIP-PENDING-COMMIT` report
  instead (the Park step in `${CLAUDE_PLUGIN_ROOT}/reference/autonomy.md`).
- **FAIL:** show `${CLAUDE_PLUGIN_ROOT}/scripts/temper report`, and ask with `AskUserQuestion`, header `Temper gate`:
  "Override and commit" or "Save for later". "Override and commit" needs the
  person's reason: when the answer carries none, ask `Override and commit. What is the reason?` (options "I accept
  the risk" / "It is not a real issue" / "Cancel"). Then run `${CLAUDE_PLUGIN_ROOT}/scripts/temper override {stage} --reason "<the reason>"`
  for every stage the gate names, all in one Bash call (the mod lets that one call through for the person's
  answer), re-run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit` (it should now PASS) and go on with the PASS steps.

Print the final ledger (`${CLAUDE_PLUGIN_ROOT}/scripts/temper report`) either way — the last thing the user sees is
what was actually verified, not a narrated summary.

---

## Resume

`/temper` with no arguments, or with the feature that is already in progress, while
`build-state.json` exists → validate per
`${CLAUDE_PLUGIN_ROOT}/reference/orchestrator-patterns.md` → "Resume Validation", then take the run
up: when `next_stage` already has a verdict (the run waits at its gate, or was saved for later), ask
its gate question; otherwise launch its stage. The mod's Go on button is this same `/temper` with no
arguments. Start over is under the gate question's "More options": when the person picks it, ask with
`AskUserQuestion`, header `Temper resume`: "Start over" / "Cancel" (the person's Start over answer
lets the reset through). `/temper "new feature"` while state exists for a **different** feature →
follow "Nested Invocation Protection" there (say "feature", not "item").

---

## Entering at a stage (the stage commands)

`/temper:plan`, `/temper:design`, `/temper:build`, `/temper:review` and `/temper:check` are
doors into this flow, so there is one flow to keep right. Each one reads this file and enters
at its stage, with its arguments as the feature (Plan) or the spec folder's name. Then:

1. **A run is active** (`${CLAUDE_PLUGIN_ROOT}/scripts/temper state get spec_path` prints a path):
   the run is where the CLI says, and a door never moves it. When the run's next stage is the
   door's stage, take it up as Resume says. Otherwise say in one line where the run is ("The run
   is at Review.") and take it up from there as Resume says.
2. **No run is active, the Plan door:** start a run for the feature as `/temper "<feature>"`
   does. The Intent gate comes first: the plan is derived from the accepted intent.
3. **No run is active, a later door:** the run is for the spec folder in the project's
   `.temper/specs` folder that holds `plan.md` and `tasks.md` (the one the arguments name, the
   single such folder when there is one, or else ask the user; when the project has none, say
   in one line that this stage needs a planned feature and that `/temper:temper "<feature>"`
   starts one, and do nothing else). Start a run for it
   (`${CLAUDE_PLUGIN_ROOT}/scripts/temper state init {slug} --command temper`; the spec files
   stay), and set its complexity from the `**Complexity:**` header of its `intent.md` when it has
   one (`${CLAUDE_PLUGIN_ROOT}/scripts/temper state set complexity {tier}`), as Plan does. The
   Design door runs Design only for a run that has it (a medium or complex feature with
   `phases.design: true`, or a spec folder that holds `design.md`); otherwise say so in one line
   and enter at Build. Then walk the stages before the door's stage in order, without running
   them: Intent, Plan, Design when the run has it, Build, Review. For each one run
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate {stage}` and ask its `Temper gate` question as Gates
   says (on PASS "Continue to {next} (Recommended)" / "Save for later"; on FAIL "Override and
   continue" with the person's reason / "Save for later"). On Continue run only that stage's
   `state advance` (after Plan, also create the feature branch when not on it); on Override and
   continue, run its `override` first. Then launch the door's stage as its section above says,
   and go on from there as this file says.

The stage hooks mark only `/temper:intent`, which captures a draft on its own: a door is this
flow, and a session may end at any gate of it.
