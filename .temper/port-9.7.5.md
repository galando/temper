# Port plan: Temper v9.7.5

Base: main at 595aaae (v9.7.4). Branch: claude/happy-dijkstra-l3vagh. Nothing has been edited yet.

## 1. What the read found (facts that shape the plan)

| Fact | Consequence |
|---|---|
| scripts/temper is 240,132 bytes. The limit is 262,144. 22 KB is left. | Every new operation goes into a Python module. The shell gets only a case branch and an argument parser per command. Budget: at most 8 KB of net growth in scripts/temper over the whole release. |
| scripts/flow.py is 82 KB. It will grow by roughly 60 KB. | Split first (F5), then add modules: flow_ctx.py, flow_build.py, flow_gates.py, flow_pr.py. flow.py stays the entry point. |
| scripts/selftest/view-fixtures.ts is 212,087 bytes. 13 new states will push it past 262,144. | Add view-fixtures-2.ts for the new states (the existing file is not re-laid out). make-view-fixtures.sh writes both. |
| validate-directory.sh rule 10 reads script text, comments included, for a path with a folder named hooks, tests, mod, core or ui. | No script or message may contain a path such as tests/test_cli.py. The F7 and F9 example output is built from the data at run time, and shell cases and fixtures use unit/. |
| Rule 9 and 13 bar writes into a git hooks folder by a split name. | F30 uninstall reuses the existing installer approach (the case-gate style folder named by its absolute path). No new split names. |
| ADR numbers 0001 to 0013 exist with gaps at 0007 and 0008. | New ADRs are 0014 (Pipeline stage), 0015 (draft and stacked PRs), 0016 (mod answer audit). The gaps are not reused. |
| The mod lives in hooks/temper-mod (core/*.ts, ui/*.tsx, adapter.ts, register.tsx). Its tests are in tests/mod. rules.ts is 25 KB, shell.ts 32 KB. | Mod changes: rules.ts, shell.ts, answers.ts, view.ts, runview.ts, stages.ts, band.tsx, pane.tsx, types/index.d.ts. check-mod-calls.sh must stay at 13 calls. |
| .temper/specs is git ignored, .temper/port-9.7.5.md is not. | This plan is a normal untracked file. I will not commit it unless you say so. |

## 2. Rules guard, applied to every phase

After each phase: bash scripts/validate-directory.sh, the selftest case files touched, claude plugin test . and tsc -p tsconfig.mod.json when the mod changed, bash scripts/check-mod-calls.sh, wc -c on every file I grew. One commit per feature, message `feat(9.7.5): F<n> <title>` or `fix(9.7.5): F<n> <title>`. Each feature starts with a failing case, shown failing, then the code.

New selftest case files follow the harness and R1: temper-cases-10.sh (Phase A and B), temper-cases-11.sh (C), temper-cases-12.sh (D), temper-cases-13.sh (E). The existing files are not re-laid out. test-temper.sh sources them.

## 3. Feature map

Tests named `t10_*` live in temper-cases-10.sh and so on. Mod tests are new files under tests/mod.

### Phase A: foundations

| F | Files touched | New files | Tests |
|---|---|---|---|
| F1 notes | scripts/temper (evidence add: allow --phase note, --kind input\|edit), flow.py (next re-run rule, prompt note lines), scripts/task_ops.py (task prompt notes), commands/temper.md, agents/build-task.md | none | note reaches next stage prompt; Task N, Group G, and unscoped notes reach the right task prompts; edit note re-runs the gate call only |
| F2 models | scripts/temper (model --all --source, status Models block), task_ops.py (task start records attempt model), flow.py (wait action) | scripts/cli_ctx.py (from F5) | source for override and default; attempt 3 names the escalation model; a run from 9.7.4 uses the attempt number |
| F3 says | flow.py say strings, view builder | none | no say in any state holds the banned phrases; no say string in flow.py does |
| F4 failed call | commands/temper.md, docs/flow.md | none | doc check in validate-docs.sh for the sentence and the gate exception |
| F5 speed | scripts/temper (one Python process for next), flow.py split | scripts/cli_ctx.py, scripts/flow_ctx.py | byte identical next --json and view.json for every fixture state, taken before and after the change (snapshot first, compare after); timing recorded |

Order inside Phase A: F5 first in time (its snapshot must be taken before F3 changes any wording; the byte identity claim is between F5's commit and its parent), then F1, F2, F3, F4. The section 3 label order is kept in the changelog.

### Phase B: Plan and gates

| F | Files touched | New files | Tests |
|---|---|---|---|
| F6 Context Map | scripts/temper (new `plan` dispatch: `plan review --answer [--focus]`, gate_plan row), flow.py (context_map, context_check, the question), plan agent and reference/plan.md, templates, config default (plan.context-check), mod rules.ts and answers.ts (person only call), view.ts, types | scripts/plan_ops.py, docs/auto-mode.md | row caps and modes; question in next and view.json; answer passes under the mod; Carry forward; pending only FAIL asks the check |
| F7 criteria validated | acceptance.py (build mode lines), gate_build row | none | criterion FAIL names scenario and Test: cut at 60 characters |
| F8 scenario rows | evidence run --scenario check, gate_plan row, integrate (task_ops.py integrun), flow.py fallback record pass, templates/intent.md, agents/plan.md, reference/plan.md | scripts/scenario_ops.py | plan gate row; integrate records rows; failing row keeps the gate question; plan without Test: lines; the record pass runs once per round |
| F9 task scenario tests | task_ops.py (show SCENARIO TESTS, gate runs them, exit 4 or 5 message, group gate), agents/build-task.md, agents/build.md, reference/build.md | none | exact names, traced to several tasks, PREVIOUS ATTEMPT carries the message |
| F10 intent blocking | gate_intent, templates/example-intent.md | none | Blocking fails; Deferred and accepted pass |
| F11 risk | scripts/temper (risk dispatch) | scripts/risk.py | same radius twice gives same rating; each rule; raise; refused lowering |
| F12 tasks.md, manual | tasks_md.py (bullets, **Files:** alias, manual flag), task_ops.py (task test refuses manual, task confirm), flow.py (Manual task question), gate_build all tasks count | none | parse forms; manual question; confirm name comes from the person; all manual plan passes Build; 1 of 8 no longer passes |

### Phase C: grouped Build

| F | Files touched | New files | Tests |
|---|---|---|---|
| F13 Change | flow.py (Which task changes?), task_ops.py (reopen set), temper group reopen --task | flow_build.py | reopen set rule; label and description; More options past three |
| F14 adhoc | scripts/temper (adhoc dispatch), flow.py (option, do text), mod rules.ts, shell.ts, stages.ts refusal text | scripts/adhoc_ops.py | open and close, second open refused, no reason refused, close without window, changed file set, snapshot at close, option placement and cap, hook gate does not close |
| F15 mod off | commands/temper.md, docs pages (sentence), flow.py (no TEMPER_MOD read) | none | identical next and view.json with TEMPER_MOD=off for each Build state; page sentence check |
| F16 groups | scripts/temper config read, templates/temper.config.default, flow.py stop state | none | default 2, invalid values mean 2, no groups stop with no agent, loop budget spent text |
| F17 timeouts | group gate --timeout-s, task_ops.py, flow.py rerun option | none | timeout recorded, rerun at double, integration timeout env |
| F18 PYTHONPATH | task_ops.py runner, scenario runner | none | worktree copy wins over an editable install |
| F19 covered | task_ops.py (verdict covered, task accept, task retry), flow.py question, agents/build-task.md, mod rules.ts (person only kind) | none | covered at attempt 3 neither retries nor parks; accept commits and ticks; retry; armed run parks |
| F20 scoped tests | agents/build.md, build-task.md, check.md, review.md, reference/check.md, scripts/validate-panels.py | none | validate-panels fails on a brief missing the foreground rule |
| F21 blast radius | scripts/temper and task_ops.py path filter, config path match only | scripts/blast_filter.py | armed run does not park on config or coverage files; undeclared source file parks; coverage.py counts |
| F22 Maven | task_ops.py hook for Maven test commands, gate_plan row, Java pack, agents/plan.md, reference/check.md | scripts/maven_loop.py | fake mvn and mvnd on PATH; flags kept; new surefire report per class; real Maven case prints SKIP |

### Phase D: Commit, PRs, Pipeline

| F | Files touched | New files | Tests |
|---|---|---|---|
| F23 draft PRs | flow.py (options, state keys pr and commit_path), commands/temper.md record steps, mod rule for gh | reference/pr.md, scripts/flow_pr.py | options only for unarmed /temper; never in fix; guard fails on gh pr create without --draft and on gh pr ready |
| F24 parts | none | scripts/pr_parts.py | #, //, block comment, block open at hunk end, last group comment only |
| F25 (removed) | the optional review-readiness skill was taken out: Check always offers Temper's own PR steps | none | view.json and next agree |
| F26 Pipeline | scripts/temper (STAGES, _run_seq, gate_pipeline, evidence file), flow.py, mod stages.ts and band, types, plugin.json | agents/pipeline.md, reference/pipeline.md, scripts/pipeline_ops.py | each question state; redo clears verdict and context file; mod refuses a write without the window; agent brief has no push |
| F27 record commit | commands/temper.md, state loop in scripts/temper | none | skipped record commit gives no git add or commit; latest loop reason wins |

### Phase E: sessions, hooks, mod

| F | Files touched | Tests |
|---|---|---|
| F28 branch clash | flow.py (Intent question), commands/temper.md, mod rules.ts (state set branch, whole command rule), reason question per override label | clash offers both; temp dir carries spec files; refused switch restores and names the folder; plain switch when no extra commits |
| F29 hook scope | scripts/temper gate commit --from-hook, native hook, scripts/guards/block-uncommitted-gate.sh, docs/trust.md, docs/mod.md, check-known-limits.sh | other branch passes with one line and records nothing; detached HEAD keeps the gate; orchestrator call unchanged |
| F30 uninstall | scripts/guards/install.sh, new scripts/guards_ops.py, native hook and guard scripts (plugin CLI path gone passes), mod rules.ts refusal, stage refusal text, state init Note line, README and getting-started section | uninstall twice is a no-op; user hook line named not changed; hooksPath only when ours; CLI gone passes; mod refuses while active |
| F31 band | runview.ts, view.ts, band.tsx, pane.tsx | chosen wait shows no failed rows; chip red only with a failed row |

## 4. Design changes forced by the rules in section 1 (list for the final report)

1. F12 confirm name: asked of the person, passed as `--by '<name>'`, never read from git or $USER (R6).
2. F21 settings path: matched as a path string only, never opened (R5).
4. F30 disabled plugin: the hook passes when the plugin CLI path is gone, and docs/trust.md says "after you disable the plugin, run temper guards uninstall". No enabledPlugins scan (R5, R7).
5. F5 byte identity is proven between F5 and its parent only, because F3 and F31 change wording on purpose.
6. F7 and F9 example output uses runtime data, never a literal tests/ path in a script (R1 rule 10).
7. view-fixtures.ts is split into two files to stay under 262,144 bytes (R2).

## 5. Phase F: tests, docs, release

- Mod answer audit test in tests/mod: walks every question of every fixture, answers each option through the answer code, checks every call against the rule, and a table maps person only kinds (plan review, task accept, state set branch, adhoc open, overrides) to their question.
- Selftest safety: TEMPER_SELFTEST_ROOT exported to children; any CLI call outside it exits 3, including config and model; the suite leaves the real .temper unchanged; make-view-fixtures.sh runs under the root with its own HOME.
- Optional tiers and parallel jobs only if the suite runtime needs them; decided after Phase C by measuring.
- E2E driver in scripts/e2e (Node, outside claude plugin test .), scripted agents and person, fake gh and bare origin, all paths in the list. Live model smoke off by default and not in CI.
- Docs: CHANGELOG v9.7.5 (per feature: what broke, cause, why nothing failed, fix; suite counts; Migration paragraph), plugin.json to 9.7.5 plus agents/pipeline.md, README "What's new", docs/flow.md, commands.md (plan review versus HTML plan review), grouped-build.md, mod.md, trust.md, privacy.html (gh reads CI, Commit pushes and opens draft PRs), getting-started.md ("Working on several things at once"), auto-mode.md, reference pages, templates, ADR 0014 to 0016. Placeholders in single quotes.
- Final run list from section 7, then the section 8 report.

## 6. Risks I will watch

- Size: scripts/temper headroom is the tightest limit; I will measure after every feature.
- The selftest already takes long; 13 new fixture states and many new cases may need the parallel option.
- Maven and gh behaviour is tested only with fakes; real Maven prints SKIP without a JDK.
- No contradiction between two rules was found, so I have no question for you except the approval below.

## 7. Waiting for

Your yes, or changes to this plan, before any file other than this one is edited.
