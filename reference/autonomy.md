---
description: "Autonomous Continuation mechanics for the /temper orchestrator"
---

# Autonomous Continuation

Read by `commands/temper.md` **only when `autonomy.enabled: true`** — with the block
absent or false (the default), the orchestrator never loads this file and every gate is
the ordinary interactive one. `$TEMPER` as defined there.

Opt-in, armed by the human at the **plan gate only** — never at invocation or mid-run.
The Intent gate is always interactive: no unattended run starts without a human having
accepted the intent.

**Arming** (at the plan gate, on PASS, after human review): replace "Continue to Build"
with "Stage by stage (Recommended)" (`run_mode: interactive`) / "Autonomous — run the
rest unattended" (`run_mode: autonomous`).

**While `run_mode == autonomous`, every post-plan gate:** run `$TEMPER gate {stage}` as
usual. **PASS** → auto-select Continue, no `AskUserQuestion` (but still print the summary
box — an unattended run must leave a scroll-back-readable record). **FAIL** → loop
automatically at the same budget as interactive mode, except Build→Plan (always returns
to a human, never auto-loops); budget exhausted → park instead of asking. **At commit:**
`$TEMPER gate commit` already checks blast radius + park-on-touch (autonomous-only) along
with every upstream gate — PASS or FAIL, **always park**, autonomy never auto-commits.

**Park:** `$TEMPER state set run_mode interactive` (so a plain resume lands here
normally), write `.temper/autonomy-report.md` (`**Verdict:**
SHIP-PENDING-COMMIT|PARKED-NEEDS-DECISION`, `**Parked at:**`/`**Reason:**` verbatim from
`temper gate`, `**Branch:**`, the `$TEMPER report` ledger, "Run /temper to resume").

**Operational safety (hardcoded — see `templates/temper.config.default`):** refuse a
dirty tree unless confirmed; `git commit -m "wip: {stage} passed"` after each PASS stage
(a crash loses at most one stage); `.temper/autonomy.lock` refuses a second concurrent run.
