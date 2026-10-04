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
- Each stage's contract lives in `agents/{stage}.md` and `reference/{stage}.md`.
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

- Plugin `hooks/hooks.json` binds two classic hooks: `UserPromptSubmit` →
  `stage-marker.sh` and `Stop` → `verify-stage-gate.sh` (refuses to end a standalone
  stage session until a verdict exists; fails open after two blocks).
- Opt in pack `packs/hooks/settings.hooks.json` adds `PreToolUse` guards for secrets,
  protected paths, the regression test, and `block-uncommitted-gate.sh` (runs
  `temper gate commit` before a Bash `git commit`).
- `scripts/hooks/install.sh` writes a native git `pre-commit` hook that runs
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
loaded a probe mod with `claude -p --plugin-dir`. The generated file matches the one
the plugin authoring skill ships, except that built in tool inputs moved to a separate
`claude-code-tools/index.d.ts`.

### 2.1 Probe results (run in this container)

Probe: a plugin with a classic `UserPromptSubmit` hook and a module that denies every
`Write`, in one `hooks/hooks.json`.

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

1. A `modules` key in Temper's existing `hooks/hooks.json` is safe on old versions.
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
| `agent.spawn` reviewer model | returns `{ model }`; can rewrite it | optional: rewrite the model for the `temper:review` agent |

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
- `allowManagedHooksOnly`: also blocks user classic hooks, so Temper's
  `hooks/hooks.json` entries stop too unless the plugin is force enabled.
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
nothing else (20 calls; the list is enforced by `scripts/check-mod-calls.sh`):

`config.list, config.set, fs.list, fs.read, fs.stat, fs.write, prompt.submit,
prompt.suggest, session.version, state.get, state.set, store.get, store.set, ui.ask,
ui.close, ui.focus, ui.invalidate, ui.open, ui.resolve, ui.toast`

Why each call is there:

| Call | Reason |
|---|---|
| `config.list`, `config.set` | `/temper mode` and `/temper enforcement` read the row (locked by an administrator or not) and change it the way `/config` does |
| `fs.list`, `fs.read` | rebuild the run from `.temper/` files and the spec's events |
| `fs.stat` | resolve `.` to the project root so absolute tool paths can be made relative |
| `fs.write` | the one write: event files and `.temper/report.md` |
| `prompt.submit` | a pressed Button sends its action to Claude (never from a hook) |
| `prompt.suggest` | the next action as a Tab suggestion after a turn |
| `session.version` | the version guard |
| `state.get`, `state.set` | the run view and live mode that the drawing hooks read |
| `store.get`, `store.set` | own event ids, consumed human decisions, "mode already asked" |
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

Commit is not a phase: after Check passes, the state is Done and `git commit` is allowed.

### 3.2 Pure module (`hooks/temper-mod/core/`, no `claude-code` import)

- `machine.ts`: event sourced. `reduce(events) → RunState` and
  `decide(state, command) → { events } | { error }`. Commands: `approve`, `advance`,
  `back(to, reason)`, `override(phase, reason)`, `acceptFinding(id, reason)`,
  `drift(path, choice, reason)`, `checkResult(pass|fail)`, `pause`, `resume`.
  Rules: forward only one phase at a time and only on a PASS verdict or an override;
  `back` marks every later phase invalidated; an invalidated phase needs a fresh verdict
  (newer timestamp than the invalidation); Check FAIL enters Fix and counts a loop; at
  `fix.max-loops` the only legal commands are re-plan (`back` to Plan), override, or
  hand over (pause).
- `rules.ts`: `evaluate(state, toolCall) → allow | deny(reason)`. Every reason ends
  with what to do next (examples in 3.4).
- `criteria.ts`: parses `AC-NN` criteria from `intent.md` using the same patterns as
  `acceptance.py`, and merges per criterion status from `.temper/status.json`.
- `planfiles.ts`: reads the allowed file list from `plan.md` tables and `tasks.md`.
- `bash.ts`: classifies a Bash command (git commit, temper CLI decisions, writes into
  protected Temper paths).
- `report.ts`: renders `.temper/report.md` from `RunState`.
- `config.ts`: reads the few keys the mod needs from `.claude/temper.config`.

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
`command`, `builtin`, `exec`, `sudo`, a path to `git` or `temper`, `bash scripts/temper`, `sh -c`,
`eval`), and resolves shell variables statement by statement, left to right, in `export`,
`declare`, `local`, `readonly` and `typeset` forms and in env prefixes, to a fixed depth. Brace
expansion is expanded to a fixed cap, `..` segments are collapsed, `cd` is followed, and quotes and
backslashes are removed before a path is compared.

Every write capable construct in the command is then checked: redirects (including `>|` and
`&>`), `tee` (every target), `dd of=`, `cp`, `mv`, `install`, `ln`, `rsync`, `rm`, `truncate`,
`touch`, `sed -i` and `sed w`, `curl -o`, `wget -O`, `tar -C`, `find -delete` and `-exec`. The
rules are:

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

The CLI calls that matter are matched to the person's decision. A decision call that repeats
`--id`, `--stage` or `--reason` is refused, because the CLI reads the last one and the mod must not
read a different one. `state set next_stage` is allowed once for the stage of a person's `back`
decision and otherwise refused; `state set stage|branch|spec_path` is refused while a run is active;
`state set run_mode autonomous` is allowed only after the person approved the Plan in this run and
`autonomy.enabled: true` is set in `.claude/temper.config` (`run_mode interactive` is always allowed); `state clear` and `state archive` are refused
while a run is active and allowed after it is Done or when no run is active. `state set
complexity|base_sha|regression_test` stay allowed. In follow up prompts the reason is single quoted
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
prompt based phases" and go on as today.

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

Key 1 is the main action and changes when the phase is ready to move on.

| Phase | 1 | 2 | 3 | 0 shows also |
|---|---|---|---|---|
| Intent | Approve intent (when the gate passes), else Check intent | Ask questions | Edit intent | Capture intent |
| Plan | Approve plan (when the plan gate passes), else Write plan | Show files the plan touches | Propose an alternative | Split tasks, Back to Intent |
| Build | Next task, or Send to Review when tasks are done | Run tests | Show diff | Pause |
| Review | Start review, or Fix all when findings exist | Review again | Show diff | per finding Fix, Accept, Explain (in the pane) |
| Check | Run checks, or Mark done when all pass | Rerun failed only | Failures by criterion | |
| Fix | Fix failures | Fix findings | Back to Check | at the loop limit: Plan again, Override, Take over |

9 is override everywhere (asks for a reason; no reason, no override). Global actions
are subcommands and pane buttons. Every action that runs something submits a prompt
to Claude; none submit on their own.

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

An optional runner game for the time Claude works. It adds no engine call.

- `core/game.ts` is pure: a seeded generator, the physics, the score, the heat level and the
  drawing rows. The same seed and the same keys give the same game, so the tests need no clock.
  The art is data: a flame of three flicker frames (3 by 3), a taller jump frame and a spark;
  two anvils and two cold obstacles. Every row of a sprite has the same width, and a test checks
  that the hit box lies inside the sprites. The field is 36 to 60 cells wide (it follows the
  region) and 10 rows tall. The height is fixed on purpose: a region sized by its content would
  feed the height back into the game.
- `ui/game-client.tsx` is a Client module (a surface module). It draws with Box and Text, reads
  keys with `onKey`, and moves the game on `surface.every`. It has no `$` call at all, and
  `scripts/check-mod-calls.sh` fails if one appears in any `*-client.tsx` file.
- The best score reaches the store through the existing path: the Client posts the score with
  `surface.post`, and the `ui.message` hook in `register.tsx` validates it and calls the
  already reviewed `$.store.set`. The Buttons of the game pane (w Jump, s Start or Again, q Quit)
  add one to a counter in `$.state` (`game`); the pane passes the counters to the Client as props,
  and the Client applies each new press once. No call is new: the reviewed list stays at 20.
- The pane asks for the keyboard with `focus` and for Esc to close it with `closeOnEscape`. The
  surface may or may not grant the keys, and the mod cannot read which (`ui.panes` reported an
  unfocused pane while the keys did reach the game, so it is not used). The toast is always the
  same: "The game is open. Press s to start, w to jump, q or Esc to leave." The Client finds out
  by itself: with no key, click or press within 3 seconds of opening and the game not started, it
  draws one dim line, "No keys yet? Press Ctrl+X, then Tab, to give the game the keys." Any key
  or press removes the line. That Ctrl+X, Tab path is in the API text; it is not verified live.
- The pane is `temper-game`. The Client exists on the terminal and the desktop app only, so the
  hook checks `e.surface` and draws a short text elsewhere.
- The offer: while Claude works, the band draws `8: Play while you wait` as a normal secondary
  button, the pane lists it in Actions, and the terminal hint starts with "Press 8 to play while you
  wait." (the hint is cut at the row end, so the offer comes first). The pane learns that Claude
  works from the band and hint props, and redraws once when that changes. The setting `game` is
  `on` (offers and command), `command` (command only) or `off`, checked in `core/config.ts`. It
  takes a digit because only a digit works from an empty prompt. `/temper:temper play` is the 17th
  reserved word. Only a person can open the game: a call that does not come from the composer
  gets a refusal.
- The game cannot weaken a gate. Refusals are decided in `tool.call` and do not read game state.
- What is not verified: the game was checked live on the terminal only. Keys reach the Buttons
  while the pane holds the keyboard. It does after `/temper:temper play` with an empty prompt, and
  after a click on the Play button. A key reaches the Client itself only after a click.

### 3.9 Layout in the repo

```
hooks/hooks.json             + "modules": ["./temper-mod/register.tsx"]
hooks/temper-mod/register.tsx   adapter: wiring only
hooks/temper-mod/core/*.ts      pure module (3.2)
hooks/temper-mod/ui/*.tsx       band, pane, hint, spinner, question header
types/index.d.ts             $.state contract (named in plugin.json "types")
tests/mod/*.test.ts(x)       claude plugin test
```

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

**Feasible with effort and retries:** the hero GIF. VHS is not installed, but Go and
ffmpeg are, so I can build VHS and ttyd here. Claude is signed in here, so a recording
works, but each take costs tokens and output varies. The `.tape` file is committed;
nothing runs in CI. Light and dark terminal screenshots come from VHS themes.

---

## 5. Test plan

- `claude plugin test` (no sign in, no network), in `tests/mod/`:
  state machine transitions and invalidation; every deny rule per phase and tool;
  forgery guard; human only decisions (origin checks); override with and without
  reason; accept finding; each drift choice; fix loop limit; mode switching including a
  locked row; criteria parsing against `templates/intent.md` and the eval fixtures;
  report output; UI mounted on `terminal` and `desktop` (and a smoke on `vscode`,
  `mobile`); composition with a simulated prepend tier guard; version guard inertness.
- `bash scripts/tests/test-temper.sh` cases for each CLI addition.
- CI (`quality.yml`): install Claude Code 2.1.287 with npm, run `claude plugin test`
  and `claude plugin validate --strict`, assert the `calls:` line. No sign in needed.
- Manual matrix: terminal at 80, 120 and 160 columns, fullscreen and main screen;
  desktop; `claude -p`; 2.1.200 and 2.1.259 (plugin loads, prompt based phases work);
  `/compact` keeps the section.

## 6. Test on your laptop before merge and release

Nothing is released from this branch until you have run it in your own terminal.
Deliverable: `docs/mods-testing.md`, a checklist you tick by hand. The steps:

1. Claude Code 2.1.287 or later: `claude --version`, then `claude update` if older.
2. Get the branch: `git fetch origin ccr-ea3cb3cc-wsa4sb && git checkout ccr-ea3cb3cc-wsa4sb`
   in your Temper clone (or a fresh clone).
3. If you have Temper installed from the marketplace, turn that copy off for the test
   so only one Temper runs: `claude plugin disable temper@<marketplace>` (the id is
   shown by `/plugin`). Turn it back on afterwards with `claude plugin enable`.
4. Run the automated checks from the clone: `claude plugin validate --strict .` and
   `claude plugin test .` (no sign in needed), plus `bash scripts/tests/test-temper.sh`.
5. Open the demo project with the branch loaded for that session only:
   `cd <clone>/demo/<fixture> && claude --plugin-dir <clone>`. The folder is watched,
   so a `git pull` of the branch reloads the mod without restarting.
6. Walk the checklist: each phase's denials and hotkeys; `/temper mode full`, `minimal`,
   `off`; `/compact` keeps "Temper enforcement: active"; a narrow (80 columns) and a
   wide (160 columns, fullscreen) terminal; light and dark themes.
7. Old version check without touching your installed CLI:
   `npx @anthropic-ai/claude-code@2.1.259 -p --plugin-dir <clone> "/temper status"`
   should answer through the prompt based path with no load error.
8. Your installed Temper is untouched by all of this: `--plugin-dir` lasts one session
   and writes nothing to your settings, except the mode you pick with `/temper mode`,
   which is stored in your user settings under `pluginConfigs`. The checklist ends with
   how to clear it.

After you tick the checklist: merge, then release with the existing
`release-bump.yml` and `release.yml` workflows as today.

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
