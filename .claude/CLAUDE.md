# Temper

| Command | Purpose |
|---------|---------|
| `/temper` | Unified SDLC: intent → plan → design → build → review → check |
| `/temper:fix` | RCA + fix |

Words of `/temper:temper`: `draft <idea>` (a draft `intent.md`, no run), and alone `status`, `report`, `init`,
`pack`; other text is a request. Each word has its row in the Arguments table of `commands/temper.md`.

**The run to the commit (default):** the approval's first option, Approve and build, lets the run go
on by itself to the commit question: a passed check moves on, a failed check gets one repair by rule, every other case
stops and asks. Started only by that answer (never at invocation); never pushes or merges; the commit always asks.
`run.default` (`to-commit`, `ask`, `never-unattended`) orders the options; `autonomy.enabled: false` reads as `ask`.
See `reference/autonomy.md`.

**The deterministic spine (v7):** every gate verdict is computed by `scripts/temper`
(`temper gate {stage}`) from an evidence ledger (`temper evidence add`), not asserted by
a model. `git commit` is blocked by a native pre-commit hook (and, with the guardrails pack,
an in-agent PreToolUse hook) whenever a gate is FAIL and unoverridden: see `packs/guardrails/rules.md`.

**One flow (ADR 0012, ADR 0013).** `temper next --json` (`scripts/flow.py` and its `flow_*.py` modules)
says what comes next, with each gate's exact question and options; `commands/temper.md` is a loop
over it. The CLI writes `.temper/view.json` after every change, the one file of the CLI's the mod reads.
The person decides each gate only in the `Temper gate` question, with the mod or without it, in every mode
(after Approve and build, only at the stops and the commit); the mod
counts an answer only on an exact match for the CLI's run and step, guards, and draws the run (its
bar decides nothing). With the mod loaded, the mod also carries a run itself (the run driver,
`hooks/temper-mod/core/driver.ts`): it runs the CLI's calls, launches its agents and asks its questions, and hands
the run to the conversation for whatever needs a model. The guard is not a sandbox (`docs/trust.md`).

**Version:** 9.8.5 (history: `CHANGELOG.md`).
Config: `.claude/temper.config` | Docs: `reference/`
CLI reference: `scripts/temper --help` | Retired systems: `docs/history/`

**Developing temper (this repo):**
- Test: `bash scripts/verify.sh quick` after a change (about 3 minutes, ends `verify quick: PASS`), and
  `bash scripts/verify.sh full` before a push (every case file, the end to end suite in every mode, the mod).
- Selftest: `bash scripts/selftest/run-selftest.sh [--fast|--changed|--touched|--slow] [--shard K/N] [--list]` runs
  the case files in parallel; a case file is found by its name (`temper-cases-N.sh`), so a new one needs no list.
  `bun scripts/e2e/run.ts both` is the end to end driver (the real CLI, with the mod's rule engine and without it).
- Directory readiness: `bash scripts/validate-directory.sh` (no raw HTML in the README, no
  assets folder path in text, no `options` key). Run it before any README or manifest change.
- The mod (pure rules, wiring, drawing) and its test suite: after any change to them run
  `claude plugin test .`, `tsc -p tsconfig.mod.json` (TypeScript 5.6, as CI runs it) and
  `bash scripts/check-mod-calls.sh`; the reviewed `$` calls live in that script.
- Layout: `commands/` (slash commands) · `agents/` (stage subprocess briefs) ·
  `reference/` (methodology) · `packs/` (rules) · `scripts/temper` and its Python modules
  (`json_ops.py`, `state_ops.py`, `ledger_ops.py`, `spec_text.py`, `commit_rows.py`, `report_ops.py`,
  `groups_ops.py`, run as `python3 -I`): the deterministic spine, the CLI; gate logic lives in the CLI,
  never in a prompt · `scripts/guards/` ·
  `scripts/plan_review.py` (renders and merges the HTML plan review).
- Known mistakes: a gate-mechanics change is an edit of the CLI (`scripts/temper` or its module) plus a
  `test-temper.sh` case, not a prompt edit; new CLI logic goes into a module and one line into the bash
  file; what comes next, a gate's options and the grouped Build loop are `scripts/flow.py` and its
  `flow_*.py` modules (a case in `temper-cases-8.sh`; regenerate `scripts/selftest/view-fixtures.ts`
  with `make-view-fixtures.sh` when the view changes), never a list in a page; hooks must fail OPEN except their one
  detected-violation path; never re-add per-stage logic to `commands/temper.md` or
  `commands/fix.md` — it belongs in that stage's own brief in `agents/` (including the
  stage's return box: a brief must never point a clean-context subprocess at an
  orchestrator file); new commands and agents must be listed in `.claude-plugin/plugin.json`;
  a finding is resolved by `temper repair close` (scripts/repair_ops.py), never by a brief or an agent's
  call; the person decides only in a question dialog, so never add a button that decides to the
  mod, and never add a command (a new word is a row of the Arguments table of `commands/temper.md`, with a page in `reference/`); a cap
  of `scripts/caps.json` is never raised by a building session (`now` follows the measure,
  `final` never moves), and a count of the floor (`scripts/e2e/floor.json`) moves only in the
  commit that moves the behaviour (`bun scripts/e2e/run.ts all <name> --floor scripts/e2e/floor.json`);
  a check is taken off the expected to fail list (`scripts/selftest/expected-fail.txt`) by the
  commit that makes it pass and by no other, and its assertion is never weakened to get there
  (`python3 scripts/check_done.py`; a changed assertion goes into `docs/plans/one-go/changed-tests.md`).

<!-- Nothing follows. Do not add a generated advice section here: validate-docs.sh
     rejects the TOKENOMICS:START / TOKENOMICS:END markers (docs/history/tokenomics.md).
     Never write the markers' full comment syntax inside this comment; the embedded
     close-delimiter would end it early. -->
