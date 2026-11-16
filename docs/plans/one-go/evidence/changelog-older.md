# Temper history, older half (v5.0.1 to v9.6.8): what was built, retired, and why "lean" never settled

Reader: planners who will not open the code again. Source tree: `/home/user/temper` at branch `pr115`
(9.8.5). All `CHANGELOG.md:N` citations are line numbers in that file at that commit.

## 0. Method and confidence labels

- **Read:** `CHANGELOG.md:1159-3027` in full (9.6.8 down to 5.0.1), plus `:810-975` (9.7.1 to 9.7.4) and
  `:200-217` (9.8.1) and `:976-1025` (head of 9.7.0) because deliverable 3 and the "later retired" column
  need them; `docs/history/README.md`, `docs/history/tokenomics.md`, `docs/history/pricing.md`,
  `docs/plans/v7-deterministic-spine.md`, `docs/decisions/0003`, `0006`, `0010`,
  `docs/evidence/opus5-plan-prompt-ab.md`, `docs/context-hygiene.md`.
- **Measured:** a scratch clone
  (`/tmp/claude-0/-home-user-temper/1ba4743b-465f-5ae6-8b88-a04ebb2fe840/scratchpad/work-changelog-older/repo`)
  and two scripts next to it, `measure.sh` and `cfgkeys.sh`, which read each release commit with
  `git ls-tree` / `git show` / `git cat-file -s`. In `/home/user/temper` only read-only commands were run
  (file reads, `grep`, `git log`, `git rev-parse`). HEAD there is `9a01eff`, the same commit as the clone.
  The repo has no tags; release commits were taken from `git log` subjects (for example `eed2513` = v7.0.0,
  `6b4d462` = v8.0.0, `896e576` = v9.0.0, `eaba313` = v9.6.0, `c8fc548` = v9.6.8, `9a01eff` = PR #115 head).
- **Labels used below:** `[measured]` = I counted it from a commit; `[code]` = verified in a file at HEAD;
  `[doc]` = only a claim in the changelog or a doc; `[inferred]` = my reading.
- **Limit:** git history starts at v5.8.0 (`55c2976`, 2026-06-23). Everything said about 5.0.1 to 5.7.0 is
  `[doc]` only.
- **"Prompt surface" as measured here** = bytes of every `*.md` under `commands/`, `agents/`, `skills/`,
  `packs/`, `reference/` at the commit. It is the whole shipped surface, not what one run loads
  (`/temper:pack` and `/temper:init` pages, for example, are not read in a `/temper` run). The v8 changelog's
  own figure excludes `packs/`: my v7.0.0 number minus packs is 372,967 bytes, exactly the changelog's
  (`CHANGELOG.md:2363`), so the two measures agree.

---

## 1. Systems built and later retired

Dates are commit dates. "Life" is from the release that added it to the release that removed it.

| # | System | Added | Removed | Life | What it was | Why it went | Lesson for the plan (do not propose again) |
|---|---|---|---|---|---|---|---|
| 1 | **Eval stage** (LM-judge score between Check and Commit) | v5.5.0 `CHANGELOG.md:2898-2905` | v8.0.0 (2026-08-04) `:2353-2360` | 3 majors | A 7th stage: agent, command, 232-line reference, `eval-judge` skill, `evalset.json`, config block, score table, Eval to Build loop. Extra readability work shipped for it unreleased (`:2863-2891`). | "No other gate consumed it, no feedback loop acted on it, and in practice the score was read and ignored" (`docs/decisions/0003:15-16`); name collision with `evals/`; counted against the 35% prompt cut (`0003:21-22`). | No model-judged score inside or beside a gate (`0003:56-59`). A stage whose output nothing consumes is pure cost. Delete, do not disable: "A disabled stage is still a stage the reader has to understand and the maintainer has to keep passing CI" (`0003:50-52`). |
| 2 | **`evals/` seeded-defect fixtures + nightly workflow** | v7.0.0 (07-20) `:2542-2546`, wiring smoke `:2648-2663` | v9.5.0 (10-03) `:1981-1986` | 75 days | Three fixture projects + a wiring smoke run through `claude -p` in CI; README badge "catch rate 3/3" (`docs/plans/v7-deterministic-spine.md:226-227`). Took two further "passes" inside v7 (the fourth and fifth) to make its own "caught" signal honest (`:2577-2636`). | "Its job needed a repository setting that was never made, so the latest nightly run concluded `skipped`, and it never gated a merge" (`:1981-1983`; `docs/decisions/0010:9-13`). | A behaviour suite that needs a secret or a repo setting will not run. ADR 0010's own rule: "A future one should run in CI with nothing to configure, or run on demand only" (`0010:43-44`). Consequence still open: since 9.5.0 "Temper has no behavioral regression suite for its own prompts" (`0010:43`). |
| 3 | **Model routing tables** (`models.routing`, `models.tiers`, `escalate-on`, `drift-threshold`) | v5.6.0 `:2818-2830` | v7.0.0 `:2475-2478`, `:2501-2503` | about 1 month | Config-driven tier per stage, resolved by a "Model Routing Resolution" algorithm written in the orchestrator prompt. | "a resolution algorithm a prompt had to execute correctly on every run" (`docs/history/tokenomics.md:31-33`). | Model choice is a lookup in code. What survived: `model:` frontmatter per brief + a flat `models.{stage}` override resolved by `temper model` (`:2439-2446`). No tiers, no escalation rules in prose. |
| 4 | **Observability / economics** (`observability.json` v2/v3, `cost_usd`, price table, ECONOMICS panel) | v5.6.0 `:2832-2851` | v7.0.0 `:2490-2492`, `:2501-2504` | about 1 month | Per-stage tokens, latency, cost from a price table, rolling averages, CapEx/OpEx panel in `/temper:status`. | The numbers were "at best, a plausible guess derived from a price table, never a measured, mechanically-verified number" (`docs/history/pricing.md:8-10`). | Do not estimate cost in the product from a price table. (A second attempt in 9.7.0 read Claude Code's transcripts for real tokens and cost and was removed in 9.7.2 and 9.7.4 for the plugin directory: `:929-938`, `:823-831`. See section 3.) |
| 5 | **Drift detection v1** (`stage_baseline`, `drift_flags[]`) | v5.6.0 `:2841-2845` | v7.0.0 `:2501-2504` | about 1 month | Std-dev flags on per-stage cost and latency, never blocking. | Went with observability. | It came back in code as `temper bands` in v9.0.0 (`:2300-2303`) and is still shipped (7 config keys, `scripts/bands.py`, `scripts/temper:4904` `[code]`). No changelog entry after v9.0 shows it used. Candidate for removal, not for a third design. |
| 6 | **Token levers** (`tokens.cache`, `tokens.adaptive-depth`, `tokens.loops`) | v5.9.0 (06-24) `:2730-2754` | v7.0.0 (07-20) `:2501-2503` | 26 days | (a) read static context first to help the prompt cache; (b) a reduced pipeline by complexity tier with an "Escalate" option; (c) inline / fix-mode / full re-launch loop tiers. Each default-on with a "byte-identical when off" contract (`:2756-2760`). | "~9,000 lines of prompt describing an algorithm an LLM had to execute correctly on every run" (`tokenomics.md:13-17`); cache hints "the API layer never promised to honor" (`tokenomics.md:16-17`); adaptive depth "traded a small saving for a weaker plan gate" (`tokenomics.md:25`). | Two different lessons. (i) Never put a cost-saving *algorithm* in a prompt. (ii) The *needs* behind (b) and (c) were real and came back in code: trivial requests skip Intent (`:2295`), "small changes" (9.7.5 title, `:698`), a fix pass of Build on a loop back (`:1010`), and the unbuilt ADR 0017 "lighter route". A plan may scale depth by request, but only as a CLI decision, and it must say what it does to the plan gate. |
| 7 | **Nested subagent depth budget** (`agents.nested`, `max-depth`, `parallel-width`) | v5.1.0 `:3001-3013` | v7.0.0 `:2484-2486`; dangling prose until v9.2.0 `:2164-2168` | about 2 months (+6 weeks of dead text) | Stages got a `depth_remaining` budget to decide spawn or inline. | Config collapse in v7; three reference pages still branched on a budget "no launch prompt passes" two majors later. | Removing a mechanism leaves prose behind unless a check fails on it. A removal needs a grep-style guard, as v8 added for the TOKENOMICS block (`:2418-2419`). |
| 8 | **`capabilities.*` toggles** (Grill Me, Teach Me, HTML review, architecture depth, evals) | through v5.x, e.g. `:2804-2805` | v7.0.0 `:2484-2489` | n/a | One flag per optional feature. | "always offered at their gates; there's no toggle to turn them off, just don't pick them" (`:2487-2489`). | The toggles went, the options stayed: every Intent and Plan question still carries Grill Me, Teach Me, HTML review or Share (`scripts/flow.py:632-683` `[code]`). The cost moved from config to the question the person reads. |
| 9 | **Adaptive learning / learning state** (`learning.json`, `packs/adaptive-learning/`, `reference/learning.md`, suggestion queue, learning curve) | ADR 0001 dated 2026-05-14 (`docs/decisions/0001:4`) | v9.0.0 (08-24) `:2268-2272`, `:2319-2323` | about 3 months | A second finding memory running the same promote/suppress thresholds as `review-memory.json`. | "Two systems remembered the same thing. Every review updated both" (`docs/decisions/0006:21-22`). It was split out only for a "zero breaking changes" constraint (`0006:23-25`). | One store per fact. A compatibility promise is how the duplicate got built; do not make such promises. |
| 10 | **OCR external review engine** | v5.2.0, default `auto` `:2975-2997` | not removed. v9.0.0 moved behind a probe (`:2327-2329`); 9.6.5 made it off by default (`:1555-1557`) | still shipped | Optional `ocr` CLI does line-level defect detection in Review. | Off by default because it sends the diff to another model provider (directory "credentials" note). | Still costs prompt: about 22 lines in `reference/review.md:44-65` `[code]` are read by every Review agent for a default-off feature. Either delete or move behind its own page. |
| 11 | **Cursor export** (`.cursor/`, two generator scripts) | before 5.x; frozen at v5.1 in v5.2.1 `:2971` | archived v7.0.0 `:2508-2510`; removed v8.0.0 `:2380-2382` | n/a | A second platform's copy of the commands and rules, regenerated every release. | "A generator bug had silently frozen it at v6.0.1, three major versions behind; shipping it misrepresented what Cursor users got" (`:2380-2382`). | No second host until the first is cheap and stable. |
| 12 | **Pack manifest cache** (`.temper/pack-manifest.json`) | documented v5.3.0 as done `:2944-2947` | removed *from the docs* v8.0.0 `:2378-2379` | never existed | A cache that pack loading was said to consult. | "documented-but-never-written" (`:2378`). Same release found pack `phases:` had never been declared by any built-in pack (`:2420-2422`), though v5.3.0 said the benefit "is now realized" (`:2942-2943`). | Two efficiency features were reported as shipped for three majors and did nothing. A saving that is not measured cannot be assumed to exist. |
| 13 | **Byte-identity "degradation contracts"** + `validate-phase2.sh` / `validate-phase3.sh` | v5.6.0 `:2829-2830`, `:2856-2858`; v5.9.0 `:2756-2760`, `:2767` | v7.0.0 `:2501-2506` | about 1 month | Every new lever promised "byte-identical to the previous version when off", with a validator per phase. | They were "promises that no prompt can actually keep" (`docs/plans/v7-deterministic-spine.md:19-20`). | Do not carry an off-switch plus an equivalence promise for a new feature. Ship it or do not. |
| 14 | **TOKENOMICS block in `CLAUDE.md`** | before v7 | v8.0.0 `:2415-2419` | n/a | Generated standing advice ("prefer Sonnet", "run /compact after turn 28") injected into every session. | "a saving smaller than the block describing it" (`:2416-2417`). | Advice text is not a saving. |
| 15 | **Parallel Review + Check** | built during v8 | reverted before v8.0.0 shipped `:2372-2375` | never released | Launch the two stages together. | "it left Check's results stale when a human requested changes at the Review gate" (`:2373-2375`). | Parallel stages are safe only if no person can change the tree between them. The fix is one decision point after both, not two gates. Since PR #115 Check can reuse a passing run "on the same tree" (commit `28fff04`), which is the condition that makes this safe to revisit. |
| 16 | **Standalone stage commands with their own flow** | v5.x to v7 | hook pair added v8.0.0 `:2384-2406`; made "doors into `/temper`" in 9.7.0 `:989` | n/a | `/temper:plan`, `:build`, `:review`, `:check` each ran their stage inline with their own steps. | v7's third pass found they "never recorded evidence or ran gates at all" (`:2547-2551`); v8 found the spine was invoked in "1 of 3 live runs" (`:2386-2388`). | Two entry paths means two things to keep correct. One flow. Already a project rule (`.claude/CLAUDE.md`, "never give a stage command a flow of its own"). |
| 17 | **`stages.subprocess`** config key | v9.1.0 (08-24) `:2235-2240` | inert since 9.7.0 (10-15) (`docs/context-hygiene.md:56-57`) | 52 days | Run standalone stage commands in the isolated subprocess. | Doors made it moot. | A key added to choose between two modes is a sign the default is wrong. |
| 18 | **Per-task Build checkpoints** (one task, then a Continue/Change/Stop question, a commit per green scenario) | v9.4.0 (09-30) `:2022-2026` | 9.7.0 (10-15): "Per task Build and `build.mode` are removed" `:1009-1010` | 15 days | One question to the person per task. | Replaced by grouped Build: "a person reviews each group once" (`:1008`). | Never a question per unit of work. The requirement row it added, `checkpoint feedback answered`, is still in the build gate (`scripts/temper:3685-3689` `[code]`). |
| 19 | **The 9.6.0 mod as a second controller**: a bar with keys 1 to 3, 9, 0; 19 reserved `/temper` words; "mirror" prompts; an event store; a shell parser; a first-run mode question | v9.6.0 (10-05) `:1708-1723`, `:1744-1757` | 9.7.0 (10-15) `:986-996`, `:998-1003`; last button 9.7.3 (10-21) `:886-895` | 10 to 16 days | The mod kept its own run state and decided moves from button presses, then asked Claude to mirror them in the CLI. | A bug class of its own: "Continue to Review moved the bar but the mirror call was refused" (`:1764-1766`); four security reviews in one release (`:1758-1763`, `:1796-1803`, `:1848-1887`). 9.7.0: "The CLI is the only run state" (`:986`); mod 6,092 lines to 3,224 (`:1002-1003` `[doc]`; my count 7,319 to 3,562 lines of `hooks/**/*.ts(x)` `[measured]`). Reserved words 19 to 7 (`hooks/temper-mod/core/commands.ts:6` `[code]`). | One state, one decider. A second view must never hold state or decide. Already a project rule. |
| 20 | **Temper Run game**, **demo folder**, **bundled images/icon** | game 9.6.0 `:1724-1736`; demo 9.6.0 `:1804-1806`; icon 9.3.2 `:2111` | game 9.7.0 `:1002`; demo 9.6.1 `:1686-1688`; icon out 9.6.5 `:1548-1550`, in 9.6.6 `:1377-1379`, out 9.6.7 `:1239-1244`, in 9.8.1 `:216` | 10 days; same day; four flips | A dinosaur-style game "for the time Claude works"; a demo project; listing art. | Game: removed with the mod rewrite. Demo and images: directory holds. | The game existed because a run makes the person wait. The plan should remove the wait, not entertain it. |
| 21 | **Second plan-review sharing path** (a link through another CLI's login) | v9.5.0 (10-03) `:1956-1957` | 9.6.5 (10-06) `:1554-1555`; `docs/decisions/0010:48-53` | 3 days | Fallback share without the Artifact tool. | Directory "credentials" note. | One path per feature. |
| 22 | **Guard settings merge** (`guard-entries.py`, `/temper:pack enable guardrails` writes settings) | 9.6.5 (10-06) `:1513-1527` | 9.7.3 (10-21) `:868-874` | 15 days | The pack wrote its hook entries into the project's settings file. | Directory read it as reading a file that may hold credentials. | Now prints a snippet for the person to paste. A setup step moved from the tool to the person. |
| 23 | **Templates `spec.md`, `quickstart.md`** | before v8 | v9.0.0 `:2273-2274` | n/a | Extra plan artifacts. | "the documented three-artifact rule forbids them". The old Plan prompt "always wrote 6" files, three of which no gate read (`docs/evidence/opus5-plan-prompt-ab.md:54-55`). | Artifacts no gate reads are written by Opus at output-token price. Count required output, not only prompt input. |

**Pattern across the table `[inferred]`.** Of 23 systems, seven lived 26 days or less or never shipped (rows 6,
15, 18, 19, 20, 21, 22). Removal always had one of three triggers: the thing was already dead (1, 2, 12),
it duplicated something (9, 16, 19), or an outside party forced it (20 to 22). No row was removed because it
cost the person time or money in a run.

---

## 2. Earlier efficiency releases: claim, measurement, did it last

| Release | What it did | Saving it claimed | Measured? | Did it last? |
|---|---|---|---|---|
| **v5.0.1 Token optimization** `CHANGELOG.md:3015-3027` | Moved repeated schemas and gate prose into `reference/orchestrator-patterns.md`; "single-load contract"; Progressive Loading Maps in `plan.md` and `review.md`; trimmed `CLAUDE.md`. | None stated. | No `[doc]`. | No. By v6.0.1 `commands/temper.md` was 1,353 lines and the surface 499,229 bytes `[measured, 8bdae11]`. `orchestrator-patterns.md` itself reached 979 lines (`:2479-2480`). The loading maps were defended in v7 as "themselves a token-efficiency mechanism" (`:2572-2573`) and cut in v8 with the rest (`plan.md` 1,086 to 224 lines, `:2363-2364`). |
| **v5.3.0** (not titled efficiency, but claims one) `:2940-2947` | Phase-scoped pack loading and a manifest cache "wired in". | "The promised token/scoping benefit is now realized". | No. | It was not real. v8: "No built-in pack had ever declared one, so every enabled pack loaded into all five stages regardless" (`:2420-2422`); the cache was "documented-but-never-written" (`:2378`). |
| **v5.6.0 Harness economics** `:2812-2861` | Enforced model routing (Opus plan/design, Sonnet build, Haiku review/check/eval), telemetry, cost, drift, economics panel. | No number. Claim: "Routing stops being advisory; observability stops being self-estimated" (`:2815-2816`). | No. v7 called its numbers "estimates with no mechanical backing" (`:2490-2491`). | Mechanism deleted in v7 (rows 3 to 5 above). The *assignment* lasted in part: Opus for Plan and Design is still the default and is now 45% to 83% of a run's cost (given, `docs/evidence/bench-2026-11.md`). Haiku for Review and Check was reversed in v8 (`:2361-2362`). |
| **v5.9.0 Token efficiency & loop engineering** `:2724-2767` | Cache read ordering, adaptive depth, loop cost tiers. | No number. | No. Only a `cached_input` field labelled measured or estimated (`:2735-2736`). | Deleted 26 days later in v7 (row 6). |
| **v7.0.0 prompt diet** `:2479-2489` | `commands/temper.md` 1,353 to 363 lines; `orchestrator-patterns.md` 979 to 327; config 211 to about 55 lines. Target `reference/` 10,700 to 1,500 lines. | Line counts. `docs/history/tokenomics.md:24` says "the plugin's own prompts are ~85% smaller". | Lines only. The 1,500-line target was missed and disclosed: `reference/` stayed at about 6,500 lines (`:2532-2538`). | The 85% figure is false `[measured]`: whole surface v6.0.1 to v7.0.0 went 499,229 to 407,649 bytes (−18%), 11,076 to 9,512 lines (−14%). `temper.md` then went 365 (v7), 318 (v8), 433 (v9.0), 467 (9.6.0), 591 (9.6.8), 168 (9.7.0), 215 lines (now) `[measured]`. Config template: 60 lines at v7, 171 now `[measured]`. |
| **v8.0.0 shorter prompts** `:2346-2446` | Outcome briefs; Eval stage removed; pack `phases:` made real; `tdd` pack 207 to 69 lines. | Surface −43.7% (372,967 to 209,863 bytes). Plan run $1.74 median against $3.37 (−48%). "It is not faster — 384s vs 388s" (`:2363-2369`). | **Yes, the only one.** Controlled A/B, 6 runs per arm for behaviour, 3 per arm for cost, one fixture, Plan stage only (`docs/evidence/opus5-plan-prompt-ab.md:3-6`, `:13-18`, `:35`). | Bytes: confirmed at release (my v8.0.0 figure without packs is 211,707, within 1%). Not held: `reference/plan.md` 11,947 bytes at v8, 27,927 now; `agents/plan.md` 1,793 to 11,905. The Plan stage's two pages together are 39.8 KB now against 13.7 KB at v8 and 46.8 KB before the diet `[measured]`. Whether the −48% cost held was never measured again. |
| **v9.0.0** (claims a cut) `:2251-2253` | Removed adaptive learning, dieted `reference/fix.md` 517 to 143 lines. | "Net prompt-surface change from the simplification alone: −9.2% (266KB to 242KB)". | Bytes of the removals only. | The release as shipped was *larger* than v8: 244,711 to 251,768 bytes (+2.9%) `[measured, 6b4d462 vs 896e576]`, because it also added the Intent stage, a command, hooks and `bands`. It also added one agent launch and one mandatory human gate to every non-trivial run (`:2258-2261`) with no measurement of what that costs or saves. |
| **v9.1.0 "the token-efficiency release"** `:2201-2244` | `commands/fix.md` 22.9 KB to 7.1 KB; briefs carry their own return box so a subprocess never reads the 21 KB orchestrator; `reference/review.md` 19.6 KB to 13.6 KB; autonomy text loads on opt-in. | −69% main context on `/temper:fix`; −31% on `review.md`. | Bytes only, and it says so: "this pass has no controlled A/B behind it yet — the eval fixtures are the regression net" (`:2229-2230`). | File sizes confirmed `[measured]` (22,877 to 7,165; 19,588 to 13,708). Whole surface −4.2% (251,768 to 241,277). The "regression net" it relied on had never gated a merge and was deleted two releases later (`:1981-1983`). `reference/review.md` is 17,159 bytes now. |
| **v9.2.0 prompt audit** `:2157-2199` | Removed dated patterns: dangling budgets, numeric clamps, a self-filter instruction, version narrative. | None; "Prompt surface only" (`:2159`). | No. "191 CLI assertions and every validator green" checks structure, not behaviour. | −1.5% (241,277 to 237,680 bytes), the all-time low. One month later (9.5.0, 10-03) the surface was 272,671 (+15%); at 9.6.5 (10-06) it was 372,834 (+57%) `[measured]`. |

**Prompt surface over time `[measured]`** (bytes of `*.md` in the five prompt folders; words in brackets):

| v6.0.1 | v7.0.0 | v8.0.0 | v9.0.0 | v9.2.0 | v9.5.0 | v9.6.0 | v9.6.5 | v9.6.8 | v9.7.0 | v9.8.4 (main) | v9.8.5 (PR) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 499,229 (61.9k) | 407,649 (51.4k) | 244,711 (32.4k) | 251,768 (33.9k) | 237,680 (32.6k) | 272,671 | 286,202 (40.2k) | 372,834 | 385,111 (54.6k) | 338,229 (49.2k) | 379,596 | 387,370 (57.7k) |

So after four diets the shipped prompt surface is 95% of v7.0.0's bytes and 112% of its words, and 63% above
the 9.2.0 low.

**The one finding that should have redirected the work and did not `[doc + inferred]`.** The v8 A/B concluded:
"The diet does not make Plan faster... Wall-clock is dominated by the model exploring the repo and writing
artifacts, not by reading the methodology doc" (`docs/evidence/opus5-plan-prompt-ab.md:42-44`), and withdrew
"faster pipeline" from the headline (`:77-79`). Median Plan output was 24,617 tokens (`:18`). The November
bench reports Plan writing "about 25,000 tokens" (`docs/evidence/bench-2026-11.md:457-458`). Output volume
did not move in three months, and 9.1.0 and 9.2.0 went on cutting input bytes. No release in this range set
out to reduce what the agents *write*, how many agents are launched, or how many questions are asked.

---

## 3. Release effort spent on the plugin directory and host changes

Classification: a release is "directory" when its own headline says it answers the directory's validation
or holds. `[measured]` with a script over `CHANGELOG.md` (lines starting `- `, `**` or `N. ` at column 0
counted as entries).

| Block | Releases | Dates | Changelog lines | Top-level entries | Words |
|---|---|---|---|---|---|
| 9.3.1 to 9.3.5 `:2072-2133` | 5 | 09-26 to 09-29 | 62 | 12 | 463 |
| 9.6.1 to 9.6.7 `:1186-1692` | 7 | 10-05 to 10-07 | 507 | 86 | 6,886 |
| 9.7.1 to 9.7.4 `:810-975` | 4 | 10-18 to 10-21 | 166 | 29 | 2,353 |
| **Sum** | **16** | | 735 | **127** | 9,702 |
| All v9 releases, 9.0.0 to 9.8.5 | 33 | 08-24 to 11-15 | 2,340 | 488 | 32,765 |
| **Share of v9** | **48%** | | 31% | **26%** | 30% |
| Share inside 9.0.0 to 9.6.8 only | 12 of 20 = 60% | | | 98 of 208 = 47% | 7,349 of 14,277 = 51% |

Not counted above but the same kind: 9.8.1 (`:200-217`, 4 entries), v6.0.1 "in preparation for
plugin-directory submission" (`:2687-2688`), and the submission kit in v7.0.1 (`:2450`). With 9.8.1 the count
is 17 of 33 releases.

Caveats, so the share is not over-read:
- 9.6.5 is the largest directory release (35 entries) and also fixed real defects found on the way: a crafted
  stage name "could overwrite a file outside `.temper/`" (`:1438-1441`), two Python code injections
  (`:1452-1454`), a staged secret that blocked its own unstaging (`:1478-1481`), a formatter that ran shell
  text from a file name (`:1482-1483`).
- 9.6.7 spent part of its length repairing 9.6.x's own regressions: the run report could not be read after a
  commit (`:1246-1256`), the installer wrote over lefthook's hook (`:1258-1269`), four behaviour changes of
  9.6.5 had gone unsaid (`:1271-1276`), a Python 3.9-only call (`:1278-1279`).

**What the holds changed in the product, against the owner's goal:**

| Change | Where | Effect on time, cost or ease |
|---|---|---|
| Every prompt names the CLI by the full braced plugin path | 9.6.5 `:1417-1431` | Surface +30% in one release: 286,202 to 372,834 bytes; `CLAUDE_PLUGIN_ROOT` occurrences in prompts 111 to 526 (359 at HEAD); `commands/pack.md` 4.0 to 19.6 KB, `commands/temper.md` 28.1 to 39.7 KB `[measured, c4b892b vs 3f7df41]`. Partly a host limit, not only policy: "the Bash tool does not set that variable" (`:1418-1419`). |
| Cost reading removed | 9.7.2 `:929-938` | `scripts/usage_cost.py` deleted; reports show "no cost". |
| Token counts removed | 9.7.4 `:823-831` | "Temper records the time only now." The product cannot show what a run cost. |
| The mod's last button and its mode commands removed | 9.7.3 `:886-895` | "The bar has no button; you type `/temper:temper` to take a run up again." |
| Guardrails setup no longer written for the person | 9.7.3 `:868-874` | The person pastes hook entries by hand. |
| No file over 256 KiB | 9.6.6 `:1293-1295`, 9.7.1 `:968-972` | The test file and then the CLI were split for size, not for design. |
| Path-spelling rules 9 to 13 in `scripts/validate-directory.sh` | 9.6.6 `:1319-1324`, 9.6.7 `:1211-1230`, 9.7.2 `:918-922`, 9.7.3 `:855-856` | Fixture folders may not be named `tests`, `hooks`, `core`, `ui`, `mod`; every contributor and every agent must know this. |

**Outcome so far `[doc]`.** 9.8.1 opens: "The plugin directory refused 9.8.0. These changes answer its findings
that apply to every publisher; the rest (hooks, mods and scripts) it accepts only from Verified organizations"
(`CHANGELOG.md:202-203`). I could not determine from the files I read whether Temper is listed today.

**Host changes** (not directory): v6.0.1 layout move (`:2687-2694`); v8 and v9.2.0 rewrites for a new model
generation (`:2348-2351`, `:2160-2162`); v9.6.0 built on Claude Code mods and pinned a minimum version
(`:1933-1938`). The mod then drove 9.6.1 to 9.6.7 and much of 9.7.1 to 9.7.4, since most holds were about the mod.

---

## 4. The product's shape over time `[measured]`

Counts from the release commit. "Stages" is the CLI's `STAGES` variable. "Config keys read" is a lower bound:
distinct dotted keys passed to `_cfg_get`, `.cfg("...")` or `config get` in non-test code (keys read only by
prompts, such as `phases.design` or `setup.*`, are not caught).

| | v7.0.0 (07-20) | v8.0.0 (08-04) | v9.0.0 (08-24) | v9.6.0 (10-05) | now, PR #115 (11-15) | Trend |
|---|---|---|---|---|---|---|
| Stages in the CLI | 6 + commit (plan, design, build, review, check, eval) | 5 + commit | 6 + commit (+intent) | 6 + commit | 7 + commit (+pipeline) (`scripts/temper:104`) | up |
| Stage briefs in `agents/` | 6 | 5 | 6 | 8 | 13 (adds build-task, plan-review, pipeline, acceptance, env) | up 2.2x |
| Commands | 11 | 10 | 11 | 11 | 11 | flat |
| Skills | 6 | 5 | 5 | 5 | 5 | flat |
| Packs (folders) | 10 | 10 | 9 | 9 | 9 | flat |
| Config template lines | 60 | 68 | 98 | 121 | 171 | up 2.9x |
| Config keys read by code (lower bound) | 7 | 6 | 15 | 18 | 38 | up 5.4x |
| Plugin settings (`userConfig`) | 0 | 0 | 0 | 7 | 5 | new surface |
| Gate requirement labels in `scripts/temper` (lower bound; Python emitters not counted) | 13 | 11 | 18 | 26 | 32 | up 2.5x |
| `scripts/temper` lines | 901 | 1,026 | 1,487 | 2,280 | 5,121 | up 5.7x |
| `scripts/flow.py` lines | 0 | 0 | 0 | 0 | 3,111 | new |
| All non-test script lines / files | 2,447 / 13 | 2,511 / 14 | 3,259 / 18 | 5,120 / 25 | 21,728 / 70 | up 8.9x |
| Test lines (`scripts/selftest`, `scripts/tests`, `scripts/e2e`, `tests/`) | 254 | 531 | 1,067 | 11,367 | 39,601 | up 156x |
| Mod lines / files (`hooks/**/*.ts(x)`) | 0 | 0 | 0 | 6,834 / 28 | 4,984 / 26 | new; peaked 7,319 at 9.6.8 |
| Prompt surface bytes | 407,649 | 244,711 | 251,768 | 286,202 | 387,370 | down then back |
| ADRs | 2 | 5 | 6 | 8 | 16 | up |
| `CHANGELOG.md` lines | 582 | 688 | 788 | 1,345 | 3,027 | up 5.2x |

Reading: the *user-typed* surface (commands, skills, packs) is flat. Everything a run does or a person must
understand grew: stages, agents launched, config, gate rows, code. v8 is the only release in which stages,
agents, commands, skills and the prompt surface all shrank together. The v7 plan's own targets were a "~20-line config" (`docs/plans/v7-deterministic-spine.md:154`),
"~1,500 lines" of prompt (`:41`, `:180`), gate functions of "~30 lines of shell a user can read in one sitting"
(`:101-102`) and "a newcomer can read the entire plugin end-to-end in ~20 minutes" (`:191-192`). None holds
today.

---

## 5. Why "make it lean" did not settle, and what "once and for all" must do differently

### 5.1 Why not `[inferred from the evidence above]`

1. **Wrong unit.** Seven releases carried an efficiency headline (5.0.1, 5.6.0, 5.9.0, 7.0.0, 8.0.0, 9.1.0,
   9.2.0; the last on 2026-09-02, the first before the git history starts). Six measured bytes or lines or
   nothing. The one that measured dollars and seconds
   (v8) found that seconds did not move and said why (`opus5-plan-prompt-ab.md:42-44`). The owner's units
   (seconds, dollars, questions, launches, loop backs) were never a target of any release in this range.
2. **Cut input, never output or launches.** All diets shortened what agents read. Cost and time sit in what
   Opus writes and how many agents run (given bench; `opus5-plan-prompt-ab.md:22-24`). Meanwhile the required
   output grew: stable `AC-NN` ids with `Why:` / `Validate:` / `Covers:` and ten new Intent gate rows (9.4.0,
   `CHANGELOG.md:1992-1999`, `:2007-2010`), gherkin fences and a cross-repo search section (`:2017-2021`), an
   `Out of scope:` line and a soft-word ban (9.6.0, `:1907-1927`).
3. **No cap, so every cut was refilled.** Nothing fails when the surface, the agent count, the config or the
   question count grows. v8's cut was 163 KB; the surface has since regained 143 KB (table in section 2).
4. **A one-way ratchet on faults.** Each observed fault was answered with a new row, hook, key or agent.
   9.4.0's own format shows it: "What broke / Root cause / Nothing failed because / Fix" (`:2038-2070`).
   Gate labels went 13 to 32, agents 6 to 13. No fault in this range was answered by removing the step that
   failed.
5. **Removal only of the dead.** See the pattern under section 1. When speed met rigor, rigor won without a
   number on either side: adaptive depth went because it "traded a small saving for a weaker plan gate"
   (`tokenomics.md:25`), the size of the saving and of the weakening both unmeasured.
6. **No standing meter and no behaviour net.** Cost telemetry: built v5.6, deleted v7 as unbacked, rebuilt
   9.7.0, deleted 9.7.2 and 9.7.4 for the directory. Behaviour suite: built v7, deleted 9.5.0 without ever
   gating a merge. For most of the product's life a "lean" claim could not be checked and a regression in
   cost could not be seen.
7. **v7 settled where logic lives, not how much of it there is.** The rule "No feature ships in prompt-space
   if it has exactly one correct output" (`CHANGELOG.md:2457-2459`) is about trust. The v7 plan kept the flow
   "unchanged on the surface" (`v7-deterministic-spine.md:57-60`) and parked "new stages, any new config flag"
   as "noise until the spine is deterministic" (`:286-290`). Once it was, they arrived: Intent (v9.0), per-task
   checkpoints (9.4.0), the mod (9.6.0), Pipeline (9.7.5). Moving a rule into code made it cheap to add rules.
8. **Half the release train answered an outside party** (section 3), and several answers worked against the
   goal (longer prompts, no cost figure, no button).

### 5.2 What a "once and for all" plan has to do differently

1. **State the target in run units against the vanilla baseline, and make it a release gate.** For example:
   a clear feature within N times vanilla's dollars and seconds, at most Q questions, at most L launches, zero
   loop backs on a clean task. Run it on demand before a release, with nothing to configure (the ADR 0010
   condition, `0010:43-44`); never as a nightly job that needs a secret.
2. **Reduce what a run does, not what its pages say:** fewer agent launches, less Opus output, fewer
   questions. Treat prompt bytes as a secondary number.
3. **Put fixed caps in CI** on the things in section 4 (agents launched in a default run, required artifact
   sections, gate rows, config keys, per-run prompt bytes) so an addition needs a removal in the same change.
4. **Scale depth by request in the CLI** (the need behind 5.9.0's adaptive depth and ADR 0017, whose status
   is "Proposed (a draft; nothing of it is built)", `docs/decisions/0017:3`), and state for each route which
   gate rows still hold, so the v7 objection is answered with facts.
5. **A removal-first rule for faults:** before adding a check for a fault, show that the failing step cannot
   be removed or merged; an added row, agent or question must show its cost on the bench.
6. **Decide the directory once, in an ADR.** If it stays a goal, its rules are design inputs from day one
   (section 6, item 11). If not, delete spelling rules 9 to 13 and the path text that 9.6.5 forced, where the
   host does not need it.
7. **Delete, do not disable** (ADR 0003's argument), and guard each deletion with a check so the prose does
   not linger (row 7).

### 5.3 Do not propose again

Cache-ordering hints; routing, depth or loop-tier logic in a prompt; a cost estimate from a price table inside
the product; reading Claude Code transcripts or settings from the plugin; an LM-judge score as a gate; a second
memory or state store; a second controller beside the CLI; a question per task; parallel stages with separate
human gates; a config toggle per optional feature; "byte-identical when off" promises; a second host export; a
nightly model-driven CI suite; another prompt diet presented as the efficiency plan.

---

## 6. Constraints any redesign must keep (with source)

1. Gate verdicts are computed by code from an evidence ledger, never asserted by a model
   (`CHANGELOG.md:2457-2468`; `docs/plans/v7-deterministic-spine.md:32-36`; `.claude/CLAUDE.md`).
2. `git commit` is blocked while a gate is FAIL and unoverridden; a person may always override, and the
   override is recorded (`CHANGELOG.md:2465-2474`; `v7-deterministic-spine.md:113-115`).
3. Autonomy is armed only at the last question before Build, never at invocation, and never commits, pushes
   or merges (`CHANGELOG.md:2493-2497`; `.claude/CLAUDE.md`).
4. Hooks fail open except on their one detected-violation path (`CHANGELOG.md:2396-2397`; `.claude/CLAUDE.md`).
5. A stage brief is self-contained, return box included; a clean-context subprocess is never pointed at an
   orchestrator file (`CHANGELOG.md:2215-2222`; `.claude/CLAUDE.md`).
6. Evidence is cleared when a stage is redone (`CHANGELOG.md:2370-2372`).
7. No model-judged score decides a gate (`docs/decisions/0003:56-59`).
8. One finding memory, `review-memory.json` (`docs/decisions/0006:29`).
9. Nothing is published without the person confirming where it goes (`docs/decisions/0010:32`).
10. The person decides only in the question dialog; the mod holds no state of its own and has no deciding
    button; stage commands are doors into `/temper` (`CHANGELOG.md:986-989`; `.claude/CLAUDE.md`).
11. If the directory stays a goal: no non-image file over 256 KiB (`:968-972`); the mod writes no file
    (`:1641-1646`), runs no command and sets no setting (`:886-895`); nothing reads Claude Code's files,
    settings, transcripts or the git identity (`:929-938`, `:866-880`); no token count or
    credential-looking name (`:823-831`); plugin paths are fixed text after the braced root (`:1409-1411`,
    `:1421-1424`); script and fixture paths avoid folders named `hooks`, `tests`, `mod`, `core`, `ui`
    (`:918-920`); `userConfig` declares no `options` (`:1936-1938`).
12. Model defaults live in brief frontmatter with a flat `models.{stage}` override resolved in the CLI
    (`CHANGELOG.md:2439-2446`).
13. A stale config key or state key from an older version must be inert, not an error
    (`docs/decisions/0003:35-39`).
14. The plugin still loads and runs its prompt-based stages on a Claude Code without mods
    (`CHANGELOG.md:1933-1935`).

---

## 7. Where a doc and the tree disagree

| Doc claim | What the tree shows |
|---|---|
| `docs/history/tokenomics.md:24`: after v7 "the plugin's own prompts are ~85% smaller". `v7-deterministic-spine.md:171`: "deleting 9k lines". | v6.0.1 to v7.0.0: −18% bytes, −1,564 lines `[measured]`. The 85% was the plan's target; v7's changelog itself discloses the miss (`CHANGELOG.md:2532-2538`). Even v8.0.0 was −51% against v6.0.1. |
| `CHANGELOG.md:2942-2947` (v5.3.0): phase-scoped packs and the manifest cache are "wired in", benefit "now realized". | v8: no pack declared `phases:`; the cache was never written (`:2378-2379`, `:2420-2422`). |
| `CHANGELOG.md:2251-2253` (v9.0.0): surface −9.2%. | True "from the simplification alone"; the release as shipped is +2.9% over v8.0.0 `[measured]`. |
| `CHANGELOG.md:2229-2230` (v9.1.0): "the eval fixtures are the regression net". | The fixtures' CI job had never gated a merge (`:1981-1983`). |
| `docs/decisions/0003:3`, `0002:3`, `0004:3`: Status "Proposed". | All three shipped (v8.0.0, v5.1.0, v8.0.0). |
| `CHANGELOG.md:2966` (v5.2.1): Temper catches 12/12 bug patterns against vanilla 8/12. | The November bench reports equal correctness on a clear task (given). Different tasks; the older claim has no file I could check in this range. |
| `CHANGELOG.md:1002-1003`: the mod went "from 6,092 lines to 3,224". | `wc -l` over `hooks/**/*.ts(x)`: 7,319 to 3,562. Same direction; the changelog likely counts differently. |
| `CHANGELOG.md:2319`: "Four memory systems → one". | ADR 0006 describes two (`docs/decisions/0006:9`). |

---

## 8. Open questions

1. Is the directory listing still a goal, given `CHANGELOG.md:202-203`? Is Temper listed today? Not
   determinable from the files read.
2. How much of the 9.6.5 full-path text is forced by the host ("the Bash tool does not set that variable",
   `:1418-1419`) rather than by the directory, and can one line in a launch prompt replace 359 mentions?
3. Has the Plan stage's cost been measured against its v8 figure since its two pages grew from 13.7 KB to
   39.8 KB? (The bench's Plan rows, `docs/evidence/bench-2026-11.md:356`, are a different fixture.)
4. Does anyone use `temper bands`, OCR, Teach Me, Grill Me, the HTML plan review, Share, or the architecture
   depth review? No usage evidence exists in this range; each costs prompt text, config keys or an option
   in a question.
5. What does the Intent stage cost and save on a *clear* request? It was made mandatory in v9.0.0 on
   reasoning alone (`:2291-2293`).
6. What did 5.0.1 to 5.7.0 look like in code? The repository's history starts at 5.8.0.

---

## Appendix: reproduce the measurements

In `/tmp/claude-0/-home-user-temper/1ba4743b-465f-5ae6-8b88-a04ebb2fe840/scratchpad/work-changelog-older/`:

- `./measure.sh <commit> <label>` prints commands, agents, skills, packs, reference lines, prompt bytes by
  folder, CLI and script lines, test lines, mod lines, ADR count, config template lines.
- `./cfgkeys.sh <commit>` prints the distinct dotted config keys the non-test code reads.
- Release commits: v5.8.0 `55c2976`, v6.0.1 `8bdae11`, v7.0.0 `eed2513`, v8.0.0 `6b4d462`, v9.0.0 `896e576`,
  v9.1.0 `c88da69`, v9.2.0 `c109188`, v9.3.0 `aabeb85`, v9.4.0 `00bb7b6`, v9.5.0 `cecbb4b`, v9.6.0 `eaba313`,
  v9.6.4 `c4b892b`, v9.6.5 `3f7df41`, v9.6.8 `c8fc548`, v9.7.0 `a17c0e7`, v9.7.4 `595aaae`, v9.8.0 `eceabad`,
  v9.8.4 `7c7a1c1` (origin/main), v9.8.5 `9a01eff` (PR #115).
- Changelog entry counts: a Python pass over `CHANGELOG.md` splitting on `## ` headings and counting lines
  that start with `- `, `**` or `N. ` at column 0.
