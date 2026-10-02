# Intent: Claude Code mods support for Temper

**Author:** galando <galando@gmail.com>
**Status:** draft
**Created:** 2026-10-02
**Ticket:** none
**Reviewer:** galando <galando@gmail.com> (Engineer)
**Complexity:** complex

---

## Intent (IDD)

### Problem

Today Temper's phases live in prompts (`commands/temper.md`, `agents/*.md`) plus a
deterministic CLI (`scripts/temper`) and a few classic hooks. Claude can still write
code during Intent or Plan, because nothing restricts Write or Edit by stage (fact:
only `block-protected-paths.sh` and `protect-regression-test.sh` touch edits). The
user cannot see the current phase, the intent, or criteria progress without running
`/temper:status`. Example: during Plan, Claude edits `src/app.ts`; today that write
succeeds and is only noticed at review. Desired: the write is refused with a reason
that says what to do next, and the phase bar shows Plan as current.

### Success Criteria

- [ ] AC-01 [required]: In every phase, a Write, Edit or NotebookEdit outside that phase's allowed paths is refused by the mod's `tool.call` hook with a reason naming the next action (source: request Part A.1)
  Why: Claude cannot write code before the user approves the intent
  Validate: code — `claude plugin test` cases per phase and per tool
- [ ] AC-02 [required]: `git commit` through Bash is refused until the Check gate is PASS or overridden (source: request Part A.1)
  Why: no unchecked code reaches history
  Validate: code — `claude plugin test` deny and allow cases
- [ ] AC-03 [required]: Every request's system prompt carries a Temper section with "Temper enforcement: active", the phase and the intent title, and it is still present after `/compact` (source: request Part A.2, A.3)
  Why: Claude knows the phase without reading files
  Validate: code — compose hook test; manual — `/compact` check in terminal
- [ ] AC-04 [required]: When the marker is absent, the skills tell the user enforcement is off and continue with prompt based phases (source: request Part A.3)
  Why: Temper keeps working where mods do not run
  Validate: manual — run on 2.1.286 without mods and on claude.ai/code
- [ ] AC-05 [required]: `/temper override <reason>` skips one phase only with a non-empty reason, and the reason is logged and appears in the report (source: request Part A.4)
  Why: escape hatch stays auditable
  Validate: code — state machine and command tests
- [ ] AC-06 [required]: Going back to an earlier phase invalidates every later phase, and the state machine refuses to skip forward over an invalidated phase (source: request Architecture)
  Why: stale approvals never carry over
  Validate: code — state machine unit tests
- [ ] AC-07 [required]: The phase bar, pane, spinner text, turn line, suggestions, hints, toasts and question styling follow `uiMode` full, minimal and off exactly as the request specifies, on terminal and desktop (source: request Part B, C)
  Why: the user chooses how interactive Temper is
  Validate: code — `$.ui.mount` tests on terminal and desktop; manual — both apps
- [ ] AC-08 [required]: `/temper mode <full|minimal|off>` switches with no restart, persists, and reports when an administrator has locked the value (source: request Part C.3, C.4)
  Why: mode changes are cheap and honest
  Validate: code — mode tests with locked and unlocked rows
- [ ] AC-09 [required]: An edit outside the plan's file list raises a scope drift choice (add to plan, revert, allow once with reason) and the decision is logged (source: request Part B Build)
  Why: scope creep is visible and decided by a person
  Validate: code — one test per choice
- [ ] AC-10 [required]: After the configured number of failed Check to Fix loops (default 3), Temper stops and offers re-plan, override with reason, or hand over (source: request Part B Fix)
  Why: no endless fix loops
  Validate: code — loop limit test
- [ ] AC-11 [required]: Completion writes `.temper/report.md` with phases passed, overrides, accepted findings, drift decisions with reasons, and criteria status (source: request Part B)
  Why: one audit artifact per run
  Validate: code — report generation test
- [ ] AC-12 [required]: On Claude Code older than 2.1.287, and where mods are off by policy, the plugin loads as today with no error, and the mod stays inert (source: request disclaimers 1, 4, 5)
  Why: existing installs keep working
  Validate: manual — `claude -p --plugin-dir` on 2.1.200, 2.1.259, 2.1.286 and 2.1.287
- [ ] AC-13 [required]: The mod calls no `$.process`, `$.http` or `$.env` method; tests, lint and git run as prompts to Claude (source: request disclaimer 6)
  Why: smallest possible API surface
  Validate: code — CI asserts the `calls:` line of `claude plugin validate`
- [ ] AC-14 [required]: README shows the value line, badges, hero GIF, Mermaid diagram, mode screenshots, collapsible action references and a "Where enforcement works" section, and still passes `validate-readme.sh` (source: request Part D)
  Why: the GitHub page explains Temper at a glance
  Validate: code — validate-readme.sh; manual — view on GitHub
- [ ] AC-15 [optional]: Per phase model or effort through `turn.step`, and a reviewer model through `agent.spawn`, both off by default (proposed)
  Why: cost and quality tuning per phase
  Validate: code — hook tests with the option on and off
  Deferred: built after AC-01 to AC-14 pass

### Constraints

- Mods need Claude Code 2.1.287 or later (source: mods overview)
- `userConfig` fields must not use `options`: it stops the whole plugin loading before 2.1.271 (source: probe on 2.1.200 and 2.1.259, docs/mods-plan.md)
- Gate verdicts stay in `scripts/temper`; the mod reads them (source: .claude/CLAUDE.md)
- Hooks fail open except on their one detected violation (source: .claude/CLAUDE.md)
- New commands and agents are listed in `.claude-plugin/plugin.json` (source: .claude/CLAUDE.md)

### Scope and Non-goals

- In scope: a pure TypeScript phase module, the mod adapter, CLI additions it needs, skill and command text for the marker, report, README, demo assets
- Out of scope: changing gate verdict logic; a hosted service; recording in CI
- Must keep working: prompt based `/temper` on every surface, `scripts/temper` gates, the native pre-commit hook, the classic `hooks/hooks.json` entries

### Target Users

- Developer using Temper in the CLI or desktop app: sees the phase bar, presses a digit to act → Claude runs the next step under enforcement
- Team lead: reads `.temper/report.md` or the generated PR description → reviews overrides and drift decisions

### Open Questions

- Blocking: approve the plan in docs/mods-plan.md, including the decisions marked "needs your call"; consequence: no build starts; owner: galando.

### Decisions

- Is Intent split from Plan? -> No split needed; Intent is already its own stage and gate (repo fact, 2026-10-02)

---

## Scenarios (BDD)

## Scenario Coverage Checklist

## Source Traceability

### Context Sources

- consulted: https://code.claude.com/docs/en/plugins/mods/overview, create, reference, interface, events, api, test, admin, troubleshoot (2026-10-02)
- consulted: generated types `.claude-plugin/types/claude-code/index.d.ts` written by Claude Code 2.1.287 (2026-10-02)
- consulted: probe runs on Claude Code 2.1.200, 2.1.259, 2.1.286, 2.1.287 (2026-10-02)
