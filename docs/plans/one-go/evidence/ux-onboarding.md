# What a user meets: onboarding, surface, context weight, friction

Reader: ux-onboarding (1 of 17). Tree: `/home/user/temper` at the head of PR #115 (`pr115`, 9.8.5, commit `9a01eff`).
All paths are relative to that tree unless absolute. Runs were made only in a clone and throwaway projects under
`/tmp/claude-0/-home-user-temper/1ba4743b-465f-5ae6-8b88-a04ebb2fe840/scratchpad/work-ux-onboarding`.

Confidence tags used below:
**[code]** read in code, **[ran]** a command I ran in the scratch clone and its result, **[doc]** only a claim in a doc or
a prompt, **[inferred]** my reasoning from the above. Token figures are bytes divided by 4 (an estimate, not a tokenizer count).

## 0. The main findings, in order of weight for the owner's goal

1. **The default run asks 5 gate questions plus one per Build group plus up to 6 Intent questions; the least-friction
   run asks 3 gate questions, but reaching it takes two config edits, one environment variable set outside Temper and one
   click on a non-recommended option in every run.** None of the three is described in README or Getting Started
   (section 5).
2. **The approvals show little of what is being approved.** The Intent panel shows the count of criteria, not the
   criteria. The Plan panel shows counts of files, not the files, groups or tasks. The Check question shows no number at
   all; the 88-line report is printed after the person has chosen Commit (section 6).
3. **Two defaults fail a first run on an ordinary existing project with correct code:** Check requires total project
   line coverage of 80% or more, and Maven, Gradle and Rust have no coverage command unless a config key that the template
   does not list is set. A measured value below 80% recommends a loop back to Build (section 1.4).
4. **The surface is large and partly dead:** 11 commands (5 are doors, 1 is automatic), 5 skills (3 not user-invocable,
   2 of those generic advice), 8 packs plus 6 stack files that nothing loads, 53 keys in the shipped config (2 with no
   reader, a third group read only by prompts), 5 plugin options, 66 option label templates, 115 terms (section 2).
5. **PR #115 adds surface and two small defects in my area:** 9 config keys, 1 agent, 3 CLI commands in the user
   reference; a duplicate top-level `build:` key in the config template that silently cancels the grouped-build tuning
   keys once a user uncomments them; and `.temper/preflight.json` left untracked in the user's `git status`
   (sections 1.2, 2.4).
6. **Context weight is modest per session (about 1,150 tokens always on) but heavy per agent:** Plan reads about 23,000
   tokens of Temper's own text before any project code; Review and the Build fix pass about 10,500 each; every agent
   that reads the project's config reads 2,400 tokens of mostly comments; every brief is named in the launch prompt of an
   agent type whose system prompt is that same brief (section 3).

---

## 1. The first run on an existing project, step by step

### 1.1 Install and first command

| Step | What the user does or sees | Source |
|---|---|---|
| 1 | `/plugin marketplace add galando/temper`, then `/plugin install temper` (one step on Claude Code 2.1.275 or later) | `README.md:13-18` [doc] |
| 2 | The same install loads the mod on Claude Code 2.1.287 or later (stage bar, pane, write guard) | `docs/getting-started.md:29-36`, `hooks/hooks.json:37-39` [code] |
| 3 | Types `/temper:temper "describe the feature"`. The short `/temper` "may not resolve in every surface" | `README.md:20`, `docs/getting-started.md:20-21` [doc] |
| 4 | Without the mod, the first line of the reply is "Temper enforcement is off here (no mods support); continuing with prompt based phases." | `commands/temper.md:9-14` [doc] |
| 5 | The command body (17,042 bytes) enters the main conversation; the turn runs on Sonnet (`model: sonnet`) | `commands/temper.md:4` [code] |

Prerequisites (`bash`, `git`, `python3`) are not stated in README or Getting Started; the CLI fails with
"python3 is required" when it is missing (`scripts/temper:264`) [code]. `docs/trust.md:12` names them.

Nothing in the user docs mentions Claude Code's own permission prompts. No command declares `allowed-tools`
(frontmatter of all 11 commands holds only `description`, `argument-hint` and, for two, `model`) [ran: frontmatter
parse]. How many permission prompts a first run raises in the default permission mode I could not determine (no live
session); see Open questions.

### 1.2 What Temper writes into the project before any question

`temper next --json` in a fresh git project returns `setup` with three calls: `temper config init`, `temper init`,
`temper guards install` [ran]. After running them in a throwaway project:

| Written | Where | Size or content | Tracked by git? | Source |
|---|---|---|---|---|
| `.claude/temper.config` | project | 9,647 bytes, byte-identical to `templates/temper.config.default` (172 lines, 123 of them comments) | untracked: `git status` shows `?? .claude/` | [ran: `diff` says SAME] |
| `.temper/gates.json`, `overrides.json`, `feedback-loops.json` | project | scaffold | hidden by `.git/info/exclude` | [ran] |
| `.temper/view.json` | project | written by `temper next` itself | hidden | [ran] |
| 26 lines appended to `.git/info/exclude` | git folder | the run files and `/.claude/worktrees/` | n/a | [ran], `scripts/temper:632-634` [code] |
| `.git/temper-gate/pre-commit` | git folder | 5,529 bytes | n/a | [ran] |
| `git config --local core.hooksPath` | git config | absolute path of `.git/temper-gate` | n/a | [ran] |

Then `temper state init <slug> --feature '<text>'` writes `.temper/build-state.json` and `.temper/agents-named.json`
and reserves the branch name `feature/<slug>` [ran].

Things a new user can trip on here:

- **A hook manager is already there** (husky, lefthook, the pre-commit framework, git-lfs hooks). The installer refuses
  to set `core.hooksPath`, keeps its hook aside and prints one shell line the user must paste into their own hook; the
  run goes on "without the commit gate until you add it" (`commands/init.md:130-174`, `docs/commands.md:649-665`) [doc].
  The explanation of this in `commands/init.md` is 116 lines (59 to 174).
- **`.claude/temper.config` stays untracked** until the user commits it. The run never commits it: the changed-file list
  drops `.claude/` and `.temper/` (`scripts/flow.py:2940-2941`) [code]. A second worktree (`claude --worktree x`, which
  `docs/getting-started.md:288-289` recommends for parallel work) has no config and gets a fresh default from
  `config init`, so config edits made in the first checkout do not apply there [inferred from the two facts above].
- **`.temper/preflight.json` shows up as untracked** after a run: `git status` printed `?? .temper/preflight.json` after
  the e2e full run [ran]. It is written by `scripts/preflight.py:166` (new in 9.8.5) and is not in `_RUN_FILES`
  (`scripts/temper:632-634`). `.temper/decisions.json` (`scripts/decisions.py:21`) is not in the list either [code].
- **Agents run in the background by default** in Claude Code, and "Claude Code does not promise that turn for a session
  that sits idle: if a run waits after an agent finished, send any message, such as 'go on'". The cure is an environment
  variable the user sets by hand, because "A plugin cannot set it for you, and Temper does not edit your settings"
  (`docs/getting-started.md:92-108`) [doc]. Whether the mod's run driver removes the stall is another reader's question;
  `docs/mod.md:274-293` says the driver "launches each agent ... and waits for it" [doc].

### 1.3 Every question before the first line of code (default config)

Verified by running the e2e scenarios `full-run`, `design` and `context-check` in plain mode in the scratch clone and
printing each question (`scripts/e2e/run.ts`, instrumented only in the clone) [ran].

| # | Question (header) | Options, in order | When | Source |
|---|---|---|---|---|
| a | `Question 1` to `Question 6`: the Intent agent's Blocking questions | up to 3 ready answers (first marked Recommended) then `Carry forward`; 4 questions per dialog, so 6 take two dialogs | whenever the request leaves a rule open; "Ask at most six" | `agents/intent.md:131-135`, `scripts/flow.py:2488-2507`, `commands/temper.md:163-167` [code] |
| b | `Temper gate`: "Intent: the check passed. Accept the intent and continue to Plan?" | Continue to Plan (Recommended), Grill Me, Teach Me, Save for later | always | `scripts/flow.py:633-637` [ran] |
| c | `Temper gate`: branch clash variant of (b) | Continue on `<branch>`, Continue on a new branch, Grill Me, Save for later | the run's branch exists from an earlier run with commits HEAD lacks | `scripts/flow.py:622-632` [code] |
| d | `Temper gate`: the Context check, e.g. "It could not find: no rate limit policy ... Is that right?" | As planned (Recommended), [Include what is left out], Something else, Carry forward | `plan.context-check: auto` (default) and the plan's Context Map has an `ignore` or `gap` line | `scripts/flow.py:2289-2329`, `templates/temper.config.default:104` [ran] |
| e | `Temper gate`: "Plan: the check passed. Approve the plan and continue to Build?" | Stage by stage (Recommended), Autonomous Build: run Build unattended, Fresh review first, More options (Open HTML review, Grill Me, Teach Me, Save for later) | simple features (no Design) | `scripts/flow.py:672-680` [ran] |
| e' | same header: "... continue to Design?" | Continue to Design (Recommended), Fresh review first, Open HTML review, More options (Share HTML review, Grill Me, Teach Me, Save for later) | medium and complex features | [ran: `design` scenario] |
| f | `Temper gate`: "Design: the check passed. Continue to Build?" | Continue to Build (Recommended), Autonomous Build: run Build unattended, Walk through step by step, More options (Grill Me, Loop back to Plan, Teach Me, Save for later) | medium and complex features, `phases.design: true` (default) | [ran: `design` scenario] |
| g | `Temper gate`: preflight or environment failure | Add the proposed setup block (Recommended) or Let an agent find the setup, Loop back, Override, Save | the plan's commands fail on the environment (new in 9.8.5) | `scripts/flow.py:693-700, 1183-1205` [code] |

Count before code: 2 gate clicks at least (b, e), 3 for medium or complex (b, e', f), plus 0 to 6 answers (a), plus (d)
when it applies. "First line of code" here is the acceptance tests, which the acceptance agent writes right after the
plan is approved (`temper acceptance start`, in the e2e trace) [ran].

Files and commits made before code: `.temper/specs/<slug>/intent.md`; branch `feature/<slug>` created or switched to;
commit `docs(intent): accept <slug>`; `.temper/brief.md`; `plan.md`, `tasks.md` (and scenarios added to `intent.md`);
`.temper/preflight.json`; commit `docs(plan): approve the plan of <slug>`; for Design, `design.md` and, only in a project
that already keeps ADRs in `docs/decisions/`, new ADR files (`reference/design.md:85-99`) [code and ran].

### 1.4 The rest of the run and what it leaves

| # | Question | Options | Source |
|---|---|---|---|
| h | `Build group`: "Group G1 (title) passed its check. Continue?", once per group | Continue (Recommended), Change, Stop | `scripts/flow.py:1928-1950`; skipped for a plan with one group (`:1761-1765`) and in an armed run (`:1759-1760`) [ran] |
| i | `Temper gate`: "Build: the check passed. Continue to Review?" | Continue to Review (Recommended), Change something, Teach Me, More options | [ran] |
| j | `Temper gate`: "Review: the check passed. Continue to Check?" | Continue to Check (Recommended), Architecture Depth Review, Grill Me, More options | [ran] |
| k | `Temper gate`: "Check: the check passed. Commit?" | Commit (Recommended), Loop back to Build, Commit and open PR, More options | [ran] |

Totals for one clean run, default config [ran, `full-run` trace]: 2 groups gave **7 gate questions** (b, e, h, h, i, j,
k) plus the Blocking answers. One group gives 5. Armed (the person picked "Autonomous Build" at e) gave **4** (b, e, j,
k) [ran, `armed-run` trace]. Armed with `autonomy.policy: decide` gives **3** (b, e, and the commit question the park
raises): `scripts/flow.py:1144-1181, 2227-2231, 2243-2245` [code; not run end to end].

What a two-task feature leaves in the repository [ran, e2e `full-run`, `git log`]:

- 8 commits on `feature/<slug>`: `docs(intent): accept`, `docs(plan): approve the plan`, one `feat(<slug>): Task N` per
  task, one merge per group plus a base merge, and `docs(<slug>): record the run: spec, gate ledger and report`.
- Tracked files: `.temper/specs/<slug>/intent.md`, `plan.md`, `tasks.md`, `gate-ledger.json` (12 KB), `report.html`
  (4.5 KB), plus the code and tests.
- During Build: one git worktree per group at `.claude/worktrees/temper-<slug>-<G>` on branch `temper/<slug>/<G>`
  (`scripts/temper:2306, 2380`) [code].

**Two defaults that fail Check on a first run with correct code** [code]:

- Check's `coverage >= threshold` row compares the **total line coverage of the project** (`scripts/check_run.py:11,
  161`: `totals.percent_covered`) with `check.coverage-threshold`, 80 by default (`templates/temper.config.default:34`,
  `scripts/temper:3904-3913`). An existing project under 80% fails the row whatever the change did. For a measured value
  below the threshold the question's recommended option is `Loop back to Build` (`scripts/flow.py:875`:
  `back_opt(rec=not gap)`), and an armed run under `policy: decide` loops back by itself while the budget lasts
  (`scripts/flow.py:1176-1180`).
- Maven, Gradle and Rust projects have `coverage: None` unless `check.commands.coverage` is set
  (`scripts/check_run.py:139-144`); a Python project without `coverage.py` gets the same row (`:99-110, 712`). The row
  fails with "recorded coverage 'none'" and the question recommends "Run Check again" (`scripts/flow.py:852-865`; the
  comment at `:853-854` records a benchmark run that "ran Check again 52 times" before a fix).
  `check.commands.coverage` is read by the CLI (`scripts/temper:4938`) but is not in the config template, whose
  `check.commands` example lists only `test`, `lint` and `typecheck` (`templates/temper.config.default:42-45`).

**One edge where the first promise is weaker than its wording** [ran]: `temper gate intent` passes when `intent.md` does
not exist ("intent.md absent, trivial path, no artifacts", `scripts/temper:2038-2039`). In a scratch run with a started
run and no `intent.md`, the next `temper go` asked "Intent: the check passed. Accept the intent and continue to Plan?"
with the option text "Accept intent.md, commit it on the run's branch". An Intent agent that returns without writing
the file therefore leads to an approval question about a file that is not there.

---

## 2. Inventories

### 2.1 Commands: 11 registered (`.claude-plugin/plugin.json:25-37`)

| Command | Kind | Body bytes | What it is | Verdict for 90% of users |
|---|---|---|---|---|
| `/temper:temper` | the flow | 17,042 | the loop over `temper go`; also 16 reserved first words (below) | keep |
| `/temper:fix` | second flow | 5,212 | RCA, then the same loop (`commands/fix.md:70-77`) | keep |
| `/temper:intent` | capture | 7,809 | interviews and writes a draft `intent.md`, no run | merge into `/temper:temper` (the Intent gate already has Save for later) |
| `/temper:plan` | door | 941 | "Read commands/temper.md now and follow it" | remove from the listing |
| `/temper:design` | door | 909 | same | remove |
| `/temper:build` | door | 893 | same | remove |
| `/temper:review` | door | 893 | same | remove |
| `/temper:check` | door | 891 | same | remove |
| `/temper:status` | dashboard | 2,977 (+ `reference/status.md` 10,814) | metrics, bands, drift, MCP probe | fold into `/temper:temper status`, which exists (`commands/temper.md:37`) |
| `/temper:pack` | manager | 12,692 (+ `reference/pack.md` 16,453) | toggle packs, build packs, print guardrail hooks | hide; a doc page and one CLI call |
| `/temper:init` | setup | 15,493 | "most people never call `/temper:init` by hand" (`commands/init.md:12-13`) | remove from the listing; keep `temper guards install|uninstall` |

README shows 4 commands (`README.md:66-71`); `docs/index.md:77` says "Three you'll actually type"; the plugin registers
11 and every session lists all 11.

Reserved first words of `/temper:temper` (`commands/temper.md:35-44`): `status`, `report`, `timeline`, `help`,
`approve`, `next`, `back`, `override`, `accept`, `drift`, `pr`, `discuss`, `chose`, `mode`, `enforcement`, `pane` = 16.
With the mod, 7 of them are matched in code on the first word alone (`hooks/temper-mod/core/commands.ts:6, 15-19`), so
an unquoted request that begins with one ("status badge on the order page", "report export to CSV") is answered as a
subcommand, not started as a feature [code]. A quoted request is safe in the mod, because the first token then starts
with the quote character [inferred from the regex at `commands.ts:17`].

### 2.2 Skills: 5 (`.claude-plugin/plugin.json:53-59`)

| Skill | Bytes | User-invocable | Used by | Verdict |
|---|---|---|---|---|
| `temper-core` | 6,370 | no | named in `reference/review.md:14`, `reference/build.md:169`, `reference/check.md:17`; holds a third copy of the enforcement-marker paragraph (`skills/temper-core/SKILL.md:11`), a list of pack paths and an index of reference pages | remove; inline the 3 definitions it is cited for |
| `context-engineering` | 3,835 | no | one mention, `reference/fix.md:23` | remove |
| `source-driven-development` | 5,314 | no | `agents/build.md:17, 104`, `agents/fix.md:18`, `reference/build.md:145` | fold 2 lines into the build and fix briefs |
| `grill-me` | 4,255 | yes | an option at the Intent, Plan, Design and Review gates (`scripts/flow.py:632-640, 647, 731, 777`) | keep as a file read on demand |
| `teach-me` | 8,323 | yes | an option at 5 gates | keep as a file read on demand |

All 5 are listed to the model in every session: this session's own skill list holds 16 `temper:` entries, the 11
commands and the 5 skills, including the three marked `user-invocable: false` [observed in this session].

### 2.3 Packs: 8 built in, 5 on by default, plus 6 stack files

| Pack | Bytes | `phases:` | On by default (`templates/temper.config.default:16`) | Note |
|---|---|---|---|---|
| quality | 784 | all | yes | 12 generic rules ("names should be descriptive") (`packs/quality/rules.md:10-24`) |
| tdd | 3,041 | build, review, check, fix | yes | RED/GREEN is already enforced by the CLI from recorded runs |
| security | 1,176 | all | yes | 16 OWASP-style rules |
| git | 555 | all | yes | commit-message and branch rules; the CLI writes the run's commits itself. One live use: `/temper:fix` branches off main "when the git pack is on" (`commands/fix.md:67-68`) |
| performance | 4,348 | build, review, check, fix | yes | starts with frontend Core Web Vitals |
| api-design | 3,845 | all | no | |
| architecture-depth | 3,655 | design, review | no | the Review gate offers "Architecture Depth Review" either way (`scripts/flow.py:769`, [ran]) |
| guardrails | 28,644 (+ 2,347 JSON) | `[]` | no | never loaded into a stage; documentation for people and `/temper:pack` (`packs/guardrails/rules.md:14-18`) |
| stacks/*.md (6 files) | 5,513 in total | none | n/a | **no brief or reference page loads them**: every mention is of the project's own `.claude/packs/stacks/{stack}.md` "if present" (`reference/build.md:15`, `reference/design.md:15`, `skills/temper-core/SKILL.md:17`); the only other mention is `CONTRIBUTING.md:55-65` [ran: grep] |

**The CLI never reads `packs:`.** There is no reader of the key in `scripts/temper` or `scripts/*.py` [ran: grep]. Packs
reach an agent only because a reference page tells the agent to read the config and then the rule files. `stack:` and
`tools.mode` are the same: prompt-read only.

Three-tier resolution (project `.claude/packs`, global `~/.claude/packs`, built in), per-pack `phases` and `link`
overrides, "launcher packs" and a pack builder are all described in `reference/pack.md` (16,453 bytes) and
`commands/pack.md` (12,692 bytes).

### 2.4 Config keys in `templates/temper.config.default` (172 lines, 9,647 bytes): 53 leaf keys under 18 top-level names

Counted by parsing the file, commented keys included [ran].

| Top-level | Live keys (18) | Commented keys (35) |
|---|---|---|
| `stack` | `stack` | |
| `packs` | `packs` | |
| `tools` | `tools.mode`, `tools.ocr.mode` | |
| `review` | `review.block-on` | |
| `check` | `check.coverage-threshold` | `check.environment`, `check.commands.test`, `.lint`, `.typecheck` |
| `fix` | | `fix.max-loops` |
| `models` | | `models.plan`, `.design`, `.build`, `.review`, `.check`, `.rca`, `.fix` |
| `bands` | | `bands.window`, `.min-points`, `.drift-run`, `.metrics`, `.tiers.1sigma`, `.2sigma`, `.3sigma` |
| `protect` | | `protect.paths` |
| `format` | | `format.cmd` |
| `plan` | `plan.context-check`, `plan.fresh-review`, `plan.fresh-review-twice`, `plan.fresh-review-rounds` | `plan.preflight-timeout`, `plan.preflight-skip` |
| `phases` | `phases.design`, `phases.pipeline` | |
| `feedback` | `feedback.enabled` | |
| `loops` | `loops.max-per-type` | |
| `build` | | `build.grouped.task-model`, `.escalation-model`, `.max-parallel`, `.max-groups`, `.keep-days`, `build.red-before-code` |
| `autonomy` | `autonomy.max-blast-radius`, `autonomy.park-on-touch`, `autonomy.budget.max-total-loops`, `autonomy.budget.max-stages` | `autonomy.policy` |
| `evidence` | | `evidence.claimed-runs` |
| `setup` | | `setup.run`, `setup.env`, `setup.services`, `setup.tools` |

PR #115 adds 9 of them: `plan.preflight-timeout`, `plan.preflight-skip`, `autonomy.policy`, `build.red-before-code`,
`evidence.claimed-runs`, `setup.run`, `setup.env`, `setup.services`, `setup.tools` (`git diff origin/main...HEAD --
templates/temper.config.default`) [ran]. The file grew from 7,898 to 9,647 bytes.

Keys that the code or a prompt reads but the template does not list: `check.commands.coverage`,
`check.mutation-threshold` (default 70), `models.acceptance`, `models.plan-review`, `models.intent`, `models.pipeline`
(`scripts/temper:568, 3918, 4938`) [code]; prompt-read only: `check.live-scenarios` (`reference/check.md:67`),
`review.confidence-threshold` (`reference/review.md:29, 207`), `tools.ocr.timeout`, `tools.ocr.replace-defect-subagent`
(`reference/review.md`), `review.auto-fix`, `check.debt-tracking` [ran: grep].

Dead or misleading keys:

| Key | State | Evidence |
|---|---|---|
| `autonomy.budget.max-total-loops`, `autonomy.budget.max-stages` | shipped live in the template, read by no code | only hits outside the template: a selftest fixture and one display line in `reference/status.md:104` [ran: grep] |
| `autonomy.enabled` | "no longer read (9.8.0)" (`templates/temper.config.default:144`, `scripts/flow.py:300-303`), yet the comment 9 lines above still says "With this block absent or enabled: false, the plan gate offers only the ordinary stage-by-stage continuation" (`:135-136`), and `.claude/CLAUDE.md` repeats it | [code] |
| `tools.label-findings` | in `docs/getting-started.md:239` and `docs/recommended-setup.md:94`; no reader anywhere | [ran: grep] |
| `plan.default-depth`, `branch.pattern`, `branch.commit-style` | in `docs/enterprise.md:159-176`; no reader | [ran: grep] |
| `check.live-scenarios` | documented as a user choice (`docs/getting-started.md:234, 242-248`); read only by the Check agent's reference page, and Check is run by the CLI with no agent whenever it finds a test command (`scripts/flow.py:1356-1364`) | [code] |
| second top-level `build:` | **PR #115 regression.** The template has a commented `# build:` block for grouped Build at line 124 and a live, empty `build:` at line 155. After a user uncomments the first block, `temper config get build.grouped.max-parallel` returns the default: the later key wins. On `origin/main` only the commented block exists | [ran in scratch: set `max-parallel: 7`, got the default back] |

### 2.5 Plugin options (`userConfig`): 5 (`.claude-plugin/plugin.json:61-97`)

`uiMode` (full, minimal, off), `enforcement` (on, off), `prAttribution` (on, off), `phaseModels`, `reviewerModel`.
The last two overlap the config file: a stage's model can be set in five places, namely the brief's `model:` line,
`models.<stage>` in `temper.config`, `build.grouped.task-model` and `escalation-model`, `phaseModels` and
`reviewerModel` (`hooks/temper-mod/register.tsx:658-682`) [code].

### 2.6 Agents: 13 (`.claude-plugin/plugin.json:38-52`)

intent (Sonnet), plan (Opus), plan-review (Sonnet), design (Opus), acceptance (Sonnet), build (Sonnet, the fix pass),
build-task (Haiku), review (Sonnet, effort high), check (Sonnet), pipeline (Sonnet), rca (Opus, effort high), fix
(Sonnet), env (Sonnet, new in PR #115). Models are the `model:` lines of the briefs; `temper model --all --source`
printed the same [ran].

### 2.7 Modes and switches a user can be in

| Axis | Values | Source |
|---|---|---|
| Mod loaded | yes, no (older Claude Code, or blocked by the organization) | `docs/getting-started.md:29-45` |
| `uiMode` | full, minimal, off | `plugin.json:62-68` |
| `enforcement` | on, off | `plugin.json:69-75` |
| Who carries the run | the mod's run driver, or the conversation ("hand back") | `commands/temper.md:23-28` |
| Run mode | interactive ("Stage by stage"), autonomous ("armed") | `scripts/flow.py:300-303` |
| Run policy | ask, decide | `scripts/flow.py:296-298` |
| Command | feature run, fix run, draft capture | `commands/*.md` |
| Entry | from the start, or through one of 5 doors | `commands/temper.md:190-206` |
| Complexity tier | trivial, simple, medium, complex | `agents/plan.md:30-33` |
| Risk | L, M, H | `scripts/panel.py:130` |
| `plan.fresh-review` | ask, auto, always, off | `templates/temper.config.default:105` |
| `plan.context-check` | auto, always, off | `:104` |
| `tools.mode` | auto, heuristic-only, require | `:21` |
| `tools.ocr.mode` | off, auto, require | `:28` |
| `check.live-scenarios` | prompt, always, never | `docs/getting-started.md:234` |

Fifteen axes. Not every combination exists (without the mod there is no `uiMode`), but the first six rows alone
decide who runs each step, what is drawn, what is refused and which questions are asked.

### 2.8 Questions and option labels

Five question headers (`Temper gate`, `Build group`, `Temper resume`, `Scope drift`, `Question N`; `scripts/flow.py:40-43,
2502`) plus a reason question and a name question (`:459-481`). `scripts/flow.py` holds 89 `self.opt(` calls with **66
distinct option label templates** (a template such as "Continue to %s" counted once) [ran: grep and count]. A question holds four options at most; the rest go under "More options"
(`docs/flow.md:92, 210`).

### 2.9 Vocabulary a user meets (115 terms, counted from the table below)

Grouped by where it appears. Each is used in a question, a panel, the config template or the user docs.

| Area | Terms |
|---|---|
| Flow (14) | stage, phase (both words are used for the same thing: "phase bar" in `plugin.json:4`, "stage bar" in the docs, `phases:` in the config), gate, Temper gate, run, slug, spec folder, door, Save for later, Temper resume, loop back, loop budget, override, trivial path |
| Intent (13) | intent.md, criteria (AC-NN), required and optional, Validate type (scenario, code, metric, manual), Blocking and Deferred question, Carry forward, Decisions, Assumptions, rules checklist (Rules covered), house rule, Status (draft, accepted, completed), Context Sources, Reviewer |
| Plan (16) | plan.md, tasks.md, group (G1), task, chain, Cases, group Context, Context Map, Context check, blast radius, risk (L, M, H), complexity tier, scenario (Gherkin, Covers), fresh review (lens, reviewer A and B, paraphrase), contest and escalate, preflight (passes, needs new code, environment fault, command fault) |
| Environment (5) | setup block, environment contract, doctor, SETUP verdict, ENV fault |
| Design (3) | design.md, Areas of Concern, ADR |
| Build (15) | acceptance tests (locked), RED, GREEN, REFACTOR, grouped Build, worktree, attempt, escalation, group check (Validate), integrate (Integration), fix pass, plan patch, Scope drift (Add to plan, Revert, Allow once), small change (adhoc window), covered task and manual task |
| Autonomy (7) | Autonomous Build, arm and armed, park and parked, run policy, park-on-touch, max-blast-radius, autonomy report |
| Review and Check (12) | finding, severity, confidence, block-on, accept a finding, evidence, ledger (gate ledger), labels (PROVEN, HEURISTIC, SEMANTIC, PERSON), coverage threshold, mutation score, scenario tracing, Check markers |
| Commit and after (6) | commit gate, pre-commit hook (`core.hooksPath`, `temper-gate`), Pipeline stage, draft and stacked pull requests, report and report.html, spec drift (`temper drift`, a second meaning of "drift") |
| Packs and tooling (10) | pack, BLOCK, WARN and SUGGEST, pack phases, pack link, launcher pack, guardrails, stack, preset, bands (control bands, sigma tiers), review memory |
| Mod (9) | mod, bar (also "band"), pane, toast, hint, uiMode, enforcement, run driver, hand back |
| Add-ons (5) | Grill Me, Teach Me, Architecture Depth Review, HTML review (open, share), config suggestions |

The task's own list (gate, ledger, evidence, pack, band, park, arm, door, tier, fresh review, Context Map, blast radius,
drift, adhoc) is 14 of these 115.

---

## 3. Context weight

### 3.1 What the plugin puts into every session of the user, run or no run

| Item | Size | Tokens (bytes/4) | Source |
|---|---|---|---|
| 11 command names, descriptions and argument hints | 1,258 chars | about 315 | frontmatter parse [ran] |
| 5 skill names and descriptions | 628 chars | about 155 | [ran] |
| 13 agent type names and descriptions (as listed with the Agent tool) | 2,615 chars | about 650 | [ran] for the sizes; that Claude Code lists them in every session is [inferred] |
| The mod's system prompt section, no run: "Temper enforcement: active" and "Phase: none. No Temper run is active." | 2 lines | about 20 | `hooks/temper-mod/core/section.ts:22-28` [code] |
| The same section during a run: phase, criteria, next step, one sentence about messages at a gate | 5 to 6 lines | about 80 | `section.ts:30-42` [code] |
| **Total, always on** | about 4,570 chars | **about 1,150** | |

Three command hooks run in every session (`hooks/hooks.json:4-34`). Measured, 10 runs each, in a non-Temper project and
in a Temper project: `stage-marker.sh` (every prompt) 28 to 29 ms, `block_stdin_wait.py` (every Bash call) 21 to 23 ms,
`verify-stage-gate.sh` (every stop) 8 to 9 ms [ran]. They are not a cost worth changing.

### 3.2 What a run puts into the main conversation

| Item | Bytes | Tokens | When |
|---|---|---|---|
| `commands/temper.md` | 17,042 | about 4,260 | each time the user types `/temper:temper` (start, every resume); also at each "hand back" from the driver, which arrives as a note after the command (`commands/temper.md:26-28`) [inferred for hand backs] |
| A door command | 891 to 941, then "Read commands/temper.md now" | about 4,490 with the read | each door |
| `docs/flow.md` | 27,211 | about 6,800 | only if the model follows the pointer at `commands/temper.md:18` ("its format") |
| `commands/fix.md` + the three sections of `temper.md` it tells the model to read | 5,212 + 17,042 | about 5,560 | each `/temper:fix` |
| Each agent's returned panel, printed again "verbatim" by the main session | 10 to 30 lines | output tokens, twice | `commands/temper.md:85`; without the mod only |
| `temper report --end`, copied "as it is, in a code block" | 88 lines, 5,776 bytes for a 2-task run | about 1,440 output tokens | `commands/temper.md:102-104`, `scripts/flow.py:2144-2146` [ran] |

`docs/context-hygiene.md:41` says the orchestrator file is "about 10 KB since 9.7.0"; it is 17,042 bytes.
`docs/context-hygiene.md:33` says `reference/plan.md` went "from 1,086 lines to 224"; it is 428 lines, 27,927 bytes
[ran: `wc`]. The prompt surface has grown back by about 70% to 90% since those figures were written.

### 3.3 What each agent reads of Temper's own text before it reads the project

The launch prompt is built in `scripts/flow.py:1119-1136` (stages) and `:1712-1716` (Build tasks): "Follow
`<plugin>/agents/<stage>.md` exactly", a spec path, notes, and the `Plugin folder:` line; when the project has a
`setup:` block, one more line with the run line and variables (`scripts/flow.py:448-456`). The mandatory reads are
named in each brief and its reference page.

| Agent (model) | Mandatory reads | Bytes | Tokens |
|---|---|---|---|
| intent (Sonnet) | brief 14,976 + `templates/intent.md` 4,455 | 19,431 | about 4,900 |
| plan (Opus) | brief 11,905 + `reference/plan.md` 27,927 + `templates/tasks.md` 2,181 + `templates/plan.md` 2,311 + the project's `temper.config` 9,647 + 5 default packs 9,904 + `.temper/brief.md` (up to 30,000 chars of whole files plus lists, `scripts/brief.py:34-40`) | up to 93,875 | up to about 23,500 |
| plan-review (Sonnet), 1 or 2 per round | brief 7,859 + the three spec files | 7,859 + spec | about 2,000 + spec |
| design (Opus) | brief 3,732 + `reference/design.md` 6,611 + 2 templates 2,685 + config 9,647 + 3 packs 2,515 | 25,190 | about 6,300 |
| acceptance (Sonnet) | brief 6,897 + `intent.md` | 6,897 + intent | about 1,700 + intent |
| build-task (Haiku), one per chain | brief 6,043 + `task show` (group Context up to 4,096, task block up to 2,048; `scripts/temper:106-107`) | up to 12,187 | up to about 3,050 |
| build, the fix pass (Sonnet) | brief 10,681 + `reference/build.md` 11,287 + config 9,647 + 5 packs 9,904 | 41,519 | about 10,400 |
| review (Sonnet, effort high) | brief 6,360 + `reference/review.md` 17,159 + config 9,647 + 5 packs 9,904 | 43,070 | about 10,800 |
| check agent (Sonnet), only when the CLI cannot run Check or a criterion is of type code or metric | brief 6,501 + `reference/check.md` 12,480 + 5 packs 9,904 | 28,885 | about 7,200 |
| rca (Opus) | brief 3,937 + `reference/fix.md` 8,679 + config 9,647 + 5 packs 9,904 | 32,167 | about 8,000 |
| fix (Sonnet) | brief 6,694 + `reference/fix.md` 8,679 + 5 packs 9,904 | 25,277 | about 6,300 |

Four avoidable weights in that table:

1. **The brief may be loaded twice.** Each agent is launched as type `temper:temper-<stage>` (`scripts/flow.py:1135`),
   whose system prompt is the brief, and its prompt also begins "Follow `<plugin>/agents/<stage>.md` exactly"
   (`:1122`), which tells it to read the same file. The file path is there for the fallback to the general purpose
   agent (`commands/temper.md:81-82`). Whether the typed agents do re-read it I could not observe [inferred]. If they
   do, it is 1,500 to 3,700 tokens per launch, on every launch.
2. **The config as shipped is 9,647 bytes of which 30 lines are live.** Every agent told to read
   `.claude/temper.config` (plan, design, review, the fix pass, rca) reads about 2,400 tokens to learn about 10 values.
3. **`reference/pack.md`, 16,453 bytes.** Five reference pages say packs resolve to "the built-in files listed in
   `${CLAUDE_PLUGIN_ROOT}/reference/pack.md`" (`reference/plan.md:181`, `build.md:14`, `review.md:31`, `check.md:103`,
   `design.md:14`). An agent that opens it to find 8 paths reads about 4,100 tokens [inferred that some do].
4. **Agent-drawn boxes.** The CLI draws the Plan, Design, RCA and task panels since 9.8.0, because a model drawing a
   76-column box cost "2,000 to 3,000 output tokens and 30 to 40 seconds a stage" (`scripts/panel.py:8-10`). Intent,
   acceptance, plan-review, review, the fix pass and the Check agent still draw their own (`agents/intent.md:162-187`,
   `acceptance.md:78-85`, `plan-review.md:97-106`, `review.md:72-93`, `build.md:127-142`, `check.md:85-92`). The cost on
   Sonnet is not measured anywhere I found.

### 3.4 Which packs reach which agents (default config: quality, tdd, security, git, performance)

| Agent | Packs it is told to read | Source |
|---|---|---|
| intent, acceptance, plan-review, pipeline, env | none | no pack instruction in those briefs [ran: grep] |
| plan | all 5: rules whose `phases` is `all` or holds `plan`, "and also those that contain `build`", to distil them into each group's Context | `reference/plan.md:180-183, 362-367` |
| design | quality, security, git (`phases` all); architecture-depth and api-design if enabled | `reference/design.md:12-15` |
| build-task | none: "load no pack files"; it reads the group Context that Plan distilled (4,096 bytes at most) | `agents/build-task.md:20-24` |
| build (fix pass) | all 5 | `reference/build.md:12-16` |
| review, and each review subagent it spawns | all 5 ("Each subagent gets the pack rules, the stack pattern file") | `reference/review.md:28-33, 79` |
| check agent | all 5, used only for the semgrep step | `reference/check.md:99-104` |
| rca, fix | "the enabled packs from `.claude/temper.config` plus stack-specific rules" | `agents/rca.md:23-25`, `agents/fix.md:16` |
| nobody | guardrails (`phases: []`), the 6 files in `packs/stacks/` | section 2.3 |

In money the packs are small (about 2,500 input tokens per loading agent). Their real cost is conceptual: a manager
command, a 16 KB reference, three tiers, phases, links, and a config key the CLI does not read.

---

## 4. What can be defaulted, merged, hidden or removed for 90% of users

### 4.1 The smallest surface that keeps the promise

The promise has three parts: the model cannot write code before the person approves the intent; gates are computed by
the CLI; tests come first. What each part needs from the user:

| Promise | What enforces it | What the user must touch |
|---|---|---|
| No code before the intent is approved | the Intent gate and the mod's write guard (`docs/commands.md:166-173`) | answer the Intent questions; one approval |
| Gates computed by the CLI | `temper gate`, the pre-commit hook | nothing, unless a gate is red |
| Tests first | the acceptance tests locked before Build; RED then GREEN recorded by the CLI (`README.md:34`) | nothing, unless a task fails |

So the smallest surface is: **two commands** (`/temper:temper`, `/temper:fix`), **three approvals** (the intent, the plan,
the commit), **the Intent questions**, and **exception questions** when something is red. That is what an armed run
under `policy: decide` already does (section 1.4); it is not the default, and not documented where a new user reads.

### 4.2 Item by item

| Item | Today | Where it would go | Loss for 90% of users |
|---|---|---|---|
| `/temper:plan`, `:design`, `:build`, `:review`, `:check` | 5 listed commands; a later door starts a run with no evidence, so its earlier gates fail and ask "Run it" or "Override" (`docs/getting-started.md:112-119`, `scripts/flow.py:600-614`) | remove from the listing; `/temper:temper` with no words already resumes | none; removes 5 listing lines, the "Entering at a stage" section (`commands/temper.md:190-206`) and the `walked` branch |
| `/temper:intent` | a second Intent path with different rules: it must "always ask who reviews the intent" (`commands/intent.md:46-47`) while the stage agent must "never ask for a reviewer" (`agents/intent.md:58-60`) | `/temper:temper "idea"` then Save for later at the Intent gate, or one word such as `draft` | the interactive interview in the main session |
| `/temper:init` | automatic on the first run (`commands/init.md:12-13`); 15,493 bytes, 116 lines of them on hook-manager cases | CLI only: `temper guards install`, `temper guards uninstall` | none |
| `/temper:status` | a model-drawn dashboard over metrics, bands, drift, review memory, MCP probing (`commands/status.md:17-34`) | `/temper:temper status` (exists) printing `temper status` and `temper report` | the bands and hotspots view |
| `/temper:pack` | 12,692 + 16,453 bytes; toggles, launcher packs, links, a builder, guardrail printing | one docs page; `temper guards print` for the guardrail hooks; edit `packs:` by hand | the interactive pack builder |
| Skills `temper-core`, `context-engineering`, `source-driven-development` | listed in every session, not user-invocable | delete; inline the few cited lines | none |
| Skills `grill-me`, `teach-me` | listed in every session; offered at 4 and 5 gates | reference files that the gate option reads; offered under More options only | they leave the first row of options |
| Default packs `quality`, `git`, `performance` | on by default; generic or not applicable to what the CLI already does | off by default; keep `security` and `tdd` | generic advice a current model applies anyway (the project's own words: `docs/context-hygiene.md:80-84`) |
| `packs/stacks/*.md` | 6 files nothing loads | delete, or load the matching one from the plugin | none today |
| Config template | 53 keys, 172 lines | ship about 10 live lines (packs, `review.block-on`, coverage rule, run profile, setup block when proposed); the rest in a reference page | none; agents stop reading 2,400 tokens of comments |
| `autonomy.budget.*`, `autonomy.enabled` comments, `tools.label-findings`, `plan.default-depth`, `branch.*` | dead | delete from template and docs | none |
| `tools.mode`, `tools.ocr.*`, `check.live-scenarios`, `review.confidence-threshold` | prompt-read only | move to an "advanced" page or delete | OCR and MCP users keep a documented key |
| `bands:` (7 keys), `/temper:status` bands, intent drafts from breaches | a second product (metric drift detection) inside the first | separate optional feature, out of the template | none for a feature run |
| `phaseModels`, `reviewerModel` (plugin options) | duplicate `models.*` | keep one place, the config file | none |
| `plan.fresh-review` (4 values) + `-twice` + `-rounds` | an option slot at every Plan question under the default `ask` | default `off` for simple, `auto` only for risk H; drop the two sub-keys from the template | the offer on simple plans |
| `plan.context-check` | asks when the map has an `ignore` or `gap` | fold its sentence into the Plan question text; no separate dialog | a separate click |
| `Stage by stage` vs `Autonomous Build` + `autonomy.policy` | a per-run choice plus a hidden key | one run profile; see section 5 | none if the plan approval stays a person's click |
| Group questions | one per group in a stage-by-stage run, nothing to decide when the check passed | drop; the Build question follows anyway (the reason given at `scripts/flow.py:1761-1762` for one group holds for N) | a mid-Build review point |
| Build gate question when Build passed | "Build: the check passed. Continue to Review?" | automatic; Review reads the same work | a pause before Review |
| 16 reserved first words | common English words | keep `status`, `report`, `help`; decisions are clicks anyway | none |
| Vocabulary | 115 terms | a user needs about 12: intent, criteria, plan, task, gate, override, loop back, park, report, setup block, Save for later, small change | none |

---

## 5. The least-friction run today, and why it is not the default

| # | What the user must do | Where | Kind | Effect | Why it is not the default (the source's own reason) |
|---|---|---|---|---|---|
| 1 | Choose "Autonomous Build: run Build unattended", the second option, at the Plan question (or the Design question) | the dialog, **every run** | click on a non-recommended option | group questions and the Build question are answered by the CLI | "armed by a human at the PLAN GATE, never at invocation" is listed as a safety invariant (`templates/temper.config.default:133-141`, `reference/autonomy.md:11-19`); no setting can pre-select it (`scripts/flow.py:300-303`). The first option is labelled "Stage by stage (Recommended)" (`:673`) |
| 2 | Uncomment `autonomy.policy: decide` | `.claude/temper.config` line 146 | config edit | Review and Check decide by fixed rules; the run parks only at the commit or on a fault | "only the person writes it"; "With the key absent or `ask`, every gate after Build asks, as before" (`docs/flow.md:226, 235`). New in PR #115, shipped off |
| 3 | Set `plan.context-check: off` | line 104 | config edit | no Context check dialog | default `auto`; the only stated reason is the comment on the key |
| 4 | Set `plan.fresh-review: off` | line 105 | config edit, cosmetic | removes "Fresh review first" from the first row (no reviewer runs under `ask` unless clicked: `scripts/fresh_review.py:117-123, 206-210`) | "worth it for medium and complex work" (`scripts/flow.py:1041`) |
| 5 | Set `phases.design: false` | line 112 | config edit, optional | no Design stage for medium and complex (an Opus agent and a gate) | Design is "auto-skipped otherwise", i.e. on for medium and complex |
| 6 | Set `check.coverage-threshold` to the project's real figure, or `check.commands.coverage` | line 34; the second key is not in the template | config edit, needed on most existing projects | Check stops failing on total coverage or on a missing measurement | none given |
| 7 | Set `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` | the shell, or `.claude/settings.json` by hand | outside Temper | a run does not wait for a turn after an agent returns | "A plugin cannot set it for you, and Temper does not edit your settings" (`docs/getting-started.md:97-100`) |

So: **two config edits that change the question count (2, 3), up to three more that most projects want (4, 5, 6), one
environment variable outside Temper (7), and one click on a non-recommended option in every run (1).** After all of
them a clean run still asks: the Intent questions (0 to 6), the Intent gate, the Plan gate, and the commit question.

Where a new user could learn this: `autonomy.policy` appears in user-facing text only in `docs/flow.md:226` (a format
page for the CLI's JSON) and in the commented template line; `plan.context-check` only in the template and in two
prompt files (`reference/plan.md:71`, `agents/plan.md:94`); README and Getting Started do not mention Autonomous Build
at all [ran: grep]. `docs/index.md:89-90` has one sentence on it.

---

## 6. What the person reads during a run, and what a one-minute decision needs

Sizes are from the e2e `full-run` and `design` scenarios in the scratch clone [ran] and from the panel formats in the
briefs [code].

| Approval | What is shown today | What is not shown | What a decision in under a minute needs |
|---|---|---|---|
| Intent questions | one dialog tab per question, up to 3 ready answers, the first marked Recommended, then Carry forward (`scripts/flow.py:2495-2502`) | why the question matters; what the recommended answer was based on (a house rule is marked only in the file) | as today, plus one line of consequence per answer |
| Intent gate | the Intent agent's box: PROBLEM (one line), `CRITERIA: N (n required / n optional)`, OPEN QUESTIONS, ASSUMPTIONS, DECISIONS (`agents/intent.md:174-187`); then "Intent: the check passed. Accept the intent and continue to Plan?" | **the criteria themselves**, the scope and non-goals, the constraints. The person approves "the Problem and success criteria" (`docs/getting-started.md:74-76`) from a count, or opens `intent.md` (5.5 KB in the fixture) | each criterion in one line, the out-of-scope line, the assumptions. About 10 to 15 rows, drawn by the CLI from `intent.md` as it draws the Plan panel |
| Context check | "The plan leaves out: ... It could not find: ... Is that right?" with the Context Map table as the option preview (`scripts/flow.py:2289-2329`) | which choice costs a whole Plan pass: "Include what is left out" and "Something else" both run Plan again (`--redo`, `:2318, 2327`) | the same text as a line of the Plan question; the cost of a re-plan stated on the option |
| Plan gate | the CLI's box, 12 lines for the fixture: INTENT (first sentence), "create N files, modify N files", RISK, COMPLEXITY, SEARCH, SCENARIOS (names), DECISIONS (headings), then a diagram (`scripts/panel.py:129-137`); the question; with a fresh review, its paraphrase in the question (`scripts/flow.py:651`) | **the files, the groups, the tasks, how many agents will run, on which models, roughly how long.** The mod's pane shows "the plan's files by Build group" (`docs/mod.md:55-56`); without the mod, or below 144 columns before the user opens the pane (`docs/mod.md:66-68`), nothing does | files by group marked create or modify; the task count and agent launches; the risk and why; what is left out. One screen |
| Design gate | the CLI's box: "API CONTRACTS: n DATABASE CHANGES: n CONCERNS OPEN: n", AREAS OF CONCERN, DECISIONS (`scripts/panel.py:195-198`) | what in the plan a Design decision changes: a Design answer given after the plan fails the gate until `tasks.md` changes and recommends "Loop back to Plan" (`docs/flow.md:168-172`) | the decisions that differ from the plan, or no gate at all when there are none |
| Build group | one 10-line box per task (attempt, red and green exits, CHANGED files, SCENARIOS), then "Group G1 (title) passed its check. Continue?" | nothing is missing; there is nothing to decide when the check passed | no question; show the boxes |
| Build gate | "Build: the check passed. Continue to Review?" and, under `--brief`, no rows when it passed | nothing to decide | no question |
| Review gate | the Review agent's box (FILES, FINDINGS by severity, INTENT satisfied or not, SCENARIO COVERAGE, each finding) (`agents/review.md:84-93`); the question names open findings per level | on a clean review there is nothing to decide, yet the first row offers Architecture Depth Review and Grill Me | ask only when there is an open finding at medium or above |
| Check gate | one sentence ("Check: the CLI runs the suite, coverage, the scenario tests and the mutation score (no agent)", `scripts/flow.py:1363-1364`) and "Check: the check passed. Commit?". The orchestrator's Bash output is not visible to the person (`commands/temper.md:103`) | **every number**: tests run, coverage, mutation score, acceptance result. They are in the mod's pane (Check markers) or nowhere | 5 lines: tests, coverage, mutation, acceptance, files changed against the plan |
| After "Commit" | `temper report --end`: 88 lines, 5,776 bytes for a two-task run, 64 rows marked `[v]`, none failed, then a usage table; copied into the reply in a code block | it arrives after the decision it would inform. The label "Commit" also understates what is already done: the task commits and merges are on `feature/<slug>` since Build (8 commits in the e2e run) | the 5-line summary before the question; the full ledger in `report.html`, which is written anyway (`scripts/flow.py:2238-2241`) |

Three more texts a person meets:

- **A typed message at a gate re-runs the stage's agent.** "A change request: you never make it yourself ... run
  `temper state redo {stage} --reason '{the text}'` ... the stage's agent runs again with the note"
  (`commands/temper.md:157-160`). A one-line wording change typed at the Plan gate is a second Plan pass. The user docs
  say the opposite ("Type a change request: Claude makes it, the gate runs again", `docs/commands.md:60`), and so does
  the mod's own system prompt line ("If it asks for a change, make the change, run the gate again",
  `hooks/temper-mod/core/section.ts:12`).
- **The enforcement sentence** as the first line of every conversation without the mod (`commands/temper.md:9-14`,
  repeated in `commands/intent.md:30-39`, `commands/fix.md:12-18`, `skills/temper-core/SKILL.md:11`).
- **The doc examples do not match the product.** `docs/getting-started.md:127-152, 192-209` and `docs/commands.md:365-408,
  506-547, 602-626, 821-846` show emoji reports ("Analyzing blast radius...", "Review Results ... Confidence: 94%",
  a status dashboard with "Learning (planned)") that no code prints; the real output is the 76-column boxes above. The
  documented Plan question (`docs/commands.md:45-51`, `docs/getting-started.md:80-87`: Continue to Build, Open HTML
  review, Share HTML review, More options) is not what the default config asks (section 1.3, row e).

---

## 7. Where the docs and the code disagree (found while reading)

| # | Doc or prompt says | Code does | Sources |
|---|---|---|---|
| 1 | Plan gate options: Continue to Build / Open HTML review / Share HTML review / More options | Stage by stage / Autonomous Build / Fresh review first / More options | `docs/commands.md:45-51` vs `scripts/flow.py:672-680` [ran] |
| 2 | "With the `autonomy:` block absent or `enabled: false`, every gate is the ordinary interactive one" | `autonomy.enabled` is not read; the option is always offered | `.claude/CLAUDE.md`, `templates/temper.config.default:135-136` vs `scripts/flow.py:300-303` |
| 3 | The run "asks whether to write the report as an HTML page too" | no question since 9.8.0 | `commands/temper.md:104`, `docs/mod.md:72-74` vs `scripts/flow.py:2238-2241`, `docs/flow.md:302-304` [ran] |
| 4 | Review gate blocks on "`review.block-on` severity (default: `critical`)" | default `critical,high` | `agents/review.md:27` vs `scripts/temper:3814` |
| 5 | "Type a change request: Claude makes it" | the conversation writes no file; the agent runs again | `docs/commands.md:60`, `hooks/temper-mod/core/section.ts:12` vs `commands/temper.md:157-160` |
| 6 | `/temper:intent` must "always ask who reviews the intent" | the Intent agent must "never ask for a reviewer" | `commands/intent.md:46-47` vs `agents/intent.md:58-60` |
| 7 | Config example with `review.confidence-threshold`, `check.live-scenarios`, `tools.label-findings` | none is in the template; the last has no reader | `docs/getting-started.md:213-240` |
| 8 | `plan.default-depth`, `branch.pattern`, `branch.commit-style` | no reader | `docs/enterprise.md:159-176` |
| 9 | "8 built-in packs", stack packs under `packs/stacks/` | the 6 stack files are loaded by nothing | `docs/packs.md:12`, `CONTRIBUTING.md:55` vs section 2.3 |
| 10 | `reference/plan.md` is 224 lines; the orchestrator file is about 10 KB | 428 lines; 17,042 bytes | `docs/context-hygiene.md:33, 41` |
| 11 | "ten Python scripts (about 3,600 lines)"; README: "A small CLI" | 49 Python scripts, 12,335 lines, plus 5,121 lines of bash | `docs/trust.md:5-6`, `README.md:5` vs `wc` [ran] |
| 12 | Emoji output examples for plan, review, check, fix, pack, status | 76-column boxes; no such text | `docs/commands.md`, `docs/getting-started.md` vs `scripts/panel.py`, the briefs |

---

## 8. What PR #115 changes in this subsystem

`git diff --stat origin/main...HEAD` over the user-facing paths: 13 files, +191, -20 [ran].

- +1 agent (`agents/env.md`, 70 lines) and its manifest entry; version 9.8.4 to 9.8.5.
- +9 config keys and +1,749 bytes in the template (section 2.4); `review.block-on` default now `[critical, high]`.
- +53 lines in `docs/commands.md` for `temper doctor`, `temper plan patch`, `temper plan preflight`.
- New questions and options: "Add the proposed setup block", "Let an agent find the setup", "Check it again",
  "Repair the environment and run again", "Change the group's command" (`scripts/flow.py:841, 1197, 1202`).
- It lowers friction in two real ways: the preflight catches an environment fault before Build, and
  `autonomy.policy: decide` removes the Review and Check questions from an armed run. Both are right for the goal. The
  second is shipped off and undocumented for users (section 5).
- Two defects: the duplicate `build:` key (section 2.4) and `.temper/preflight.json` missing from the exclude list
  (section 1.2).

---

## 9. Not determined

- How many Claude Code permission prompts a first run raises in the default permission mode, with and without the mod.
- Whether typed agents (`temper:temper-plan` and so on) re-read their own brief when the prompt says "Follow ...
  exactly" (section 3.3, item 1).
- Whether agents open `reference/pack.md` to resolve the built-in pack paths.
- The output-token cost of the boxes that Sonnet agents still draw.
- Whether the mod's run driver removes the background-agent stall for every surface.
- The `/temper:fix` flow end to end: the e2e `fix` scenario failed in this sandbox at "the regression test fails first"
  (the sandbox's `python3` has no `pytest` module), so I read that flow in `commands/fix.md` only.
