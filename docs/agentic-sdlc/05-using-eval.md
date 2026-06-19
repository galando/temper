# 05 — Using eval

Eval is the verification stage between `check` and `commit`. It answers the question tests
can't: **"did the change actually do what we meant, and was the agent's path to it sane?"**
This chapter is the practical, day-to-day guide. (Mechanics are grounded in
`reference/eval.md` and `templates/evalset.json`.)

---

## Why eval exists

> _"Without both [tests and evals], the practice is always vibe coding."_

Tests check deterministic behavior. Eval checks the **non-deterministic** part: intent
satisfaction and trajectory quality, scored 0–1 across five dimensions, **pass ≥ 0.75** by
default. Dimensions split into two categories that drive what you do about a low score:

| Category | Dimensions | A low score means |
|---|---|---|
| **ARTIFACT** ("fix the code") | `task_success`, `hallucination` (inverted), `response_quality` | The produced change is defective — fix it |
| **PROCESS** ("fix the run") | `tool_use_quality`, `trajectory` | The run was messy; the code may be fine |

---

## The normal flow — you author almost nothing by hand

1. **Plan writes a draft evalset for you.** Running `/temper "…"` makes the plan stage emit
   a draft `evalset.json` next to `intent.md`, one case per Gherkin scenario. The plan
   summary shows an `EVALS: N` line.
2. **You review/tighten it** before build — this is the contract with the agent.
3. **The eval stage runs automatically** in the pipeline, judges with a cheap model
   (`tier-fast`), prints a grouped score table, and offers a gate.

---

## Authoring an evalset directly

```bash
/temper:eval --create        # scaffold from intent.md scenarios
```

Lands at `.temper/specs/{feature}/evals/evalset.json`. A worked example:

```json
{
  "version": 1,
  "feature": "refund-idempotency",
  "rubric": {
    "dimensions": [
      { "name": "task_success",     "weight": 0.35 },
      { "name": "hallucination",    "weight": 0.15, "invert": true },
      { "name": "response_quality", "weight": 0.15 },
      { "name": "tool_use_quality", "weight": 0.15 },
      { "name": "trajectory",       "weight": 0.20 }
    ],
    "pass_threshold": 0.75
  },
  "cases": [
    {
      "id": "c1",
      "input": "Same Idempotency-Key replayed within 24h on POST /refunds",
      "expected": "Returns the original refund result; no second ledger write",
      "labels": ["payments", "idempotency"],
      "must_not": ["double refund", "new DB row on replay"]
    }
  ]
}
```

**The two fields that matter most:**
- `expected` — observable *behavior*, not implementation detail.
- `must_not` — the failure you're most afraid of (for payments: a double-charge).

---

## Running it

```bash
/temper:eval                 # output mode — judge the produced change
/temper:eval --trajectory    # also score the tool-call sequence
```

Results are written to `.temper/specs/{feature}/evals/results/results-{ts}.json` with
per-case scores, justifications, an aggregate, and `passed`.

---

## Reading the score table (the decision)

The gate prints a legend, then groups rows under **ARTIFACT** and **PROCESS** headers, and
annotates any row below threshold with a recommended action:

| Condition | Annotation | What to do |
|---|---|---|
| ARTIFACT row low | `→ Re-run (code defect)` | Fix the change, re-run |
| any `block-on` dim low | `→ Re-run (block-on failed)` | Forces the Eval→Build loop |
| PROCESS row low, not block-on | `→ accept (process noise)` | Code's fine; the run was messy — move on |
| dimension `unscored` | `— unscored` | Excluded from the aggregate |

**Partial aggregate warning:** if any dimension was `unscored` (e.g. the judge was
unavailable), the aggregate is computed over the scored subset only and printed with a loud
caveat — e.g. `⚠ Aggregate 0.80 over 3/5 scored dims … partial.` Never read a partial as a
full pass. If **zero** dims scored, it prints "cannot produce aggregate" and forces a
non-pass.

---

## The gate (inside `/temper`)

After the score table, the Eval stage offers:
- **Continue** → commit
- **Re-run** → loop back to Build (when a `block-on` dim failed)
- **View results** → open `results-{ts}.json`
- **Save-for-later** → persist state and stop

---

## It never hard-fails (the degradation contract)

| Missing input | Behavior |
|---|---|
| `eval.enabled: false` | Skip stage; one-line notice; no subprocess |
| `evalset.json` absent | Skip stage; "no evalset found"; proceed to commit |
| Judge model unavailable | **Deterministic fallback**: `expected`/`must_not` string checks; semantic dims `unscored` (never 0) |
| `build-state.json` / `observability.json` absent | Skip trajectory dims; score output dims only |

---

## Configuration (`.claude/temper.config`)

```yaml
eval:
  enabled: true              # stage runs; false = skip with a one-line notice
  block-on: [task_success]   # which dimensions force the Eval->Build loop on failure
  pass-threshold: 0.75       # aggregate >= this => passed
  judge-model: tier-fast     # cheaper/faster model for the LM-judge
```

**For production code at Booking:** keep `block-on: [task_success]` (and consider adding
domain-critical labels). That's what converts "looks done" into "verified."

---

## Practical authoring tips

1. **Write `expected` + `must_not` before you build** — it's the precise contract, more so
   than any prose prompt.
2. **One case per real scenario.** Don't pad; each case should map to a behavior you'd lose
   sleep over.
3. **Phrase `expected` behaviorally** ("returns the original result; no second ledger
   write"), not structurally ("calls `refundService.replay()`").
4. **Use `must_not` for the scary failures** — the ones that "look right" and pass tests
   (the 80% problem).
5. **Treat the judge's output as data, not truth** — calibrate it (see ch. 07, gap #4) and
   spot-check justifications, especially for high-stakes paths.
