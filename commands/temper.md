---
description: "Unified SDLC command: intent → plan → design? → build → review → check → commit, gated by the temper CLI"
argument-hint: "<feature-description>"
---

# Temper: Unified SDLC Command

**FIRST OUTPUT (do this before reading anything else).** Look at your system prompt now for a line that starts with `Temper enforcement:`. If there is none, your very first line of text in this reply must be exactly: `Temper enforcement is off here (no mods support); continuing with prompt based phases.` If the line reads `Temper enforcement: off (UI only)`, the Temper mod is loaded and the user turned enforcement off, so your very first line must be exactly: `Temper enforcement is off (turned off by the user); continuing with prompt based phases.` Then carry on as written below. Never treat either case as an error, and say it only once per conversation. If the line reads `Temper enforcement: active`, say nothing about it. You state this once, here in the main conversation: a stage subprocess never has that line in its system prompt, so its brief says nothing about enforcement, and you never ask a stage to say it. Wherever this file says **With the Temper bar**, it means the system prompt has a `Temper enforcement:` line, either `active` or `off (UI only)`: the mod is loaded and keeps the bar either way, and turning enforcement off only stops the mod from refusing tool calls.

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
run. With the Temper mod loaded (the system prompt has a `Temper enforcement:` line),
the mod already answers the read-only words and has already recorded the person's
decision for the others; this table is what you do next, and everything you do when the
mod is absent. Any other first word is a feature description.

| Word | What to do |
|---|---|
| `status` | Print `${CLAUDE_PLUGIN_ROOT}/scripts/temper status` and `${CLAUDE_PLUGIN_ROOT}/scripts/temper state get next_stage`. |
| `timeline` / `report` | Print `${CLAUDE_PLUGIN_ROOT}/scripts/temper report`. |
| `help` | List these words with their one line meanings. |
| `approve` / `next` | Treat it as the human answer at the current gate: confirm the gate with `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate {stage}`, record the move with `${CLAUDE_PLUGIN_ROOT}/scripts/temper state advance {stage}_complete {next}`, then continue. Refuse and print the failing requirements when the gate is not PASS. |
| `back <phase> <reason>` | `${CLAUDE_PLUGIN_ROOT}/scripts/temper state loop {current stage} {phase} --reason "{reason}"` (stop when it prints `BLOCKED`: the loop budget is spent), `${CLAUDE_PLUGIN_ROOT}/scripts/temper state set next_stage {phase}`, record the reason with `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence add --stage {phase} --phase feedback --claim "back: {reason}"`, and rerun every later gate before advancing. |
| `override <reason>` | `${CLAUDE_PLUGIN_ROOT}/scripts/temper override {stage} --reason "{reason}"`. With no reason, refuse: "Override needs a reason. Use /temper:temper override <reason>." The skip is the person's go-ahead for that stage: with the Temper bar, the bar sends `continue {stage}` after the skip (the hook lets that stage's `state advance` through once the skip is recorded), and you do that stage's On Continue steps and launch the next stage. Without the bar, treat it as the answer "Override and continue" and go on to the next stage. |
| `accept <id> <reason>` | `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence accept --stage review --id {id} --reason "{reason}"`. With no reason, refuse. |
| `drift <add\|revert\|allow> <reason>` | `add`: put the file in plan.md's Files table. `revert`: restore the file to its committed state (a file in the project only, never a file in the plugin folder). `allow`: continue once. Record the choice with `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence add --stage build --phase feedback --claim "drift {path}: {choice}: {reason}"`. |
| `pause` / `resume` | Stop at the next gate and wait for the person, or continue from it. |
| `pr` | Write a pull request description from `${CLAUDE_PLUGIN_ROOT}/scripts/temper report`: overrides, accepted findings and drift decisions with their reasons. |
| `continue <stage>` | The person already approved `<stage>` (the Temper bar recorded the decision; the matching state advance is allowed once). Do the "On Continue" steps of that stage exactly as written for it: the status flip and `Accepted-by` for Intent, `state advance`, the feature branch (`git checkout -b feature/{slug}` when not on it) and the commit of the approved artifacts for Plan, `base_sha` before the first Build launch, and so on. Use the `state advance` of that stage as written. Then launch the next stage. Do not ask the gate question. The bar also sends it after the person skipped `<stage>` with a reason (the stage's gate may then be FAIL; the skip is recorded by `${CLAUDE_PLUGIN_ROOT}/scripts/temper override`, which the mirror message asks for): the same steps apply. For `check` do only the `state advance check_complete commit`: the Done bar's Commit button asks for the commit, so do not commit and do not run the Commit section. |
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
- **With the Temper bar**: the CLI state is the truth for where the run is.
  Never run `state init`, `state clear`, `state archive` or `state loop` on your own while a run is
  active (with enforcement active, the mod refuses them). The one exception is the
  `state clear` of the TRIVIAL exit in Stage 0, which the mod allows. If Resume
  Validation fails or the state looks wrong, stop, show what is wrong in one line, and
  wait. Never choose Start over or Delete saved state yourself. If a mirror
  call (`state advance`, `state set next_stage`) is refused or fails, say so in one line and wait: the bar
  shows the problem and offers to record the choice again.
- **On commit:** `${CLAUDE_PLUGIN_ROOT}/scripts/temper state clear` (evidence, gates, loop counters — spec artifacts
  under `.temper/specs/` are untouched, they're the permanent record).

## Gates

Every stage gate follows the same shape. After a stage Agent returns:

1. Print the summary box it returned, verbatim (each agent brief defines its format —
   not restated here).
2. Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate {stage}`. It prints PASS/FAIL with each requirement's status and
   writes the verdict to `.temper/gates.json`.
3. Show an `AskUserQuestion` gate. **With the Temper bar** (the system prompt has a
   `Temper enforcement:` line, `active` or `off (UI only)`) do not show it: the bar already offers the same choices with
   the same words (Continue to, Loop back to, Skip with a reason, Save for later, Grill me,
   Teach me, Discuss) and records the decision. Print the stage panel and the gate result, then
   end the turn with one line: `Waiting for you. Use the Temper bar, or type /temper:temper approve (or back, override, pause), or type a change.` (Minimal and off modes draw no buttons, so the typed words are the way there.) The
   person's message at a gate is the original "Other": if the user writes a message at a gate,
   answer it; if it asks for a change, make the change, run the gate again, then wait for the
   user again. Every other dialog stays (the autonomy arming choice, clarifying questions, the
   Build checkpoint feedback text). Without a `Temper enforcement:` line, show the gate as follows:
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
gate — none advance or block the pipeline.

Never re-derive gate logic here or in a stage prompt. Gate mechanics live only in the
temper CLI and its tests, never in a prompt.

## Feedback Loops

When a gate FAILs and the user selects "Loop back":

1. `${CLAUDE_PLUGIN_ROOT}/scripts/temper state loop {from} {to} --reason "<why>"` — this enforces
   `loops.max-per-type` (default 2), prints `BLOCKED` (exit 1) once the budget is spent,
   and auto-clears evidence for `{to}` and every stage downstream of it in
   the sequence — a stale row from the stage being redone must not survive to inflate
   the next gate's count. If blocked, don't offer the loop option again this run; fall
   through to Override / Save.
2. Re-launch the upstream stage's Agent (same template as its first launch), adding one
   line to its prompt: *"Feedback re-entry: {reason}. Fix this, then continue."*
3. When it returns, re-run the downstream gate that triggered the loop.

**With the Temper bar** a loop moves the run, and only the person decides that (with
enforcement active, the hook also refuses `state loop` from you). The
person's **Loop back** button (or `/temper:temper back <phase> <reason>`) is the loop: the
mod records the decision and sends you one message. In it, run `${CLAUDE_PLUGIN_ROOT}/scripts/temper state loop {from}
{to} --reason "<why>"` (the hook lets it through once, for that decision; it keeps the
budget and clears the evidence of `{to}` and every later stage), and when it does not print
`BLOCKED`, run `${CLAUDE_PLUGIN_ROOT}/scripts/temper state set next_stage {to}`. When it prints `BLOCKED`, the budget is
spent: say so in one line and stop (the person can skip with a reason or save for later). The
bar then runs `/temper:temper` with no arguments: continue from `next_stage` (see Resume) and
add the line from step 2, with the reason from that message, to the stage's prompt. Do not
call `state loop` or `state set next_stage` on your own; with enforcement active, the hook
refuses both without the person's decision.

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
(PASS or FAIL at commit, it always parks; grouped Build's local task commits and the local
`temper integrate` merge, both made by the CLI, are allowed), and
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
with the Temper bar and enforcement active, but only for a run that never left Intent:
no stage has completed and the next stage is still Intent, no gate holds a verdict, no
override is recorded, the spec folder holds none of `intent.md`, `plan.md`, `tasks.md`
and `design.md`, and the bar has recorded no advance and no loop back for the run. A
TRIVIAL return wrote nothing, so such a run has nothing to lose. Run it at once, before
anything writes a file in the spec folder. If mid-change it turns out NOT to be
trivial, stop and restart `/temper` properly.

Gate: `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate intent` (Problem stated, >=1 criterion, Status header). Options:
**"Continue to Plan (Recommended)"** / Grill Me / Teach Me / "Save for later" / Other
(a correction — edit intent.md, re-run the gate, re-show; this is the whole point of
the gate: intent corrections here cost words, the same correction after Plan costs the
plan). Open Questions are presented FIRST — each is answered by the human here or
explicitly carried forward; an intent accepted with open questions records that
choice.

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
single "Continue" option.

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
decision log; only sections `design.md` actually has) / Save / Other.

**On Continue:** `${CLAUDE_PLUGIN_ROOT}/scripts/temper state advance design_complete build`, launch Build.

---

## Stage 2: Build (one task per checkpoint)

Build runs **one task per launch**, gated at every checkpoint — nobody (human or
autonomy loop) should have to wait until all the work is done to redirect it.

1. Before the first Build launch, record the diff baseline:
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper state set base_sha "$(git rev-parse HEAD)"`. Checkpoint commits land
   during Build, so every later reader of "changed files" diffs against this sha,
   not HEAD.
2. Loop from the **next unchecked `- [ ]` task in `tasks.md`** (disk is the source
   of truth for resume — an interrupted run picks up exactly where tasks.md says).
   Launch:

   ```
   Use the Agent tool, model: {build}, prompt:
   "Follow ${CLAUDE_PLUGIN_ROOT}/agents/build.md exactly. Spec: {spec_path from state}.
   Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder.
   Checkpoint: task {N}.
   {One "Checkpoint feedback #{K}: {text}" line per pending feedback item.}
   {If a review-context.json or check-context.json feedback file exists, name it here.}"
   ```
3. Print the returned panel verbatim, then record the launch's usage once: `${CLAUDE_PLUGIN_ROOT}/scripts/temper usage add --stage build --model {build} --tokens {subagent tokens} --ms {duration ms}`.
4. Gate with `AskUserQuestion`:
   - **"Continue (Recommended)"** — on a non-last task, go to step 2 for the next
     task. On the last task, this becomes the normal Build completion gate below.
   - **"Change"** — never approval. Record
     `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence add --stage build --phase feedback --claim "feedback #{K}: {text}"`
     for each item the user typed, then relaunch **the same task** with the feedback
     lines added to its prompt.
   - **"Stop"** — run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate build`, then save for later.
5. **On the last task's Continue** (the normal completion gate): `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate build`
   (RED-then-GREEN evidence recorded, no unchecked tasks, all feedback answered).
   Options (four max; Override and corrections arrive via "Other"): Continue to
   Review / Teach Me / "Loop back to Plan" (only if Build judges the plan
   infeasible — human-driven, no circuit breaker, max 1 per run) / Save.
   **On Continue:** `${CLAUDE_PLUGIN_ROOT}/scripts/temper state advance build_complete review`, launch
   Stage 3.
6. **Autonomy enabled:** the panel still prints and the per-scenario checkpoint
   commits still happen, but Continue is auto-selected at every checkpoint — Change
   and Stop stay interactive-only. The autonomy blast-radius check in
   `gate commit` uses `base_sha`-relative diffs plus still-uncommitted paths.

### Grouped mode (`build.mode: grouped`)

When `${CLAUDE_PLUGIN_ROOT}/scripts/temper config get build.mode` prints `grouped`, replace steps 2 to 4 with this loop
and keep steps 1, 5 and 6 (the per-task launch above is the default and stays unchanged).
The loop holds no rules of its own: every decision is a CLI output, so relay it.

1. For each group in `tasks.md` whose `Depends` groups have passed:
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper group start G<n>` (it makes the group's worktree).
2. `${CLAUDE_PLUGIN_ROOT}/scripts/temper schedule` prints one JSON line per ready task (task, group, title, worktree,
   model, attempt). Before each launch run `${CLAUDE_PLUGIN_ROOT}/scripts/temper task start N`. Launch **every ready
   task in ONE turn**, so they run in parallel, each on the `agent_model` its line prints (the alias the Agent tool takes; `model` is the full id):

   ```
   Use the Agent tool, model: {agent_model}, prompt:
   "Follow ${CLAUDE_PLUGIN_ROOT}/agents/build-task.md exactly.
   Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder.
   Task: {N}."
   ```
3. After each returns: `${CLAUDE_PLUGIN_ROOT}/scripts/temper task gate N --model {model} --tokens {subagent tokens} --ms {duration ms}`.
   Grouped task agents are **not** recorded with `usage add`; `task gate --tokens --ms`
   records them, so each launch is counted once. Act on the single `NEXT:` line it
   prints: `NEXT: schedule` goes back to step 2; `NEXT: retry Task N on {model}` and
   `NEXT: escalate Task N on {model}` go back to step 2 (the schedule prints the model);
   `NEXT: park group G` leaves that group parked (other groups go on).
4. When the schedule prints `{"waiting"...}`, start any group whose dependencies have now
   passed (step 1) and ask the schedule again. When every task of group G has passed:
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper group gate G<n>`. A parked group, or a FAIL, goes to the user with the CLI's
   reason; nothing else is decided here.
5. One `AskUserQuestion` per group, with the group's gate output: **"Continue (Recommended)"**
   (next group) / **"Change"** (never approval: record the feedback, then
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper group reopen G<n> --task N --feedback {ID}` for each task it concerns, and go
   back to step 2; only those tasks re-run) / **"Stop"** (`${CLAUDE_PLUGIN_ROOT}/scripts/temper gate build`, then save).
6. When the schedule prints `{"done": true, ...}`: `${CLAUDE_PLUGIN_ROOT}/scripts/temper integrate`, then
   `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate build`, and go on to the normal Build completion gate (step 5 above).
   Show the group-level panel from the CLI output, not a per-task one.
7. **Autonomy enabled:** every group's Continue is auto-selected; Change and Stop stay
   interactive-only; a parked group, or an integrate FAIL, parks the run (see
   `${CLAUDE_PLUGIN_ROOT}/reference/autonomy.md`).

---

## Stage 3: Review

Launch:

```
Use the Agent tool, model: {review}, prompt:
"Follow ${CLAUDE_PLUGIN_ROOT}/agents/review.md exactly. Spec: {spec_path from state}.
Plugin folder: the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off); wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use this folder."
```

After it returns, record its usage once: `${CLAUDE_PLUGIN_ROOT}/scripts/temper usage add --stage review --model {review} --tokens {subagent tokens} --ms {duration ms}` (the numbers the Agent result reports; omit a flag the result does not give).

Gate: `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate review` (zero open findings at or above `review.block-on`). An
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

**On Continue:** `${CLAUDE_PLUGIN_ROOT}/scripts/temper state advance check_complete commit`, proceed to Commit.

---

## Commit

Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit`. It aggregates every upstream gate's last verdict (PASS or
overridden), and — only when `run_mode == autonomous` — blast radius and park-on-touch.

- **PASS (interactive):** `AskUserQuestion` — "Commit" / "Save for later" / "Other".
  **With the Temper bar** do not ask: the Done bar's Commit button is this question, and its
  message ("The user pressed Commit ...") means the person chose Commit. The bar never clears
  or archives the state itself, so you do every step below, in order, ending with `state
  clear`; when the bar sees the state gone it shows no run (it never goes back to Intent).
  On Commit: set `intent.md`'s header to `**Status:** completed` + `**Completed:**
  {date}` — this orchestrated path owns the terminal state flip (the standalone
  `/temper:check` gate does it only when Check runs as its own command; here the
  subprocess never gates, so the orchestrator must). If `build-context.json` recorded
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
- **FAIL:** show `${CLAUDE_PLUGIN_ROOT}/scripts/temper report`, offer "Override and commit" (records the override,
  re-run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit`, it should now PASS) or "Save for later".

Print the final ledger (`${CLAUDE_PLUGIN_ROOT}/scripts/temper report`) either way — the last thing the user sees is
what was actually verified, not a narrated summary.

---

## Resume

`/temper` with no arguments and `build-state.json` exists → validate per
`${CLAUDE_PLUGIN_ROOT}/reference/orchestrator-patterns.md` → "Resume Validation", then launch `next_stage`.
`/temper "new feature"` while state exists for a **different** feature → follow
"Nested Invocation Protection" there (say "feature", not "item"). `/temper` (no args) for
the **same** feature already in progress → "Continue from {next_stage} (Recommended)" or
"Start over (replan)". **With the Temper bar** skip that
question: the bar's Continue button runs `/temper` with no arguments after the person's
decision is recorded, so continue from `{next_stage}` at once and launch its stage.

---

## Individual Commands Still Work

```
/temper:plan    → Just planning, stops at gate
/temper:design  → Just design (for complex features), stops at gate
/temper:build   → Just building, stops at gate
/temper:review  → Just review, stops at gate
/temper:check   → Just check, stops at gate
```

These run directly in the current context by default — use them for granular control —
or in the same per-stage subprocess as `/temper` when `stages.subprocess: true` is set.
They still call `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate {stage}` at their own gate either way.
