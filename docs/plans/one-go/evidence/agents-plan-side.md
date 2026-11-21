# Everything in front of Build: Intent, Plan, fresh review, Design, acceptance writer, env agent

Reader: planners who will not open the code again. Scope: what runs between the person's request and the first Build
task, what it costs, what is redundant, and what a single front agent would change.

All paths are relative to `/home/user/temper` at the head of PR #115 (`pr115`, commit `9a01eff`, version 9.8.5).
Every claim carries a tag:

- **[code]** I read it in the code at that line.
- **[measured]** I ran it, in a clone or a throwaway project under
  `/tmp/claude-0/-home-user-temper/1ba4743b-465f-5ae6-8b88-a04ebb2fe840/scratchpad/work-agents-plan-side` (never in the shared tree).
- **[doc]** only a doc says so; I did not check it against a run.
- **[inferred]** my reasoning from the above; treat as an estimate.

Token figures marked "~" are bytes divided by 4, an approximation.

---

## 0. The findings that matter most

1. **A default run launches 3 clean agents and opens at least 3 dialogs before the first Build task**, 4 and 4 when
   Design runs. Intent (Sonnet), Plan (Opus), acceptance writer (Sonnet); Intent gate, Context check, Plan gate
   [measured, section 5]. The fresh review is not part of a default run (`plan.fresh-review: ask`).
2. **The Context check is asked on every run, though the doc and the config comment say it is asked only when the map has
   an `ignore` or a `gap`.** Nothing in the CLI ever writes `reviewed: auto`; Plan is told to write `reviewed: pending`,
   and `pending` fails the row and raises the question in `auto` mode [measured; `scripts/flow.py:2338`,
   `scripts/plan_ops.py:92-94` against `reference/plan.md:71` and `templates/temper.config.default:104`].
3. **Most of what Plan writes is read by no script and by no later agent.** At simple tier the plan gate passes with no
   `plan.md` at all, and the Context check is then not asked [measured]. In the one real Plan output in git history, `plan.md` is 42% of Plan's artifact bytes;
   the Given/When/Then lines are 72% of the scenario bytes and no script reads them; the Build task agent sees only a
   scenario's name and its `Test:` command (`scripts/task_ops.py:386-389`) [code, measured on the sample].
4. **`design.md` is read by no agent after Design.** No Build, Review or Check brief or reference page mentions it
   [measured by grep]. Its effects on the run are the concerns it turns into questions and the Decision Log the panel
   shows. It costs 88 to 116 s and $0.48 to $0.61 on Opus when it runs (`docs/evidence/bench-2026-11.md:357`) [doc].
5. **Design after Plan builds a loop into the flow.** A Design answer that replaces a rule fails the Design gate until
   `tasks.md` changes (`scripts/decisions.py:60-69`), the mod refuses any write of `tasks.md` from Design on
   (`hooks/temper-mod/core/rules.ts:243-247`, [measured] on the rule), so the recommended way on is "Loop back to Plan"
   (`scripts/flow.py:733-739`): another Opus Plan pass, then Design again.
6. **Every revision of a plan is a new clean Opus Plan agent** that reads its 11,000 tokens of instructions and the
   brief again (`scripts/flow.py:1056-1059`, `:2318`, `:2327`; `commands/temper.md:158-160`) [code]. A first Plan pass
   is 143 to 246 s and $0.75 to $1.13 (`docs/evidence/bench-2026-11.md:356`) [doc].
7. **The project brief is shared with Plan, Design and RCA only** (`scripts/flow.py:1123-1125`, `:1384`;
   `agents/rca.md:15-16`). Intent, the fresh reviewers and the acceptance writer each read the conventions and the tests
   by themselves [code]. The brief takes 0.04 to 0.28 s to make [measured].
8. **PR #115 adds one more agent in front of Build (the env agent) and its draft file is refused by the mod's own write
   rule at Plan** [measured on the pure rule function; not run in a live session].

---

## 1. Each agent in front of Build

### 1.1 Overview

| Agent | Model, and where it is set | Runs when | Launch prompt carries | Fixed instructions it must read |
|---|---|---|---|---|
| Intent (`agents/intent.md`) | `sonnet`, frontmatter `agents/intent.md:4`; override `models.intent` (`scripts/cli_ctx.py:57-68`) | every `/temper` run, first (`scripts/flow.py:47`) | brief path, `Feature:` (the request, verbatim), spec path (`scripts/flow.py:1119-1136`) | brief 14,976 B + `templates/intent.md` 4,455 B, ~4,900 tokens [measured sizes] |
| Plan (`agents/plan.md`) | `opus`, `agents/plan.md:4`; override `models.plan` | after the person accepts the intent | brief path, `Project brief: .temper/brief.md`, spec path. **Not the request text** (`scripts/flow.py:1123-1131`) | brief 11,905 B + `reference/plan.md` 27,927 B + two templates 4,492 B = ~11,100 tokens; plus `.claude/temper.config` (9,647 B as shipped) and the enabled packs' `rules.md` (9,904 B for the five default packs) = ~16,000 tokens, before the project brief and intent.md (`agents/plan.md:12-18`, `reference/plan.md:180-183`) |
| Fresh reviewer A, B (`agents/plan-review.md`) | `sonnet`, `agents/plan-review.md:4`; override `models.plan-review` (`scripts/flow.py:1284-1287`) | only when the person picks "Fresh review first", or config `auto`/`always` (`scripts/fresh_review.py:117-125`) | spec path, instance, lenses, round (`scripts/flow.py:1291-1305`). No brief. | brief 7,859 B, ~2,000 tokens |
| Design (`agents/design.md`) | `opus`, `agents/design.md:4`; override `models.design` | `phases.design` on and (risk H at medium or complex, or complex and Intent asked the person anything), or a `design.md` exists (`scripts/flow.py:251-266`) | brief path, `Project brief`, spec path | brief 3,732 B + `reference/design.md` 6,611 B + template 1,758 B = ~3,000 tokens, plus packs, plus intent.md, plan.md and the brief again (`agents/design.md:13-16`, `reference/design.md:12-15`) |
| Acceptance writer (`agents/acceptance.md`) | `sonnet`, `agents/acceptance.md:4`; override `models.acceptance` (`scripts/flow.py:1411-1414`) | at stage build, before any group starts, at most 2 launches (`scripts/flow.py:1394-1420`, `scripts/check_run.py:625`) | brief path, spec path. No brief. | brief 6,897 B, ~1,700 tokens |
| Env agent (`agents/env.md`, new in PR #115) | `sonnet`, `agents/env.md:4`; `scripts/flow.py:1222` falls back to `"sonnet"` and `env` is not in `AGENT_STAGES` (`scripts/cli_ctx.py:21`), so the config cannot change it [code] | only when the preflight row failed on the environment, no rule of `doctor --propose` fits, and the person picks "Let an agent find the setup" (`scripts/flow.py:1200-1204`, `:2377-2379`) | failing commands, what `doctor --propose` found | brief 5,055 B, ~1,300 tokens |

`/temper:intent` (`commands/intent.md`) is a separate inline command, not an agent: it interviews the person in the main
session and writes a draft `intent.md` (`commands/intent.md:8-18`). It still says to "always ask who reviews the intent"
(`commands/intent.md:46-48`), which 9.8.0 removed from the Intent stage because that question "looped runs"
(`scripts/intent_draft_rows.py:158-160`, `agents/intent.md:58-60`). Doc and code disagree. [code]

### 1.2 Intent: what it reads and writes

Reads: the request; every linked source (ticket, PR, doc) (`agents/intent.md:22-30`); "at most a quick look at the repo
for naming and context" (`agents/intent.md:53-54`); the house rule files CONVENTIONS.md, CLAUDE.md, AGENTS.md,
CONTRIBUTING.md and "a pattern the existing code follows everywhere" (`agents/intent.md:110-113`). The last asks for a
code read that lines 24 and 157 forbid. It gets no project brief, although the brief already holds those four files
(`scripts/brief.py:25`, `:204-208`). [code]

Writes `intent.md` and returns a 76 column panel it draws by hand (`agents/intent.md:162-187`).

| Section of intent.md | Intent gate row that checks it (18 rows in all [measured]) | Read later by |
|---|---|---|
| Header: Author, Status, Created, Ticket, Reviewer (optional), Complexity | `status header` (`scripts/temper:2077-2083`), `header fields` (`scripts/intent_draft_rows.py:156-167`) | the CLI (status; `state set complexity` rewrites the line, `agents/plan.md:30-33`) |
| Problem | `problem stated` (`scripts/temper:2044-2059`) | Plan panel's first sentence (`scripts/panel.py:130`) |
| Success Criteria (`AC-NN`, `[required]`, `Why:`, `Validate:`) | `success criteria` (`scripts/temper:2063-2074`); `criteria ids`, `criteria priority`, `criteria validate`, `criteria why` (`scripts/intent_draft_rows.py:77-110`); `no soft words` (`:175-223`) | plan gate, build gate, Check, the acceptance writer (`agents/acceptance.md:15`) |
| Constraints | `no soft words` | the acceptance writer (`agents/acceptance.md:15-16`) |
| Scope and Non-goals | `out of scope stated` (`scripts/intent_closure_rows.py:27-40`) | the acceptance writer |
| Target Users (action chains) | `target users action chain` (`scripts/intent_draft_rows.py:112-118`) | **no script and no brief after Intent names it** [grep] |
| Business Outcome (optional) | none | none [grep] |
| Open Questions (`Blocking:` with `choices:`, `Deferred:`) | `open questions labeled`, `no duplicate question` (`scripts/intent_draft_rows.py:120-154`), `open questions resolved` (never fails, `scripts/intent_closure_rows.py:42-51`), `blocking question open` (`scripts/gate_rows.py:27-41`) | the CLI builds the dialogs (`scripts/flow.py:2488-2505`) |
| Assumptions | none | the person at the gate; Plan only as part of the whole file |
| Rules covered (7 items) and the `**States:**` line | `rules checklist covered` (`scripts/gate_rows.py:53-90`) | Rules covered: **nothing after the gate** [grep]. States: the acceptance writer (`agents/acceptance.md:27-30`) |
| Decisions | used by `no duplicate question`; by the plan gate's `request routes kept` (`scripts/gate_rows.py:286-290`) | the acceptance writer ("Decisions first"), Build task prompts for `Design:` rows only (`scripts/decisions.py:93-105`) |
| Scenarios (must stay empty in a draft) | `no scenarios in draft` (`scripts/intent_draft_rows.py:169-173`) | filled by Plan |
| Source Traceability, Context Sources | `task context recorded` (`scripts/intent_draft_rows.py:52-74`) | Plan, which is told to fetch every `consulted:` source again (`agents/plan.md:24-29`) |

Size [inferred]: the non-scenario part of the one real intent in git history is about 8,000 B, ~2,000 tokens, for 16
criteria (`git show eaba313:.temper/specs/mods-support/intent.md`, measured: Success Criteria 4,898 B, Decisions 830 B,
Problem 668 B, Constraints 506 B, Scope 409 B, Sources 377 B, Target Users 274 B). That file predates the Assumptions and
Rules covered sections. For 5 to 8 criteria expect ~1,000 to 1,500 tokens of file plus the hand drawn panel. The docs
give Intent's time (30 to 45 s, `docs/evidence/bench-2026-11.md:457-459`), not its tokens.

Two instructions in the brief collide [code, measured]:

- The agent must run `temper gate intent` and "fix any FAIL it reports" (`agents/intent.md:141-143`). When it wrote a
  Blocking question, as the rules checklist tells it to, the row `blocking question open` fails by construction
  (`scripts/gate_rows.py:37-40`; in my run the gate printed FAIL with that one row). The only way an agent can "fix" it
  is to drop the question.
- That same failed row sets `intent_asked` in the run state (`scripts/temper:2096-2100`), which later turns Design on
  for a complex plan (`scripts/flow.py:265-266`).

### 1.3 Plan: what it reads and writes

Reads: `reference/plan.md` and the project brief in its first turn (`agents/plan.md:12-18`); intent.md; every
`consulted:` source again (`agents/plan.md:24-29`); `.claude/temper.config` and the enabled packs' rules
(`reference/plan.md:180-183`); the code, "with your own tools" (`reference/plan.md:175-179`); a cross repo search tool
when one is connected (`agents/plan.md:34-41`).

Writes: the scenarios into intent.md, `tasks.md`, `plan.md`, optionally `.temper/security-map.json`
(`reference/plan.md:403-405`), and runs `state set complexity`, `risk`, `gate plan` (`reference/plan.md:391-395`). Its
panel is drawn by the CLI (`agents/plan.md:121-127`, `scripts/panel.py:91-137`).

The plan gate has 26 rows at simple tier [measured], 27 at medium and complex (`blast radius documented`,
`scripts/temper:3560-3568`), 30 when the fresh review applies (`scripts/fresh_review.py:299-324`).

| Artifact part | Bound or size | Plan gate rows | Scripts that read it | Later agents that read it |
|---|---|---|---|---|
| intent.md `## Scenarios`: one fenced block each with `Scenario:`, Given/When/Then, `Note:`, `Covers:`, `Test:` | medium 3 to 8, complex 5 to 15 (`reference/plan.md:232`); the A/B fixture got 11 to 15 (`docs/evidence/opus5-plan-prompt-ab.md:32`); sample: 32 scenarios, 14,540 B, ~114 tokens each | `criteria -> scenarios` (`scripts/temper:3507-3514`), `criteria -> validation` (`scripts/acceptance.py:336-394`), `scenarios in gherkin blocks` (`scripts/temper:3524-3546`), `scenario test commands` (`scripts/gate_rows.py:105-133`), `preflight` runs each `Test:` | `acceptance.scenario_blocks` reads only the name, `Test:` and `Covers:` lines (`scripts/acceptance.py:91-112`); `temper integrate` runs `Test:` (`scripts/scenario_ops.py:133-155`); panel lists names and Covers (`scripts/panel.py:96-107`) | Build task agent: name and `Test:` only (`scripts/task_ops.py:386-389`). Review step 3 and the Check agent read the steps (`reference/review.md:137-150`, `agents/check.md:42-44`). The acceptance writer is not told to read scenarios (`agents/acceptance.md:15-19`) |
| intent.md: the line `- Blocking: Context check: ... choices: ...` | 1 line | none | filtered out of the question list (`scripts/flow.py:371-373`); its choices are parsed by `context_choices`, which has **no caller** (`scripts/flow.py:392-396`, grep) | none. A dead instruction (`agents/plan.md:91-92`) |
| tasks.md: `**Integration:**`; per group Depends, Validate, Interfaces, Context; per task File, Depends, Test, Cases, Traced to, done box | Context at most 4,096 B, task block at most 2,048 B (`scripts/temper:107-108`); at least 2 Cases a task (`scripts/plan_rows.py:44-46`); sample (old format, no Cases, no Context): 23 tasks, 16,405 B, 713 B a task | 14 rows of `scripts/plan_rows.py:21-195`; `maven group verify`, `maven filtered verify` (`scripts/gate_rows.py:136-191`); `preflight` | the whole Build loop (`scripts/tasks_md.py`), `risk.py:35-42`, `panel.py:108-112` | Build task agent: its task block and its group's Context (`scripts/task_ops.py:384-390`) |
| tasks.md `**Traced to:**` | sample: 3,635 B, 22% of tasks.md | none by name | `scenario_ops.traced` to find which task owes a scenario test (`scripts/scenario_ops.py:30-36`, `:74-98`); the same owner is also derived from the `Test:` command's file and the task's `**File:**` (`:85-90`) | inside the task block |
| plan.md `## Context Map` | at most 12 entries of 100 characters (`scripts/plan_ops.py:26-27`), ~300 tokens | `context map reviewed` (`scripts/plan_ops.py:81-101`) | the Context check question (`scripts/flow.py:2289-2329`) | reviewer and Design read plan.md whole |
| plan.md `## Architecture` | sample 4,516 B | none | none | Design, the fresh reviewer, the acceptance writer for entry point names (`agents/acceptance.md:16-17`), the HTML review (`scripts/plan_review.py`) |
| plan.md `## Approach Decisions` (optional) | sample 2,878 B | none | panel lists the headings (`scripts/panel.py:120-121`) | as above |
| plan.md `## Diagram`: mermaid block and the same diagram as ASCII (`reference/plan.md:296-304`) | sample 1,259 B (mermaid only, older format) | none | panel prints the `text` block (`scripts/panel.py:144-158`); the mermaid block: none | none |
| plan.md `## Cross-Repo Search` | 1 line or more; sample 407 B | `cross-repo search recorded`, at every tier (`scripts/temper:2126-2151`, `:3548-3559`) | panel's SEARCH field (`scripts/panel.py:118-119`) | none |
| plan.md `## Blast Radius` | sample 3,247 B without the file tables | `blast radius documented`: a heading grep, medium and complex only (`scripts/temper:3561-3568`) | `risk.py` looks only for `[CROSS-REPO]` in it (`scripts/risk.py:59-65`) | Build's fix pass (`reference/build.md:12-13`) |
| plan.md `## Files to Create`, `## Files to Modify` | sample 8,406 B, 37% of plan.md | none | `flow.plan_files` unions them with the tasks' `**File:**` lines (`scripts/flow.py:2538-2559`); `scripts/drift.py:8` | Build's fix pass (`agents/build.md:79-80`) |
| plan.md `## Patterns to Follow`, `## Dependencies`, `## Risk Level` | sample 588 + 427 + 439 B | none | **none** [grep]; the risk is computed by `risk.py` | none |
| `.temper/security-map.json` | optional | none | `risk.py:45-56`, `panel.py:123-135` | **none**; `reference/plan.md:403-405` says "for Review/Check to read", and no Review or Check page mentions it [grep] |

### 1.4 Design: what it reads and writes

Reads intent.md, plan.md, the brief, `reference/design.md`, the enabled packs' rules and the stack pack
(`agents/design.md:13-16`, `reference/design.md:12-15`).

Writes `design.md` from `templates/design.md`: System Architecture, API Contracts, Database Changes, Integration
Points, Decision Log, Security Considerations, Performance Considerations, Areas of Concern. It may add
`- Blocking: Design: ...` lines to intent.md (`reference/design.md:37-42`) and, in a project that keeps ADRs, files under
`docs/decisions/` (`reference/design.md:83-99`).

| Section | Design gate row (2 rows in all) | Scripts that read it | Later agents |
|---|---|---|---|
| Areas of Concern | `concerns flagged`: a heading grep (`scripts/temper:3727-3734`) | the Design question names the open ones (`scripts/flow.py:707-718`), the panel (`scripts/panel.py:176-198`), `answer_ops.py` writes `resolved:` | none |
| Decision Log | none | panel | none |
| API Contracts, Database Changes | none | panel counts their sub headings (`scripts/panel.py:193-196`) | none |
| System Architecture, Integration Points, Security and Performance Considerations | none | none | none |
| (answers to `Design:` questions) | `tasks agree with decisions` (`scripts/decisions.py:60-69`) | written to intent.md Decisions; `Design:` rows reach Build task prompts (`scripts/decisions.py:93-105`, `scripts/flow.py:1432-1434`) | Build task agents, as prompt lines |

No brief or reference page of Build, Build task, Review or Check contains the word "design" [measured:
`grep -n -i design agents/{review,build,build-task,check}.md reference/{review,build,check}.md` returns nothing]. The
comment at `scripts/temper:1176-1177` says "Build, Review and the report read what was decided" in design.md; for Build
and Review the code does not bear that out. [doc against code]

Tokens: not in the evidence docs. Design costs about half of Plan on the same model ($0.48 to $0.61 against $0.75 to
$1.13, `docs/evidence/bench-2026-11.md:356-357`), so roughly 10,000 to 13,000 output tokens [inferred from the cost
ratio].

### 1.5 Fresh reviewer, acceptance writer, env agent

- **Fresh reviewer.** Reads only intent.md, plan.md, tasks.md, and searches the code where a lens asks
  (`agents/plan-review.md:24-26`). Writes ledger rows (`temper evidence add --stage plan --phase fresh`): findings, one
  completion row per lens, one paraphrase; returns a hand drawn panel (`agents/plan-review.md:63-107`). Gate rows:
  `fresh review ran`, `fresh reader's paraphrase`, `no open plan blockers` (`scripts/fresh_review.py:299-324`). 26 s mean,
  about 61,000 tokens in all per reviewer (`docs/evidence/fresh-review.md:70-78`) [doc].
- **Acceptance writer.** Reads intent.md (criteria, Decisions, Constraints, Scope), plan.md for entry point names only,
  the project's existing tests and the four house rule files (`agents/acceptance.md:15-19`). Writes tests under
  `{spec}/acceptance/`, at least one per required criterion and per state, runs them once, locks them
  (`agents/acceptance.md:21-50`), returns a hand drawn panel (`:74-86`). No plan gate row; Check runs the locked tests.
  30 to 45 s (`docs/evidence/bench-2026-11.md:457-459`) [doc]. Tokens not measured.
- **Env agent (PR #115).** Reads CI files, Dockerfiles, Makefile, README and the machine, read only
  (`agents/env.md:17-26`); writes `{spec}/setup-proposal.yaml` (`:27`); the CLI tests the draft
  (`scripts/flow.py:1223-1225`). The mod's write rule at stage `plan` allows only intent.md, plan.md, tasks.md,
  design.md, config-suggestions.json, `*-context.json` and `docs/decisions/*.md`
  (`hooks/temper-mod/core/rules.ts:263-275`). I ran that rule (`evaluate`, with bun, in my clone) on a Write of
  `.temper/specs/pw/setup-proposal.yaml` at stage `plan`: **deny**; at stage `check`: allow. No test in `tests/mod` or
  the selftest covers the path under the mod (grep `setup-proposal` finds only `scripts/flow.py` and
  `scripts/selftest/temper-cases-27.sh`). Whether a live session hits this I did not run. [measured on the rule]

### 1.6 Sections nothing downstream reads

No script and no later brief uses these (the fresh reviewer, Design and the HTML review read whole files, which is the
only way they are read at all):

- intent.md: Target Users, Business Outcome, Rules covered, the `Why:` lines, Assumptions (all gate checked or shown at
  the Intent gate, then unused).
- intent.md: the Given/When/Then lines of every scenario, for every script; Review's step 3 is their one model reader in
  a normal run.
- intent.md: the `Blocking: Context check` line Plan writes.
- plan.md: Patterns to Follow, Dependencies, Risk Level, the mermaid block; Architecture and Blast Radius for every
  script except one `[CROSS-REPO]` search and one heading grep.
- plan.md Files to Create and Files to Modify: read, but every path in them is also on a task's `**File:**` line, which
  the same function reads (`scripts/flow.py:2555-2558`), and the panel already counts created and modified files from
  tasks.md and the file system (`scripts/panel.py:108-112`).
- design.md: every section except Areas of Concern and the Decision Log.
- `.temper/security-map.json` for Review and Check.

---

## 2. What each agent derives again, and what `temper brief` shares

### 2.1 What the brief holds

`temper brief` (`scripts/brief.py`) is made with no model from the request's words: file paths, backticked names,
routes, nouns (`:80-91`). It writes `.temper/brief.md` with: those terms; up to 25 ranked files with line counts and why
(`:98-149`, `:193-196`); up to 30 test files that mention them (`:152-167`); the conventions files CONVENTIONS.md,
AGENTS.md, CLAUDE.md, `.claude/CLAUDE.md`, CONTRIBUTING.md, `docs/CONVENTIONS.md`, 6,000 characters each (`:25`,
`:204-208`); the best ranked files whole, up to 30,000 characters (`:34-35`, `:209-220`); and up to 200 project file
names (`:221-224`).

Measured: on the benchmark's Ledger repo (23,507 B of Python) with the partial-payments task text, 22,362 B (~5,600
tokens) in 0.04 s, with 17,622 characters of source copied whole. On the temper repo itself, 56,108 B (~14,000 tokens) in
0.28 s.

Limits [code]:

- It is made from `build-state.json`'s `feature`, the request as typed (`scripts/brief.py:241-244`), not from intent.md.
  What the person added at Intent does not steer the ranking.
- It is made before Plan and again before Design (`scripts/flow.py:1384`) and handed to those two only
  (`scripts/flow.py:1123-1125`); the RCA agent makes its own (`agents/rca.md:15-16`).
- It holds no importers or call sites, no test command, no pack rules.
- With it, Plan was "about 14% cheaper and 25% faster, Design about 13% faster", 2 runs against 3
  (`docs/evidence/bench-2026-11.md:367-368`) [doc, small sample].

### 2.2 Redundancy, agent by agent

| What | Intent | Plan | Fresh reviewer (each of A and B) | Design | Acceptance writer |
|---|---|---|---|---|---|
| The request, verbatim | yes (`scripts/flow.py:1126-1130`) | no: only intent.md and the brief's term list | no | no | no |
| Linked sources (ticket, PR, doc) | fetches (`agents/intent.md:22-30`) | **fetches again by instruction** (`agents/plan.md:24-29`, `reference/plan.md:47-50`) | no | no | no |
| CONVENTIONS, CLAUDE, AGENTS, CONTRIBUTING | reads for house rules (`agents/intent.md:110-113`) | in the brief | no | in the brief | **reads again** (`agents/acceptance.md:17-19`) |
| Code the request touches | "a quick look" | brief, then its own exploration (`reference/plan.md:175-183`) | **greps for every new module, class or helper** (`agents/plan-review.md:38-40`) | brief again, plus plan.md | reads the code the tests call |
| Existing tests | no | brief's test list; blast radius by grep (`reference/plan.md:185-193`) | **searches the test folders for tests the change breaks** (`agents/plan-review.md:45-48`) | no | **reads the tests for framework, helpers, style** (`agents/acceptance.md:17-19`) |
| Pack rules | no | reads and distils into each group's Context (`reference/plan.md:362-367`) | no | **reads again** (`reference/design.md:12-15`) | no |
| intent.md | writes | reads | reads | **reads** | **reads** |
| plan.md, tasks.md | n/a | writes | reads both whole | **reads plan.md** | reads plan.md for names |
| Architecture: components, data flow, interfaces | no | writes `## Architecture` and the diagram | paraphrases it (comprehension lens) | **writes it again** for medium: "primary system components, data flow between them, key interfaces" (`reference/design.md:24`) | no |
| Expected behaviour, case by case | criteria | scenarios, then each task's Cases (`reference/plan.md:354-360`) | checks each Case has an expected value | n/a | **a test per criterion**, from the intent alone |

The same behaviour is stated five times before any production code exists: a criterion (Intent), a scenario (Plan), a
task Case (Plan), an acceptance test (acceptance writer), and then the task's own test (Build task agent). The
criterion to scenario to task to test link is written four ways and cross checked by the gate: the criterion's
`Validate: scenario — covered by "name"` (`templates/intent.md:24-26`, `reference/plan.md:260`), the scenario's `Covers:`, the task's
`Traced to:`, and the scenario's `Test:` command naming a file a task declares (`scripts/acceptance.py:371-394`,
`scripts/gate_rows.py:117-125`). A mismatch among them parked one measured group three times
(`scripts/scenario_ops.py:78-80`) [doc in a code comment].

The task agent's PATTERN TEST (an existing test to copy, found by the CLI, `scripts/task_ops.py:391-394`) shows the CLI
can already do part of what the acceptance writer reads the test folders for.

---

## 3. The fresh review

| Fact | Value | Source |
|---|---|---|
| Lenses, round 1 | readiness (builder's view of each task block), zoom-out (unneeded work, reuse missed), comprehension (a paraphrase in the reader's words), tests (existing tests the change breaks, and which task updates them) | `scripts/fresh_review.py:38`; `agents/plan-review.md:33-48` [code] |
| Lenses, later rounds | `recheck` only: whether each earlier finding is fixed, on changed task blocks | `scripts/fresh_review.py:40`, `:165-190`; `agents/plan-review.md:49-54` [code] |
| Reviewers | one (A); two independent (A and B) when risk is H and `plan.fresh-review-twice` is not false | `scripts/fresh_review.py:128-129`; [measured]: at risk H `temper next` named two agents, each with all four lenses |
| When it runs | default `ask`: the plan question offers "Fresh review first", at every tier, and nothing runs unless the person picks it. `auto`: medium and complex. `always`. `off`. | `scripts/fresh_review.py:117-125`; `templates/temper.config.default:105`; [measured]: the option appears on the passed plan question |
| Rounds | at most `plan.fresh-review-rounds` = 3 launches a run, plus one for each loop back or replan after which plan.md or tasks.md changed | `scripts/fresh_review.py:91-100`; `templates/temper.config.default:107` [code] |
| What blocks | only `high` and `critical`; medium and low go to the named task's builder as a note | `scripts/fresh_review.py:41`, `:282-283`; `scripts/flow.py:656-669` [code] |
| What a failed round costs | "Revise the plan (Recommended)" is `state redo plan`: a new clean Opus Plan agent with the findings in its prompt, then the review again as a recheck | `scripts/flow.py:1055-1059`, `:1330-1334` [code] |
| Stale rule | any edit of the three files after the launch (outside the Context Map) runs it again | `scripts/fresh_review.py:49-76`, `:218` [code] |
| Cost of one clean round, one reviewer | +26 s of reviewer, +37 s of wall, +$0.17, about 17% of the Plan stage (3 runs each arm; "an order of size, not a rate") | `docs/evidence/fresh-review.md:70-78` [doc] |
| Launches, worst case with no loop back | 3 rounds x 1 reviewer = 3 reviewers and 2 Plan revisions; at risk H, 6 reviewers and 2 Plan revisions | from the rows above [inferred] |

What it has caught, by the evidence docs:

- **A built fixture** (`docs/evidence/fresh-review.md:24-61`): on a plan seeded with five defects, one Sonnet reviewer
  raised 5 high and 4 medium findings and found all five planted ones, plus one real flaw nobody planted (middleware that
  could not see whether the login succeeded). On the corrected plan: 0 high, 2 medium, 2 low. Two Haiku builders given the
  seeded task both passed their own tests and both failed the hidden acceptance test; two given the fixed task both
  passed. One reviewer run per plan, two builders per variant, a fixture "written for this test" (`:85-88`).
- **Two live benchmark runs** with `always` at risk H (`docs/evidence/live-brief-checks.md:11-12`, `:22-24`): reviewer
  A raised one high readiness finding in run 2; the recheck found it fixed. Each recheck also carried 7 and 6 medium
  and low findings forward. Both runs passed every hidden test (26 of 26, `:30`).
- **No benchmark run shows the review changing a hidden test result.** The 18 runs of the Haiku and Sonnet comparison
  never asked for it ("the simulated person never asked for a fresh review", `docs/evidence/live-brief-checks.md:5-6`)
  and every one passed every hidden test (`CHANGELOG.md:124-126`). [doc]
- **The failed real run** (`CHANGELOG.md:72-74`): 6 reviewers over 3 rounds. Before 9.8.4 each round read the whole
  plan again and found 18, 14 and 4 new findings without converging (`scripts/fresh_review.py:34-37`). The `tests` lens
  was added because it would have caught that run's split of a test between two groups
  (`docs/decisions/0017-a-request-that-arrives-as-a-spec.md:72`); the same split is now also a deterministic gate row,
  `group validate order` (`scripts/plan_rows.py:130-175`).

Reading [inferred]: the readiness lens finds a class of defect no gate can (a Case with no expected value, a file missing
from `**File:**`). The gate checks only that a task has 2 Cases (`scripts/plan_rows.py:44-46`). Since 9.8.4 a task agent
that needs an undeclared file records `task blocked` and the run loops to Plan (`CHANGELOG.md:129-133`), which catches
the second kind later and at a higher price. The second reviewer and rounds two and three have no evidence of their own.

---

## 4. Where Plan's 25,000 output tokens go

What is measured: "Plan about 200 s (Opus writing about 25,000 tokens: intent scenarios, tasks, plan)"
(`docs/evidence/bench-2026-11.md:457-458`), and a median of 24,617 output tokens per Plan run on the password-reset
fixture (`docs/evidence/opus5-plan-prompt-ab.md:18`). Neither doc splits the figure by section, and it includes
everything the model emits (tool call arguments and its text between calls), not only the three files.

No model written spec is in the working tree (`.temper/specs/` is ignored, `.gitignore`). One real Plan output exists in
git history: `.temper/specs/mods-support/` at commit `eaba313` (v9.6.0, a complex feature: 16 criteria, 32 scenarios, 23
tasks). It predates the Context Map, grouped tasks, Cases and `Test:` lines. I measured it; the proportions are the only
measured split available, from one sample.

| What Plan wrote (sample) | Bytes | ~Tokens | Share of Plan's files |
|---|---|---|---|
| plan.md, whole | 22,634 | 5,650 | 42% |
| of which Files to Create + Files to Modify | 8,406 | 2,100 | 16% |
| of which Architecture (with "Context sources re-read") | 4,516 | 1,130 | 8% |
| of which Blast Radius proper (with the hot path table) | 3,247 | 810 | 6% |
| of which Approach Decisions (5) | 2,878 | 720 | 5% |
| of which Diagram | 1,259 | 310 | 2% |
| of which Patterns, Dependencies, Risk Level, Cross-Repo Search | 1,861 | 465 | 3% |
| intent.md Scenarios (32) | 14,540 | 3,635 | 27% |
| of which Given/When/Then lines | 10,426 | 2,600 | 19% |
| tasks.md (23 tasks) | 16,405 | 4,100 | 31% |
| of which `Traced to:` lines | 3,635 | 910 | 7% |
| of which free text Notes | 5,270 | 1,320 | 10% |
| **Total** | **53,579** | **~13,400** | 100% |

So on this sample the three files are a little over half of a 25,000 token Plan run; the rest is tool calls and text
between them [inferred: the sample and the 25,000 figure come from different runs].

Section by section: who needs it, and whether the CLI could make it.

| Part | Verdict | Basis |
|---|---|---|
| plan.md, all of it, at simple tier | **Drop.** With only intent.md and tasks.md in the spec folder and the default config, `temper gate plan` printed PASS (25 rows) and `temper next` went straight to the plan question: no Context check | [measured] in a throwaway project; `scripts/gate_rows.py:310-311`, `scripts/temper:3549-3550` |
| Files to Create, Files to Modify | **Compute.** Every reader also reads the tasks' `**File:**` lines; create or modify is a file system check the panel already does | `scripts/flow.py:2538-2559`; `scripts/panel.py:108-112` |
| Risk Level | **Drop.** `temper risk` computes it; nothing reads the section | `scripts/risk.py:72-108`; grep |
| Patterns to Follow, Dependencies | **Drop or fold into the group Context**, which is what the builder actually receives | `reference/plan.md:362-367`; grep |
| Diagram, twice | **Keep one form at most**, none at simple tier. Only the `text` block is printed | `scripts/panel.py:144-158` |
| Cross-Repo Search | **Compute the default.** With no tool connected it is one fixed line, and its absence is named as a usual cause of a failed gate | `scripts/temper:2126-2151`; `reference/plan.md:96-97` |
| Context Map `use:` lines | **Compute** from the brief's ranked files; keep only `ignore:` and `gap:`, which are Plan's judgment | `scripts/plan_ops.py:25`; `scripts/brief.py:193-196` |
| Blast Radius: importers and their tests | **Compute a first cut** (the brief already finds the tests that mention a touched module); Plan adds only what a grep cannot see. Only the heading is gate checked | `scripts/brief.py:152-167`; `scripts/temper:3562` |
| Architecture | **Shrink.** Its readers are Design, the fresh reviewer and the acceptance writer's search for entry point names; `**Interfaces:**` in tasks.md already names the seams | `agents/acceptance.md:16-17`; `reference/plan.md:385-387` |
| Approach Decisions | Keep; already optional and short | `reference/plan.md:283-287` |
| Scenario step lines | **Drop or cut to one line.** No script reads them; the builder never sees them; each task's Cases state the same behaviour with exact values | `scripts/acceptance.py:91-112`; `scripts/task_ops.py:386-389`; `reference/plan.md:354-360` |
| `Covers:`, `Test:`, scenario names | Keep: this is what the gates and Build use | as above |
| `Traced to:` | **Compute.** The owner task follows from the `Test:` command's file and the `**File:**` lines | `scripts/scenario_ops.py:85-98` |
| tasks.md task blocks and group Context | **Keep; this is the product.** It is all a builder gets | `scripts/task_ops.py:384-390` |
| The `Blocking: Context check` line in intent.md | **Drop.** Never read | `scripts/flow.py:371-373`, `:392-396` |

Estimate [inferred from the sample's proportions]: dropping plan.md's unread sections, the step lines and `Traced to:`
removes roughly 40% to 60% of the bytes Plan writes into files (plan.md alone is 42%, step lines 19%, `Traced to:` 7%;
a short Architecture, the decisions and the blast radius notes stay).

The prompt is also heavier than it needs to be [code]:

- `reference/plan.md` (27,927 B, ~7,000 tokens) is read on every Plan launch, a revision included, and holds text for
  other readers: the fresh review's bookkeeping (`:101-128`), the approval dialog (`:414-418`).
- It contradicts the gate: "Skip this section for Trivial/Simple" on scenarios (`:224`) against the gate's scenario
  per criterion row at every tier (`:85-86`, `scripts/temper:3507-3514`).
- It is stale on Design: "Medium ... / Complex ...: Design runs" (`:40-41`), also `reference/design.md:7-8`, `:103-105`
  and `templates/temper.config.default:112`, against `scripts/flow.py:258-266`.
- It still asks for decision lines "in the summary box" (`:293-294`), which the CLI has drawn since 9.8.0 (`:407-412`).
- Shrinking this page from 1,086 to 224 lines cut the cost of a Plan run by 41% to 48% with equal gate results and no
  change in wall time (`docs/evidence/opus5-plan-prompt-ab.md:13-17`, `:42-45`) [doc]. It has since grown to 428 lines
  [measured].

Two more costs inside the Plan agent's own run:

- Plan runs `temper gate plan` itself (`agents/plan.md:59-61`). The row `context map reviewed` fails by construction
  while the line says `pending` [measured], and the fresh review rows fail when it applies; the agent has to read a FAIL
  and judge it harmless. The flow already knows these rows as `PERSON_ROWS` (`scripts/flow.py:2626`).
- Since PR #115 that gate call also runs every Validate, Test, Integration and scenario `Test:` command once on HEAD,
  each up to 300 s (`scripts/preflight.py:6-12`; `agents/plan.md:100-105`), inside the Opus agent's turn. The result is
  stored and reused while HEAD and the commands are unchanged. On my four trivial commands the whole gate took 1.4 s
  [measured]; on a Maven project it is the suite's own time.

---

## 5. Launches and output tokens between the request and the first Build task

Defaults (`templates/temper.config.default:103-112`): `context-check: auto`, `fresh-review: ask`,
`fresh-review-twice: true`, `fresh-review-rounds: 3`, `phases.design: true`.

The sequence, traced with the real CLI in a throwaway project [measured]:

1. `temper next` names the Intent agent on `sonnet`; after it: `usage add`, `gate intent`.
2. With a Blocking question open, the intent gate fails on that one row and `next` gives the question list. After
   `temper intent answer`, the gate passes with no agent launched again.
3. Intent gate question: "Accept the intent and continue to Plan?" Its calls: `spec branch`, `intent accept`,
   `spec commit`, `state advance intent_complete plan`.
4. `next` runs `temper brief` and names the Plan agent on `opus`; after it: `usage add`, `panel plan`, `gate plan`.
5. With `reviewed: pending` and only `use:` lines in the map, `gate plan` fails on `context map reviewed` and `next`
   asks "Is this the right context for the plan?" (As planned / Something else / Carry forward).
6. Plan gate question: Stage by stage / Autonomous Build / Fresh review first / More options. With a Design stage ahead
   it reads "Continue to Design (Recommended)" instead and the arm option moves to the Design question.
7. At stage build, `next` names the acceptance writer on `sonnet` (before: `acceptance start`). Only after it does
   `next` say `group start G1`.

| Case, with defaults | Agent launches before the first Build task | Dialogs with the person, at least | Agent wall time [doc] | Output tokens |
|---|---|---|---|---|
| Trivial (Intent returns `TRIVIAL`) | 1: Intent (`agents/intent.md:17-20`) | 0; the run is cleared and the session makes the change | about 30 s | a few hundred [inferred] |
| Simple; medium at risk L or M; complex at risk below H when Intent asked nothing | **3**: Intent (Sonnet), Plan (Opus), acceptance writer (Sonnet) | **3**: Intent gate, Context check, Plan gate. Plus 1 or 2 more for Intent's Blocking questions (up to six, four a dialog: `agents/intent.md:134`, `commands/temper.md:163-165`), plus any Blocking question Plan adds (`reference/plan.md:265-268`) | 30 to 45 + 143 to 246 + 30 to 45 s | Plan about 25,000 [doc]; Intent and the acceptance writer not measured, a few thousand each [inferred] |
| Medium or complex at risk H; complex when Intent asked anything | **4**: the above plus Design (Opus) (`scripts/flow.py:266`) | **4**: plus the Design gate, plus a dialog for `Design:` questions when there are any | plus 88 to 116 s | plus roughly 10,000 to 13,000 [inferred from cost] |
| Any of the above when the person picks "Fresh review first" (never by default) | plus 1 reviewer a round (2 at risk H); a round with a high finding adds a Plan relaunch and another round; at most 3 rounds | plus 1 plan question a round | plus 26 to 37 s a clean round; plus a Plan pass per revision | reviewer about 61,000 tokens in all (`docs/evidence/fresh-review.md:78`); output not split |
| Worst case with no loop back: risk H, fresh review, 3 rounds | **12**: Intent 1, Plan 3, reviewers 6, Design 1, acceptance 1 | | | |
| The failed real run | 5 Plan passes, 6 reviewers, about 30 questions (`CHANGELOG.md:72-74`) | | | |

Where the time and the dollars sit in that front part [doc]: Plan and Design on Opus were 45% to 60% of a run's cost with
a Sonnet loop and 64% to 83% with a Haiku loop (`docs/evidence/bench-2026-11.md:239`, `:275-277`).

Three things make the count grow without a fault:

- **Design switches on for most complex requests.** `intent_asked` is set whenever Intent leaves one Blocking question
  (`scripts/temper:2096-2100`), and Intent's brief makes it ask for every checklist item the request leaves open
  (`agents/intent.md:93-113`). [inferred that this is the usual case]
- **The person can be asked product questions at three separate points**: Intent's Blocking questions, Plan's
  (`reference/plan.md:265-268`), Design's (`reference/design.md:37-42`), each written by a different clean agent.
- **Any change is a full relaunch**: a typed change request, "Include what is left out" or "Something else" at the
  Context check, and "Revise the plan" all run `state redo plan` (`commands/temper.md:158-160`;
  `scripts/flow.py:2318`, `:2327`, `:1056-1059`).

Loop budgets that send the run back through this front part: Build to Plan once a run; every other pair
`loops.max-per-type` = 2 (`scripts/loop_step.py:20-32`). A step back redoes the later stages too
(`scripts/flow.py:591-593`).

No evidence doc measures Plan on a model other than Opus ("The agents' models never changed (Plan and Design on Opus)",
`docs/evidence/bench-2026-11.md:225`). `models.plan: sonnet` is a config key away (`scripts/cli_ctx.py:61-64`).

---

## 6. One front agent: Intent, Plan and Design in one context, one approval

### 6.1 What it would gain

| Gain | Size | Basis |
|---|---|---|
| Launches before Build | 3 or 4 down to 2 (front agent, acceptance writer) | section 5 |
| No separate Design pass | 88 to 116 s and $0.48 to $0.61 when it runs; some of that work moves into the front agent | `docs/evidence/bench-2026-11.md:357` [doc] |
| Dialogs | 3 or 4 gate dialogs down to 1, plus the question dialog. The mechanics exist: any gate question can carry the Blocking list, asked first in the same step, four questions a dialog | `scripts/flow.py:2478-2481`; `commands/temper.md:108`, `:163-170` [code] |
| No second and third reading | Design reads intent.md, plan.md, the brief and the packs again; Plan fetches Intent's sources again | section 2.2 |
| The Design to Plan loop cannot happen | decisions are made before the tasks are written, so `tasks agree with decisions` has nothing to check | `scripts/decisions.py:1-13`; `scripts/flow.py:733-739` |
| The request stays in context | today only Intent gets `Feature:`; a Plan once built the request's route as another path, and a gate row was added for it | `scripts/flow.py:1126-1130`; `scripts/gate_rows.py:263-268` |
| One place asks questions | today three stages can each add Blocking questions | section 5 |

### 6.2 What it would lose or risk

| Loss | How much it matters | Basis |
|---|---|---|
| The cheap first gate. The intent gate exists so "the human review the CHEAP artifact before the expensive stages run" | Real for a vague request: Temper's one measured win is asking before building. A front agent that plans before the answers arrive wastes the plan when an answer changes it. It needs either two steps in one context (questions, then the plan), or a plan written under the recommended answers with a narrow patch when one differs | `scripts/temper:2028-2031` [code]; `docs/evidence/bench-2026-11.md:118` [doc] |
| Sonnet prices for the intent part | Small: Intent is 30 to 45 s of a run. Or the whole front agent runs on Sonnet, which nobody has measured | `docs/evidence/bench-2026-11.md:457-459` |
| A second Opus look at the plan (Design) | Unknown value. The code's own comment says of Design before 9.8.0: "minutes per run, and concerns the person only approved" | `scripts/flow.py:258-262` [doc in a comment] |
| A bigger instruction set in one context | The three briefs and two reference pages are about 65,000 B if only joined; they must be rewritten as one short contract, which the A/B says pays for itself | sizes [measured]; `docs/evidence/opus5-plan-prompt-ab.md:13-17` |
| Intent as a file that stands alone | `/temper:intent` and the control bands write a draft to be built later; the front agent must take an existing draft or accepted intent as its input, and intent.md must stay a file | `commands/intent.md:8-18`; `agents/intent.md:32-51` |
| The acceptance writer's independence | Keep it a separate agent: its tests "come from the intent alone" so that they cannot share the builder's or the planner's guess | `agents/acceptance.md:7-10` |

### 6.3 What the code and the gates assume today, that would have to change

Each item is verified in code; the mod rules were also run.

1. **Three stages in the sequence.** `SEQ` and `BACK_TO` name intent, plan, design (`scripts/flow.py:47-55`);
   `advance_ok` lets a run leave only the stage it is at, on that stage's own verdict (`scripts/flow.py:2510-2535`).
2. **The intent gate refuses a draft that holds scenarios** (`no scenarios in draft`,
   `scripts/intent_draft_rows.py:169-173`) and fails while a Blocking question is open (`scripts/gate_rows.py:27-41`).
   The draft rows are skipped only once the Status is `accepted` (`scripts/intent_draft_rows.py:19-34`). A file that
   holds intent and scenarios cannot pass as a draft.
3. **Acceptance of the intent is the person's "Continue to Plan"**: `spec branch`, `intent accept`, `spec commit`,
   `state advance intent_complete plan` (`scripts/flow.py:557-565`, `:633-637`). The run's branch is created there. "A
   recorded acceptance is never revisited" except on a loop back (`agents/intent.md:42-51`).
4. **The mod's write rule is per stage.** At `intent` only intent.md and `intent-context.json` may be written; a Write
   of plan.md or tasks.md is denied. At `plan` the `acceptance/` folder is denied. From `design` on tasks.md is denied
   (`hooks/temper-mod/core/rules.ts:243-275`) [measured with the rule function for each of these paths].
5. **Three agent types and three briefs**: `temper:temper-{stage}` (`scripts/flow.py:1135`), the model table
   (`scripts/cli_ctx.py:21`), the agents list in `.claude-plugin/plugin.json:38-42`, and the mod's exact prompt match
   for a launch (`scripts/flow.py:1255-1257`).
6. **Design is wired in several places**: `has_design` (`scripts/flow.py:251-266`); the Design gate
   (`scripts/temper:3718-3739`); the commit gate and the CLI's own commits demand a design verdict whenever design.md
   exists (`scripts/temper:2906-2915`, `:4124-4129`); the arm option moves to the Design question when Design follows
   (`scripts/flow.py:670-675`, `:726-728`); `state advance design_complete` approves tasks Design changed
   (`scripts/temper:1178-1183`), which the mod forbids Design to change.
7. **The fresh review is tied to the plan stage**: its digest covers intent.md, plan.md and tasks.md
   (`scripts/fresh_review.py:45`, `:62-76`) and it launches only when the plan gate's other rows pass
   (`scripts/flow.py:2424-2429`).
8. **The doors and the walk**: `/temper:plan` and `/temper:design` enter at a named stage, and `walked` uses the fixed
   order of all seven stages (`scripts/flow.py:1110-1116`; `commands/temper.md:192-200`).
9. **Panels and usage rows are per stage**: `temper panel plan|design` (`scripts/panel.py:3-6`),
   `usage add --stage` (`scripts/flow.py:1136`); the report and the mod's pane draw stages by name.
10. **The brief is made from the request text and only for plan and design** (`scripts/brief.py:241-244`;
    `scripts/flow.py:1384`).
11. **The project's own rules for a change of this kind** (`.claude/CLAUDE.md`): what comes next and a gate's options
    live in `scripts/flow.py` with a case in `temper-cases-8.sh`; the view fixtures are regenerated; a new agent is
    listed in `plugin.json`; stage logic lives in that stage's brief, never in `commands/temper.md`.

A smaller step that keeps most of the gain [inferred]: keep the stage names in the run state, so the commit hook, the
doors and the ledger stay as they are, and let one agent launch satisfy the intent gate and the plan gate, with the
design concerns written as Blocking questions and the person answering once. That needs items 2, 3 and 4 changed and
item 6 made optional; items 1, 7, 8 and 9 can stay.

---

## 7. Other defects and drift found on the way

| What | Where | Tag |
|---|---|---|
| `plan.context-check: auto` asks on every run; documented as conditional | `scripts/flow.py:2338`, `scripts/plan_ops.py:92-94` against `reference/plan.md:71`, `templates/temper.config.default:104` | measured |
| Intent's own gate call fails by construction when it asks a question, and the brief says to fix every FAIL | `agents/intent.md:141-143`, `scripts/gate_rows.py:37-40` | measured |
| The CLI lets Design change tasks.md and approves the change; the mod refuses the write | `scripts/temper:1181-1183`, `scripts/flow.py:719-725` against `hooks/temper-mod/core/rules.ts:243-247` | code, measured on the rule |
| The env agent's draft path is denied at Plan by the mod's rule | `agents/env.md:27`, `hooks/temper-mod/core/rules.ts:263-275` | measured on the rule, not live |
| `models.env` cannot be set | `scripts/cli_ctx.py:21`, `scripts/flow.py:1222` | code |
| `context_choices` has no caller; Plan still writes the line it parses | `scripts/flow.py:392-396`, `agents/plan.md:91-92` | code |
| `reference/plan.md` says to skip scenarios at simple tier; the gate requires them | `reference/plan.md:224` against `scripts/temper:3507-3514` | code |
| Docs and the config comment say Design runs for every medium and complex plan | `reference/plan.md:40-41`, `reference/design.md:7-8`, `:103-105`, `templates/temper.config.default:112` against `scripts/flow.py:258-266` | code |
| `security-map.json` is "for Review/Check to read"; neither reads it | `reference/plan.md:403-405` | grep |
| `/temper:intent` still always asks for a reviewer | `commands/intent.md:46-48` against `scripts/intent_draft_rows.py:158-160` | code |
| Intent, the acceptance writer, the fresh reviewer and the env agent still draw their own 76 column box. The CLI took this over for Plan and Design because it cost "2,000 to 3,000 output tokens and 30 to 40 seconds a stage", and a Build task agent spent about one of its three minutes on it | `agents/intent.md:162-187`, `agents/acceptance.md:74-86`, `agents/plan-review.md:92-107`, `agents/env.md:57-70`; `scripts/panel.py:8-10`; `docs/evidence/bench-2026-11.md:459-460` | code; the cost for these four agents is not measured |
| A Blocking question Plan adds is answered into Decisions, but only `Design:` answers are tracked against tasks.md | `scripts/decisions.py:42-43` | code |
| `scripts/acceptance.py` is the criteria and scenario link checker; the acceptance tests' lock lives in `scripts/check_run.py` | `scripts/acceptance.py:1-25`, `scripts/check_run.py:625` | code |

---

## 8. What I could not determine

- The output tokens of Intent, Design, a fresh reviewer and the acceptance writer one by one. The docs give seconds, and
  dollars for Design only.
- How Plan's 25,000 output tokens split between the three files and its tool calls in a current run. My split is from one
  spec written under v9.6.0.
- How often Design runs in practice, and how often a real person takes the recommended answer to a Blocking question
  (the benchmark's person always takes the first option, `docs/evidence/bench-2026-11.md:189`).
- Whether Claude Code or the mod's run driver can send a follow up to a stage agent that keeps its context. Every path I
  read launches a new agent.
- Whether the mod applies its stage write rule to the env agent's Write in a live session. I ran the rule function only.
- Whether Plan, or a single front agent, holds its quality on Sonnet. Never measured.
