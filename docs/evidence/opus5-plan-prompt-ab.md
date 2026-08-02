# A/B: old vs new Plan prompt on Opus 5

Controlled comparison run 2026-08-02, closing the gap the design specified but Build
skipped. Same model (Opus 5), same fixture (`evals/fixtures/password-reset`), same
feature string, 3 runs each, standalone `/temper:plan` via `claude -p --plugin-dir`.

- **Old prompt:** `reference/plan.md` @ `main` (v7.0.1), 1,086 lines.
- **New prompt:** `reference/plan.md` @ v8.0.0, 224 lines.

## Results

| Metric | Old (v7, 1086 ln) | New (v8, 224 ln) | Verdict |
|---|---|---|---|
| Wall-clock (s) | 414 / 364 / 379 — **median 379** | 377 / 391 / 455 — **median 391** | **no change** (12s apart; ranges overlap) |
| `gate plan` verdict | PASS ×3 | PASS ×3 | equal |
| Blast-radius recall | 3/3 files, all runs | 3/3 files, all runs | equal |
| Scenarios in intent.md | 12 / 11 / 13 — median 12 | 13 / 15 / 13 — median 13 | **new slightly better** |
| Seeded rate-limit topic found | 3/3 runs | 3/3 runs | equal |
| Artifacts emitted | 6 / 6 / 6 (spec, quickstart, evals + the 3 the gate reads) | 3 / 6 / 3 | **new better, not yet reliable** |

## Conclusions

1. **The prompt diet did not make Plan faster on this fixture.** Median 379s → 391s is
   noise. The wall-clock is dominated by the model's own exploration and artifact
   writing, not by reading the methodology doc. The ">10 minutes" figure in `intent.md`
   was a user report from full `/temper` runs on a real repo, never a measurement of
   this fixture — SC6's premise was never baselined, so its 4-minute target was set
   against a number that does not describe what was measured.
2. **The diet did not cost quality — it slightly improved it.** More scenarios, equal
   blast-radius recall, equal seeded-defect attention, at 20% the prompt length.
   That is the claim the cuts actually support.
3. **Artifact discipline improved but is not deterministic.** The old prompt reliably
   emitted 6 artifacts (3 the gate never reads); the new one emitted exactly 3 in 2 of
   3 runs. The v8 hardening of that rule landed after these runs and is still unverified
   live — the one open follow-up.

## What this means for the release

`faster pipeline` in the v8.0.0 headline is **not supported for the Plan stage** by this
measurement. The defensible speed claims are the structural ones: one fewer stage (Eval
removed) and Review+Check running in parallel instead of sequentially. The CHANGELOG was
corrected accordingly.
