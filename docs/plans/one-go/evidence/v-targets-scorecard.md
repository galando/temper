# Verification: the measures and the targets (draft section 2, WP1a, 1b, 1c, 1f)

Tree read: `/home/user/temper` at `10e965a` (PR #115 head, 9.8.5). Nothing was written or run there except `grep`,
`wc`, `ls`, `sed -n` and `git log`. The selftest, the end to end suite and the bench were not run.

Short names: B = `docs/evidence/bench-2026-11.md`. HS = `docs/evidence/haiku-sonnet-task-agents.md`.
RP = `docs/evidence/ab-replay-9.8.5.md`. XC = `understand/_crosscheck.md`. EB = `understand/evidence-bench.md`.
LF = `verify/v-lean-front.md`. BT = `verify/v-build-one-tree.md`.

Marks on every number:
- **measured**: a figure printed in a repository document, or a count I made with the command shown. The raw runs
  behind B and HS are not in the repository (EB 0.3), so a "measured" bench figure is the document's claim.
- **measured by a reader**: a reader ran it at `10e965a`; I did not repeat it (the end to end suite is off limits).
- **assumed**: my arithmetic on measured figures, or an estimate. The basis is given each time.

## Verdict

| Draft pass line | Reachable? | Honest line |
|---|---|---|
| Bug: cost at most 1.5 times, time at most 2 times, 2 dialogs | Cost yes (already 1.14 to 1.35 on clean runs). Time no: the plan removes about 7 s from a bug run; expected 2.2 times | 1.5 and 2.5; 2 dialogs; and no clean task run handed back |
| Clear feature: 2 times, 3 times, 2 dialogs | Cost yes if the front agent is on Sonnet (1.3 to 1.8), or on Opus with a Haiku builder (2.0, on the line). Time only in the best case (2.95) | 2 and 4.5 with a Sonnet builder; or 1.5 and 5.5 with a Haiku builder; 2 dialogs |
| Vague feature: 3 times, 4 times, 3 dialogs | Cost yes (1.7 to 2.6). Time borderline: expected 4.1 (Sonnet builder) to 4.7 (Haiku). Dialogs 3 only when Intent asks at most 4 questions | 3 and 4.5; dialogs 2 + one per four open rules (3 or 4 on the bench's vague tasks) |

Every target number rests on agent costs that were never measured alone and on a front agent that does not exist.
The lines stay hypotheses until round M1 and M2 of section 4 are run.

---

## 1. The scorecard

### 1.1 What a run folder holds today

`bench/run.mjs` writes, per run: `run.json`, `person.jsonl`, `transcript.jsonl`, `work/`, and a copy of Claude Code's
own logs in `session/` (`main.jsonl`, `subagents/*.jsonl`, `subagents/*.meta.json`) (`bench/run.mjs:16-21, 90-106, 268`).

- `run.json`: task, arm, rep, cost, cost per model, wall seconds, API seconds, turns, sessions, `questions`
  (`bench/run.mjs:248-264`). `questions` counts AskUserQuestion calls, so dialogs (`bench/run.mjs:160-163`).
- `person.jsonl`: one line per question with `t` (ms since start), `stage`, `header`, `question`, `options`, `answer`
  (`bench/run.mjs:167, 187-188`). The option's `move` is known at that moment (`ctx.moves`, `bench/run.mjs:77-88, 164`)
  and is not written.
- `session/subagents/*.meta.json`: `agentType`, `model`; each `*.jsonl` line has a timestamp and each assistant
  message its `usage` (read by `bench/compare_models.py:25-48, 58-108`).
- Prices: `bench/loop.py:34-38` (Opus $4 in, $20 out, $0.20 cache read; Sonnet $2, $10, $0.10; Haiku $0.10, $0.50,
  $0.01 per million tokens: measured, equal to the platform table in `understand/platform.md:83-87`).

### 1.2 Field by field

| Field | Comes from | Do the logs hold it today? | Printed today? | Code change in `bench/` |
|---|---|---|---|---|
| Dialogs per run | `run.json.questions` | yes | only in `compare_models.py:133, 142`; not in `report.py` | a column in `report.py:41-59` |
| Dialogs by stage | `person.jsonl` `stage` | yes | no | group by `stage` in the new `scorecard.py`. Add `dialog: questions` to both `px.write` calls (`run.mjs:167, 187`): today a dialog of four Blocking questions is four lines and only `t` ties them |
| Dialogs by kind (gate, group, drift, resume, Blocking, Context check, manual task) | `person.jsonl` `header` and `who` | mostly: the header is one of four constants (`scripts/flow.py:40-43`), "Manual task", or `Question N` for a Blocking question (`scripts/flow.py:2488-2493`); the Context check shares the gate header (`scripts/flow.py:2340-2341`) and must be told apart by its text | no | a 10 line classifier in `scorecard.py`; it becomes one field once WP1e gives each question an id |
| Loop backs asked for by the person | the answer's `move` (`back` 8 sites, `redo` 27 sites in `scripts/flow.py`: measured, `grep -oE 'move="[a-zA-Z]+"' scripts/flow.py \| sort \| uniq -c`) | no: the move is in memory and dropped | no | write `move: ctx.moves[answer] ?? null` in both `px.write` calls (2 lines) |
| Loop backs taken with no question (armed run, policy) | `.temper/view.json` `loops` (`scripts/flow.py:2842`) | no: `feedback-loops.json` is deleted at `state clear` (`scripts/temper:1448`, XC section 4 item 5) | no | in `temperMoves` (`run.mjs:77-88`) also read `work/.temper/view.json` and write its `loops` on the question's line; plus one read at the end of each session (`run.mjs:227-230`) |
| Launches by agent type | `agentType` in each `*.meta.json` | yes | only `build-task`, `temper-build`, `temper-review` (`compare_models.py:122, 136, 139`). `loop.py`'s own agent list is empty under the driver (`loop.py:181-184`) | count by exact `agentType`. `subagent_secs` matches its kind anywhere in the meta JSON (`compare_models.py:96`) and `kind_cost` by substring (`:34`), so "build" would also count "build-task": the scorecard must match the whole type |
| Seconds per agent type | first to last timestamp of each agent log | yes | only for `build-task` (`compare_models.py:88-108, 135`) | call it for every type; report the sum and the union of intervals (agents that run at once add up in the sum) |
| Dollars per agent type | `usage` of each assistant message, priced by `loop.price` | yes | only for `build-task` (`compare_models.py:29-48, 135`) | call it for every type; add output tokens per type (LF 1.6 needs output split before the contract cut is used as a pass line) |
| Hand backs: did the run leave the driver | main session turns above 0 in a run with the mod (`loop.py:206, 221`); its dollars are `cost_main` (`loop.py:228`) | yes for "whether" and "how much" | by hand, in prose (B:437-445) | `handed_back`, `main_turns`, `main_cost` columns |
| Hand backs: how many, and why | the driver's end value (`hooks/temper-mod/core/driver.ts`, 5 `kind: 'handback'` sites: measured, grep) | no: nothing the bench copies holds it | no | not a `bench/` change: the mod would append `{args, why}` to a run file. Not determined whether the first main session message after a hand back carries the reason |
| Time outside the agents | `run.json.wall_s` less the union of the agents' intervals | yes | once, by hand (B:482-484) | one subtraction in `scorecard.py` |
| Longest stretch with no dialog, and gaps between dialogs | `person.jsonl` `t` | yes | no | in `scorecard.py`; with a stated reading time per dialog it gives a modelled human time (the person answers at once: `bench/person.mjs:22-34`) |
| Which code ran | nothing | no (`run.mjs:248-264` has no plugin commit, version, Claude Code version or mod on/off) | no | four fields in `run.json` |
| Spread | every run | yes | means only (`report.py:48-58`) | n, median, min, max per cell |
| Arm names | folder name | yes | five fixed names (`report.py:14`) | free arm names |

### 1.3 The change, as files

1. `bench/run.mjs`: about 10 lines (dialog index, `move`, the view's `loops`, the four stamp fields).
2. `bench/agentlog.py` (new): `metas`, `agents`, `kind_cost`, `subagent_secs` moved out of `compare_models.py:17-108`
   (that file runs at import, so nothing can import it today), with exact type matching and an interval union.
3. `bench/scorecard.py` (new, about 120 lines): writes `scorecard.json` per run and one markdown table per task and
   arm. A 46 line prototype of the per agent part exists and ran on synthetic logs only (EB 4.2: measured by a reader).
4. `bench/report.py`: read `scorecard.json`; free arm names; median, min, max.
5. `bench/README.md:42` says cost comes from the SDK's results; round 5 prices from session logs. One source, stated.

Effort: 1 to 2 days (assumed). No model call is needed to build it; it needs one real run folder to be tried on.

---

## 2. The free structural floor

### 2.1 Which scripted scenarios give questions and launches with no model call

`bun scripts/e2e/run.ts <mode> <scenario...>` runs the real CLI with scripted agents and a person who takes the
recommended option (`scripts/e2e/run.ts:7-11`, `scripts/e2e/scenarios.ts:93-130`). Each question is one trace line
`ask:<stage>:<labels>` (`scripts/e2e/loop.ts:94, 169`). Launches are not traced by type; only `replay.ts` counts them
(`scripts/e2e/replay.ts:197-198, 205-208`).

| Scenario | What it is | Questions today | Launches today | Source |
|---|---|---|---|---|
| `fix` | `/temper:fix`, faultless | 4 (RCA, Fix, Review, Check) | 3 (rca, fix, review) | measured by a reader (EB 1.3) |
| `full-run` | two groups, no Design | 7 | 6 (intent, plan, acceptance, 2 build-task, review) | measured by a reader (EB 1.3) |
| `design` | the same with Design | 8 | 7 | measured by a reader (EB 1.3) |
| `three-groups` | three groups, one task each | 8 | 7 (assumed from the fixture: `scenarios.ts:494-538` adds one group with one task) | questions measured by a reader |
| `armed-run` | Autonomous Build picked at the plan question | 4, and 3 automatic steps | 6 (assumed: same project as `full-run`, `scenarios.ts:445-463`) | questions measured by a reader |
| `pyjokes-full` | risk H, two fresh reviewers, a recheck, Design, one finding sent back, a fix run | 15 | not measured | measured by a reader (EB 1.3) |
| replay, 9.8.5 | the Java run's faults, fake tools | 8 | 7; 1 loop recommended; 0 repairs by hand | measured (RP:26-35) |
| replay, 9.8.5 with `autonomy.policy: decide` | | 4 | 7; 0 loops | measured (RP:26-35) |

One correction the floor must make. The fixtures write `reviewed: auto` (`scripts/e2e/project.ts:4`,
`scripts/e2e/pyjokes.ts:119`), which no Plan brief tells an agent to write, so every scripted count is one question
below a real default run (XC section 1 rows 1 and 2). A floor that is to mean "what a person meets" needs one more
scenario, `default-run`: `full-run` with `reviewed: pending`, as `agents/plan.md:89-94` says. Its value today is
8 questions and 6 launches (assumed: 7 + the Context check; XC section 3 totals).

### 2.2 The code change

- `scripts/e2e/world.ts`: `counts = { dialogs: 0, by_stage: {}, launches: {}, auto: 0, loops: 0, handbacks: 0 }` on `World`.
- `scripts/e2e/loop.ts`: increment at the ask branch (`:190-208`) and `port.ask` (`:122-134`); at each agent
  (`:175-181`, `:114-120`); at an `auto` action (`:173`); at an answer whose option has `move: "back"`; at
  `driver handback` (`:150`).
- `scripts/e2e/run.ts`: `--floor FILE`: after each scenario compare `w.counts` with the file; exit 1 on a difference.
- `scripts/e2e/replay.ts:375-388` already prints the same numbers as JSON; the floor reads `questions`,
  `agent_launch_total` and `loops_recommended`.

### 2.3 How CI holds it

A new job of about 2 minutes (assumed: about 20 s a scenario, EB 4.4, measured by a reader), separate from the
31 minute end to end job (`.github/workflows/quality.yml:87-96`; 30.6 minutes: measured by a reader):

```
bun scripts/e2e/run.ts plain default-run full-run design three-groups armed-run fix --floor scripts/e2e/floor.json
bun scripts/e2e/run.ts driver default-run fix --floor scripts/e2e/floor.json
```

The comparison is exact, not "at most": a change that raises a number fails until the file changes in the same
commit, and a change that lowers one fails until the file is lowered, so the file never drifts above the truth. The
raise is then one visible line in the pull request. A second, hard number per scenario (`ceiling`) is the owner's
line: the job fails when `now` is above it, whatever the commit says.

### 2.4 The shape of the cap file

```json
{
  "version": 1,
  "scenarios": {
    "default-run": {
      "plain":  { "now": { "dialogs": 8, "launches": 6, "by_type": { "intent": 1, "plan": 1, "acceptance": 1, "build-task": 2, "review": 1 }, "auto_steps": 0, "loop_backs": 0 },
                  "ceiling": { "dialogs": 8, "launches": 6 }, "target": { "dialogs": 2, "launches": 4 } },
      "driver": { "now": { "dialogs": 8, "launches": 6, "handbacks": 0 }, "ceiling": { "dialogs": 8, "launches": 6, "handbacks": 0 } }
    },
    "full-run":     { "plain": { "now": { "dialogs": 7, "launches": 6 }, "ceiling": { "dialogs": 7, "launches": 6 } } },
    "design":       { "plain": { "now": { "dialogs": 8, "launches": 7 }, "ceiling": { "dialogs": 8, "launches": 7 } } },
    "three-groups": { "plain": { "now": { "dialogs": 8, "launches": 7 }, "ceiling": { "dialogs": 8, "launches": 7 } } },
    "armed-run":    { "plain": { "now": { "dialogs": 4, "launches": 6, "auto_steps": 3 }, "ceiling": { "dialogs": 4, "launches": 6 } } },
    "fix":          { "plain": { "now": { "dialogs": 4, "launches": 3 }, "ceiling": { "dialogs": 4, "launches": 3 }, "target": { "dialogs": 2, "launches": 3 } } },
    "replay":       { "plain": { "now": { "dialogs": 8, "launches": 7, "loops_recommended": 1, "manual_repairs": 0 } } }
  }
}
```

The `now` values above are today's as listed in 2.1; the ones marked assumed there must be read off the first run
of the job, not from this page.

---

## 3. The targets, with the arithmetic

### 3.1 The baseline and the lines in absolute terms

Vanilla Claude Code, same day, 2 runs a task (measured, B:380-383): cent-mismatch $0.36, 48 s; tenant-leak $0.37,
46 s; vague-refunds $0.43, 99 s; partial-payments $0.49, 88 s.

| Class | Reference task | Draft line | In dollars and seconds (assumed: the product) | Today with the mod (measured) |
|---|---|---|---|---|
| Bug | cent-mismatch, tenant-leak | 1.5, 2 | $0.54 to $0.56; 92 to 96 s | $0.45, 89 s; $0.50, 110 s (B:427-428); $0.41, 113 s; $0.49, 133 s (B:472-473). Ratios 1.14 to 1.35 and 1.85 to 2.9. A handed back run: $1.27, 290 s, so 3.4 and 6.3 (B:441-444) |
| Clear feature | partial-payments | 2, 3 | $0.98; 264 s | $2.28, 865 s; $2.50, 811 s (B:430, B:471). Ratios 4.7 to 5.1 and 9.2 to 9.8 |
| Vague feature | vague-refunds | 3, 4 | $1.29; 396 s | $1.93, 661 s; $1.93, 597 s (B:429, B:470). Ratios 4.5 and 6.0 to 6.7 |

The draft's "today" for a bug (1.9 to 2.4 times the time) leaves out the two later single runs; with them it is 1.85
to 2.9.

### 3.2 The unit figures every row below uses

| # | Unit | Seconds | Dollars | Mark and source |
|---|---|---|---|---|
| U1 | Root cause agent, Opus, effort high | 33 to 61 | $0.23 to $0.34 | measured, B:386-388 (2 tasks, 2 runs) |
| U2 | Plan agent, Opus, today's contract | 143, 185 (mean 164) | $0.75, $1.01 (mean $0.88) | measured, B:356 (one task, 2 runs) |
| U3 | Design agent, Opus | 88, 90 | $0.48, $0.51 | measured, B:357 |
| U4 | A Sonnet stage agent (Intent, acceptance writer, Review, Fix) | 30 to 45; Review 27 to 54 | $0.06 to $0.15, used as $0.10 | seconds measured (B:457-459, B:477). Dollars assumed: never split in any table. Basis: a clean bug run $0.45 to $0.50 less U1 leaves $0.11 to $0.27 for Fix and Review; vague-refunds $1.93 less Plan $0.88, Design $0.50, tasks $0.07 leaves $0.48 for three or four Sonnet agents |
| U5 | The builder, a whole plan of 5 or 6 tasks, partial-payments | Sonnet 129, 133, 103 (mean 122); Haiku 261, 191 as one chain (mean 226) | Sonnet $0.33, $0.33, $0.26 (mean $0.30); Haiku $0.06 | measured, HS:30-35. Means of 9 runs an arm: Sonnet 134 s, $0.33; Haiku 259 s, $0.07 (HS:72-75). One Haiku agent on 9.8.0: 122 s (B:475) |
| U6 | Time outside the agents, with the mod | 42 to 103 a feature run; 13 to 14 a bug run | $0.00 | measured, B:482-484, with a person who answers at once |
| U7 | The front agent on Sonnet with the cut contract | 100 best, 150 expected, 185 worst | $0.30 to $0.44, used as $0.37 | assumed. Dollars: half of U2 at equal tokens ($0.37 to $0.51) less 6,800 to 7,500 output tokens at $10 a million ($0.07; LF 1.6). Seconds: not measured; 150 is U2's mean less 15 s; 100 is 30% under the fastest measured Plan. The prompt A/B found Plan's wall time is exploring, not writing (LF 1.6) |
| U7b | The front agent on Opus with the cut contract | as U7 | $0.61 to $0.87, used as $0.74 | assumed: U2 less $0.14 to $0.15 (LF 1.6) |
| U8 | One repair in place: a fix agent and a recheck of the diff | 60 to 100 | $0.12 to $0.30 | assumed: two U4. A repair through Build today is $0.40 to $0.50 (measured, B:271-273) |
| U9 | CLI calls of the target run | 30 best, 45 expected, 60 worst | $0.00 | assumed: below U6, since four to six gate rounds go. A reader measured about 31 s of CLI process starts in a small run (XC section 5) |

The cut contract saves a quarter to 30% of a Plan launch's output, not half: file bytes fall 50% to 56%, but thinking
and tool calls are output too (LF 1.6: measured by a verifier on one spec). "A contract half the size" is worth $0.07
on Sonnet and $0.14 on Opus a pass. The model, not the contract, is the money.

### 3.3 Clear feature (against $0.49 and 88 s)

Steps of the target run: (1) the front agent writes the criteria, the task list and its tests, and Intent is accepted
by rule; (2) one approval dialog; (3) the acceptance writer beside the builder, no serial seconds; (4) one builder in
one tree; (5) the suite with coverage and the locked acceptance tests once at the end of Build; (6) Review beside
Check; (7) one commit dialog; (8) the commit calls. No Design, no Context check dialog, no group, Build, Review or
Check question.

| Step | Best | Expected, seconds first (Sonnet builder) | Expected, cents first (Haiku builder) | Worst |
|---|---|---|---|---|
| Front agent | 100 s, $0.30 (U7) | 150 s, $0.37 (U7) | 150 s, $0.37 | 185 s, $0.87 (U7b: Opus stays) |
| Acceptance writer, beside the builder | 0 s, $0.06 | 0 s, $0.10 | 0 s, $0.10 | 0 s, $0.15 |
| Builder | 103 s, $0.26 (Sonnet) | 122 s, $0.30 | 226 s, $0.06 | 133 s, $0.33 |
| Review | 27 s, $0.06 | 40 s, $0.10 | 40 s, $0.10 | 54 s, $0.15 |
| CLI | 30 s | 45 s | 45 s | 60 s |
| One repair in place | none | none | none | 100 s, $0.30 (U8) |
| **Total** | **260 s, $0.68** | **357 s, $0.87** | **461 s, $0.63** | **532 s, $1.80** |
| **Against vanilla** | **1.4 and 2.95** | **1.8 and 4.1** | **1.3 and 5.2** | **3.7 and 6.0** |
| Dialogs | 2 | 2 | 2 | 3 (one stop for a decision) |

All totals and ratios are assumed (sums of the rows). If the Sonnet A/B fails and the front agent stays on Opus, the
expected columns become $1.24 (2.5 times) with a Sonnet builder and $1.00 (2.0 times) with a Haiku builder.

- **Cost at most 2: reachable** when the front agent is on Sonnet (1.3 to 1.8), or on Opus with a Haiku builder
  (2.0, no margin).
- **Time at most 3: not reachable as an expected value.** 264 s less Review (40) and CLI (45) leaves 179 s for the
  front agent and the builder together. The fastest measured Plan is 143 s and the mean Sonnet builder 122 s. It
  holds only when the front agent finishes in about 100 s and the builder is on Sonnet at its fastest measured value.
- **Cost 2 and time 3 pull against each other** through the builder: Sonnet is 104 s faster and $0.24 dearer a run
  (U5). This is owner decision 8 of the draft.
- **The honest line: cost at most 2 and time at most 4.5 with a Sonnet builder; or cost at most 1.5 and time at most
  5.5 with a Haiku builder.** Either is about half of today's time and a third to a quarter of today's cost.
- WP5 (one tree) adds nothing here: its saving on the bench's small Python tasks is about 0 s (BT section 8).

### 3.4 Vague feature (against $0.43 and 99 s)

Steps: (1) the Intent agent; (2) the Blocking dialog or dialogs, four questions to a dialog
(`scripts/flow.py:2478-2505`); (3) the front agent, with Design's concerns folded in as Blocking questions; (4) one
approval; then as the clear run from its step 3.

| Step | Best | Expected, Sonnet builder | Expected, Haiku builder | Worst |
|---|---|---|---|---|
| Intent agent | 30 s, $0.06 (U4) | 40 s, $0.10 | 40 s, $0.10 | 45 s, $0.15 |
| Front agent | 100 s, $0.30 | 150 s, $0.37 | 150 s, $0.37 | 185 s, $0.87 (Opus stays) |
| A revise pass after the answers | none | none | none | 60 s, $0.20 (assumed: a Sonnet agent on the affected blocks, LF section 4) |
| Acceptance writer | 0 s, $0.06 | 0 s, $0.10 | 0 s, $0.10 | 0 s, $0.15 |
| Builder | 91 s, $0.21 (lowest Sonnet task mean, HS:64) | 134 s, $0.33 (HS:73-75) | 190 s, $0.07 (middle of 122 and 259) | 190 s, $0.47 (highest Sonnet task mean, HS:62) |
| Review | 27 s, $0.06 | 40 s, $0.10 | 40 s, $0.10 | 54 s, $0.15 |
| CLI and the owner's answers | 30 s | 45 s | 45 s | 60 s |
| One repair in place | none | none | none | 100 s, $0.30 |
| **Total** | **278 s, $0.69** | **409 s, $1.00** | **465 s, $0.74** | **694 s, $2.29** |
| **Against vanilla** | **1.6 and 2.8** | **2.3 and 4.1** | **1.7 and 4.7** | **5.3 and 7.0** |
| Dialogs | 3 | 3 or 4 | 3 or 4 | 5 |

All totals and ratios are assumed. With the front agent on Opus the expected columns are $1.37 (3.2 times) and $1.11
(2.6 times).

- **Cost at most 3: reachable** in every mix but one (Opus front with a Sonnet builder, 3.2).
- **Time at most 4: borderline.** Expected 4.1 with a Sonnet builder, 4.7 with Haiku. The largest single saving is
  measured: no Design stage, 88 to 90 s and $0.48 to $0.51 (U3).
- **Dialogs: 3 holds only when Intent asks at most four questions.** The bench's vague briefs hold 5 or 6 facts and
  one Intent agent asked six questions (measured, B:494, B:502), so two Blocking dialogs and 4 in all.
- **The honest line: cost at most 3, time at most 4.5, dialogs 2 plus one per four open rules.**
- The line is only worth holding while Temper still beats one added sentence. "Ask me before you build" met 85% of
  the facts at 0.84 times vanilla's cost in round 2 (measured, B:108-110, B:120-122); it was never rerun on the
  current model.

### 3.5 Bug (against $0.36 to $0.37 and 46 to 48 s)

Steps: (1) the root cause agent; (2) one approval of the cause and the fix; (3) the Fix agent with the regression
test run red and green by the CLI; (4) Review beside Check; (5) one commit dialog.

No package of the draft touches the three agents of a bug run. What changes is two dialogs (4 to 2) and the CLI
rounds between them: at most about 7 s of the 13 to 14 s outside the agents (assumed; U6). One thing the draft
missed: Check starts beside Review only in a `/temper:temper` run (`scripts/flow.py:1375-1378` tests
`r.command == "temper"`); a fix run starts Check after Review. On the bench Check is 1 to 2 s (XC section 3 row 26:
measured by a reader on a toy project), so this saves seconds only on a real suite.

| | Best | Expected | Worst |
|---|---|---|---|
| Today's clean runs (measured) | $0.41, 113 s; 89 s is the fastest cell | mean of the four cells: $0.46, 111 s | $0.50, 110 s; 133 s is the slowest cell |
| Target run (assumed: today less 7 s) | $0.41, 82 s | $0.46, 104 s | $0.50, 126 s; with one repair in place (U8) $0.80, 233 s |
| Against vanilla | 1.1 and 1.7 | 1.25 and 2.2 | 1.35 and 2.7; with the repair 2.2 and 5.1 |
| Dialogs | 2 | 2 | 3 |

- **Cost at most 1.5: reachable**, and already met on every clean run.
- **Time at most 2: not reachable as stated.** One of the four measured cells meets it today, and the plan takes
  about 7 s off. Two untested levers could: the root cause agent at a lower effort or on Sonnet (it is 33 to 61 s of
  the run and has never run on anything but Opus at high: B:212-213, `agents/rca.md:5`); or no separate Review for a
  fix under a size the owner names.
- **The honest line: cost at most 1.5, time at most 2.5, 2 dialogs, and a tail rule:** no run of a clean bug task
  above 2.5 times vanilla's cost. One of four runs with the mod was handed back at 3.4 and 6.3 times (measured,
  B:441-444); the target for that run is the worst column, 2.2 and 5.1.

### 3.6 What must be true

1. The front agent runs on Sonnet for simple and medium plans below risk H, and its plans build as well. Never
   tested (B:225, HS:12). Without it the clear feature's cost line holds only with a Haiku builder, and the vague
   line loses its margin.
2. The front agent takes about 150 s or less. Not measured for any model on the cut contract.
3. One builder, with no retry and no second builder for a group. Measured in 11 of 18 runs (HS:30-47).
4. A Sonnet stage agent costs about $0.10. If it is $0.15, the expected clear run with a Sonnet builder is $0.97
   (2.0 times, on the line) and the vague one $1.15 (2.7 times).
5. Review runs beside the CLI's checks and a finding is repaired in place, not through Build.
6. No Design stage and no Design, Context check, group, Build, Review or Check dialog on a clean run.
7. The driver keeps the run: no hand back on a clean task (today 1 of 8 feature and bug runs: B:437).

---

## 4. The measurement program, in order

Run costs are the latest figures per task (measured, B:427-430, B:491-496, B:520, HS:57-64); the sums and the hours
are assumed (the products). Hours are one run at a time; three at a time is about a third (HS:17).

| # | Round | Runs | Dollars | Hours | Decision it settles |
|---|---|---|---|---|---|
| M0 | The scorecard and the floor (section 1 and 2); no model call | 0 | $0 | 1 to 2 days of work | Without it M1 to M5 are prose again |
| M1 | **"Before" on the PR head, with the mod.** 2 bug, 2 vague, 2 clear tasks (cent-mismatch, tenant-leak, vague-refunds, vague-late-fees, partial-payments, ts-seat-holds), 3 runs, Temper and vanilla | 36 | Temper $30.45 + vanilla $8.25 = $38.70; with up to 25% more for 9.8.5's extra repair rounds: $40 to $50 | 3.1 to 3.9 | The "today" column, which does not exist for 9.8.5. The dollars of Intent, the acceptance writer, Review and a fix pass, each alone (U4). Dialogs by kind. How the 28 `temper-build` launches of the old table split (XC row 13). Whether "High blocks" and "Medium recommends a loop" cost enough to flip before merge (WP0) |
| M2 | **Plan and Design on Sonnet against Opus.** `--config-yaml 'models:\n  plan: sonnet\n  design: sonnet'` (`bench/run.mjs:119-131`). The Opus arm is M1's four feature tasks; new: the Sonnet arm (12 runs), plus one complex task (subscriptions) in both arms (6 runs) | 18 | $18 + $19.50 = $38 to $45 | 4 to 4.5 | The default model of the front agent by tier and risk: the largest untested lever, $0.37 to $0.51 a pass. It decides whether the clear feature's cost line is real, and whether one front agent (4e) can be the Sonnet Intent agent going on to plan. Fix the rule before the run: Sonnet wins when hidden tests are equal, there is no extra loop from Build to Plan, and the median run is at least 20% cheaper. Run the two anchor tasks again after the contract cut ($12), since this round measures today's contract (LF section 3). Option: a fresh reviewer on every plan as a measuring device ($0.17 a plan, measured on 9.7.6); it then has to run in the Opus arm too, so M1's feature runs are repeated with it ($26 more) |
| M3 | **Effort on the Opus agents.** `effort: low` in `agents/plan.md` and `agents/design.md` (no launch carries an effort: `scripts/flow.py:1135`; medium is Opus's default, so pinning medium changes nothing: LF section 3); `effort: medium` in `agents/rca.md`. A worktree arm each | 9 to 21 | If Sonnet won M2: subscriptions 3 runs ($10) and the two bug tasks 3 runs each ($4) = $14. If Opus stays: 12 feature runs more ($22 to $26), $36 to $40 in all | 1.5 to 4 | The `effort:` line of three briefs. Whether a bug's time can reach 2 times |
| M4 | **The acceptance writer's value.** An arm without it: no config key exists; `acceptance_work` stands down once a skip is recorded (`scripts/flow.py:1394-1410`), so one line in a worktree arm. 2 vague and 2 clear tasks, 3 runs, against M1 | 12 | $26 | 2.5 | Keep it beside the builder, fold it into the front agent, or remove it. Hidden tests are at the ceiling, so judge by `bench/mutate.py` on the tests left behind, by Check failures on a locked test split into "defect caught" and "wrong test", and by the agent's own seconds and dollars |
| M5 | **One real project with a slow build.** A public Maven or Gradle project, a feature of 8 to 12 plan tasks, hidden tests written first; 2 Temper runs and 1 vanilla; `--timeout-min 240` (the default 60 minutes and 60 questions would cut the run off: `bench/run.mjs:51, 163`) | 3 | $25 to $75 (assumed: $11 to $35 a run, from 4 to 13 times the bench's seconds a launch, RP:21-22, on a $2.70 mean run; vanilla $1 to $3) | 3 to 7 (assumed: 92 to 191 agent minutes a run, RP:34) | Whether WP5 and "once per tree" are worth building: their saving on the bench is about 0 s (BT section 8). The first split of a 25 minute Build task into cold tree, tool start and model. Whether any time ratio survives off the bench |
| | **Total** | 78 to 90 | **$143 to $236** | **14 to 22** | |

For scale: everything recorded so far cost $653.78 for 276 priced runs (assumed: EB 4.4's sum of the documents'
round totals). Each later "after" round is M1's Temper half: $30 and 2.7 hours.

---

## 5. Growth caps for `scripts/quality-check.sh`

`quality-check.sh` is offline, must finish in 30 s and needs only python3 and git (`scripts/quality-check.sh:3-6`),
so it can hold the static counts. The run counts of section 2 belong to the floor job, which needs bun.

Counted at `10e965a`, from `/home/user/temper`:

| # | Count | Command | Today (measured) | Proposed cap | Target once the plan lands (assumed) |
|---|---|---|---|---|---|
| 1 | Agent launches in a default run | the floor file, scenario `default-run` | 6 (4 + T with T = 2: `scripts/flow.py:1119-1136, 1394-1420`; `full-run` measured by a reader) | 6 | 4 on a clear request, 5 on a vague one (front, acceptance, one builder, Review; plus Intent) |
| 1b | Agent briefs | `ls agents/*.md \| wc -l` | 13 (and 13 listed in `.claude-plugin/plugin.json`) | 13 | 10 or fewer |
| 2 | Question sites in `flow.py` | `grep -c 'self\.question(' scripts/flow.py`; `grep -c 'self\.with_more(' scripts/flow.py` | 41 + 12 = 53 | 53 | 35 or fewer (the Build, Review, Check and group "passed" questions and the Context check go) |
| 3 | Option sites | `grep -c 'self\.opt(' scripts/flow.py` | 89 | 89 | 65 or fewer |
| 3b | Distinct option labels | `grep -oE 'self\.opt\(\s*f?"[^"]+"' scripts/flow.py \| sed -E 's/self\.opt\(\s*f?//' \| sort -u \| wc -l` | 71 | 71 | 50 or fewer |
| 4 | Gate row names in the CLI | `grep -oE '_req "[^"$]+"' scripts/temper \| sort -u \| wc -l` | 32 (74 call sites) | 32 | 30 (two plan rows go: LF 1.5) |
| 4b | Gate row names in the Python files | `grep -ohE '\brow\("[^"]+"' scripts/*.py \| sort -u \| wc -l`; `grep -cE '^\s+name = "' scripts/gate_rows.py` | 19 + 4 = 23 | 23 | 22 |
| 5 | Config template: live key lines | `grep -cE '^\s*[A-Za-z_][A-Za-z0-9_.-]*:' templates/temper.config.default` | 30 | 30 | about 10 (WP6b) |
| 5b | Config template: commented key lines | `grep -cE '^\s*#\s*[A-Za-z_][A-Za-z0-9_-]*:( \|$)' templates/temper.config.default` | 46 | 46 | each one read by code, or gone |
| 5c | Config template: lines | `wc -l templates/temper.config.default` | 171 | 171 | about 40 |
| 6 | Prompt bytes: commands, agents, reference | `cat commands/*.md \| wc -c`; `cat agents/*.md \| wc -c`; `find reference -type f -name '*.md' \| xargs cat \| wc -c` | 65,752 + 94,919 + 147,041 = 307,712 | 308,000 | no target: the draft rules out another byte diet; the cap only stops growth |
| 6b | Packs and skills, read by the same agents | `find packs -type f -name '*.md' \| xargs cat \| wc -c`; the same for `skills` | 51,561 + 28,097 = 79,658 | 80,000 | falls with WP6c |
| 7 | `scripts/temper` | `wc -c scripts/temper` | 260,504 of 262,144 allowed (1,640 under) | already held (`scripts/quality-check.sh:21-29`) | |

Notes on the counts:
- Row 4 and 4b are static and miss a row whose name is built in a variable. The count a person sees is the rows a
  gate prints: `gate plan` printed 25 rows with no plan.md (LF section 5: measured by a verifier) and 26 on a full
  spec (XC: measured by a reader). Put the printed row count per gate of `default-run` in the floor file as well.
- Row 5 differs from the readers' "38 to 53 config keys": they counted by other rules. The cap must name its command,
  as above, or two people will count two numbers again (XC section 1 rows 6 to 10 are five such cases).
- Row 1b: 5 agent types are launched in a default run; the other 8 briefs are conditional or belong to other commands.

How the script holds them: one file, `scripts/caps.json`, `{ "version": 1, "caps": { "question_sites": 53, ... } }`,
and one block in `quality-check.sh` that runs each command and fails on any difference, above or below. A raise is
then a one line diff in the same commit, and the removal first rule (7d) is what the reviewer applies to it.

---

## 6. What must never be read into this evidence

1. **Sample sizes.** Most cells are 2 runs; seven tasks have 1 run each (B:486-497); the Plan and Design unit costs
   are one task, 2 runs (B:354-357). The document calls its own two run results "a first measure, not a result"
   (B:370-371). The rule of the bench is at least 3 (`bench/README.md`, "Rules that keep it honest").
2. **The spread is as large as most effects.** One task cost $1.99 to $3.19 in one arm (HS:88-89); Review took 27 to
   54 s and Plan 153 to 234 s on one code state (B:477-478). A gain under about 20% on two runs is noise. A pass
   line set at the expected value fails about every second round.
3. **Nothing was measured live on 9.8.5.** Every dollar and second is 9.8.0 or 9.8.4 (EB 0.1). The replay's "191 to
   92 agent minutes" multiplies launch counts by fixed weights from one run (`scripts/e2e/replay.ts:192-196, 374`;
   RP:55).
4. **Two pricing methods.** Rounds 1 to 4 summed SDK results and counted a resumed run more than once; round 5 prices
   session logs (B:227-229; `bench/run.mjs:239-247`). "10 times, now 4.5 times" is not one series.
5. **The tasks.** All 11 were written by the author (`bench/README.md`, last rule). Ten Python, one TypeScript; 22
   to 583 lines of code; 7 share one code base of about 565 lines (EB section 6 item 4: measured by a reader). Plans
   had 3 to 7 tasks. No task has an environment fault, a build tool slower than seconds, or a second service.
6. **The simulated person** answers at once, takes the recommended option, never types a change and never asks for
   the fresh review (`bench/person.mjs:1-34`). So every time ratio is machine time only; at 8 to 26 dialogs a run
   the person's time may be the largest part of a real run and is in no number here. The bench also never takes the
   paths behind the two bad real runs.
7. **Seconds do not carry to a real project.** On the one Java run a Plan launch took 12 minutes and a Build task 25
   (RP:21-22), 4 to 13 times the bench. Section 3's time ratios are for small Python tasks only.
8. **A ceiling on correctness.** Every arm passes nearly every hidden test (B:499-501). The bench cannot show that a
   lighter Temper builds worse code. A redesign that keeps 100% here has not been shown safe.
9. **The advantages are thin or old.** The vague request lead is one task in the last pass (5 of 5 facts against 3
   of 5; equal on one other task, behind then equal on the third: B:493-494, B:520). The mutation score lead was last
   measured in round 3 on old code (B:149).
10. **A count is not a cause.** The `fix passes` column counts every `temper-build` launch
    (`bench/compare_models.py:136`), not loop backs (XC row 13). The correlation of cost with dialogs (0.93) mixes in
    task size.
11. **The scripted counts are floors.** They leave out the Context check (section 2.1), every Blocking dialog, and
    every failure. The live mean was 13 dialogs against a scripted 7 or 8 (HS:30-47).
12. **Section 3 of this page is arithmetic, not evidence.** Three of its unit figures (U4, U7, U8) were never
    measured; M1 and M2 replace them.

## 7. Not determined

- The dollars of any Sonnet stage agent alone, and the seconds of a Plan launch on Sonnet or on the cut contract.
- How many hand backs a run has and why: the logs the bench copies hold only that the main session took turns.
- The printed row count of each gate on the head, and the launches of `three-groups`, `armed-run` and
  `pyjokes-full`: I did not run the end to end suite.
- The dollars of the Java run; M5's cost is a range from seconds, not from tokens.
