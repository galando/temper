# 07 — Remaining gaps: a v5.7 hardening proposal

v5.6.0 is genuinely well built — every hook has a fail-open contract, telemetry honestly
flags `estimated` vs `measured`. But a post-implementation audit found **six real gaps**,
ranked by impact. Several directly affect trustworthy daily/org use. This chapter is the
proposed hardening backlog. (Analysis only — no implementation is included here.)

---

## Severity legend
🔴 blocker for trustworthy daily/org use · 🟠 important · 🟡 strategic / larger effort

---

## Gap 1 — Deterministic hooks have no tests, and CI doesn't run them 🔴

`block-secrets.sh` is the **only fail-closed path** in the system, yet there is no test
suite and `.github/workflows/quality.yml` never executes it. Both failure modes are silent:
a too-broad regex blocks legitimate commits (a workflow DoS); a too-narrow one leaks a key.
The script even comments on this precision trade-off — exactly what needs tests.

**Why it's #1:** it protects the one mechanism that *blocks*. Untested guardrails are
worse than no guardrails because they breed false confidence.

**Fix:**
- A `bats` (or pure-shell) test suite with **positive** cases (real AWS/GitHub/private-key
  patterns ⇒ exit 2) and **negative** cases (doc strings, fixtures, env-var references ⇒
  exit 0), covering all three hook scripts and their fail-open paths.
- Wire it into `quality.yml`.
- Add a `validate-plugin.sh` check that every script in `scripts/hooks/` has a test.

---

## Gap 2 — No headless / CI mode 🔴

`/temper` is entirely gate-driven (`AskUserQuestion` at every stage). There is no unattended
run that produces a pass/fail + report. This blocks two things the adoption playbook needs:
**enforcing the eval gate in CI** (ch. 06, Lever 2) and the paper's **orchestrator /
background-agent** mode ("hand off, review the PR later").

**Fix:** a `--ci` / non-interactive mode that runs plan→…→eval, auto-applies feedback loops
up to `feedback.max-loops`, and emits a machine-readable report + exit code instead of
gates. This is the missing piece for "everyone, daily" plus merge enforcement.

---

## Gap 3 — Eval is a per-feature gate, not a flywheel 🟠

The paper's quality flywheel = *benchmark suite → diagnose → optimize → regression suite →
monitor production*. Temper builds only the first link. Missing:
- **`/temper:eval --all`** — run every evalset as a regression suite in CI (catch
  behavioral regressions across the repo, not just the feature you touched).
- **An accumulating eval corpus** — today evalsets live per-spec and are effectively
  run-once; nothing turns them into a persistent benchmark.
- **Production feedback** — no path to turn a prod incident into a new eval case.

**Fix:** a repo-level eval corpus + `--all` regression mode + a documented "incident → eval
case" workflow.

---

## Gap 4 — The LM-judge itself is unvalidated 🟠

> _"An eval without a clear rubric measures nothing."_

The same is true of the judge: an uncalibrated judge produces confident, meaningless
scores. There is no meta-eval confirming the judge agrees with humans.

**Fix:** ship a small **human-labelled golden set** and a **judge-agreement metric** (e.g.
correlation / exact-match against the golden labels), surfaced in `/temper:status`, so teams
can trust the scores before gating on them.

---

## Gap 5 — Token "measurement" is estimate-grade in practice 🟠

The `observability.json` v2 schema supports `source: measured`, but Claude Code doesn't
currently expose per-subagent token usage to the orchestrator — so values are almost always
`estimated`. The honesty (source-flagging) is right; the **leader-facing OpEx value** (real
cost tracking) isn't delivered yet.

**Fix:** wire an external usage source (parse Claude Code's own session/cost output, or
OpenTelemetry), **or** explicitly frame the economics dashboard as estimate-based and
calibrate the estimator against a handful of known runs. Either way, label it clearly.

---

## Gap 6 — Two strategic gaps still open 🟡

### 6a — Production / deploy / maintain phase (the deferred Phase 3)
The SDLC stops at commit — it omits the half that touches real users: deployment-risk
scoring, health monitoring, auto-rollback, and the production→development feedback loop the
paper describes. For a production org this is the highest-value *new* surface area.

### 6b — Org-scale distribution & governance
Packs resolve project > global > built-in, but `docs/enterprise.md` recommends distributing
shared config by **git copy**. For hundreds of repos there's no version-pinning or central
governance; `examples/company-pack` is an example, not a managed channel.

**Fix:** a managed company-pack distribution channel (versioned, pinnable) + config
inheritance so an org can update guardrails once and have every repo pick it up.

---

## Recommended order

A **v5.7 "hardening" pass before scaling org-wide**, in this order:

1. **Gap 1** — hook tests + CI wiring (self-contained, low-risk, protects the blocker path).
2. **Gap 2** — headless/CI mode (unlocks merge enforcement + background-agent use).
3. **Gap 4** — judge calibration (makes eval scores trustworthy enough to gate on).
4. **Gap 3** — regression-eval corpus + `--all`.

Then the larger strategic work:

5. **Gap 5** — real cost measurement (or explicit calibration + labelling).
6. **Gap 6** — production phase + org distribution (a genuine Phase 3 / Phase 4).

---

## Summary table

| # | Gap | Severity | Effort | Unlocks |
|---|-----|----------|--------|---------|
| 1 | Hook tests + CI | 🔴 | S | Trustworthy guardrails |
| 2 | Headless / CI mode | 🔴 | M | Merge enforcement, async agents |
| 3 | Eval regression/flywheel | 🟠 | M | Catch regressions, compounding quality |
| 4 | Judge calibration | 🟠 | S–M | Trustworthy eval scores |
| 5 | Real token measurement | 🟠 | M | Billing-grade OpEx tracking |
| 6 | Production phase + org distribution | 🟡 | L | Full SDLC + org scale |
