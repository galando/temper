---
description: "Root cause analysis + structured fix for a bug"
argument-hint: "<bug-description-or-JIRA-123>"
---

# Fix: Root Cause Analysis + Structured Fix

**Goal:** find the real root cause, prove it with a failing test, apply the minimal fix,
validate. Never guess — a fix without a reproduction is a hope. This doc is the
methodology; `commands/fix.md` is the orchestrator (routing, the RED/GREEN evidence
rows the build gate reads, stage gates). Fix maps onto the `build` gate — a regression
test is a RED-then-GREEN pair — then Review and Check are the ordinary stages.

## Usage

```
/temper:fix "users get 500 error on checkout" | "JIRA-123" | "#456"
```

**Modes:** Standalone (`/temper:fix`) runs the four stages (RCA → Fix → Review → Check)
as Agent subprocesses with its own gates. Agent subprocess (from `/temper`) starts clean
and returns a summary — no `AskUserQuestion`, the orchestrator owns the gate. Same
methodology either way. Apply the context-engineering skill for hierarchical loading.

## Stage 1 — RCA: understand WHY, not just WHERE

**Read `.temper/lessons.md` first** (committed post-mortem corpus; skip silently if
absent). A prior incident matching this failure shape hands you the highest-confidence
hypothesis, its trigger data, and the test that caught it last time — cite the match in
the RCA. An unread lessons file is an incident paid for twice.

Then investigate, inline by default; hand the wide reading to an Explore subagent only
when the codebase is large enough that reading it directly would crowd your context:

- **Detect input** the way `/temper:plan` does (Jira / GitHub / prose), and extract
  symptom, trigger, reproducibility, and when it started.
- **Multi-hypothesis** only when the cause is ambiguous: list up to 5 plausible causes
  with confidence + evidence, investigate the strongest first, fall back on a denial.
  After 3 dead ends, return a blocker naming what was tried; you run headless, so the
  orchestrator asks the user. Skip straight to investigation when there's one obvious
  cause or an exact stack trace.
- **Trace the call chain** to the failing point. With the `code-review-graph` MCP server
  (and `tools.mode` ≠ `heuristic-only`), `query_graph_tool` + `get_affected_flows_tool`
  give an AST-level chain and user-facing blast radius → `[PROVEN]`; else grep →
  `[HEURISTIC]`.
- **Check git history** (`git log`/`git show` on the affected files) for the introducing
  change, and **check related code** for the same defect — that's the blast radius.

Return a ≤30-line RCA: bug, symptom, root cause (specific line + condition + *why*),
location, call chain, introduced-by, trigger, impact, blast radius, confidence, and the
suggested minimal fix + the scenario the regression test must exercise.

### The debugging floor (no shortcuts)

Reproduce → Localize → Reduce → Bisect → Root-cause → Regression test, in that order.
The one hard gate: **without a reliable reproduction, stop and gather more evidence** —
do not proceed to a fix. "I can see it right there" is not a reproduction; eyes lie,
tests don't. Bisect is logarithmic (`git bisect run` for 1000 commits ≈ 10 steps) — use
`git log -20 -- {files}` only when a real bisect is impractical. Root cause is "line 47
returns early on `items.length === 0` when the guard should check `items === null`", not
"the function has a bug".

**Multiple causes:** one HIGH → take it; multiple HIGH → fix the *deepest* (cascading
A→B→C, fix A); ambiguous → present both, recommend the strongest. Never fix two causes
at once — you can't tell which worked.

## Stage 2 — Fix: RED, then the minimal GREEN

1. **Write the regression test first (RED).** Reproduce the exact failing scenario;
   assert the *correct* behavior, not the current broken one; name it for the bug
   (`shouldHandleExpiredTokenGracefully`). Run it — it MUST fail, with an assertion
   error about the bug (not an NPE or compile error). Then record it as this run's proof:
   ```
   $CLAUDE_PLUGIN_ROOT/scripts/temper state set regression_test {test file path}
   ```
   With the hooks pack enabled, `protect-regression-test.sh` now blocks any edit to that
   file for the rest of the run — fix the code, not the test. A genuinely-wrong test is a
   human's call to unlock (`temper state set regression_test ""`), never the agent's.

2. **Validate the approach against enabled packs** before writing the fix (read
   `.claude/temper.config` for the pack list + the stack pack): a BLOCK-rule violation
   (SQL concatenation, a logged secret, a bypassed auth check) means reconsider the
   approach, not implement it; a WARN is noted and proceeds.

3. **Implement the minimal GREEN.** Read the whole file, not just the line. Fewest lines;
   no refactoring of surrounding code, no unrelated improvements — the diff should be
   small and obviously correct. Verify it handles the trigger data, the near edge cases
   (off-by-one → empty/one/many/max), and doesn't break the happy path. Regression test
   passes; **all** existing tests still pass.

4. **Blast radius.** Grep every consumer of the changed code; for a changed
   signature/return/params/error-handling, check all callers. Apply the *same* fix to any
   related code carrying the same defect (add test cases); flag anything unclear rather
   than guessing. A breaking change stops for the user with the required-changes list.

5. **Intent cross-reference** (only if an active `intent.md` exists): note a related
   scenario; verify any `Validate: code`/`Validate: scenario` criterion the fix touches
   still holds; and if the regression test covers a behavior no scenario does, suggest
   adding that scenario. Most fixes are standalone — skip cleanly when there's no spec.

6. **Simplify** the changed files with the `code-simplifier` agent if it's available
   (behavior-preserving only); skip if not installed.

## Stage 3-4 — Review + Check

Run Review then Check (`/temper:check`) as the ordinary stages. After Check passes,
verify the regression test *individually* with the stack's single-test runner and read
its body — classify STRONG (proves the fix) / WEAK (incomplete) / TRIVIAL (always
passes), label `[PROVEN]` from real runner output. A pre-existing unrelated failure is
noted (confirm with `git stash` → test → `git stash pop`), not blamed on the fix.

## Commit + record

The commit gate is the standard one (`temper gate commit`; fix checks build/review/check,
no plan stage). On the user's explicit **Commit** (a typed change is never approval —
make the edit, re-show the gate): a conventional `fix({scope}): {desc}` message naming
the root cause, the regression test, and the closed ticket.

Then two records, both committed:

- **Metrics:** bump `.temper/metrics.json` `fixes` (total, rca_used, confidence,
  blast-radius fixes, regression_test_added).
- **Lessons:** append one entry to `.temper/lessons.md` (create with a `# Lessons`
  header if absent) — this is the corpus Stage 1 reads first, so write it for a future
  investigator:
  ```markdown
  ## {date} — {bug title}
  - **Root cause:** {the specific condition, not "a bug"}
  - **Trigger:** {data/state that provoked it}
  - **Fix:** {commit hash or one line}
  - **Regression test:** {test file}#{test name}
  - **Watch for:** {the generalized failure shape a future RCA should recognize}
  {- **Band change:** only if the fix came from a `temper bands` breach — what was retuned}
  ```
  Incident memory, distinct from review-memory (finding patterns): lessons record *what
  broke and why*, so the next investigation starts from evidence, not zero.

## Rollback

- Tests fail after the fix → `git checkout -- {file}`, re-run, re-investigate.
- 3+ fix attempts fail → keep the regression test (it proves the bug), show the RCA and
  what you tried, ask for context.
- It's actually a design flaw, not a bug → "this needs `/temper:plan` for a redesign,
  not a patch"; offer a workaround with a TODO if one exists.
