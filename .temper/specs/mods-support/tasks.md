# Tasks: Claude Code mods support for Temper

Build order (agreed): CLI additions with `test-temper.sh` cases → pure core (TDD with
`claude plugin test`) → enforcement adapter → UI and modes → optional AC-15 →
docs / README / demo → version 9.5.0 and CHANGELOG. One PR, opened only after the
maintainer ticks `docs/mods-testing.md`.

## Prerequisites

- [x] Read `docs/mods-plan.md` sections 2 to 7 (the approved design)
- [x] Read `.temper/specs/mods-support/intent.md` Scenarios and `plan.md`
- [x] `claude --version` ≥ 2.1.287 (2.1.288 installed)

## Tasks

### Task 0: Generate the mods types for this build [SEQUENTIAL]

**Action:** CREATE (generated, gitignored)
**File:** `.claude-plugin/types/claude-code/index.d.ts`, `.gitignore`
**Traced to:** Infrastructure: required by hooks/temper-mod/register.tsx and tests/mod (event and prop names)
**Test:** none (generated)
**Validate:** `test -f .claude-plugin/types/claude-code/index.d.ts && grep -q "prompt.compose" .claude-plugin/types/claude-code/index.d.ts`
**Notes:** Load a minimal module with `claude -p --plugin-dir .` per mods-plan 2.1 / docs "Get the types for your build". Add `.claude-plugin/types/` to `.gitignore`. Check every event/prop name used later against this file.

### Task 1: Config keys `check.commands.*` and `fix.max-loops` [SEQUENTIAL: after Task 0]

**Action:** MODIFY
**File:** `scripts/temper`, `templates/temper.config.default`, `reference/check.md`, `reference/fix.md`
**Traced to:** Scenario: "Check uses configured commands and the fix loop limit comes from config", "The fix loop stops at the configured limit"
**Test:** `scripts/tests/test-temper.sh`
**Validate:** `bash scripts/tests/test-temper.sh 2>&1 | tail -1`
**Notes:** `temper config get fix.max-loops` defaults to 3. `temper state loop check fix|build` uses `fix.max-loops` only when the key is set; `loops.max-per-type` unchanged otherwise (Decision 5). Existing loop tests must stay green.

### Task 2: `temper evidence accept` [SEQUENTIAL: after Task 1]

**Action:** MODIFY
**File:** `scripts/temper`, `scripts/tests/test-temper.sh`, `reference/review.md`
**Traced to:** Scenario: "temper evidence accept stops the review gate counting a finding"
**Test:** `scripts/tests/test-temper.sh`
**Validate:** `bash scripts/tests/test-temper.sh 2>&1 | tail -1`
**Notes:** Mirror `cmd_evidence_resolve` (scripts/temper:640). Store `accepted: {reason, author, ts}`. Empty `--reason` exits 1 and writes nothing. Counters at scripts/temper:849-869 and `_ev_claims` 1362-1372 skip accepted like resolved; `evidence list` prints `[accepted: …]`; gate_review detail names accepted count.

### Task 3: `gate_intent` out-of-scope and resolved-questions checks [SEQUENTIAL: after Task 2]

**Action:** MODIFY
**File:** `scripts/temper`, `scripts/tests/test-temper.sh`
**Traced to:** Scenario: "Intent gate requires an out-of-scope line and resolved questions"
**Test:** `scripts/tests/test-temper.sh`
**Validate:** `bash scripts/tests/test-temper.sh 2>&1 | tail -1 && scripts/temper gate intent --spec-path .temper/specs/mods-support`
**Notes:** New `_req` rows "out of scope stated" (a `- Out of scope:` bullet with non-placeholder text) and "open questions resolved" (accepted/completed intent carries no `Blocking` question; `none` passes). Update `setup()` and `good_draft()` fixtures with an `Out of scope:` line. Note the verdict change in CHANGELOG.

### Task 4: `temper status --json` and `.temper/status.json` [SEQUENTIAL: after Task 3]

**Action:** MODIFY
**File:** `scripts/temper`, `scripts/acceptance.py`, `scripts/tests/test-temper.sh`, `reference/status.md`, `commands/status.md`
**Traced to:** Scenario: "temper status --json writes per-criterion status after each gate"
**Test:** `scripts/tests/test-temper.sh`
**Validate:** `bash scripts/tests/test-temper.sh 2>&1 | tail -1`
**Notes:** `acceptance.py status <intent> <evidence-dir>` reuses `parse_criteria` + `supported_pass`; output `{criteria:[{id, priority, status: passed|open, evidence}], ts}`. `cmd_gate` writes it after `_gate_write_verdict` when intent.md exists; failure to write never changes the verdict (fail open). Add `status` to `main()` dispatch and `--help`.

### Task 5: Manifest, hooks.json, types contract, validator [SEQUENTIAL: after Task 4]

**Action:** MODIFY / CREATE
**File:** `.claude-plugin/plugin.json`, `hooks/hooks.json`, `types/index.d.ts`, `scripts/validate-plugin.sh`
**Traced to:** Scenario: "Old Claude Code versions load the plugin as today"
**Test:** `scripts/validate-plugin.sh`
**Validate:** `bash scripts/validate-plugin.sh && claude plugin validate --strict .`
**Notes:** `userConfig` uiMode (default "full"), enforcement ("on"), fixMaxLoops ("3"), prAttribution ("on"), phaseModels (""), reviewerModel ("") — plain strings, NO `options`. Add `"types": "./types/index.d.ts"`. `"modules": ["./temper-mod/register.tsx"]` beside the unchanged `hooks`. Validator: module paths exist; no userConfig field has `options`. Start register.tsx as a pass-through stub so validate passes.

### Task 6: Event codec and phase machine (TDD) [SEQUENTIAL: after Task 5]

**Action:** CREATE
**File:** `hooks/temper-mod/core/events.ts`, `hooks/temper-mod/core/machine.ts`
**Traced to:** Scenario: "Going back to Plan invalidates every later phase", "Skipping forward over an invalidated phase is refused", "A torn event file is skipped and reported", "The fix loop stops at the configured limit", "Override with a reason skips one phase and is reported"
**Test:** `tests/mod/events.test.ts`, `tests/mod/machine.test.ts`
**Validate:** `claude plugin test .`
**Notes:** Write tests first. `reduce(events, verdicts) → RunState`, `decide(state, command) → {events}|{error}`. Event name `{ts}-{session}-{seq}.json`. Override needs non-empty reason. No `claude-code` import in core/.

### Task 7: Deny rules and Bash classifier (TDD) [PARALLEL: with Task 8]

**Action:** CREATE
**File:** `hooks/temper-mod/core/rules.ts`, `hooks/temper-mod/core/bash.ts`
**Traced to:** Scenario: "Each phase allows exactly its own paths for Write, Edit and NotebookEdit", "git commit is refused until Check passes, then allowed", "Claude cannot forge an approval"
**Test:** `tests/mod/rules.test.ts`, `tests/mod/bash.test.ts`
**Validate:** `claude plugin test .`
**Notes:** Table-driven over 6 phases × 3 tools × allowed/disallowed. Every deny reason ends with "Next: …". Bash: `git commit` (incl. `&&` chains, `git -c … commit`), `temper override|evidence accept|state advance` decision calls, any write naming events dir / gates.json / status.json / overrides.json.

### Task 8: Criteria, plan files, config readers (TDD) [PARALLEL: with Task 7]

**Action:** CREATE
**File:** `hooks/temper-mod/core/criteria.ts`, `hooks/temper-mod/core/planfiles.ts`, `hooks/temper-mod/core/config.ts`, `tests/mod/fixtures/`
**Traced to:** Scenario: "Every request carries the Temper section and it survives compaction", "Scope drift offers three choices and logs each decision", "The fix loop stops at the configured limit"
**Test:** `tests/mod/criteria.test.ts`, `tests/mod/planfiles.test.ts`
**Validate:** `claude plugin test .`
**Notes:** Criteria regexes copied from `scripts/acceptance.py` (`^(AC-\d+)\s*\[(required|optional)\]:`); test against `templates/intent.md` and this spec's intent.md. Plan files from `### Files to Create` / `### Files to Modify` tables plus `**File:**` lines in tasks.md.

### Task 9: Section text, report, actions and modes tables (TDD) [SEQUENTIAL: after Task 7, Task 8]

**Action:** CREATE
**File:** `hooks/temper-mod/core/section.ts`, `hooks/temper-mod/core/report.ts`, `hooks/temper-mod/core/actions.ts`, `hooks/temper-mod/core/modes.ts`
**Traced to:** Scenario: "Every request carries the Temper section and it survives compaction", "Completion writes the audit report", "Full mode draws every Temper element on terminal and desktop", "Minimal mode shows phases only and off mode draws nothing"
**Test:** `tests/mod/report.test.ts` (section/actions/modes covered by compose and ui tests)
**Validate:** `claude plugin test .`
**Notes:** Section lines exactly as mods-plan 3.5; "Temper enforcement: off (UI only)" when enforcement off. Report sections: Phases, Overrides, Accepted findings, Scope drift, Criteria.

### Task 10: Enforcement adapter [SEQUENTIAL: after Task 9]

**Action:** MODIFY
**File:** `hooks/temper-mod/register.tsx`
**Traced to:** Scenario: "Plan phase refuses a source write with the next action", "Subagent tool calls are held to the same phase rules", "Claude cannot forge an approval", "git commit is refused until Check passes, then allowed", "Every request carries the Temper section and it survives compaction", "State comes back after /clear from the event files", "On an unsupported Claude Code version the mod stays inert", "Temper's denials compose with a prepended managed guard", "Completion writes the audit report"
**Test:** `tests/mod/enforcement.test.ts`, `tests/mod/compose.test.ts`, `tests/mod/version.test.ts`, `tests/mod/composition.test.ts`
**Validate:** `claude plugin test . && claude plugin validate --strict .`
**Notes:** Version guard via `$.session.version()` (< 2.1.287 or reject → inert). Rebuild on `session.start` and `classic.SessionStart`. Own-event ids in `$.store`; foreign events "unverified". Every hook has `.catch` → pass through. Write `.temper/report.md` on Done.

### Task 11: `/temper` reserved subcommands and scope drift [SEQUENTIAL: after Task 10]

**Action:** MODIFY
**File:** `hooks/temper-mod/register.tsx`
**Traced to:** Scenario: "Override with a reason skips one phase and is reported", "Override without a reason is refused", "Scope drift offers three choices and logs each decision", "A feature description after /temper still reaches the prompt-based orchestrator"
**Test:** `tests/mod/commands.test.ts`, `tests/mod/drift.test.ts`
**Validate:** `claude plugin test .`
**Notes:** Reserved first words: status, timeline, back, override, approve, accept, drift, pause, resume, help, report, pr, mode, enforcement, next, pane. Decisions only from person origin. Anything else → `next(e)`. Bare `/temper` toggles pane only while a run is active. `attribution.text` kind `pr` adds one Temper line when prAttribution is on.

### Task 12: Marker rule in prompts [SEQUENTIAL: after Task 11]

**Action:** MODIFY
**File:** `commands/temper.md`, `skills/temper-core/SKILL.md`, `agents/intent.md`, `agents/plan.md`, `agents/design.md`, `agents/build.md`, `agents/review.md`, `agents/check.md`, `agents/rca.md`, `agents/fix.md`
**Traced to:** Scenario: "Without the marker the skills announce prompt-based phases"
**Test:** `scripts/validate-panels.py`, `scripts/quality-check.sh`
**Validate:** `python3 scripts/validate-panels.py && bash scripts/quality-check.sh`
**Notes:** One rule, outside every return panel. `commands/temper.md` also handles the reserved subcommands in prose via the CLI when mods are absent — no per-stage logic added there (repo rule).

### Task 13: Band and pane [SEQUENTIAL: after Task 12]

**Action:** CREATE
**File:** `hooks/temper-mod/ui/band.tsx`, `hooks/temper-mod/ui/pane.tsx`
**Traced to:** Scenario: "Full mode draws every Temper element on terminal and desktop", "Minimal mode shows phases only and off mode draws nothing", "Scope drift offers three choices and logs each decision"
**Test:** `tests/mod/ui.test.tsx`
**Validate:** `claude plugin test .`
**Notes:** Only Box, Text, Button, Markdown. Hotkeys 1, 2, 3, 9, 0 from actions.ts; 9 asks a reason. Pane auto-opens only where it would dock.

### Task 14: Hint, spinner, question header, turn line, toasts, suggestions [SEQUENTIAL: after Task 13]

**Action:** CREATE
**File:** `hooks/temper-mod/ui/hint.tsx`, `hooks/temper-mod/ui/spinner.tsx`, `hooks/temper-mod/ui/question.tsx`, `hooks/temper-mod/register.tsx`
**Traced to:** Scenario: "Full mode draws every Temper element on terminal and desktop"
**Test:** `tests/mod/ui.test.tsx`
**Validate:** `claude plugin test .`
**Notes:** Hint: terminal `tail`, desktop pass-through. Spinner word "Building · criterion 2 of 5". One toast per transition. `prompt.suggest` never submits.

### Task 15: Modes, live switch, admin lock, first-run ask [SEQUENTIAL: after Task 14]

**Action:** MODIFY
**File:** `hooks/temper-mod/register.tsx`
**Traced to:** Scenario: "Mode switch takes effect without restart and persists", "A locked mode row is reported, not changed", "Minimal mode shows phases only and off mode draws nothing"
**Test:** `tests/mod/modes.test.ts`
**Validate:** `claude plugin test .`
**Notes:** `$.config.list` → isLocked → message; else `$.config.set` + mirror in `$.state`. First interactive `/temper` asks once via `$.ui.ask` (stored in `$.store`); never in `claude -p`.

### Task 16: Optional per-phase model and reviewer model (AC-15) [SEQUENTIAL: after Task 15]

**Action:** MODIFY
**File:** `hooks/temper-mod/register.tsx`
**Traced to:** Scenario: "Per-phase model and reviewer model are off by default"
**Test:** `tests/mod/optional.test.ts`
**Validate:** `claude plugin test .`
**Notes:** Deferred until AC-01..AC-14 pass. Empty config → pure pass-through.

### Task 17: CI and API-surface assertion [SEQUENTIAL: after Task 16]

**Action:** CREATE / MODIFY
**File:** `scripts/check-mod-calls.sh`, `.github/workflows/quality.yml`
**Traced to:** Scenario: "The mod uses no process, http or env call"
**Test:** `scripts/check-mod-calls.sh`
**Validate:** `bash scripts/check-mod-calls.sh`
**Notes:** Parse `claude plugin validate --json .` calls; fail on `process.`/`http.`/`env.` and on any call outside the reviewed list. Workflow job installs `@anthropic-ai/claude-code` (≥2.1.287), runs `claude plugin test .` and the script.

### Task 18: Laptop testing checklist [SEQUENTIAL: after Task 17]

**Action:** CREATE
**File:** `docs/mods-testing.md`
**Traced to:** Scenario: "The maintainer tests the branch on their laptop without touching the installed Temper", "Old Claude Code versions load the plugin as today", "Without the marker the skills announce prompt-based phases"
**Test:** `scripts/validate-docs.sh`
**Validate:** `bash scripts/validate-docs.sh`
**Notes:** Steps 1-8 of mods-plan section 6, each a checkbox with exact command and expected result; includes old-version matrix and `/compact` check; ends by clearing the `pluginConfigs` row.

### Task 19: Demo fixture, tape, demo script, assets [SEQUENTIAL: after Task 18]

**Action:** CREATE
**File:** `demo/password-reset/`, `demo/temper.tape`, `docs/demo-script.md`, `docs/assets/`
**Traced to:** Scenario: "README explains Temper at a glance and still validates"; Infrastructure: required by docs/mods-testing.md step 5
**Test:** manual
**Validate:** `bash scripts/validate-docs.sh && test -f demo/temper.tape`
**Notes:** Tape committed, never run in CI. GIF and light/dark screenshots recorded with VHS where possible; desktop screenshot and video are the maintainer's.

### Task 20: README rewrite and command docs [SEQUENTIAL: after Task 19]

**Action:** MODIFY
**File:** `README.md`, `docs/commands.md`
**Traced to:** Scenario: "README explains Temper at a glance and still validates"
**Test:** `scripts/validate-readme.sh`
**Validate:** `bash scripts/validate-readme.sh && bash scripts/validate-docs.sh`
**Notes:** Keep "Install" and "How It Works" headings, ≤300 lines. "Where enforcement works" uses the surfaces table (mods-plan 2.2) and states Bash/MCP limits.

### Task 21: Version 9.5.0 and CHANGELOG [SEQUENTIAL: after Task 20]

**Action:** MODIFY
**File:** `.claude-plugin/plugin.json`, `.claude/CLAUDE.md`, `commands/temper.md`, `CHANGELOG.md`
**Traced to:** Infrastructure: required by scripts/validate-plugin.sh version agreement
**Test:** `scripts/validate-plugin.sh`
**Validate:** `bash scripts/version-bump.sh 9.5.0 && bash scripts/validate-plugin.sh`
**Notes:** Fill the CHANGELOG skeleton: mod, CLI additions, the new intent-gate requirements (verdict change), minimum versions, Where enforcement works.

### Task 22: Full validation [SEQUENTIAL: after Task 21]

**Action:** none
**File:** none
**Traced to:** Infrastructure: required by Review and Check
**Test:** all
**Validate:** `bash scripts/tests/test-temper.sh && bash scripts/quality-check.sh && claude plugin test . && claude plugin validate --strict . && bash scripts/check-mod-calls.sh`
**Notes:** Then hand `docs/mods-testing.md` to the maintainer; no PR until it is ticked.
