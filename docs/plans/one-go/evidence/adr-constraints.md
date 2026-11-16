# Temper: the commitments, their reasons, and what a new plan may change

Reader: adr-constraints (1 of 17). Scope: `docs/decisions/*` (16 records), `docs/methodology.md`,
`docs/ai-native-sdlc.md`, `docs/trust.md`, `docs/auto-mode.md`, `docs/context-hygiene.md`, `docs/enterprise.md`,
`docs/grouped-build.md`, `reference/autonomy.md`, `reference/orchestrator-patterns.md`,
`docs/directory-submission.md`, `CONTRIBUTING.md`, `.claude/CLAUDE.md`, `packs/guardrails/rules.md`, all read in full.
Where a doc makes a claim about behaviour I checked the code that implements it (`scripts/flow.py`,
`scripts/loop_step.py`, `scripts/fresh_review.py`, `hooks/temper-mod/core/rules.ts`, `templates/temper.config.default`,
`scripts/quality-check.sh`).

Paths are relative to `/home/user/temper`. Confidence tags: **[code]** read in code, **[ran]** run by me in a scratch
clone, **[doc]** a claim in a doc that I did not check in code, **[inf]** my inference.

## 0. Three things to know before reading

1. **The working tree is not the head of PR #115.** Local `pr115` is `9a01eff` (13 commits). The pull request on
   GitHub is at `10e965a` (16 commits, updated 2026-11-15T21:37Z). The three missing commits add
   `docs/evidence/ab-replay-9.8.5.md`, `scripts/e2e/ab-replay.sh`, `scripts/e2e/replay.ts`, two selftest cases, a
   `gate_rows.py` change and a 7 line `same_failure` helper in `scripts/flow.py` (so `flow.py` line numbers from
   2570 on are 7 higher at the PR head). I fetched the head into my scratch clone and read the diff; nothing in it
   changes a finding below. **[ran]** (`gh api repos/galando/temper/pulls/115`; `git fetch ... pull/115/head`;
   `git diff --stat pr115..pr115-remote`: 10 files, 579 insertions). Citations of `ab-replay-9.8.5.md` below are to
   the file at `10e965a`, which the local tree does not hold.
2. **The guard enforces fewer decisions than the product asks.** The mod treats only two forward moves as the
   person's: `state advance intent_complete` and `state advance plan_complete`
   (`hooks/temper-mod/core/rules.ts:491`). Leaving a passed Design, Build, Review or Check needs no answer for the
   guard, and the CLI lets it through on a PASS (`scripts/flow.py:2510-2535`). The questions at those four passed gates
   exist only because `flow.py` chooses to ask them. That is the cheapest lever for "no back and forth", and it
   reverses no safety decision.
3. **PR #115 already contradicts one stated safety invariant.** Four documents say an armed run never plans again by
   itself. With `autonomy.policy: decide` the PR's code does exactly that after a failed group check (section 3, T2).
   This has to be decided before the PR merges.

## 1. Hard commitments a new plan must keep

### 1.1 The product promise

| # | Commitment | Source | Reason given | Verified |
|---|---|---|---|---|
| P1 | "Claude cannot write code before you approve the intent." | `README.md:3`; listing text `docs/directory-submission.md:46`; `.claude-plugin/plugin.json` description | Every later artifact derives from the intent; a correction there "costs words", after Plan "costs the plan" (`docs/ai-native-sdlc.md:45-47`) | **[code]** only leaving Intent and Plan are person-only advances (`rules.ts:491`); with the mod a source edit before plan approval is refused, without it the control is prompt level (`docs/ai-native-sdlc.md:83-87`, **[doc]**) |
| P2 | Every gate verdict is computed by the CLI from an evidence ledger, never asserted by a model | `.claude/CLAUDE.md:22-25`; `docs/decisions/0005:14-16`; `docs/decisions/0003:57-59` | Measured: standalone stage commands called the CLI in 1 of 3 runs when it was the model's choice (`0005:21-27`); a model score inside a gate "inverts the v7 deterministic-spine principle" (`0003:57-59`) | **[doc]** for the measurement; **[code]** `state advance` refuses a FAIL nobody skipped (`flow.py:2510-2535`) |
| P3 | A red gate blocks `git commit` through a native pre-commit hook | `.claude/CLAUDE.md:22-25`; `packs/guardrails/rules.md:82-92,161-165` | Claude Code settings have no PreCommit event, so only a git hook fires on every commit (`rules.md:84-88`) | **[doc]** |
| P4 | The record: intent, plan, design, gate ledger and diff committed together; overrides keep their reason and never erase the FAIL | `docs/trust.md:7-8`; `docs/ai-native-sdlc.md:19-23`; `rules.md:339-345` | The audit chain is what Temper leaves that vanilla does not (`docs/evidence/bench-2026-11.md:508-511`) | **[doc]** |
| P5 | Temper is not a sandbox, and the docs may not claim more than the code enforces | `docs/trust.md:62-72`; `docs/decisions/0013:76-79,124-126` | A 1,591 line shell parser "could not be finished"; two fifths of the mod's test lines chased it (`0013:20-24`) | **[doc]** |
| P6 | No network call, no telemetry, no credential handed to a command, no Claude Code settings file, transcript or git identity read | `docs/trust.md:7,12-17,44-48`; `docs/directory-submission.md:57-62,104` | Each was a plugin directory hold on a named release (`directory-submission.md:104`) | **[doc]** |

The honest positioning is also a commitment now in the README: use it "when a wrong guess is expensive", skip it for
"a change whose rules are already written down" (`README.md:54-58`).

### 1.2 What only the person may decide

Source of the list: `docs/decisions/0013:58-66`, `docs/decisions/0016:9-10`, `docs/auto-mode.md:8-15`, and the code
that enforces it, `hooks/temper-mod/core/rules.ts:476-497` **[code]**.

| Decision | Enforced where | Note |
|---|---|---|
| Accept the intent (leave Intent) | `rules.ts:491` | "no unattended run starts without a person having accepted the intent" (`reference/autonomy.md:17-19`) |
| Approve the plan (leave Plan) | `rules.ts:491` | Arming happens only here, or at the Design question when Design runs (`reference/autonomy.md:12-16`; `flow.py:670-675,726-728`) |
| Skip a failed check (`temper override`, with a reason) | `rules.ts:478`; ASK tier hook `packs/guardrails/rules.md:253` | The CLI refuses to leave a failed stage without it (`flow.py:2530-2535`) |
| A step back (`state loop`), start over, clear, archive | `rules.ts:492` | Exception: the CLI's own action in `view.json` may carry the call (`0013:65-66`); that is how an armed run loops |
| Arm the unattended run (`state set run_mode autonomous`) | `rules.ts:493` | Never at invocation (`templates/temper.config.default:133-134`) |
| Accept a review finding; clear a ledger | `rules.ts:489` | |
| Keep an agent's commits (`--accept-foreign`) | `rules.ts:487` | `docs/decisions/0011:70-82` |
| The Context check answer; a plan patch | `rules.ts:481` | `docs/auto-mode.md:10,17-18` |
| Confirm a manual task; accept a covered task | `rules.ts:482` | An armed run takes a covered task as done (`reference/autonomy.md:24`) |
| Open a small change window; choose the branch | `rules.ts:483,486` | |
| Reopen locked acceptance tests | `rules.ts:485` | |
| Each Scope drift row (Add to plan, Revert, Allow once) | prompt rule, `commands/temper.md:180-187` | "never answered for the person, in an armed run either" |
| The final feature commit of an armed run; any push; any pull request | `flow.py:2227-2231,887-898`; `docs/decisions/0015:27`; `0014:22-24` | |
| Publishing the plan review | `docs/decisions/0010:32` | |
| `autonomy.policy`, `plan.preflight-skip` in the config | the mod's config rule during a run (`docs/decisions/0018:63`) | Without the mod it is an ordinary file |

How the person decides is itself fixed: only in an AskUserQuestion dialog with the header `Temper gate`, matched
exactly against the header, question and option label the CLI wrote for that run and step; a typed message is never a
move; a subagent's question counts for nothing; the mod never has a button that decides
(`docs/decisions/0012:37-47`; `0013:58-62`; `0016:16-24`; `.claude/CLAUDE.md:64-65`). A new person-only call needs its
question in the view fixtures and a row in the test's table in the same change (`0016:28`).

### 1.3 What the CLI computes (never a prompt, never the mod)

| Thing | Source |
|---|---|
| Every gate verdict | `.claude/CLAUDE.md:22-25` |
| What comes next, every question, its options and the calls each maps to (`temper next --json`, `scripts/flow.py`) | `docs/decisions/0013:33-41`; `.claude/CLAUDE.md:27-28` |
| `.temper/view.json`, the one file the mod reads | `0013:42-48` |
| Refusing to leave a failed stage, or a stage out of order | `0013:49-54`; **[code]** `flow.py:2510-2535` |
| The plan's approved files and `base_sha`, frozen at approval | `0013:52-54,89-92` |
| Run id and step; a step back clears the verdicts and skips of what is redone | `docs/decisions/0012:30-36` |
| Loop budgets (Build to Plan once per run; others `loops.max-per-type`, default 2) | **[code]** `scripts/loop_step.py:20-32`; `reference/orchestrator-patterns.md:152-157` |
| Model per stage (`temper model --all`) | `docs/context-hygiene.md:59-63`; `templates/temper.config.default:53-58` |
| Build scheduling, worktrees, the task commits and merges | `docs/decisions/0011:21-33,41-48` |
| Check's suite, coverage, mutation score and scenario tests (no agent when the stack is known) | **[code]** `flow.py:1355-1364` |
| Which test runs count (only runs the CLI made or the person confirmed, 9.8.5) | `CHANGELOG.md:53-57` |
| Risk (so it cannot be lowered to skip Design) | `CHANGELOG.md:265-266` |
| State format healing on write, never interpreted by a hook on read | `docs/decisions/0004:91-92` |

### 1.4 Safety invariants of the unattended run

| Invariant | Source | Verified |
|---|---|---|
| Armed only by the person, at the last question before Build, after its check passed; never at invocation | `reference/autonomy.md:12-19`; `templates/temper.config.default:133-134` | **[code]** `flow.py:670-675,726-728`; `rules.ts:493` |
| Never pushes | `reference/autonomy.md:35`; `docs/decisions/0015:27`; `docs/trust.md:81` | **[code]** PR options are not offered to an armed run (`flow.py:887-892`) |
| Never merges to a remote | `reference/autonomy.md:35`; `docs/decisions/0011:86-89` | **[doc]** |
| Never makes the final feature commit: it parks and the person is asked | `reference/autonomy.md:35-37` | **[code]** `flow.py:2227-2231` |
| Never plans again by itself | `templates/temper.config.default:138-141` ("Hardcoded, not configurable"); `reference/autonomy.md:28,35`; `docs/grouped-build.md:123-125`; `docs/decisions/0011:86-89` | **Broken by PR #115 under `autonomy.policy: decide`**, see T2 **[ran]** |
| Its only commits are the CLI's local task commits, task merges and `temper integrate` | `reference/autonomy.md:37-39`; `0011:86-89` | **[doc]** |
| Never overrides or accepts anything | `docs/flow.md` (PR text, "Nothing is overridden or accepted") | **[code]** `flow.py:1144-1180`; a selftest greps `policy_move` for it (`scripts/selftest/temper-cases-28.sh`) |
| Parks on: a failed Build, a failed or parked group, a foreign commit, open Design concerns, tasks changed by Design, a file outside the plan, a `park-on-touch` path | `reference/autonomy.md:27-28,39-43`; **[code]** `flow.py:2443-2467,1973-1977` | |
| A park never needs typing: the next `temper next` asks the gate's question | `reference/autonomy.md:30-33` | **[doc]** |
| Every pull request is a draft; Temper never runs `gh pr ready`; only `reference/pr.md` pushes; each Pipeline push needs the person's yes | `docs/decisions/0015:14-18`; `0014:18-24` | **[doc]** |
| Task agents never commit; a commit the CLI did not record is detected and stopped, never repaired | `0011:41-43,70-82` | **[doc]** |

### 1.5 Plugin directory rules (external, not Temper's to change)

Source: `docs/directory-submission.md:14-28` (the script's rules), `scripts/quality-check.sh:21-27`, `CONTRIBUTING.md:121-147`,
`.claude/CLAUDE.md:46-47,63`.

- README: no raw HTML; an Install heading and a "What the mod reads and writes" heading; a plain text line of the
  phases before the Mermaid diagram; alt text on every image; no bundled assets folder path in text.
- Manifests: no `options` key; `plugin.json` has description, keywords and version; `marketplace.json` lists the same
  plugin; a LICENSE file; every new command and agent listed in `plugin.json`.
- Scripts (shell, Python, workflow files, tests and comments included): no path with a folder named `hooks`, `tests`,
  `mod`, `core` or `ui` (rules 9, 10); no wildcard after a variable (11); no `..` after a variable or `$( )` (12); no
  word joined from quoted pieces (13); the plugin root variable only in its braced form, in commands, briefs and
  skills, never in a script or test.
- **No tracked file over 256 KiB (262,144 bytes).** **[ran]** Three files are close: `scripts/temper` 260,504 bytes
  (1,640 left; unchanged at the PR head), `scripts/selftest/view-fixtures.ts` 259,060 (3,084 left), `CHANGELOG.md`
  246,956 (15,188 left). Any plan that adds gate logic, a question (fixtures) or a release note hits this first.
- The mod runs only the plugin's own CLI with no shell, sets no setting and runs no command (`CHANGELOG.md:205-209`;
  `directory-submission.md:101`); it reads only `view.json` (`0013:42-48`).
- The directory accepts hooks, mods and scripts "only from Verified organizations" (`CHANGELOG.md:202-203`,
  **[doc]**), and "This plugin includes a mod" is "always a reviewer. Nothing in the code clears it"
  (`directory-submission.md:99`). So a clean scan does not by itself get the plugin listed.

### 1.6 The "known mistakes" list (`.claude/CLAUDE.md:55-65`)

1. A gate mechanics change is a `scripts/temper` edit plus a `test-temper.sh` case, not a prompt edit.
2. What comes next, a gate's options and the grouped Build loop live in `scripts/flow.py` (a case in
   `temper-cases-8.sh`; regenerate `view-fixtures.ts` with `make-view-fixtures.sh`), never a list in a page.
3. Hooks fail open except their one detected violation path (also `packs/guardrails/rules.md:233-243`,
   `docs/decisions/0005:73-81`).
4. Never re-add per stage logic to `commands/temper.md` or `commands/fix.md`; it belongs in the stage's brief in
   `agents/`, the return box included; a brief never points a clean subprocess at an orchestrator file.
5. New commands and agents are listed in `.claude-plugin/plugin.json`.
6. The person decides only in a question dialog: never a deciding button in the mod.
7. A stage command is a door into `/temper`, never a flow of its own.

Rule 1 no longer matches practice: since 9.8.0 new gate logic goes into Python modules because of the 256 KiB cap
(`CHANGELOG.md:155-158,333-334`); there are 49 Python files with 12,335 lines under `scripts/` **[ran]**.

### 1.7 Other standing decisions

| Decision | Source | Still true |
|---|---|---|
| Grouped Build is the only Build; the orchestrator launches every task agent (works with nesting off); the CLI schedules | `docs/decisions/0011:21-25,172-180`; `0013:80-88` | **[doc]** |
| One git worktree per task and one per group, managed by the CLI | `0011:26-28,152-165` | **[doc]** |
| Exactly `intent.md`, `tasks.md`, `plan.md` (and `design.md`); no `spec.md` | `0011:38-40`; `docs/ai-native-sdlc.md:219-223` | **[doc]** |
| Scenarios are derived inside Plan from the blast radius, before the file list | `docs/methodology.md:63-71`; `ai-native-sdlc.md:224-229` | **[doc]** |
| No CI platform files; the fence ends at commit except the person's PR options | `ai-native-sdlc.md:230-241` | Partly superseded by ADR 0014 and 0015 (Commit can push a draft PR) |
| No eval suite for Temper's own prompts | `docs/decisions/0010:43-44` | True: `bench/` is manual and costs money per run |
| "With the mod off, every phase works the same" | `docs/trust.md:3`; `docs/grouped-build.md:3`; `docs/flow.md:5`; `docs/auto-mode.md:20`; `commands/temper.md:23` | Gates the same; cost and time are not (section 3, T9) |

Record hygiene: ADR 0002 (nested subagents) is still "Proposed" and its `agents:` config block exists nowhere in
`scripts/`, `templates/`, `agents/`, `reference/` or `commands/` **[ran]**; ADR 0003 and 0004 are "Proposed" though
shipped in v8; ADR 0003:31-33 says `evals/` "must remain byte-identical" and ADR 0010 deleted it; there is no 0007 or
0008; ADR 0011 D-06 says the task block budget is 1536 bytes and the code says 2048 (`scripts/temper:108`).

## 2. Self imposed rules that cost time, money or questions

"Evidence the risk is real" cites a run or a defect. "None found" means I searched the docs listed above and
`docs/evidence/` and found no run or defect.

| # | Rule | Source | What it costs | Risk it guards | Evidence the risk is real | A new record could |
|---|---|---|---|---|---|---|
| R1 | A question at every passed gate (Design, each group of a plan with two or more, Build, Review, Check), with "Stage by stage (Recommended)" as the default route | `README.md:30`; `.claude/CLAUDE.md:29-30`; `flow.py:673,729-732,745-752,772-791,815-821,1758-1766` | **[ran]** interactive mode asks at passed Build, Review and Check; armed asks at Review and Check; armed with the policy asks at none of them. Measured: 8 to 26 questions per feature run, mean 13.1, on well specified tasks (`docs/evidence/haiku-sonnet-task-agents.md:28-47`, 9.8.4; the doc does not define the column). Replay: 8 questions, 4 with the policy (`ab-replay-9.8.5.md:30`) | An agent going on from a stage the person would have stopped | **For Intent and Plan: yes.** Asking first raised the facts met from 73% to 98% (`bench-2026-11.md:146-155`); a plan built another route than the request (`bench:278-285`). **For a passed Design, Build, Review or Check: none found.** The guard does not require those answers (`rules.ts:491`), and the benchmark's person approves everything (`bench:83-85`), so no run could show a catch | Make a passed gate an `auto` move by default; ask at Intent, Plan, the commit and at every failure |
| R2 | Plan, Design and RCA run on Opus | `agents/plan.md:4`; `agents/design.md:4`; `agents/rca.md:4` | 45% to 83% of a run's cost (`bench:239-240,275-277`); Plan about 200 s, Design about 100 s (`bench:457-459`) | A weaker plan (missed blast radius, wrong tasks) | **None found.** The only Plan A/B compares prompt length on Opus (`docs/evidence/opus5-plan-prompt-ab.md`). The one model A/B that exists (Build tasks) found no quality difference (`haiku-sonnet-task-agents.md:84-86`) | Route by tier after one A/B; today it is an untested default |
| R3 | Design is its own Opus stage after Plan | `agents/design.md:1-25`; `flow.py:251-266` | About 100 s and $0.48 to $0.51 (`bench:356-357`), one question. PR #115 adds a loop: a Design answer given after the plan fails the Design gate until `tasks.md` changes, and "Loop back to Plan" is recommended (`flow.py:733-739`) | A policy conflict found only after Build (`docs/ai-native-sdlc.md:58-63`) | Weak. The gate "mechanically checks exactly one thing", a heading (`agents/design.md:21-25`); the code's own comment says the concerns were ones "the person only approved" (`flow.py:261-264`); 9.8.0 already cut Design to risk H, or complex plus Intent asked | Fold the concerns into Plan for risk H plans: one launch, one question, no Design to Plan loop |
| R4 | Fresh review of the plan: default `ask`, two reviewers at risk H, up to 3 rounds | `templates/temper.config.default:105-107`; `scripts/fresh_review.py:117-129` | Per reviewer round about 26 s, 37 s of wall time and $0.17 (`docs/evidence/fresh-review.md:70-76`); the failed run used 6 reviewers over 3 rounds (`docs/decisions/0017:9-10`) | A plan that leaves a decision open, which a small builder guesses and its own test repeats | **Yes, on a seeded fixture:** both builders of the seeded plan passed their own tests and failed the acceptance check (`fresh-review.md:51-61`, 2 builders per arm). The `tests` lens would have caught the failed run's G1 and G2 split (`0017:71-72`). But whole plan rounds never converged: 18, 14, 4 new findings (`fresh_review.py:34-37`), fixed in 9.8.4 by recheck rounds | Keep one round plus one recheck; decide when it runs by a CLI fact, not a setting |
| R5 | Acceptance tests written and locked before Build | `flow.py:1394-1420`; `CHANGELOG.md:244-247` | One Sonnet launch, 30 to 45 s (`bench:459`), 8 minutes in the Java run (`ab-replay:22`). A wrong locked test looped three runs to $38.24, $26.91 and $23.19 (`bench:158-170`) and two reruns met it again (`bench:177-179`) | The builder encodes one wrong guess in code and test | Mixed. The mechanism is shown (`fresh-review.md:58-61`), but the writer was itself wrong in 5 measured runs, and a hidden test miss was a case it never covered (`bench:183-185`) | Keep; it is part of the measured test advantage. Do not add rounds around it |
| R6 | One worktree per task; "there is no lighter path" for a plan of one task | `docs/decisions/0011:152-165`; `0013:130`; `docs/grouped-build.md:129-132` | The project's setup (install, build cache) once per task (`0011:134-135,163-164`). Not measured on a compiled project: the Java run's 25 minutes per Build task is not broken down (`ab-replay:22`) | Parallel tasks in one tree: "nearly every hard defect of the review rounds" (`0011:152-157`) | Yes for parallel tasks (8 review rounds, `0011:79-82`). But in the measured runs "every task ran alone" (`CHANGELOG.md:287-289`), and 9.8.0 kept worktrees for small plans on a Python benchmark only (`CHANGELOG.md:342-343`) | Let a chain that runs in order share the group's worktree; measure `task start` on a Maven fixture first |
| R7 | Retry ladder: Haiku, Haiku again, Sonnet, then park | `0011:57-59`; `grouped-build.md:82-84` | Up to 3 launches per failing task. Measured: 11 extra task runs and 2 escalations, all from one plan defect; "extra task runs the model caused: 0" in 18 runs (`haiku-sonnet-task-agents.md:76-78,92-97`). Java run: a task failed three attempts on the JDK (`ab-replay:40-41`) | A model that fails by chance | **Not observed.** Every measured retry was a plan or environment fault. 9.8.4 and 9.8.5 added `task blocked` and the environment verdict to skip the ladder | Retry only on a failure class the CLI cannot name; otherwise ask once |
| R8 | Build tasks on Haiku for simple and medium plans | `agents/build-task.md:4`; `grouped-build.md:44-45` | Task agents take twice as long (259 s against 134 s); a run is about 100 s (13%) slower, for $0.25 (9%) saved (`haiku-sonnet-task-agents.md:87-91`) | Cost | Measured both ways; quality equal | Owner's choice between seconds and cents (D3) |
| R9 | Review blocks on high and recommends a loop back for any open finding at medium or above (9.8.5) | `templates/temper.config.default:31`; `flow.py:779-787` | Each repair is a Build fix agent, a whole Review again, and in interactive mode three or more dialogs (the loop back needs a reason, `flow.py:588-593`). Before this change: 1.3 to 1.8 fix passes and 1.44 Review rounds per run (`haiku-sonnet-task-agents.md:79-80`); a second Review round cost $0.40 to $0.50 (`bench:271-273`) | A defect in the commit | Yes for high: 9.8.4 committed the High defect in the replay (`ab-replay:37-38`, scripted agents). For medium: none found; on clear tasks Temper met no more hidden tests than vanilla (`bench:499-501`) | Loop once for high and above; carry medium to the commit question; second Review as a recheck of the fix only |
| R10 | Coverage at least 80 and mutation score at least 70 at Check | `templates/temper.config.default:34`; `CHANGELOG.md:236-241` | Up to a 300 s mutation budget (run beside Review, `flow.py:1375-1378`). A missing tool looped Check 52 times before 9.8.4 (`flow.py:853-854`) | Tests that run lines and catch nothing | Yes: the mutation score is Temper's one measured gain on clear tasks, 93% against 79% (`bench:146-149`) | Keep. Check the tools at the preflight so a missing one never costs a round |
| R11 | Intent as its own agent with a rules checklist of up to six questions | `agents/intent.md:134`; `CHANGELOG.md:254-258` | 30 to 45 s, up to six Blocking questions and the gate question | Building the wrong thing | Yes on vague requests (98% against 73%); no gain on a complete request (`bench:55-57,160-161`) | Keep the stage; make it ask nothing when the request settles every checklist item (the CLI already records `intent_asked`, `flow.py:262-265`) |
| R12 | The session only relays; questions and prompts must match the CLI's text exactly | `docs/decisions/0013:58-66`; `CHANGELOG.md:356-364` | A reworded prompt or question is refused and costs a turn; two benchmark passes (10 runs) were stopped by refusals of the CLI's own steps (`bench:292-305`) | The session leaving the script | **Yes:** a Haiku session edited spec files, locked tests and house rules, and started a run from a one line summary, 14/26 and 17/26 hidden tests (`bench:209-211,278-282,410-413`) | Keep. With the run driver the main session costs $0.00 in 7 of 8 runs (`bench:437-438`) |
| R13 | A dependent group starts only after the person's Continue on the group before it | `flow.py:1683-1687` | In interactive mode a second group idles until a click | A Change on the first group reruns work the second builds on | None found | Start it on the gate's PASS; a Change reopens what it must (the reopen set already exists, `flow.py:1931-1939`) |
| R14 | Spec commits at each gate (`docs(intent)`, `docs(plan)`, `docs(design)`) | `docs/ai-native-sdlc.md:77-82`; `flow.py:1093-1098` | CLI calls per gate; files in the branch that nobody asked for (ADRs in 11 of 21 runs before 9.8.0, `bench:63-65`) | No committed baseline for the diff | None found as a defect avoided; it is the audit promise (P4) | Keep as one squashed spec commit at plan approval if the owner wants fewer commits |
| R15 | About 50 config keys in the shipped template, 5 plugin options, 11 commands, 13 agents | `templates/temper.config.default` (my count, approximate); `.claude-plugin/plugin.json` | Concepts to learn. Two keys do nothing: `autonomy.budget.max-total-loops` and `max-stages` are read by no code **[ran]** (`templates/temper.config.default:151-153`; `grep` finds them only in the template, the repo's own config, a selftest fixture, `reference/status.md:104` and an old plan) | n/a | n/a | Delete dead keys; a selftest that every template key is read |

## 3. Tensions between the commitments and the owner's goal

| # | Commitment | Against | Narrowest change that resolves it |
|---|---|---|---|
| T1 | "You decide each gate by clicking an answer" (`README.md:30`; `0012:37-41`) | No back and forth | Keep ADR 0012 decision 4 (the dialog is the one way to decide) and change only when a question exists. A passed Design, group, Build, Review or Check becomes an `auto` move; the person is asked at Intent, at Plan, at the commit, and wherever something fails, parks, drifts or leaves a finding open. The guard already draws this line (`rules.ts:491`), and the code path exists (`flow.py:1144-1180,2441-2472`). In practice: the plan question's recommended option becomes what `autonomy.policy: decide` plus arming does today, and "Stage by stage" stays as the second option. **[ran]**: that mode asks nothing at a passed Build, Review or Check. Wording change: "You approve the intent, the plan and the commit; Temper stops for you when a check fails." |
| T2 | "NEVER re-plans unattended", "Hardcoded, not configurable" (`templates/temper.config.default:138-141`; `reference/autonomy.md:28,35`; `docs/grouped-build.md:123-125`; `0011:86-89`) | No back and forth, and the PR's own code | **[ran]** With `autonomy.policy: decide`, an armed run whose group check failed after a tried fix returned `auto` with `state loop build plan --reason 'policy: ...'`, and the next action launched `temper:temper-plan` on Opus with the run still `autonomous` (`flow.py:1963-1972,2000-2005`; unchanged at `10e965a`). `docs/flow.md` in the PR says so ("a loop back to Plan"), while the four sources above still say never. Narrowest resolution: restate the invariant as "no plan is built without the person's approval" (true in code: Plan is excluded from the armed moves, `flow.py:2441`, so the new plan's question is always asked), keep Build to Plan at once per run (`loop_step.py:24-25`), and correct the four texts. The other choice is to exclude the loop back to Plan from the policy's moves. Either way one selftest should state the rule |
| T3 | Every stage in its own clean subprocess (`docs/context-hygiene.md:38-44,53-57`) | Cost | Keep the rule (the evidence supports it for the main session: $0.30 to $0.82 a run before, $0.00 with the driver, `bench:234-235,437-438`). Cut the number of stages that launch a model on a given run instead: no Design launch (R3), no Check agent (already the CLI), Intent that asks nothing on a settled request |
| T4 | Design after Plan, and a Design answer holds Build until the tasks change (PR #115, `flow.py:733-739`) | No loop backs | The order creates the loop. Ask the design concerns before the tasks are final (inside Plan for risk H), or let the Design answer patch `tasks.md` (9.8.0 already lets Design change tasks and approves them with the design, `CHANGELOG.md:307-310`) instead of recommending a whole Plan pass |
| T5 | One worktree per task, no lighter path (`0013:130`) | Fast | Amend ADR 0011: tasks that run one after another share the group's worktree; a private worktree only for tasks that really run at once. The defects the rule fixed were all from tasks running at once in one tree (`0011:152-157`) |
| T6 | Cheapest model for Build tasks | Fast | Not resolvable by design: twice the task time for 9% of a run's cost (R8). Owner decision D3 |
| T7 | Review repairs medium findings by default (9.8.5) | No loop backs | Second Review reads only the fix and the open findings (the small change path already launches Review with "review only <files>", `flow.py:960-965`; the fresh review has a recheck round). One automatic repair, then the commit question lists what is still open |
| T8 | Plan on Opus writes about 25,000 tokens into three artifacts (`bench:457-458`) | Cost and time | No narrow change is supported by evidence yet. The cost is output, not exploration (`opus5-plan-prompt-ab.md:42-45` says exploring and writing; `bench:457-458` says writing). First measure Plan on Sonnet; second, cut what Plan must write |
| T9 | "With the mod off, every phase works the same" (5 docs) | Fast, and one thing to maintain | Keep the gates the same; stop promising the same speed. Without the mod a feature run spends 183 to 206 s outside the agents against 42 to 103 s, and costs 23% to 46% more (`bench:446-450,482-484`). The driver is the designed path; the conversation loop is the fallback |
| T10 | "Gate logic lives in `scripts/temper`" (`.claude/CLAUDE.md:52-53`) and no file over 256 KiB | Complexity | `scripts/temper` has 1,640 bytes left. State the rule as "in the CLI (the script and its Python modules), never in a prompt" and split the file on purpose, once |
| T11 | Directory rules 9 to 13 shape tests and scripts (`directory-submission.md:25-28`) | Complexity | Keep the scripted checks (they are cheap). Do not design around directory acceptance: the mod is held for a reviewer regardless (`directory-submission.md:99`; `CHANGELOG.md:202-203`) |
| T12 | No eval suite for Temper's own prompts (`0010:43-44`) | "Once and for all" | Any restructuring is checked only by scripted e2e and a paid benchmark (16 runs cost $26.17, `bench:419`). The plan needs a named budget of benchmark runs per change |

## 4. ADR 0017, "A request that arrives as a spec" (draft, nothing built)

**What it proposes** (`docs/decisions/0017:24-47`): a second route through the same CLI. (1) `temper next` at Intent
detects four parts in the request (rules, file paths, tests, a done condition) and the Intent question offers "Use the
request as the spec (Recommended)"; (2) Intent copies the rules as criteria; (3) Plan groups the named files into
tasks and skips exploration; (4) no Design at any tier; (5) one fresh review round with two lenses and one recheck;
(6) the done condition becomes the Integration command; (7) Build, Review, Check and the commit unchanged. Cost: a
detector in `flow.py`, a `route: spec` mark, sections in two briefs, lenses by route, an e2e scenario (`0017:49-56`).

**What it would save, by the evidence**

| Point | Saving | Basis |
|---|---|---|
| No Design | About 90 to 100 s, about $0.5 and one question, only where Design would have run | `bench:356-357`. Design is already skipped on a fully specified request unless risk is H (`flow.py:259-266`; `CHANGELOG.md:319-321`), so the new saving is risk H plans only |
| Intent copies | A few seconds of a 30 to 45 s agent; no questions saved on a request that already settles every rule | `bench:459`; `flow.py:262-265` (`intent_asked`) |
| Plan without exploration | Unknown, and probably small | Plan's time is Opus writing about 25,000 tokens (`bench:457-458`); the spec path still writes scenarios, tasks with cases and a plan. The project brief already cut Plan by 14% in cost and 25% in time (`bench:367-368`) |
| One fresh review round, two lenses | 0 on a default config (`plan.fresh-review: ask` runs only when asked, `fresh_review.py:117-125`). In the failed run: from 6 reviewer launches to 1 or 2 plus a recheck | `0017:9-10`; `fresh-review.md:70-76` ($0.17 and 37 s a round) |
| Gate questions | None: "Same gates" | `0017:24-25` |

My estimate **[inf]**: a feature run with the mod is $1.93 to $2.50 and 597 to 865 s today (`bench:470-471`); the
spec path removes at most the Design share and part of Plan, so it stays near $1.4 to $2.0 and 500 to 770 s, three
to four times vanilla's cost and five to eight times its time. It does not touch the "about 30 questions".

**What is weak or missing**

1. **The detector would not fire on the measured cases.** **[ran]** None of the 11 benchmark task texts names a test
   or a done condition, and only 2 name a file (`bench/tasks/*/task.md`, checked with `grep`). The class where the
   evidence says the pipeline buys little is "a request that states every rule" (`README.md:44-45`), and those
   requests state rules, not files and tests. The four part test fits the one failed run it was written for.
2. **It adds a route instead of making the one route cheaper**: a new concept, a new option at the Intent question,
   a new state mark, and "every later change ... has to say what it does on the spec path" (`0017:64-65`). That is
   against "easy to use".
3. **No number.** It names no expected saving and no measurement plan; the benchmark has no spec shaped task.
4. **It leaves the two largest costs alone:** Plan on Opus (45% to 83% of cost) and the questions at passed gates.
5. **It is silent on the model and the reviewers:** which model Plan runs on, and whether a risk H plan still gets
   two reviewers.
6. **The failed run's cause was elsewhere.** Its 5 Build attempts came from a group that could not pass its own
   Validate and blind retries (`CHANGELOG.md:77-91`), fixed in 9.8.4; the draft says so itself (`0017:18-20`).
7. **It ignores a fact the CLI already has.** `intent_asked` (did Intent have to ask the person anything) already
   skips Design (`flow.py:262-265`). The same fact, with risk and tier, can drive every skip in the draft without a
   detector or a second route.
8. **"Copying a mistake faithfully"** is named as a risk (`0017:62-63`) with no check added for it.

Its sound ideas to keep: Intent that copies and adds nothing when nothing is open; the done condition as the
Integration command; one review round with the `tests` lens; skips only, never different stages (`0017:64-65`).

## 5. Decisions the plan needs from the owner

| # | Decision | Recommended answer | Why |
|---|---|---|---|
| D1 | Is the promise "you approve the intent, the plan and the commit, and Temper stops only when a check fails", as the default route? | Yes | The guard already enforces only those (`rules.ts:491`); 8 questions become 4 in the replay; no run shows a click at a passed gate catching anything |
| D2 | May a failed Build send the run back to Plan without asking, with the new plan still put to the person? | Yes, once per run, and correct the four texts that say never. If no: take the loop back to Plan out of the policy's moves before PR #115 merges | PR #115 does it today under the policy while the config template calls the opposite "hardcoded" (T2) |
| D3 | When seconds and cents pull apart, which wins by default? | Seconds for Build tasks (Sonnet: about 100 s a run for $0.25). For Plan and Design, no change until one A/B of Sonnet against Opus is run | R8 is measured; R2 has no evidence either way |
| D4 | One route or two? (ADR 0017) | One. Reject 0017 as a route; move its skips into the single route, driven by facts the CLI holds (`intent_asked`, risk, tier) | Section 4, points 1, 2 and 7 |
| D5 | Should an open medium finding send a run back to Build by default? | No: loop once for high and above, list medium at the commit question | R9: no evidence for medium; each loop is two launches and three dialogs |
| D6 | Is the mod the designed path, with the conversation loop as a slower fallback that keeps the same gates? | Yes | T9: with the driver a run costs 23% to 46% less on three of four tasks, and spends 42 to 103 s outside the agents against 183 to 206 s (`bench:446-450,482-484`) |

## 6. Where a doc and the code disagree

| Doc says | Code or repo says |
|---|---|
| An armed run never plans again by itself (`templates/temper.config.default:138-141`; `reference/autonomy.md:28,35`; `docs/grouped-build.md:123-125`) | Under `autonomy.policy: decide` it loops back to Plan and launches the Plan agent **[ran]** (`flow.py:1963-1972`) |
| The unattended part is Build alone; Review, Check and the commit ask (`reference/autonomy.md:15-16,25-26`; `.claude/CLAUDE.md:17-18`) | With the policy, Review and Check are `auto` (`flow.py:2468-2472`); `reference/autonomy.md` is not in the PR's diff |
| "With the `autonomy:` block absent or `enabled: false`, every gate is the ordinary interactive one" (`.claude/CLAUDE.md:19-20`; `templates/temper.config.default:135-136`) | `autonomy.enabled` is not read; the option is offered in every run (`flow.py:300-303`; template line 144 says so itself) |
| A loop back under the policy happens only while "the autonomy budget" lasts (`docs/flow.md`, PR text) | Only `loops.max-per-type` and `fix.max-loops` are read (`loop_step.py:20-32`); `autonomy.budget.*` is read nowhere **[ran]** |
| "ten Python scripts (about 3,600 lines)" (`docs/trust.md:5-7`) | 49 Python files, 12,335 lines under `scripts/` **[ran]** |
| "The repo holds no image"; no icon (`docs/directory-submission.md:35-36,79,104`) | `.claude-plugin/icon.png` exists, 19,658 bytes; 9.8.1 added it (`CHANGELOG.md:215`) |
| Design runs for "medium/complex features" (`templates/temper.config.default:112`; `.claude/CLAUDE.md:8`) | Only at risk H, or complex when Intent asked (`flow.py:259-266`) |
| Task block budget 1536 bytes (`docs/decisions/0011:64-65`) | 2048 (`scripts/temper:108`; `docs/grouped-build.md:57`) |
| Gate logic lives in `scripts/temper` (`.claude/CLAUDE.md:52-53`) | Much of it is in Python modules (`gate_rows.py`, `preflight.py`, `fresh_review.py`, `check_run.py`) because of the size cap |

## 7. What I could not determine

- What the roughly 30 questions of the failed complex run were (only the count is recorded, `0017:9-11`).
- What the `questions` column of `haiku-sonnet-task-agents.md:28` counts exactly (dialogs, or questions within them).
- How much of a Build task's time on a compiled project is the per task worktree and its setup.
- Whether Plan or Design on Sonnet holds quality: no run exists.
- Whether the policy's loop back to Plan was meant (`docs/flow.md` says it, the invariants deny it).
- Whether listing in the public plugin directory is still a goal.
