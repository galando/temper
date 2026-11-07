---
description: "Show the active run, gate decisions, review memory and quality trends"
---

# Status: Quality Dashboard

**Goal:** show where the work stands, read from the files Temper keeps. Read only: this command
writes nothing but a missing `.temper/` scaffold, and changes no run.

The file shapes are in `${CLAUDE_PLUGIN_ROOT}/reference/run-state.md`.

## Steps

1. When `.temper/` does not exist, say "No Temper data yet. Start a run with
   `/temper:temper "<feature>"`." and stop.
2. **Active run.** Read `.temper/run.json` and the run's `state.json`: the slug, the command,
   the stage, the tier and risk, each gate so far (`{stage}: {PASS|FAIL} -> {decision}`, with
   the reason of an override), the loops used against `loops.max-per-type`, the drift decisions.
3. **Criteria.** From `intent.md` and `check.md`: each `AC-NN` as passed, open, manual or
   deferred, with the evidence row that backs it.
4. **Evidence.** From `evidence.md`: the counts of red, green, scenario and suite rows, the
   last coverage value, and any red row with no green row after it.
5. **Findings.** From `review.md`: open findings by severity, accepted ones with their reasons.
6. **Specs.** Each folder of `.temper/specs`: its intent status (`draft`, `accepted`,
   `completed`). For each `completed` spec, a light drift check: a file its plan names that no
   longer exists, or a scenario test file that is gone. Read only; run no test unless the person
   asks.
7. **Review memory.** From `.temper/review-memory.json` when it exists: the top patterns, and
   each candidate rule (3 or more accepted at 70% or more: WARN; 5 or more at 80% in security or
   architecture: BLOCK). Ask the person about each candidate with header `Rule`, options "Add
   as BLOCK", "Add as WARN", "Keep advisory". An added rule goes into the project's
   `.claude/packs/{pack}/rules.md` (copy the built-in pack there first when the project has no
   copy); never into the plugin folder.
8. **Metrics.** From `.temper/metrics.json` when it exists: reviews, findings per severity,
   coverage over time.
9. **Lessons.** The count of entries in `.temper/lessons.md` and the last three titles.
10. **Tools.** Whether a code-review-graph or semgrep MCP server is connected.

## Output

```
TEMPER STATUS (Markdown edition)
  Run:       {slug} ({command}) at {stage}, tier {tier}, risk {risk}
  Gates:     intent PASS -> Continue to Plan; plan PASS -> Approve the plan; ...
  Loops:     review {n}/{max}, check {n}/{max}
  Criteria:  {passed}/{required} required passed; {manual} manual; {deferred} deferred
  Evidence:  {red} red, {green} green, {scenario} scenario rows; coverage {X}%
  Findings:  {open} open ({C}C {H}H {M}M {L}L), {accepted} accepted
  Specs:     {N} ({draft} draft, {accepted} accepted, {completed} completed)
  Lessons:   {N}
  Tools:     code-review-graph {yes|no}, semgrep {yes|no}
```

Leave out a line with no data. End with one line: "These numbers are read from files Claude
wrote; the full edition computes them with its CLI."
