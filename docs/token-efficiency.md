# Token Efficiency (v5.9.0)

> **TL;DR — the defaults that ship out of the box:** all three optimizations are
> **ON**. You save tokens automatically. The only one with a quality tradeoff is
> `adaptive-depth`, and you control it per-change with the **Escalate to full pipeline**
> gate option — no config editing needed.

Phase 3 adds three independent levers that cut the token cost of a `/temper` run. Each
is config-flagged, each defaults **on**, and each is **byte-identical to v5.8.0 when its
flag is off**. Phase 2 (v5.6.0) picked the right *model* per stage; Phase 3 stops paying
full price to re-read static *context* and stops running a frontier-tier pipeline on
trivial changes.

---

## What ships by default

`.claude/temper.config`, `tokens:` block — all default-on:

| Flag | Default | What it does |
|------|---------|--------------|
| `tokens.cache.enabled` | `true` | Cache static methodology reads (~90% off re-read cost) |
| `tokens.adaptive-depth.enabled` | `true` | Size the pipeline to the change's complexity |
| `tokens.adaptive-depth.floor` | `simple` | Minimum rigor tier (allows the trivial fast-path) |
| `tokens.loops.fix-mode` | `true` | Minimal-context fix agent for re-launched loops |
| `tokens.loops.inline-threshold` | `3` | Auto-fix ≤3 files inline — no subprocess |

A fresh install gets every optimization. To get v5.8.0 behavior back, set the relevant
flag(s) to `false` (and `inline-threshold: 0`).

---

## The three levers, in plain terms

### D1 — Cache (`tokens.cache`): no quality tradeoff

**The problem:** A `/temper` run launches 6 separate Agent subprocesses, each with empty
memory. Each re-reads the methodology files (`review.md`, `plan.md`, `check.md`,
`build.md`) from scratch — at full input-token price. Reading the same 1,200-line file 6
times means paying for it 6 times. Feedback loops re-read it *again*.

**How the cache actually works (the honest mechanism):**

Anthropic's platform offers *prompt caching*: if you send the **same text at the start**
of multiple requests — first, in the same order, byte-for-byte — it charges ~10% instead
of 100% for that portion. But the repeated text must come **first**; if the prefix shifts
by one line, the cache misses and you pay full price.

Temper can't *force* the platform to cache. What it does is **structure the read order**
so the stable part (methodology, which never changes during a session) is always read
**first**, and the volatile part (git diff, spec files) is read **last**. That makes the
prefix identical across all 6 stages, so the platform's cache keeps hitting.

```
Without cache ordering:              With cache ordering (v5.9.0):
  Stage 1: [git diff][review.md]       Stage 1: [review.md][orchest][git diff]
  Stage 2: [plan.md][git diff]         Stage 2: [review.md][orchest][git diff]  ← same prefix!
  ↑ different prefix each time          ↑ identical prefix → cache HITS (~10%)
  = cache never hits                    = cache hits on stages 2-6 + feedback loops
```

So "the cache" = **a rule about what order to read files in.** Temper then records whatever
the platform reports as cached into `observability.json` (`tokens.cached_input{value,source}`),
visible in `/temper:status`. No daemon, no new dependency — pure ordering.

**Quality impact: none.** The agent reads the *exact same* files and makes the *exact same*
decisions. Cache changes token *price*, not behavior. Leave it `on` always.

> **Diagnostic toggle:** if you are actively *editing* the methodology files mid-session and
> suspect a cached read is stale, set `tokens.cache.enabled: false` temporarily.

### D2 — Adaptive depth (`tokens.adaptive-depth`): the one real tradeoff

**"Rigor"** = how much checking a change goes through before it ships. More rigor = more
stages, gates, artifacts (blast-radius analysis, design doc, eval), more chances to catch a
mistake. Think airport security: the full checkpoint vs. the PreCheck fast lane. The risk of
the fast lane is the same as adaptive-depth — **if someone is misclassified as low-risk, they
slip through with less checking.**

**The whole idea, in one line:** v5.8.0 ran the full heavy pipeline on every change —
whether a typo or an auth rewrite. The plan stage has *always* classified each change's
complexity (`trivial | simple | medium | complex`); v5.8.0 threw that label away and ran
everything at max. Adaptive-depth makes the label *drive* how much pipeline runs.

**What each tier gives up** (everything below is *added back* by escalating):

```
                      gates  design  eval  mermaid  blast-radius  full-methodology
complex  (full)         6     yes    yes    yes       yes            yes
medium   (full)         6     cond   yes    yes       yes            yes
simple   (reduced)      2     no     no     no        no             spine only
trivial  (lean)         1     no     no     no        no             spine only
```

The quality question collapses to one thing: **does skipping blast-radius / mermaid / design
/ eval on a small change cause you to miss something?**

- **When reduced depth is fine:** a typo, a one-line config change, a version bump. There is
  no blast radius to analyze. Running 6 stages here is ceremony, not quality.
- **When reduced depth will miss things:** a "small" change to a *shared interface* (one-line
  signature change breaks 12 consumers); a change with a non-obvious design decision;
  concurrency, auth, or data-migration changes. The classifier is heuristic (file count, LOC,
  dependency depth) — it **cannot see semantic risk**. A 3-line auth change is `trivial` by
  every structural metric and `critical` by every semantic one. **This gap is what the
  escalate gate and the `floor` exist to cover.**

### D3 — Incremental loops (`tokens.loops`): small, bounded tradeoff

A loop that auto-fixes 2 lint findings should not re-read the entire Build methodology.

| Mode | When | What the fix agent sees | Quality risk |
|------|------|-------------------------|--------------|
| **inline** | ≤ `inline-threshold` auto-fixable files | nothing extra — applied directly | **None** (deterministic auto-fixes) |
| **fix-mode** | more files, all auto-fixable | fix list + changed files + short preamble (NOT full `build.md`) | **Low** (mechanical fixes, not design) |
| **full** | scope/approach change | full `build.md` + tasks + intent | baseline |

The only real downside: a fix-mode agent has *less context*. If an auto-fixable finding is a
symptom of a deeper design problem, it applies the surface fix and moves on. But by definition
these findings were judged *auto-fixable* (mechanical), the circuit breaker still caps loops at
2, and any *non*-auto-fixable finding (a real correctness risk) skips straight to `full` or
back to you. Leave it `on`.

---

## How to balance cost vs. quality

There are **two** mechanisms. Keep them separate.

### A. "Escalate to full pipeline" — the on-the-fly, per-change mechanism (use this day-to-day)

No config editing. Mid-run, at the plan gate:

```
You run:   /temper "add password reset"
             ↓
Plan stage labels the change "simple" → plans the reduced 2-gate pipeline
             ↓
The plan gate appears with options, INCLUDING:
   [x] Escalate to full pipeline   ← click this
             ↓
Temper re-runs as if "complex": all 6 stages, blast radius, eval — full rigor
```

**This is the primary balance mechanism.** You look at the tier the plan chose; if your gut
says "this one's risky," you escalate. One click, this change only. Next change, back to
automatic. You almost never need to touch the config file.

### B. `.claude/temper.config` — the permanent, per-team mechanism

For a *standing policy* that applies to *every* run:

```yaml
tokens:
  adaptive-depth:
    enabled: true
    floor: medium          # permanent rule: never below medium rigor, ever
```

Set `floor: medium` once if your whole codebase is high-stakes (payments, auth, regulated) and
you want to guarantee no change ever takes the trivial fast-lane — so you don't have to click
"Escalate" every time. This is "set it and forget it."

| | "Escalate" gate option | editing `temper.config` |
|---|---|---|
| **Scope** | one change | every change (until you revert it) |
| **When** | mid-run, at the plan gate | before you run, in a file |
| **Effort** | one click | edit + save |
| **Use when** | your gut says "this one's risky" | your whole codebase is risky |

### The decision rule (the whole thing, on one screen)

```
After the plan stage labels the tier:

  Did the plan say trivial/simple, AND is the change:
    - touching a shared/public interface?         → ESCALATE (gate option)
    - auth, concurrency, data migration, money?   → ESCALATE
    - a "small" change with unclear blast radius? → ESCALATE
    - genuinely isolated/mechanical?              → accept reduced tier (keep savings)

  Is your whole codebase high-stakes?
    → set floor: medium in config, never think about it again
```

---

## When is development quality actually worse?

Only when this full chain happens:

1. `adaptive-depth` is **ON**, **AND**
2. a change is **misclassified** as simple/trivial when it's actually complex, **AND**
3. the developer **doesn't escalate** at the gate.

Break any link — disable the flag, raise the `floor`, or click "Escalate" — and you're back to
full v5.8.0 rigor. **Cache and loops have no quality cost** (cache is pure price; loops only
skip the methodology for findings already judged mechanical).

**The mental model:** adaptive-depth trades *"automatic rigor on every change"* for
*"developer-judged rigor per change, plus a fast-path for the common case."* You're now in the
loop at the gate. That's the cost — you have to look at the tier and decide. v5.8.0 never asked
you, because it always did everything.

If that per-change judgment feels like overhead you don't want, set `floor: medium` (or
`adaptive-depth.enabled: false`) — full rigor everywhere, while still keeping the cache + loop
savings. That's the real "I don't want to balance anything" option, and it's reasonable for
high-stakes codebases.

---

## Measuring the savings

Savings are now **visible**, not hidden:

- `observability.json` gains `tokens.cached_input{value,source}` per stage (D1) and a `loops[]`
  array with per-loop `mode` (inline|fix-mode|full) + token cost (D3).
- The `/temper:status` economics panel shows dollars saved from cache + cheaper loops.
- v5.8.0's `pricing.md` stated cost *"excludes caching"* — the panel was blind to this waste.
  v5.9.0 drops that exclusion and adds cache read/write multipliers per tier.

Exact dollar figures depend on your model mix and change-size distribution; the PR delivers the
*mechanism* and the *measurement*. You'll see real numbers in your own `/temper:status`.

## Graceful degradation

Every flag degrades **independently** and **byte-identically** to v5.8.0 when off. Disabling
cache does **not** disable adaptive-depth or loops. The full "all flags off" state is a tested
scenario (`validate-phase3.sh`) and reproduces v5.8.0 exactly.

## Further reading

- Reference: [orchestrator-patterns.md — Cacheable vs. Volatile Context, Pipeline Depth, Loop Cost Tiers](../.claude-plugin/reference/orchestrator-patterns.md)
- Reference: [pricing.md — cache multipliers](../.claude-plugin/reference/pricing.md)
- Reference: [tokenomics.md — the three levers as canonical guidance](../.claude-plugin/reference/tokenomics.md)
- Plan: [docs/plans/phase-3-token-efficiency.md](plans/phase-3-token-efficiency.md)
