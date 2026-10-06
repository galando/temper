# Temper mods support: research and plan

**Status:** awaiting approval (Step 0). Nothing below is built yet.
**Date:** 2026-10-02
**Intent:** `.temper/specs/mods-support/intent.md` (Temper Intent gate: PASS, 13 of 13 checks)
**Tested against:** Claude Code 2.1.287 (current), plus 2.1.286, 2.1.259 and 2.1.200 for the old version question.

Items marked **Needs your call** are decisions I will not make alone. Everything else
is my recommendation; say so if you want it changed.

---

## 1. How Temper works today (repo facts)

### Stages

- Order: `INTENT → PLAN → DESIGN? → BUILD → REVIEW → CHECK → COMMIT`
  (`commands/temper.md:2,33-44`). The CLI holds the same list:
  `STAGES="intent plan design build review check commit"` (`scripts/temper:47`).
- `/temper:fix` runs its own sequence, `STAGE_SEQ_FIX="rca fix review check"`
  (`scripts/temper:59-60`); fix evidence is gated as `build` (`:51-53`).
- **Intent is already its own stage.** It has a command (`commands/intent.md`), an
  agent brief (`agents/intent.md`), a gate (`gate_intent`, `scripts/temper:1090`), and
  it is "always interactive" (`commands/temper.md:204`). No split is needed; your
  prompt assumed it might be part of Plan.
- **Design is a seventh stage you did not list.** It is optional: skipped when
  `phases.design: false` or complexity is trivial or simple (`commands/temper.md:249`);
  `gate_design` passes when `design.md` is absent (`scripts/temper:1349`).
- Each stage's contract lives in its own brief in `agents/` and its own page in `reference/`.
  Gate logic lives only in `scripts/temper` (`.claude/CLAUDE.md`).
- Build runs one task per checkpoint, with Continue, Change and Stop
  (`commands/temper.md:269-308`).

### intent.md

- Path: `.temper/specs/{slug}/intent.md` (`scripts/temper:354`, `commands/intent.md:9,47`).
- Template: `templates/intent.md`. Sections: Problem, Success Criteria, Constraints,
  Scope and Non-goals, Business Outcome, Target Users, Open Questions, Decisions, then
  Scenarios (BDD, filled by Plan), Scenario Coverage Checklist, Source Traceability.
- **Acceptance criteria already have a defined format** (`templates/intent.md:24-30`):

  ```
  - [ ] AC-01 [required]: {criterion} (source: ...)
    Why: {...}
    Validate: {scenario | code | metric | manual} — {details}
  ```

  `scripts/acceptance.py` parses it: first line `^(AC-\d+)\s*\[(required|optional)\]:`
  (`:119`), `Validate:` by `^\s*Validate:\s*(\w+)\s*[—-]\s*(.*)$`, scenarios link back
  with `Covers: AC-01, AC-02`. A criterion counts as passed only with a supported
  evidence row (exit code 0 plus an artifact hash or a command) (`:145-155, 240-252`).
  The checkbox is cosmetic and stripped. **I will reuse this format, not invent one.**

### The CLI (the deterministic spine)

- `scripts/temper` (bash plus python3 stdlib). Subcommands: `init`, `state`,
  `evidence`, `gate`, `model`, `override`, `report`, `bands`, `metrics`, `config`.
- Evidence ledger: `.temper/evidence/{stage}.json`. Gate verdicts:
  `.temper/gates.json` as `{verdict, requirements, ts}`.
- Run state: `.temper/build-state.json` (`stage`, `next_stage`, `spec_path`,
  `run_mode`, ...), moved by `temper state advance`.
- Override: `temper override <stage> --reason "..."`; a reason is required
  (`:1741`); appended to `.temper/overrides.json` with author and time.
- Commit gate (`:1520-1678`) needs PASS or override for every stage of the run.

### Enforcement today

- The plugin's hooks file binds two classic hooks: `UserPromptSubmit` →
  `stage-marker.sh` and `Stop` → `verify-stage-gate.sh` (refuses to end a standalone
  stage session until a verdict exists; fails open after two blocks).
- Opt in pack `packs/guardrails/settings-guardrails.json` adds `PreToolUse` guards for secrets,
  protected paths, the regression test, and `block-uncommitted-gate.sh` (runs
  `temper gate commit` before a Bash `git commit`).
- `scripts/guards/install.sh` writes a native git `pre-commit` hook that runs
  `temper gate commit`.
- **Nothing restricts Write or Edit by stage today.** This is the gap Part A closes.

### Gaps your prompt assumes exist but do not

| You asked for | Today | Proposal |
|---|---|---|
| test, lint, typecheck commands in Temper config | none; Check auto detects per stack (`reference/check.md:15-26`) | add `check.commands.{test,lint,typecheck}` to `.claude/temper.config`; Check uses them when set |
| Fix loop limit, default 3 | `loops.max-per-type` default 2 per loop pair (`scripts/temper:437-478`); "3+ attempts" is prose only (`reference/fix.md:141`) | add `fix.max-loops: 3`, counted by the state machine |
| Accept a review finding with a reason | only `evidence resolve` (fixed) and gate level override | add `temper evidence accept --stage review --id N --reason` so the review gate stops counting it |
| Scope drift against plan files | only a non blocking WARN (`reference/build.md:58-63`) | the mod enforces it, using the plan's `Files to Create` and `Files to Modify` tables and `tasks.md` `**File:**` lines |
| Intent lint: out of scope section, open questions resolved | `gate_intent` checks most, not these two | add both checks to `gate_intent` |
| Live criteria status | computed inside `acceptance.py check` only | add `temper status --json` writing `.temper/status.json` (criterion, status, evidence) after each gate; the mod reads it |

All CLI additions are `scripts/temper` edits plus `test-temper.sh` cases, per the repo
rule. They also help users without mods.

---

## 2. Mods research: what the types and docs say

Sources: the docs pages overview, create, reference, interface, events, api, test,
admin and troubleshoot under `code.claude.com/docs/en/plugins/mods/`, and the types
Claude Code 2.1.287 generated at `.claude-plugin/types/claude-code/index.d.ts` when I
loaded a probe mod for one session. The generated file matches the one
the plugin authoring skill ships, except that built in tool inputs moved to a separate
`claude-code-tools/index.d.ts`.

### 2.1 Probe results (run in this container)

Probe: a plugin with a classic `UserPromptSubmit` hook and a module that denies every
`Write`, in one hooks file.

| Claude Code | Plugin loads | Classic hook runs | Module runs (Write denied) |
|---|---|---|---|
| 2.1.287 | yes | yes | yes, even under `--permission-mode bypassPermissions` |
| 2.1.286 | yes | yes | **yes** (no flag set) |
| 2.1.259 | yes | yes | no, `modules` silently ignored |
| 2.1.200 | yes | yes | no, `modules` silently ignored |

Same probe with a `userConfig` field that declares `options` (a picker):

| Claude Code | Result |
|---|---|
| 2.1.287, 2.1.286 | loads |
| 2.1.259, 2.1.200 | **the whole plugin fails to load**: no classic hook, no command (`Unrecognized key: "options"`) |

**Conclusions for disclaimer 1:**

1. A `modules` key in Temper's existing hooks file is safe on old versions.
2. `userConfig` must **not** use `options`. The docs confirm: versions before 2.1.271
   cannot load a plugin that declares it. I will declare `uiMode` and `enforcement` as
   plain strings and validate them in code.
3. The module ran on 2.1.286, one release before the documented minimum. Builds in
   the early access window may run it against an older API. The adapter checks
   `$.session.version()` in `session.start` and stays inert (every hook passes
   through) below 2.1.287 or when the call fails.

### 2.2 Surfaces (disclaimer 2)

From the overview's "Where mods run" table:

| Surface | Hooks (enforcement) | Drawing (Temper UI) |
|---|---|---|
| `claude` in a terminal, incl. editor terminals and the JetBrains plugin | yes | yes |
| Desktop app, Code tab (not WSL) | yes | yes, except terminal only elements |
| Desktop app, WSL session | no (plugins unavailable) | no |
| VS Code extension chat panel | yes | no |
| `claude -p` and the Agent SDK | yes | no |
| Remote Control from claude.ai or the mobile app | yes, on your machine | only in your machine's terminal |
| Cloud sessions (claude.ai/code) | yes, if the plugin reaches the session | no |
| claude.ai chat, Cowork | not mentioned anywhere in the docs | not mentioned |
| GitHub Actions | not named; it runs `claude -p`, so I infer hooks yes, drawing no | no |

Cloud sessions only get plugins through server managed settings; a repo's
`enabledPlugins` does not carry over. So for most users, claude.ai/code runs Temper
with prompt based phases only.

**Discrepancy:** the types list `vscode` and `mobile` as render surfaces and say
`Pane` is "raised on every surface"; the docs say the VS Code panel draws nothing. I
follow the types (the UI code handles all four surfaces and degrades to text), and I
treat the docs as the current behavior for the README.

### 2.3 Events and API: what matches the prompt, and what does not

| Prompt item | Types say | Plan |
|---|---|---|
| `tool.call` returns `{ deny }` | yes; also fires for subagents (`AgentLoop.agentId`) | as asked |
| inject via `prompt.section` or `prompt.context` | `prompt.section` can only rewrite or drop a section the engine already has; `prompt.context` changes the first user message, so a phase change spends the whole prompt cache | **use `prompt.compose`**: append one `session` scope section `temper:phase` last. It is rendered on every request, so it survives `/compact` by construction, and a change only spends the cache after it |
| `$.prompt.submit` for actions | yes; queues a turn once idle | as asked |
| `prompt.suggest` | yes; Tab to take; suppressed while the box has text or a turn runs | as asked; never submits |
| `PromptHint` site | `tail` is drawn on the terminal only; on desktop only a full `hint` rewrite shows | terminal: `tail`; desktop: no hint, the band carries the next step |
| spinner "criterion N of M" | `Spinner` props are `word`, `message`, `suffix`, `mode`; no progress slot | rewrite `word` to `Building · criterion 2 of 5` |
| `turn.complete` line | returning `{ text }` shows it beneath the answer | as asked |
| toasts | `$.ui.toast`, 4 s default | as asked, one per transition |
| `AskUserQuestion` site | a tree must hold the engine's dialog reference once, own elements above it | full mode adds a one line Temper header (phase, criterion) above the native dialog; answering stays one press |
| digit hotkeys on the band | `hotkey` is one digit or letter; works while the band holds focus, **and a bare digit typed into an empty prompt presses a band Button** | as asked: 1, 2, 3, 9, 0 |
| docked pane | `$.ui.open`; docks in fullscreen; opened unasked it needs 144 columns, opened by the person 110 | open on `/temper` or a press; only auto open where it would dock |
| `$.ui.invalidate` | exists; `$.state` writes redraw readers automatically | state in `$.state`; `invalidate` only for `prompt.compose` cache |
| compaction | event is `session.compact`; `$.state` survives compaction; `session.start` does **not** fire after `/clear`, `/resume`, `/branch` | rebuild state on `classic.SessionStart` as well |
| `attribution.text` | kinds `commit`, `pr`, `exemption`, `remedy` | add one Temper line to `pr` when enabled |
| `turn.step` per phase model or effort | async generator; `next({ ...e, model })` or `effort` | optional, off by default |
| reviewer model | `turn.step` in a subagent carries `agentId`; `$.agent.list()` names its type | optional: the steps of the `temper-review` agent run on `reviewerModel`; the `agent.spawn` event is never changed (9.6.1) |

### 2.4 userConfig at load or live (Part C.5)

- `register(on, options)` receives the values once per load (`PluginOptions`).
- But a change to a plugin's `userConfig` row in `/config` **reloads the module with
  the new options** (reference: "a change there reloads the module with the new
  `options`"), and `$.config.set({ key: 'temper.uiMode', value })` changes the row as
  if the person did.
- `$.config.list()` returns each row with `isLocked: true` when "a trusted source
  (managed settings, the organization's policy) owns the value".
- Plan: `/temper mode x` calls `$.config.set`. That persists in user settings, honors
  managed precedence (the engine refuses a locked row and returns `{ deny }`), and
  reloads the module. If the row is locked, `/temper mode` says "Your organization set
  Temper's mode to minimal; ask your admin to change it." I also mirror the live mode
  in `$.state` so the redraw is immediate across the reload. `$.store` is not needed
  for the mode itself.
- Precedence is therefore the engine's own: managed `pluginConfigs`, then user, then
  the manifest default. The docs do not spell out managed over user for an ordinary
  plugin's field; `isLocked` is the observable signal, and I will test it.

### 2.5 Storage facts that drive the state design

- `$.fs.write` replaces a file in place; not atomic (docs and types).
- `$.store` is one JSON file per plugin under `~/.claude/plugins/store/`, shared by
  every session on the machine, **not per project**; get then set is not atomic; 4 MiB.
- `$.state` is per session, survives hot reload and compaction, resets on `/clear`,
  `/resume` and `/branch`.

### 2.6 Admin controls and sec-default (disclaimer 4)

- `allowManagedModsOnly` is **not a top level setting**. It is an option of the built
  in guard: managed `pluginConfigs["cc-plugin-sec-default@builtin"].options.allowManagedModsOnly`.
  With it, Temper's mod does not load unless the organization ships Temper itself;
  the rest of the plugin (commands, skills, agents, classic hooks) still loads.
- `allowManagedHooksOnly`: also blocks user classic hooks, so the entries of
  Temper's hooks file stop too unless the plugin is force enabled.
- `disableAllHooks` in managed settings stops every mod and every settings hook.
- sec-default loads first whenever the machine has managed settings or the user is on
  Team or Enterprise. Chain order: sec-default and other prepended managed mods, then
  user mods (Temper), then appended mods, then built ins. "The managed-settings hooks
  run first: their deny is the call's result" (types, `tool.call`).
- **Composition:** a deny short circuits everything beneath it. If sec-default denies,
  Temper never sees the call. If Temper denies, sec-default has already passed it. A
  user mod cannot approve a call a `deny` rule refuses. Two denies never conflict.
- **Testing:** the test kit loads inline plugins at any tier (`tier('prepend')`), so I
  can test that Temper's denials compose with a prepended deny or allow plugin. Loading
  the **real** sec-default needs managed settings on the machine
  (`/etc/claude-code/managed-settings.json`). **Needs your call:** may I write that file
  in this throwaway container for one test run and remove it afterwards? It may also
  affect this session's own CLI. If not, the README will say the coexistence was tested
  with a simulated prepend guard only.

### 2.7 Security surface (disclaimer 6)

There is no manifest permission list. The engine scans the module and records what it
calls; `claude plugin validate` prints it and admins can refuse a mod by it
(`plugin.register` `uses`). The `calls:` line the validator prints for the built mod,
nothing else (24 calls in 9.6.2; the list is enforced by `scripts/check-mod-calls.sh`):

`agent.list, clock.sleep, command.run, config.list, config.set, fs.list, fs.read, fs.stat, prompt.fill,
prompt.submit, prompt.suggest, session.version, state.get, state.set, store.delete, store.get,
store.set, ui.ask, ui.close, ui.focus, ui.invalidate, ui.open, ui.resolve, ui.toast`

Why each call is there:

| Call | Reason |
|---|---|
| `agent.list` | the optional `reviewerModel`: whether a subagent's step belongs to the Temper review agent. Read only; the spawn is passed on unchanged |
| `clock.sleep` | (9.6.2) waits 60 ms before `build-state.json` is read again while the CLI rewrites it; replaces a `setTimeout` taken from `globalThis` |
| `config.list`, `config.set` | `/temper mode` and `/temper enforcement` read the row (locked by an administrator or not) and change it the way `/config` does |
| `fs.list`, `fs.read` | rebuild the run from `.temper/` files and the spec's events |
| `fs.stat` | resolve `.` to the project root so absolute tool paths can be made relative |
| `fs.write` | not used since 9.6.2: the mod writes no file. Events and the report are kept in `$.store` |
| `command.run` | a pressed Button ends with `/temper:temper` (no arguments) so the orchestrator launches the next stage with its own brief; `prompt.submit` refuses a text that starts with a slash, so the command runs as a command |
| `prompt.fill` | key 4 (Discuss) and key 2 at Build (Change) put a draft in the prompt box; the person types the rest and presses Enter. A press only, never from a hook; it changes no phase and writes no event |
| `prompt.submit` | a pressed Button sends its action to Claude (never from a hook) |
| `prompt.suggest` | the next action as a Tab suggestion after a turn |
| `session.version` | the version guard |
| `state.get`, `state.set` | the run view and live mode that the drawing hooks read |
| `store.get`, `store.set`, `store.delete` | own event ids, consumed human decisions, "mode already asked", and (9.6.2) the kept events and report as `vf:<path>`; `delete` drops the oldest of 40 kept folders |
| `ui.ask` | scope drift choices, the first run question, reasons |
| `ui.open`, `ui.close` | the pane |
| `ui.focus` | the band's key 9 moves the focus into the override reason field |
| `ui.invalidate` | redraw after a mode or enforcement change |
| `ui.resolve`, `ui.toast` | the element table; one toast per transition |

Three calls the first draft listed are not used and are no longer allowed:
`command.register`, `fs.exists` and `ui.status`. Reading a missing file is a rejected
`fs.read`, so `fs.exists` is not needed; the `/temper` command already exists as a
markdown command, so nothing is registered; and no status line is drawn.

- No `process.*`, `http.*` or `env.*`. Tests, lint, git and every CLI call are prompts
  to Claude, so they pass through Claude's normal tools and permissions.
- `fs.write` is the one write: Temper's own event files and `.temper/report.md`. No
  exception is needed for process spawning.
- A CI step asserts the `calls:` line so new surface needs a reviewed change.

### 2.8 UI elements (disclaimer 7)

I use only `Box`, `Text`, `Button` (and `Markdown` in the pane), which every drawing
surface has. No `Svg`, `Raster` or `Image`, so no fallback is needed.

---

## 3. Architecture

### 3.1 Phases

| Bar label | Temper stages | Notes |
|---|---|---|
| Intent | `intent` | unchanged |
| Plan | `plan`, then `design` when complexity is medium or complex | Design shown as a sub step "Plan · design"; `design.md` is a plan file |
| Build | `build` | task checkpoints unchanged |
| Review | `review` | |
| Check | `check` | PASS unlocks commit ("Done") |
| Fix | Check FAIL loop; also the entry phase of `/temper:fix` (RCA is its first action) | |

Commit is not a phase: after Check passes, the state is Done and `git commit` is allowed. The Commit
button at Done tells the orchestrator to do the Commit steps of `commands/temper.md` (gate commit, intent
Status completed, `state archive`, stage the diff and the spec artifacts, one commit, then `state clear`). The mod
never clears or archives the state itself. When the CLI state is gone the bar shows no run, never Intent.

### 3.2 Pure module (the mod's pure core, no `claude-code` import)

- The state machine: event sourced. `reduce(events) → RunState` and
  `decide(state, command) → { events } | { error }`. Commands: `approve`, `advance`,
  `back(to, reason)`, `override(phase, reason)`, `acceptFinding(id, reason)`,
  `drift(path, choice, reason)`, `checkResult(pass|fail)`, `pause`, `resume`.
  Rules: forward only one phase at a time and only on a PASS verdict or an override;
  `back` marks every later phase invalidated; an invalidated phase needs a fresh verdict
  (newer timestamp than the invalidation); Check FAIL enters Fix and counts a loop; at
  `fix.max-loops` the only legal commands are re-plan (`back` to Plan), override, or
  hand over (pause).
- The rules: `evaluate(state, toolCall) → allow | deny(reason)`. Every reason ends
  with what to do next (examples in 3.4).
- The criteria reader: parses `AC-NN` criteria from `intent.md` using the same patterns as
  `acceptance.py`, and merges per criterion status from `.temper/status.json`.
- The plan files reader: reads the allowed file list from `plan.md` tables and `tasks.md`.
- The Bash classifier: classifies a Bash command (git commit, temper CLI decisions, writes into
  protected Temper paths).
- The report: renders `.temper/report.md` from `RunState`.
- The config reader: reads the few keys the mod needs from `.claude/temper.config`.

### 3.3 Where state lives (decision)

| Data | Store | Why |
|---|---|---|
| Phase history: approvals, transitions, back, overrides, accepted findings, drift decisions, pauses | **append only event files** in `.temper/specs/{slug}/events/`, one small JSON file per event, named `{ts}-{session}-{seq}.json`, written once and never rewritten | survives sessions and machines; committed with the spec as the audit trail (Temper already commits `.temper/specs/` in user projects); a torn write damages one event, which the reader skips and reports; two sessions never overwrite each other because names are unique. This is how I get safe writes out of a non atomic `$.fs.write` |
| Gate verdicts, criteria status | read only from `.temper/gates.json` and `.temper/status.json` | the CLI owns verdicts (repo rule) |
| Folded run state for drawing | `$.state` | redraws readers; survives reload and compaction; rebuilt from files on `session.start` and `classic.SessionStart` |
| User preferences: first run asked | `$.store` | machine wide is right for a preference |
| uiMode, enforcement | `userConfig` (see 2.4) | managed precedence for free |

**Forgery guard:** Claude must not create approval events itself. The adapter denies
Write, Edit, NotebookEdit and MultiEdit on `.temper/specs/*/events/**`, `.temper/gates.json`,
`.temper/status.json`, `.temper/overrides.json` and `.temper/build-state.json`, and denies Bash
commands that write them (best effort). Trust follows content: after writing an event file the
mod stores a digest (SHA256 of the exact text) under `ev:{id}` in `$.store`. On every load an
event counts only if the stored digest matches the text now on disk, for every event type
(start, pause, resume, advance, checkResult, override, accept, drift, back). A file the mod did
not write, or one rewritten in place, is shown as "unverified" and counts for nothing. The
bootstrap start event for a run the CLI began earlier has one fixed name
(`0-bootstrap-1.json`), so entering the run again overwrites that file instead of adding
another, and a planted file under that name is replaced by a genuine one.

**Human decisions only from the human:** decisions (`approve`, `override`, `accept`,
`drift allow`, `back`) are created only by a button press or a `/temper` subcommand
whose `origin.kind` is the person's composer. The CLI commands that record the same
decisions for the commit gate (`temper override`, `temper evidence accept`,
`temper state advance` past Intent and Plan) are allowed through Bash only when a
matching unconsumed human event exists; otherwise the deny says "Only the user can
approve this. Ask them to press 1 or run /temper approve."

### 3.4 Deny rules (Part A)

| Phase | Allowed writes (Write, Edit, NotebookEdit) | Other rules |
|---|---|---|
| Intent | the spec's `intent.md` | |
| Plan | `intent.md`, `plan.md`, `tasks.md`, `design.md`, new ADRs under `docs/decisions/` | |
| Build | files in the plan, test files beside them, the spec dir | other path: scope drift choice |
| Review | spec dir only, unless a Fix finding action is active for that file | |
| Check | spec dir only | test runs allowed |
| Fix | files in the plan, test files, spec dir | other path: scope drift choice |
| any, until Check PASS or override | | Bash `git commit` denied |
| any | | Temper state paths and decision CLI calls guarded (3.3) |

Example reasons:

- "Temper: Plan phase. Writing src/app.ts is not allowed until the plan is approved.
  Next: finish plan.md and tasks.md, then ask the user to approve (key 1 or /temper approve)."
- "Temper: commit blocked, Check has not passed. Next: run the checks (key 1 in Check
  or /temper check)."

Bash coverage is best effort, but structural and conservative. The hard guarantee covers the
tool layer: Write, Edit, NotebookEdit and MultiEdit, and `git commit` through Bash. For Bash the
classifier splits the command into statements (quote, heredoc and substitution aware, heredoc
bodies left out), strips wrappers (`env`, `timeout`, `nice`, `ionice`, `nohup`, `time`, `xargs`,
`command`, `builtin`, `exec`, `sudo`, a path to `git` or `temper`, a shell given the script or a
`-c` string, and the eval builtin), and resolves shell variables statement by statement, left to right, in `export`,
`declare`, `local`, `readonly` and `typeset` forms and in env prefixes, to a fixed depth. Brace
expansion is expanded to a fixed cap, `..` segments are collapsed, `cd` is followed, and quotes and
backslashes are removed before a path is compared.

Every write capable construct in the command is then checked: redirects (including `>|` and
`&>`), `tee` (every target), `dd of=`, `cp`, `mv`, `install`, `ln`, `rsync`, `rm`, `truncate`,
`touch`, `sed -i` and `sed w`, the output file option (`-o`, `-O`) of a transfer tool, `tar -C`,
`find -delete` and `-exec`. The rules are:

- A target that resolves to a guarded file (events, `gates.json`, `status.json`, `overrides.json`,
  `build-state.json`) is refused.
- A folder that holds guarded files (`.temper`, `.temper/specs`, `.temper/specs/<slug>`, an events
  folder) cannot be removed or moved, and nothing can be copied or moved into it when a file that
  lands there would be guarded or cannot be named.
- A target that cannot be resolved (an unset variable, a command or process substitution, a glob
  that could match a guarded name, an expansion that is too large) is refused when the command
  names Temper state, or when the file name itself cannot be known. The deny says how to do it
  legitimately: spell the exact path, or use `scripts/temper gate`, `evidence` or `state`.
- An interpreter (`python`, `perl`, `ruby`, `node`) told a guarded path is refused.

Reading (`cat`, `grep`, `ls`, `jq`, `diff`, `head`, `tail`) is not flagged, and ordinary flows pass
(a heredoc into `$S/tasks.md` with `S=.temper/specs/x` in the same command, every
`scripts/temper gate`, `evidence` and `state get` call).

Limits, stated honestly. A variable set in an earlier call, in a profile or in the environment
cannot be seen. Bash can still write files in ways no classifier catches (an interpreter that builds
its path at run time, for one), and Bash writes to ordinary source files are not phase checked. MCP
file tools are not covered. The native `pre-commit` hook is the backstop. Button presses, the
reason field and menu picks carry no origin in their handlers, so their authenticity rests on the
platform.

One source of truth for the phase. The CLI state is the truth for where the run is. The mod derives the
phase of the bar and of every deny from `build-state.json` (`next_stage`: `cliPhase` in the pure core,
`reconcile` in the adapter). Events record who decided (decisions, timeline, invalidation) and are never the
source of the phase. When the mod's picture and the CLI differ, the CLI wins; if the person's last move is not
mirrored yet, the line "Temper state: the run is at <phase>. Your last choice is not recorded yet. Press 1 to
record it." shows and key 1 re-submits the mirror prompt for that same pending decision (no new event, single
use). A decision is spent after its call ran, judged by what the call changed, not by its exit status: when a call
ends in an error the mod compares the CLI's files (state, overrides, gates, evidence, loop counter) with the copy it
took before the call, and a changed copy means the decision was used (`state advance ...; exit 1`). A call that
failed and changed nothing gives the decision back. Fail open: an unknown `next_stage` blocks nothing and writes
nothing; a CLI that looks reset (earlier than checks that passed) does not block writes. A reload cannot go back; only
a person `back` that was mirrored can. A run that was in progress and whose `build-state.json` turns missing,
unreadable or corrupt (chmod 000, a delete, `git clean`) stays enforced from the last known state, with one line that
says so; it ends when the file reads again, when the person runs `/temper:temper enforcement off`, or on a reload.
A run that was Done and is archived is no run (`state archive` after the commit is the normal end).

Continue and the original On Continue steps. A button that moves the run forward records the person's decision
and runs `/temper:temper continue <stage>` through `$.command.run`. The orchestrator does the "On Continue"
steps of that stage as `commands/temper.md` writes them. Its `state advance` is the mirror, and the guard lets
it through once because the matching decision exists. The mod writes no mirror prompt for a move forward (back,
override and accept keep theirs). The mod's commit rule defers to `temper gate commit`: it allows a commit when
every gate the CLI checks passed or was overridden, when every staged file is under `.temper/specs/` (seen from
the `git add` calls of the session), or for a Build checkpoint (next stage build, command temper, the current
branch from `.git/HEAD` equals the run's branch, plan, intent and, when the spec has a `design.md`, design
satisfied, last build test row green). The artifact carve-out is for a plain `git commit` whose staged set the mod
fully understands: every other way into the index (`git stage`, `mv`, `rm`, `apply --cached`, `update-index`,
`checkout <tree> -- path`, `restore --staged`, `reset`, `stash`, `xargs git add`, `add -p|-i|-N|--pathspec-from-file`,
an alias or any subcommand the mod does not know) makes the staged set unknown, and a pathspec commit (`git commit
src/x.ts`), `-i`, `-o`, `merge`, `cherry-pick`, `am`, `pull`, `revert` and `commit-tree` never use it. `git add`
paths are read against `git -C` and the `cd` of the shell (carried from one Bash call to the next), and compared
with the CLI's case sensitive `^.temper/specs/`. The mod's picture of the index is the session's own: a file the
person staged before, or a script that stages, is not seen, and the CLI commit gate and the native `pre-commit` hook,
which read the real index, are the backstop. The project root is kept in `$.state` (key `root`) from the first
session start; when no run was found there, it is looked for again (walking up from the session folder) each time
the state is read, until a run is seen.

Third review (#39 to #48). While a run is active and enforcement is on, a Bash command is refused
when it names `temper` (a word, a path part, a glob, or a name inside a string, compared without
regard to case) and it is not a plain readable call, in these cases: the verb or subcommand of a Temper
call is built by `$'..'`, `${..}`, `$(..)` or an unresolved variable; the command uses a launcher
(`env -S`, `awk`, `make`, `find -exec`, `xargs`, `parallel`, `script`, `ksh`, `fish`, the eval and
exec builtins, `git -c alias`); the command writes a script file that names `temper` with a decision word, or runs a
file it wrote; it copies, links or sources the script; it feeds a shell the script's text or a
process substitution. Reading commands (`sed -n`, `awk '/x/'`, `nl`, `cat`, `head`, `tail`, `less`, `grep`, `rg`,
`wc`, `diff`, `pytest -k`, `git log --grep`) stay allowed. Every `state advance` and `state set
next_stage` call needs a matching human decision, or it must be the exact next stage of the run
(`STAGE_SEQ_TEMPER`, with design only for medium and complex runs) after a fresh PASS or an override
of the stage it completes. A person's Skip with a reason is the go-ahead for that stage: the `state advance`
that follows it passes with no second approval (also out of Intent and Plan) until a later step back.
`state init` is refused while a run is active; `state loop <from> <to>` is refused too, except for the
person's own Loop back: it passes while that person's back decision for `<to>` waits unspent (the `state set
next_stage` call that follows spends it). So a Loop back is a loop of the CLI: it keeps the budget
(`loops.max-per-type`) and clears the evidence of the stages that are redone. When the CLI prints BLOCKED the
budget is spent, the step is not recorded, and Skip with a reason or Save for later remain. Guarded file
names are compared without regard to case, and `ln` of Temper state or its folders is refused.
`git cherry-pick`, `merge`, `revert`, `am`, `commit-tree`, `rebase --continue`, a merging `pull` and
a `git -c alias` are treated as commits while the commit gate is open (`--abort`, `--quit`, `--skip`,
`--ff-only` and `push` are not); the native `pre-commit` hook is the backstop. A decision button takes a lock
before its first await, ignores a press for a phase that has already moved ("That step is already
done."), and ignores a second move within one second.

Fourth review (hardening, the mod's hardening tests). The stance does not change: the classifier is structural,
fail closed where that is cheap, best effort; the hard guarantees are the editing tool deny and the native
`pre-commit` hook. What was added, while a run is active:
(1) a shell, or a builtin that runs text as commands (such as `source`), that is given a program the text does not
show is refused: a pipe from anything but `echo`/`printf` (or `cat` of a heredoc), a file on stdin, a process
substitution, xargs handing what it reads to a shell as the program, a `-c` string
that is a substitution or an unset variable, and, for a program that is shown, any word split by quotes, `$`,
backticks, backslashes, braces or globs. Quote and backslash splits (`te""mper`, `ov\erride`) are removed before
the script name and the decision words are looked for. Shell setup idioms (what `pyenv init -` or a project setup
script prints) and the plain heredocs stay allowed. (2) A command that names a guarded file (`gates.json`, `status.json`,
`overrides.json`, `build-state.json`, `feedback-loops.json`, `.claude/temper.config`, `.temper/evidence/*.json`, an
events folder, `.git/hooks`, `.git/temper-gate`, `.git/temper-pre-commit`), or a glob that can stand for one (`.tem*/gates.js*`), must be a plain read (`cat`, `grep`,
`jq`, `head`, `tail`, `ls`, `stat`, `wc`, `diff`, `test`, `sed` without `-i`, `awk` whose program does not name it,
`find` without a delete, write or non reading `-exec`, `git diff|log|show|status|ls-files|blame|grep|cat-file`, the
Temper CLI) or it is refused: this closes `awk`, `sort -o`, `uniq in out`, `patch`, `find -fprintf`, `git
checkout|restore|apply`, `tar`, `unzip`, `ed`, `ex`, `cp -l`, `ln -s` and the rest of the writers by one rule instead of
a list. A write through `xargs` is refused when the command names a guarded file anywhere. `chmod`, `chown`,
`chflags`, `setfacl`, `chattr` and `xattr` on a guarded path, `find -delete` or a deleting `-exec` that can reach
`.temper` (a filter such as `-name '*.pyc'` or a start folder that cannot reach it excuse it), `git clean`
(except a dry run) and `git stash -u|-a` are refused. (3) The config, the evidence ledger files, the loop counter and
the git hooks and the Temper commit hook (`.git/temper-gate` and `.git/temper-pre-commit`; and `core.hooksPath`, `--no-verify`, `-n`) are guarded; `TEMPER_DIR` and `TEMPER_CONFIG` are refused.
The config and the hooks are guarded only while a run is active, so `/temper:init` and the hook installer still work.
(4) A decision a person made for a plan is stale once the run goes back to that stage or an earlier one; no
`state advance` lowers the stage the run is at; a skip is for the stage the run is at; `state loop` must leave the stage
the run is at and uses the back decision once. (5) A guard that throws refuses Bash while a run is active (every other tool
passes). The Bash classifier now skips shell comments, so a comment that names `.git/hooks` is no mention.

Known limits, on purpose (see the mod's known limits test). The classifier reads command text
only. It cannot see a link, a copy or a script made in an earlier call, a script already on disk and
run later with no name in the command, or a variable set earlier. It cannot see a program that builds the
script name or a guarded path at run time (a Python call that joins the name from two pieces), the names inside a patch or an
archive that is applied or extracted (`patch < x.diff`, `tar xf a.tar`), a staging made by a script or by the person
before the session, a git alias of the person for `commit`, or a `cd` made before the mod was loaded. MCP and PowerShell
file tools are not evaluated at all. Enforcement stays on from the last known state when `build-state.json` is hidden,
but a mod reload forgets it (a reload is the person's act). The marker line `Temper enforcement:
active` also appears in text files Claude can read, so an injected copy can only hide a question,
never advance a phase. At Done a model `git commit` is allowed because the run is complete and the
person pressed Continue. Bash can run shell tricks that a text reader cannot see, so the hard
guarantees are the edit tools and the native `pre-commit` hook. Future hardening: the CLI could check a
one time decision token itself, so a decision call would carry proof from the person. That is not built.

The CLI calls that matter are matched to the person's decision. A decision call that repeats
`--id`, `--stage` or `--reason` is refused, because the CLI reads the last one and the mod must not
read a different one. `state set next_stage` is allowed once for the stage of a person's `back`
decision and otherwise refused; `state set stage|branch|spec_path` is refused while a run is active;
`state set run_mode autonomous` is allowed only after the person approved the Plan in this run and
`autonomy.enabled: true` is set in `.claude/temper.config` (`run_mode interactive` is always allowed); `state clear` and `state archive` are refused
while a run is active and allowed after it is Done or when no run is active. `state set
regression_test|task` stay allowed; `state set complexity` only with a plain tier while the plan is open (a later
change would drop Design), `state set base_sha` only as a commit hash or `"$(git rev-parse HEAD)"` in Plan or Build,
and `state set command` never. In follow up prompts the reason is single quoted
with its quotes escaped, so nothing a person types is read as shell. The native `pre-commit` hook
stays as a second layer.

**Review and Check allow the whole spec directory.** In those phases a write to
`intent.md`, `plan.md` or `tasks.md` is allowed, so an approved intent or plan can be edited
without a back step. This is deliberate: Review and Check write evidence, findings and
notes into the spec directory, and a finer split would refuse legitimate work. Edits that
matter are visible in the diff, and `/temper back` is how a person invalidates later phases.
The events folder, `gates.json`, `status.json`, `overrides.json` and `build-state.json` stay
guarded in every phase.

### 3.5 Injection (Part A.2, A.3)

`prompt.compose` appends section `temper:phase`:

```
Temper enforcement: active
Phase: Build (task 3 of 7) · Intent: "Password reset by email"
Criteria: 2 of 5 passed (AC-01, AC-03)
Next: ...
```

With enforcement off it reads "Temper enforcement: off (UI only)". Skills and
commands (`commands/temper.md`, `skills/temper-core/SKILL.md`, each stage brief's
preamble) gain one rule: if the system prompt has no "Temper enforcement: active"
line, say once "Temper enforcement is off here (no mods support); continuing with
prompt based phases" and go on as today. (Since 9.6.5 the "off (UI only)" line gets
its own sentence, "Temper enforcement is off (turned off by the user)", because the mod
is loaded and still draws the bar.)

### 3.6 Commands

`/temper` already exists as the prompt based orchestrator. The adapter hooks
`command.run` for it and handles only reserved first words: `status`, `timeline`,
`back`, `override`, `approve`, `accept`, `drift`, `pause`, `resume`, `help`, `report`,
`pr`, `mode`, `enforcement`, `next`, `pane`. Anything else (a feature description)
passes to the existing command unchanged. Without mods, `commands/temper.md` handles
the same words in prose (calling the CLI).

**Needs your call:** you asked that bare `/temper` toggles the pane. Today bare
`/temper` resumes or starts a run. I propose: with mods, bare `/temper` toggles the
pane when a run is active and otherwise behaves as today; `/temper pane` always toggles.

### 3.7 Per phase actions and hotkeys

One flow, two views. The orchestrator (`commands/temper.md`) stays the driver of the stages and the CLI
stays the judge of the gates. The bar is the decision UI when the mod is active (the system prompt has
`Temper enforcement: active`); the orchestrator then does not ask its gate question a second time. Every
original option is reachable with the same words, in one digit or `0` and one digit.

Key 1 follows the check result the CLI wrote: Continue to {next} (check passed), Loop back to {upstream}
(check failed), else Start or Run the phase (the orchestrator runs the stage and its check). In Build a
failed check with open tasks is a checkpoint, so key 1 says Continue with task N. Key 4 is Discuss (the
original Other) in every phase. 9 is Skip with a reason (Override and continue). 0 is More: a numbered menu
(1 to 9, 0 goes back) that replaces the main buttons; digits only, because a letter would type into the
prompt box (checked live).

| Phase | 1 | 2 | 3 | 0 (More) shows |
|---|---|---|---|---|
| Intent | Start Intent, or Continue to Plan | Grill me | Teach me | Save for later |
| Plan | Run Plan, Loop back to Intent, or Continue to Build | Walk through step by step | Open HTML review | Grill me, Teach me, Share HTML review, Save for later |
| Build, checkpoint | Continue with task N | Change | Stop | Grill me, Teach me, Save for later |
| Build, completion | Continue to Review, or Loop back to Plan (failed) | Teach me | Grill me | Loop back to Plan, Save for later |
| Review | Run Review, Loop back to Build, or Continue to Check | Architecture depth review | Grill me | Teach me, Loop back to Build, Save for later |
| Check | Run Check | Review config suggestions (file exists), else Grill me | Teach me | Save for later (and Grill me when the file exists) |
| Fix | Fix the failures | Fix the findings | Continue to Check | at the limit: Loop back to Plan, Skip with a reason, Save for later on 1 to 3 |
| Done | Commit | Save for later | | |

Maintainer decision "Original only": a button is an option of the original `/temper` (`commands/temper.md`),
or Discuss, Play, Skip with a reason, Resume (when paused), and in the Fix phase Fix the failures, Fix the
findings and the per finding Fix, Accept and Explain. Everything else (show the files, run the tests, show
the changes, write the PR text, go back a phase, show the timeline) is typed; the subcommands stay.
`scripts/check-original-options.sh` keeps the original options in `commands/temper.md`, and the mod's own
action test refuses any other label. Where the original gives a choice only under a condition (Review config
suggestions needs the file, Loop back needs the loop budget, which the CLI keeps), the button follows the same
condition.

Every label says its result and every action has a one line description (10 words at most) in the
pane. The subcommand behind 9 is still `override` (no reason, no skip). A button that needs a stage to run
records the decision, submits the mirror prompt (the CLI call, which the guard matches to that decision),
and then runs `/temper:temper` with no arguments through `$.command.run` (`$.prompt.submit` refuses a text
that starts with a slash). That is the orchestrator's Resume: it launches the stage subagent with its own
stage brief. The mod writes no stage instructions of its own. Discuss (key 4) and Change (key 2 at
Build) put a draft in the prompt box with `$.prompt.fill`; the press changes no phase and writes no event.

### 3.8 Interaction modes

| Element | full | minimal | off |
|---|---|---|---|
| denials with reasons | yes | yes | yes |
| phase bar | phases and action buttons | phases only | no |
| pane, toasts, suggestions, hint, spinner text, turn line, styled questions | yes | no | no |
| `/temper` subcommands | yes | yes | yes |

`enforcement: on|off` is independent of the mode.

**Needs your call:** your text says minimal is "phase bar and denials only" and that
actions stay available as subcommands. I read that as no action buttons in minimal.
Confirm, or I keep the buttons.

First run: on the first `/temper` in an interactive session, `$.ui.ask` offers the
three modes, one line each. Dismissed: full, plus a toast "Change with /temper mode".
`$.store` records that it asked; never again unless `/temper mode` runs. In `claude -p`
nothing is asked.

### 3.8a The game (Temper Run)

An optional runner game for the time Claude works, in the spirit of the browser dinosaur game. It
adds no engine call. Two earlier versions (a flame runner, then a merge puzzle) were dropped after
trial: the first was not clear and not fun, the second was not what was wanted.

- The art file is data: the palette and every picture as a table of rows of palette letters
  (a letter is one pixel, a dot is none). Ember, the dragon, is 8 pixels wide and 8 tall (8
  columns by 4 rows) in five frames (run A and B, jump, duck 4 tall, dead). The obstacles are two
  iron anvils (6 by 4 and 8 by 6), a bucket of cold water (5 by 5) and a hammer (6 by 4) with two
  spin frames. The picture is 9 rows (8 of air and 1 of floor), 18 pixels tall. An earlier size, 12
  by 12, was too big. Each picture has a hit box
  one pixel in from the drawn pixels. Tests check equal row widths, defined letters, hit boxes inside
  the pictures, and the colours (3 to 1 or more against the wall, the glow and the floor, also after
  a change to 256 colours; two bright fills cannot reach 3 to 1, so the dragon and the obstacles
  differ in hue instead).
- The runner is pure and seeded: the jump arc (11 ticks of 80 ms in the air, 8 pixels high; speeds 1.2 to 1.9 pixels a tick),
  the input buffer (a jump pressed up to 3 ticks, 240 ms, before the landing fires on the landing),
  the duck (10 ticks, 0.8 s, cancelled by a jump), the boxes, the score (3 points for 4 pixels) and
  the best score, heat 1 to 5 (every 400 points), the milestone at every 100 points (a yellow flash
  of 6 ticks and a banner), and the picture as pixels and then as half block cells.
- Fairness is code and tests, not a feeling. The generator picks only an obstacle that can be
  cleared at the current speed with a window of 3 ticks or more (found by running the rules, not by a
  table), keeps a minimum gap by what each obstacle needs (jump after jump 16 ticks, a jump and a
  duck 18), starts the first obstacle 2.5 seconds after the run began, and keeps hammers for after
  100 points. A property test runs thousands of seeds at every speed and checks every gap, and a bot
  that looks, presses and then waits 0, 2 or 3 ticks (up to 240 ms) survives 900 ticks in all of them.
- The hooks module keeps only the counters of the pane Buttons in `$.state` key `game` (jumpCount,
  duckCount, startCount): a press is one write, and the clock writes nothing. The game client
  is a Client module (a surface module): it runs the frame clock (80 ms), compares the counters with
  the values it saw last and applies each new press once, and draws. After one click it also takes
  Space and the Up arrow (jump) and the Down arrow (duck) directly through `onKey`. It has no `$`
  call at all: `$` is not defined in a surface module, so the type check (`tsc -p tsconfig.mod.json`,
  run in CI) fails on an engine call written as `$.` there. The hooks module imports it statically, and the
  pane names its module path as fixed text. It posts the score once for each game over, and the `ui.message`
  hook keeps the best score with the existing `$.store.set`. The game added no call to the reviewed list.
- Measured on the terminal (tmux, 160 columns, real Claude Code 2.1.288): from `tmux send-keys` to
  Ember leaving the floor on the screen, 14 trials, median 40 ms, from 35 to 53 ms. That includes the
  send and the screen capture, so the delay of the Button route is under half a tick of 80 ms. A bot
  played from the screen through the Buttons (jump and duck from what it saw) for 170 seconds, to
  heat 5, with no game over.
- In a narrow terminal the pane sits inline and shows about 14 lines. The whole picture (9 rows), the
  heads up line, the help line and the Buttons are 13 lines, so everything fits; the Client leaves
  out only the Temper line there. The big anvil needs a window of 3 ticks, so it appears only from
  about heat 3 (at the start speed its window is 1 tick).
- A test hook: the plugin option `gameSeed` (a number) fixes the seed, so a test knows the run. It is
  not in `plugin.json` and has no effect unless it is set.
- The pane asks for the keyboard with `focus` and for Esc to close it with `closeOnEscape`. The
  surface may or may not grant the keys, and the mod cannot read which (`ui.panes` reported an
  unfocused pane while the keys did reach the game, so it is not used). The toast is always the
  same: "The game is open. Press r to run, w to jump, s to duck, q or Esc to leave."
  The Client finds out by itself: with no key, click or press within 3 seconds of opening, it draws
  one dim line, "No keys yet? Press Ctrl+X, then Tab, to give the game the keys." Any key
  or press removes the line. That Ctrl+X, Tab path is in the API text; it is not verified live.
- The pane is `temper-game`. The Client exists on the terminal and the desktop app only, so the
  hook checks `e.surface` and draws a short text elsewhere.
- The offer: while Claude works, the band draws `8: Play while you wait` as a normal secondary
  button, the pane lists it in Actions, and the terminal hint starts with "Press 8 to play while you
  wait." (the hint is cut at the row end, so the offer comes first). The pane learns that Claude
  works from the band and hint props, and redraws once when that changes. The setting `game` is
  `on` (offers and command), `command` (command only) or `off`, checked in the pure core's config reader. It
  takes a digit because only a digit works from an empty prompt. `/temper:temper play` is the 17th
  reserved word. Only a person can open the game: a call that does not come from the composer
  gets a refusal.
- The game cannot weaken a gate. Refusals are decided in `tool.call` and do not read game state.
- What is not verified: the game was checked live on the terminal only. Keys reach the Buttons
  while the pane holds the keyboard. It does after `/temper:temper play` with an empty prompt, and
  after a click on the Play button. A key reaches the Client itself only after a click.

### 3.9 Layout in the repo

- The plugin's hooks file gains one `modules` entry, which names the hooks module.
- The hooks module (the adapter) holds the wiring only.
- The pure core holds the rules (3.2).
- The drawing files hold the band, pane, hint, spinner and question header.
- The `$.state` contract is a type file that `plugin.json` names in `types`.
- The mod's test suite runs under `claude plugin test`.

`plugin.json` gains `userConfig` (`uiMode`, `enforcement`, `fixMaxLoops`,
`prAttribution`, `phaseModels`, `reviewerModel`; plain types, no `options`) and
`types`. Version 9.5.0 (minor: additive, nothing breaks).

---

## 4. Feasibility of each requested item

**Feasible as described:** tool level denies with next step reasons; override with
required reason; phase invalidation; criteria checklist; phase bar with digit hotkeys;
pane docked or inline; toasts; `prompt.suggest`; turn line; first run question; live
mode switch with admin lock message; report; PR attribution line; optional `turn.step`
and `agent.spawn` features; `claude plugin test` coverage of every listed area;
`claude plugin validate --strict`; old versions keep working.

**Feasible, but differently than described:**

1. Injection uses `prompt.compose`, not `prompt.section` or `prompt.context` (2.3).
2. Spinner progress rewrites the spinner word; there is no progress field.
3. `PromptHint` shows on the terminal only; desktop gets the hint through the band.
4. "Styled questions" add a header above the native dialog; the dialog itself stays
   the engine's.
5. `userConfig` values arrive at load; live change works through a module reload.
6. Bash enforcement is best effort (3.4).
7. Test, lint and typecheck commands, the fix loop limit, finding acceptance, intent
   lint additions and live criteria status need CLI additions first (section 1 table).
8. "Clarifying questions answered with one press" is the native dialog's behavior;
   Temper asks Claude to use `AskUserQuestion` in Intent.

**Not feasible by me in this container:**

1. Manual verification in the desktop app, and the desktop screenshot: no desktop app
   here. I will write exact steps; you run them.
2. The 60 to 90 second walkthrough video: I write `docs/demo-script.md`; you record.
3. Real sec-default coexistence without your OK on managed settings (2.6).
4. Verifying the embedded video plays on GitHub: needs an upload through the GitHub
   web editor (it hosts the file at `github.com/user-attachments/...` and renders a
   player). A repo relative `.mp4` link does not play inline. I will verify the
   method on an existing public README before recommending it, and you do the upload.

**Feasible with effort and retries:** the hero GIF, recorded in this container. A recording
works here, but each take costs tokens and output varies. The `.tape` file is committed;
nothing runs in CI. Light and dark terminal screenshots come from VHS themes.

---

## 5. Test plan

- `claude plugin test` (no sign in, no network), in the mod's test suite:
  state machine transitions and invalidation; every deny rule per phase and tool;
  forgery guard; human only decisions (origin checks); override with and without
  reason; accept finding; each drift choice; fix loop limit; mode switching including a
  locked row; criteria parsing against `templates/intent.md` and the eval fixtures;
  report output; UI mounted on `terminal` and `desktop` (and a smoke on `vscode`,
  `mobile`); composition with a simulated prepend tier guard; version guard inertness.
- `bash scripts/selftest/test-temper.sh` cases for each CLI addition.
- CI (`quality.yml`) runs `claude plugin test` and `claude plugin validate --strict` on Claude
  Code 2.1.287 and asserts the `calls:` line. No sign in needed.
- Manual matrix: terminal at 80, 120 and 160 columns, fullscreen and main screen;
  desktop; `claude -p`; 2.1.200 and 2.1.259 (plugin loads, prompt based phases work);
  `/compact` keeps the section.

## 6. Test on your laptop before merge and release

The steps are the checklist in [Testing the mod](mods-testing.md), ticked by hand before
merge and release. After that, release with the existing `release-bump.yml` and
`release.yml` workflows.

## 7. Delivery

**Needs your call:** this is large. I propose four pull requests in this order, each
green on its own:

1. CLI additions (section 1 table) plus the marker rule in skills and commands.
2. Pure module, enforcement (Part A), commands, report, tests.
3. UI and modes (Parts B and C).
4. README, demo fixture under `demo/`, `.tape`, GIF, screenshots, demo script.

Or one pull request with all of it, as your Deliverables list implies.

## 8. Decisions needed from you

1. Approve this plan (or list changes).
2. Real sec-default test: may I write managed settings in this container? (2.6)
3. Bare `/temper` behavior with mods (3.6).
4. Minimal mode: phase bar with or without action buttons (3.8).
5. Four pull requests or one (7).
