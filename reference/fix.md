# Fix: Root Cause Analysis and a Structured Fix

**Goal:** find the real root cause, prove it with a failing test, apply the smallest fix,
then Review and Check as in `/temper`. A fix without a reproduction is a hope.

## Stage 1: RCA, understand why, not only where

**Read `.temper/lessons.md` first** (skip silently when it does not exist). A past incident of
the same shape hands you the strongest hypothesis and the test that caught it; cite it.

Then investigate:

- **The input:** a ticket key, an issue number or prose. Extract the symptom, the trigger, how
  reliably it reproduces and when it started.
- **Several hypotheses** when the cause is unclear: up to 5, each with a confidence and the
  evidence; investigate the strongest first. After 3 dead ends, stop and report what you tried.
  With one obvious cause or an exact stack trace, go straight to it.
- **Trace the call chain** to the failing point: with a `code-review-graph` MCP server its
  query tools (`[PROVEN]`), otherwise grep (`[HEURISTIC]`).
- **History:** `git log` and `git show` on the affected files for the change that introduced it.
- **Related code** with the same defect: that is the blast radius.
- **Packs:** a bug that breaks a pack rule (input not validated, a secret logged) often has
  that rule as the name of its root cause.

### The debugging floor

Reproduce, localize, reduce, bisect, find the root cause, write the regression test, in that
order. **Without a reliable reproduction, stop and gather more evidence.** "I can see it right
there" is not a reproduction. A root cause is "line 47 returns early on `items.length === 0`
when the guard should check `items === null`", not "the function has a bug".

**Several causes:** one HIGH, take it; several HIGH, fix the deepest (A causes B causes C: fix
A); unclear, present both and recommend one. Never fix two causes at once.

## Stage 2: Fix, RED then the smallest GREEN

1. **Regression test first.** Reproduce the exact failing scenario; assert the correct
   behavior; name the test for the bug. It must fail on an assertion about the bug, not on a
   missing import. Record the `regression` RED row in `evidence.md` and the test's path in
   `state.json` as `regression_test`. From then on, fix the code, never that test; changing it
   is the person's call.
2. **Check the approach against the enabled packs** before writing it.
3. **The smallest GREEN.** Read the whole file. Fewest lines, no unrelated refactoring. Check
   the trigger data, the near edges (empty, one, many, the maximum) and the happy path. The
   regression test passes; the tests around it still pass. Record the GREEN row.
4. **Blast radius.** Grep every consumer of the changed code. Apply the same fix to the same
   defect elsewhere (with a test case each); flag what is unclear.
5. **Intent cross-reference**, only when an active `intent.md` exists: a criterion the fix
   touches still holds.
6. **Lesson.** Append one entry to `.temper/lessons.md` (create it with a `# Lessons` header):

   ```markdown
   ## {date}: {bug title}
   - **Root cause:** {the specific condition}
   - **Trigger:** {the data or state that provoked it}
   - **Fix:** {one line on what changed}
   - **Regression test:** {test file}#{test name}
   - **Watch for:** {the general failure shape a future RCA should recognize}
   ```

## Stages 3 and 4: Review and Check

The ordinary stages. After Check, run the regression test on its own and read it: STRONG
(proves the fix), WEAK (incomplete) or TRIVIAL (always passes).

## The commit

After the person chooses Commit at the Check question: `fix({scope}): {description}`, then
`Root cause: {explanation}` and `Regression test: {test name}`, and `Closes JIRA-123` or
`Fixes #456` when there is one. Stage only the fix's files, the test and the spec folder.

## When it is not a bug

It is a design flaw: say "this needs `/temper:plan` for a redesign, not a patch", and offer a
workaround with a TODO when one exists.
