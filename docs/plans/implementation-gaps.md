# Temper — Implementation Gaps (Promise vs. Reality)

**What this is:** An audit of whether Temper's implementation actually does what its own
docs, config, and skill files promise — independent of the paper. Each finding cites the
evidence and proposes a fix.
**Audited version:** plugin.json `5.2.1`
**Date:** 2026-06-16
**Method:** static cross-reference of commands, reference docs, skills, packs, config, and
state files; ran the repo's own validation scripts.

## Summary

| ID | Finding | Severity | Type |
|---|---|---|---|
| G-1 | Version stamps disagree across files | High | Consistency |
| G-2 | Cursor parity export is behind the plugin | High | Promise unmet |
| G-3 | Phase-scoped pack loading not wired into review/build | Medium | Promise unmet |
| G-4 | `pack-manifest.json` cache claimed but not consumed by stages | Medium | Promise unmet |
| G-5 | "track-tokens" observability is estimated, not measured | Medium | Misleading wording |
| G-6 | Adaptive-learning flywheel unproven in own dogfooding | Low | Maturity |

**Good news first:** the repo's own validation suites all pass — `validate-plugin.sh`
**13/0**, `validate-docs.sh` **6/0**, `validate-readme.sh` **5/0**. All `reference/*.md`
and `templates/*` referenced by commands resolve. All four capability flags
(`architecture-depth`, `grill-me`, `config-suggestions`, `html-review`) are both defined in
`temper.config` and read by commands. All nine commands in the `CLAUDE.md` table exist. The
core architecture (agent-per-stage, gates, feedback loops, graceful degradation when
`learning.json` is absent) is internally consistent. The gaps below are cross-file drift
and unwired promises, not broken core flows.

---

## G-1 — Version stamps disagree across files (High)

Multiple files carry their own version stamp and they no longer agree:

| File | Version stamped |
|---|---|
| `.claude-plugin/plugin.json` | **5.2.1** |
| `CHANGELOG.md` (top entry) | 5.2.1 |
| `.claude/CLAUDE.md` | **5.2.0** |
| `.cursor/VERSION` | **5.0.1** |
| `.claude/commands/temper.md` (header) | **v4.4.1** |

**Impact:** Users can't trust any single file to report the installed version; the `temper`
command header (v4.4.1) is three minor versions stale.

**Fix:** Single source of truth = `plugin.json`. Either (a) drop inline version stamps from
command/skill headers, or (b) add a `scripts/version-bump.sh` step (the script already
exists) that rewrites every stamp. Add a `validate-plugin.sh` check asserting all stamps
match `plugin.json`.

---

## G-2 — Cursor parity export is behind the plugin (High)

`.cursor/VERSION` is **5.0.1** while the plugin is **5.2.1**. The README/landing positions
Cursor parity as a first-class feature ("22 rules, capabilities listed"), and portability
across tools is an explicit design goal. A two-minor-version lag means Cursor users get
**stale rules and commands** — the parity promise is partially unmet.

**Evidence:** `.cursor/VERSION` = `5.0.1`; `git log` shows v5.1.0 (nested subagents) and
v5.2.0/5.2.1 landed after, but the Cursor export wasn't regenerated in lockstep.

**Fix:** Make `scripts/install-cursor.sh` (or a CI step) regenerate `.cursor/` on every
release and assert `.cursor/VERSION == plugin.json version` in `validate-plugin.sh`. Treat
the Cursor export as a release artifact, not a manually-synced copy.

---

## G-3 — Phase-scoped pack loading not wired into review/build (Medium)

`temper.config` attaches `phases:` to packs as an efficiency/scoping lever, e.g.:
```yaml
- name: tdd
  phases: [build]
- name: security
  phases: [review, check]
- name: performance
  phases: [plan, review, check]
```
`reference/pack.md:154-168` documents the contract precisely: *"Only packs scoped to the
current phase are loaded… Filter manifest packs: only include packs where `phases` is
'all' or contains the current phase."*

**But the consuming stages don't apply it.** The pack-load steps say only:
- `reference/review.md:78` — *"Load enabled packs from `.claude/packs/`"*
- `reference/build.md:50` — *"Read active pack rules from `.claude/packs/` (enabled packs
  only…)"*

Neither references the current phase, the `phases:` field, or the manifest filter. A grep
for phase-filtering language in the consuming commands returns nothing. So `tdd` (scoped to
`build`) and `security` (scoped to `review, check`) are effectively loaded the same way
regardless of stage — the promised token/scoping benefit isn't realized at the point of
use; the filtering logic lives only in the `/temper:pack` management doc.

**Fix:** Add an explicit step to `review.md`, `build.md`, `check.md`, `plan.md`,
`design.md` context-load sections: *"Load only packs whose `phases` is `all` or contains
`{this-stage}`, per `reference/pack.md` filtering."* Optionally centralize via the
`context-engineering` skill so every stage inherits one rule.

---

## G-4 — `pack-manifest.json` cache claimed but not consumed by stages (Medium)

`temper-core/SKILL.md:16` and `reference/pack.md:49` promise pack discovery is *"cached to
`.temper/pack-manifest.json` for instant subsequent loads."* The file legitimately doesn't
exist yet (built on demand — fine), **but the stage commands that would benefit never read
it.** `review.md`/`build.md` load packs straight from `.claude/packs/` and never check the
manifest. So the caching layer is documented and partially specified in `pack.md` but is
not part of the hot path it was designed to speed up.

**Fix:** Either (a) have stage pack-load steps consult `.temper/pack-manifest.json` first
(build if stale) — which also delivers G-3's phase filter cheaply — or (b) downgrade the
claim to "used by `/temper:pack`" so the doc matches reality. Option (a) is preferred:
it makes both G-3 and G-4 a single coherent change.

---

## G-5 — "track-tokens" observability is estimated, not measured (Medium)

`temper.config` advertises:
```yaml
observability:
  track-tokens: true   # Estimate token usage per stage
  track-latency: true
  track-tool-calls: true
```
`temper.md:458-464` writes `.temper/observability.json` after each stage — but the values
are **self-estimated by the model**, not measured from real usage. The flag name
`track-tokens` and the dashboard framing imply measurement; the inline comment admits
"Estimate." A model estimating its own token spend is unreliable and can't *"audit exactly
why an agent made a decision"* the way the observability goal states.

**Fix (also Phase 2, Deliverable 2):** capture measured usage where the harness exposes it;
mark every value with a `source: measured|estimated` flag; rename/clarify the config
comment so it never presents estimates as measurements.

---

## G-6 — Adaptive-learning flywheel unproven in own dogfooding (Low)

The adaptive-learning loop (pattern detection → rule suggestion at 3+ accepts → noise
reduction at 5+ dismissals) is well specified (`reference/learning.md`,
`temper-core/SKILL.md`) and degrades gracefully when `learning.json` is absent — which it
**is** in this repo. `metrics.json` shows `reviews.total: 1`. So the flywheel has no
in-repo evidence of having run; the `adaptive-learning/rules.md` pack exists but is empty
of promoted rules.

This is **not a defect** — graceful degradation works as designed — but the headline
feature is untested against real accumulated data in the project that ships it.

**Fix:** Dogfood it: run enough `/temper:review` cycles on Temper's own changes to populate
`learning.json` and promote at least one rule, then commit a redacted sample as a fixture.
Proves the loop end-to-end and gives users a reference shape.

---

## Recommended order

1. **G-1 + G-2** — mechanical, high trust impact; gate them in `validate-plugin.sh` so they
   can't regress.
2. **G-3 + G-4 together** — one change (manifest-driven, phase-filtered pack loading)
   closes both and delivers a real token win.
3. **G-5** — folds into Phase 2 (measured observability); do it there.
4. **G-6** — opportunistic; do it while building Phase 1 evals (same dogfooding session).
