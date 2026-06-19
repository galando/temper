# 04 — Implementation status (v5.6.0): verified

This chapter records the verification of what actually shipped, with the evidence used. The
implementation landed on `main` via PRs #50 (v5.3.0), #55 (v5.5.0), and #56 (v5.6.0); the
release is tagged **v5.6.0**.

> **Method:** static cross-reference of commands/reference/skills/packs/config against the
> plan, a live functional test of the secret-blocking hook, and the repo's own validation
> suites.

---

## Verdict

**v5.6.0 truly implements Phase 0, 1, and 2.** The core is well engineered — every hook
carries an explicit degradation contract, and telemetry honestly flags `estimated` vs
`measured`. One honest caveat on token measurement is noted below and expanded in ch. 07.

---

## Evidence table

| Plan item | Status | Evidence |
|---|---|---|
| **G-1** version consistency | ✅ | `plugin.json`, `CLAUDE.md`, `.cursor/VERSION` all `5.6.0`; `validate-plugin.sh` asserts it |
| **G-2** Cursor parity | ✅ | `.cursor/VERSION` = 5.6.0 (synced) |
| **G-3 / G-4** phase-scoped, manifest-driven pack loading | ✅ | `reference/review.md` & `build.md`: "read `.temper/pack-manifest.json`… keep only packs whose `phases` is `all` OR contains this stage" |
| **Phase 1** `/temper:eval` + LM-judge | ✅ | `commands/eval.md`, `reference/eval.md`, `skills/eval-judge/SKILL.md`, `templates/evalset.json` |
| **Phase 1** eval gate in orchestrator | ✅ | `temper.md`: EVAL subprocess, `eval_complete` stage, Eval→Build feedback loop |
| **Phase 1** deterministic hooks | ✅ | `packs/hooks/{rules.md,settings.hooks.json}`, `scripts/hooks/{block-secrets,block-forbidden-imports,verify-tests-ran,install}.sh` — **live test below** |
| **Phase 2** model routing | ✅ | `models:` block in `temper.config`; "Model Routing Resolution" in `temper.md` (tier→model map, `escalate-on`, `respect-user-override`) |
| **Phase 2** measured telemetry | ✅ | `observability.json` v2 schema in `orchestrator-patterns.md`; per-field `source` flags |
| **Phase 2** drift + economics panel | ✅ | `status.md` Economics panel: per-stage cost/latency/tier, eval-score trend, CapEx vs OpEx, drift flags |
| Repo self-validation | ✅ | `validate-plugin.sh` **30/0** (was 13), `validate-docs.sh` **6/0**, `validate-readme.sh` **5/0** |

---

## Live functional test — the secret-blocking hook

The one **fail-closed** path was tested directly:

```bash
$ echo '{"tool_input":{"content":"aws_secret_access_key=\"AKIAIOSFODNN7EXAMPLE…\""}}' \
    | bash scripts/hooks/block-secrets.sh
BLOCK: detected likely secret pattern: 'AKIAIOSFODNN7EXAMPLE'
Refusing commit/edit. Remove the secret or place it in an env var / secrets store.
$ echo "exit=$?"
exit=2          # exit 2 = blocked (deterministic, non-model)
```

The script's degradation contract is explicit and correct: **detected secret ⇒ exit 2**
(the only block path); no match / missing input / internal error ⇒ exit 0 (**fail-open** —
a script bug must never block a legitimate commit). Secret patterns are deliberately
conservative (vendor-specific formats) to avoid false-positive developer-workflow DoS.

The other hooks follow the same pattern:
- `block-forbidden-imports.sh` — denylist via `TEMPER_FORBIDDEN_IMPORTS`; **empty denylist =
  no-op**; explicit match ⇒ exit 2.
- `verify-tests-ran.sh` — blocks a commit only when `build-state.json` exists **and** stage
  isn't `check_complete`/`eval_complete`; missing state ⇒ fail-open (so it never blocks
  repos that don't run Temper).

---

## Honest caveat: token "measurement"

`observability.json` v2 is designed to record real per-stage tokens with
`source: measured`, falling back to `estimated` and flagging it. In practice, Claude Code
does not currently expose per-subagent token usage to the orchestrator, so values are
**usually `estimated`**. The source-flagging is the right, honest design — but the
leader-facing OpEx dashboard should be read as *directional, not billing-grade* until an
external usage source is wired in (ch. 07, gap #5).

---

## Capability inventory after v5.6.0

**Commands:** `temper`, `plan`, `design`, `build`, `review`, `check`, `eval`, `fix`,
`pack`, `status`.

**Skills:** `temper-core`, `context-engineering`, `source-driven-development`, `grill-me`,
`eval-judge`.

**Packs:** `quality`, `tdd`, `security`, `git`, `performance`, `api-design`,
`architecture-depth`, `adaptive-learning`, `hooks`, plus stack packs.

**Reference docs:** all command references + `orchestrator-patterns`, `learning`,
`tokenomics`, `pricing`, `eval`, `pack`, `plan-review`, `config-suggestions`,
`architecture-depth`.
