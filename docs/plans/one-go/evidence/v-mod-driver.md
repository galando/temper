# Verification: the mod's driver on unhappy paths, ids in place of text, and continuing an agent

Draft items under test: 2g, 7c, open point 1 (and what 1e, 3e, 4c, 4d, 4e lean on).
Tree: `/home/user/temper` at `10e965a` (9.8.5). Nothing was written or run there. The mod's files are the same as at
`9a01eff` (`git diff --stat 9a01eff 10e965a` touches `scripts/flow.py`, `scripts/gate_rows.py`, e2e, selftest and one
doc only), so the mod line numbers of the reports hold at the head.

Marks: **[code]** read at the cited line. **[host]** read in the installed Claude Code binary, version 2.1.325
(`/opt/claude-code/bin/claude`): this is NOT the repository, and the mod's minimum is 2.1.287. **[ran]** one probe I ran
in my scratch folder (`.../scratchpad/work-v-mod-driver/probe`, a 40 line throwaway mod; output in `probe-out.txt`,
log in `probe-debug.log`). **[doc]** a document of the repository.

## Verdict: feasible with changes

- 2g is right in direction and small, but it names one of three places that hold the rule and one of two commands
  that need it.
- "The hand back list is closed" can mean "a closed list of named kinds", never "empty": four kinds need a model or the
  person's own words.
- "A hand back returns to the driver after one step" has no mechanism in the code today. Two ways need no new host
  call. The third (`$.command.run`) is the call the plugin directory held the plugin for.
- "Ids, not text" fits in view version 1, with three conditions the draft does not state.
- Open point 1 is settled for the host installed here: **yes, a mod can continue a finished agent with its context**
  (`$.session.send`), **but the agent's second finish wakes the main session's model for one turn**. The mod's own code
  has no such call, and the call is not on the reviewed list.

---

## 1. The host API: what the mod calls, and what it does not

### 1.1 Calls the mod makes (exactly 20, the reviewed list)

`scripts/check-mod-calls.sh:25-46` is the list; CI fails on one more or one fewer (`:80-105`). Call sites in
`hooks/temper-mod/register.tsx` [code]:

| Call | Lines | Use |
|---|---|---|
| `$.agent.spawn` | 505 | `{ subagentType, prompt, description, model? }`, nothing else |
| `$.agent.list` | 520, 667 | has an agent ended; is a subagent the review agent |
| `$.process.spawn` | 480, 496 | the plugin's CLI by argument list; `sleep` |
| `$.clock.now` | 517, 519 | bound of the wait (90 minutes, `:466`) |
| `$.ui.ask` | 540, 558 | one question, labels (four at most) and a header |
| `$.ui.log` | 599, 736, 763 | panels, the report, the hand back line |
| `$.fs.read`, `$.fs.stat` | 74, 189; 277 | `view.json`; the project root |
| `$.session.version`, `$.session.id` | 83, 204; 454, 744 | version guard; the request's conversation |
| `$.state.get/set`, `$.store.get/set/delete` | 125-314; 59-82 | the drawn view; decisions, report, request, skill |
| `$.ui.open/close/panes/resolve/toast` | 324, 331; 320, 332; 291, 299; 865-917; 48 | pane, elements, toast |

Hooks registered (events, not `$` calls): `session.start`, `classic.SessionStart`, `command.run`, `attribution.text`,
`tool.call`, `prompt.compose`, six `ui.render`, `ui.close`, `turn.complete`, `turn.step` (`register.tsx:705-944`).

### 1.2 The four questions asked of the code

| Question | In the mod's code and types | What the host shows |
|---|---|---|
| A follow up to a finished agent | **Not in the code.** The only agent calls are `spawn` and `list` (`register.tsx:505, 520, 667`). `types/index.d.ts` declares only the mod's own state (`:50-56`); the host's generated types are not in the repository (`tsconfig.mod.json` reads `.claude-plugin/types`, which CI generates: `.github/workflows/quality.yml:112-119`) | [host] `$.agent` has three methods: `list`, `register`, `spawn`; `spawn` takes prompt, description, model, subagentType, name, cwd, and no resume. But `$.session.send({ to: { agentId }, text })` runs the SendMessage tool as the plugin. [ran] It works: see section 1.3 |
| Agents in the background or in parallel | **Yes, in the code.** The driver starts every ready agent, then waits on all of them (`core/driver.ts:413-422`; `register.tsx:511-531`). Each `$.agent.spawn` returns at once with an id (`register.tsx:505-506`) | [host] `spawn` always sends `run_in_background: true`; a bound on spawns running at once exists ("spawns are running at once; refused"); its value: not determined |
| Effort | **Not on a launch.** `GoAgent` has type, model, prompt (`driver.ts:20`); the spawn passes no effort (`register.tsx:505`). The mod can set effort per step in `turn.step` (`register.tsx:941-944`), today only for the main loop (`phaseModels`, `:677-688`); for a subagent it sets the model only (`:678-681`) | [host] `spawn` has no effort field; `$.agent.register` takes one. A brief's own `effort:` line needs no mod: three briefs have it (`agents/review.md`, `rca.md`, `pipeline.md`), `agents/plan.md` and `design.md` (both `model: opus`) do not |
| A dialog with several questions | **Yes, by a workaround in the code.** `$.ui.ask` raises one question; the mod's own `tool.call` hook rewrites that dialog to hold up to four, and reads all answers back (`register.tsx:552-574, 789-796, 813-817`; `driver.ts:161-175, 372-386`). When the host keeps only the first, the rest are asked one at a time (`register.tsx:565-569`). Descriptions and previews reach a dialog the same way (`driver.ts:59-75`) | [host] `$.ui.ask` takes at most four options |

### 1.3 Open point 1, settled by a run

Probe [ran], Claude Code 2.1.325, `claude -p "/probe:go"`: a mod's `command.run` hook spawned a Haiku agent ("remember
BANANA7, reply stored."), waited for its end, then called `$.session.send({ to: { agentId }, text: "what was the word?" })`.

```
spawn: {"model":"claude-haiku-5-5","agentId":"a61f596ae024e8127"}
list after 1: {... "status":"completed","spawnedBy":"probe"}
ends 1: [{"text":"stored.","reason":"answer"}]
send: {"isDelivered":true}
ends 2: [{"text":"stored.","reason":"answer"},{"text":"BANANA7","reason":"answer"}]
```

What it shows:

1. A finished agent can be continued from a mod, with its context, and the mod's `turn.complete` hook receives the
   second answer under the same agent id. No model in the main session chose or wrote the message.
2. **The second finish is not silent.** The first finish was marked "already-notified" and started nothing
   (`probe-debug.log:222`). The second queued a `<task-notification>` for the main session, and once the command
   returned the main session ran one model turn (`cc_turn_origin=task_notification`, `probe-debug.log:284`; the Sonnet
   reply is the tail of `probe-out.txt`). Under Temper's driver the notification would wait until the driver's command
   ends (the hook holds the turn), then start a turn of the session's model, which the session guard must still hold.
3. Not determined: whether `$.session.send` exists at 2.1.287 (the reports give 2.1.299 for the resume flag of the
   `agent.spawn` event); whether the notification turn can be dropped by the mod; whether an interactive terminal
   behaves as `claude -p` did; whether an agent of an earlier session (a saved run taken up again) can still be
   addressed ([host] text: "finished with no saved transcript this session reads back").
4. The host refuses the call where "this session has no SendMessage tool" [host], so a fallback is always needed.

What the driver would need: a new reviewed call (`session.send`, `scripts/check-mod-calls.sh`); a wait that counts
finishes per agent id (today `lookAtAgents` reads a status of "completed" as done, `driver.ts:513-525`, and right after
a send the status is still the old "completed"); the agent ids kept per run and stage in `$.store` (module variables
start over on a reload: `register.tsx:30-35`); a version or capability gate; and a fresh launch as the fallback.

### 1.4 What the host offers that the mod does not use

[host] names found in the 2.1.325 binary and absent from the reviewed list: `agent.register`, `session.send`,
`session.messages`, `session.append`, `session.compact`, `command.run`, `command.register`, `prompt.submit`,
`model.complete`, `model.fork`, `model.classify`, `tool.call`, `tool.register`, `turn.abort`, `fs.write`,
`http.fetch`, `env.set`, `mcp.call`, `config.set`, `process.run`, `ui.status`, `ui.notify`.
[doc] The repository itself records that `command.run`, `prompt.submit`, `prompt.fill`, `config.set`, `fs.list` and
`clock.sleep` existed at 2.1.287 and were used by the mod in 9.6.2 (`docs/mods-plan.md:250-272`), and that
`command.run` and `config.set` were removed because "every report from 9.6.4 to 9.7.2 held the plugin for these two"
(`CHANGELOG.md:886-895`).

---

## 2. Every hand back cause, and what removes it

`handback(` has 31 sites in `core/driver.ts`. Grouped by cause; "model?" is whether a model is truly needed.

| # | Cause | Lines | Model? | What removes it |
|---|---|---|---|---|
| 1 | `temper go` says `error`: a call inside `go` exited non zero and is not `<cli> gate <stage>` with `-> FAIL` | `driver.ts:352`; `scripts/go.py:108-114` | No for a recorded verdict | **`group gate` and `integrate` record FAIL and exit 1** (`scripts/temper:2509-2512, 3357-3426`); the flow already has the next step for both (`scripts/flow.py:1756-1757`, `:1655-1672`). The CLI prints one verdict marker after it recorded a verdict; `go.py` reads the marker. A true break (usage, group not started, stale plan: `scripts/temper:2448-2470`) stays an error, and `go.py`'s "same calls twice" stop (`:98-103`) already bounds a loop |
| 2 | An after call of an agent failed | `driver.ts:432` | No for a verdict | Same marker. `integrate` is an after call of the fix pass (`flow.py:1669`) and is not the agent's `gate`, so its FAIL hands back today |
| 3 | A call of the person's answer failed | `driver.ts:319`, rule at `:261` | No for a verdict | Same marker. Two options run `group gate` as their call (`flow.py:1995, 2027`); the driver's regex `/ gate [a-z]+/` cannot match `group gate G1` |
| 4 | A call that is not the plugin's CLI: `git checkout -b` (`flow.py:631`), `git -C <wt> rebase` (`flow.py:1818`), the fix branch line (`driver.ts:502`) | exit 126 at `register.tsx:476-477` | No | One `temper` subcommand each. `driver.ts:502` ignores the 126, so a driven fix run gets no branch (confirmed) |
| 5 | A step that is not a CLI call: raw `git add` and `git commit` when the run has no file list (`flow.py:2207-2208`), the pull request steps (`flow.py:2211-2214`), the Pipeline fix (`flow.py:1026-1029`) | `driver.ts:214-217, 295, 440-441, 452` | The commit: no. A pull request body and a CI fix: yes | The commit: `temper spec commit` already exists for the other branch (`flow.py:2205`). The pull request and Pipeline: an agent, or stay with the conversation as one returning step |
| 6 | The person typed an answer at a gate question | `driver.ts:288` (`discuss <text>`) | Only to tell a question from a change request (`commands/temper.md:154-162`) | The driver records the note and runs `state redo <stage> --reason` at Intent to Build, as the page tells the model to; a typed text is a change request by rule, and a separate option opens a discussion. `state redo` is uncounted today, so it must enter the one budget (draft 3f) |
| 7 | An option with a `do` text | `driver.ts:294-296` (`chose <label>`) | Mixed | Per option below |
| 7a | Grill Me, Teach Me (`flow.py:488`), the Design walk through (`:705`) | | Yes, with the person | Stays; returns after it |
| 7b | Open HTML review (`flow.py:644`) | | No | A CLI call that writes the page and prints its path |
| 7c | Share HTML review (`flow.py:646`) | | Yes (publishes an artifact) | Stays; returns after it |
| 7d | Architecture Depth Review (`flow.py:770`), Make a small change (`flow.py:911`) | | Yes | An agent the driver launches (`$.agent.spawn` is on the list); the small change window is a CLI state already |
| 7e | Review config suggestions (`flow.py:820`) | | No | A question per suggestion and a CLI write |
| 7f | Group "Change" (`flow.py:1945`), Context check "Something else" (`flow.py:2320`) | | No | The typed text fills the call, as the name question already does (`driver.ts:307-317`) |
| 7g | "Cancel" in the accept question (`flow.py:1088`) | | No | The driver asks the gate question again. A defect today |
| 8 | A placeholder the driver cannot fill (`{K}`, `{text}`) | `driver.ts:318` | No | The CLI gives the question whose answer fills it |
| 9 | No name typed after three tries | `driver.ts:316` | No | Ask again, or offer Cancel |
| 10 | An agent's answer lists DRIFT rows | `driver.ts:221, 437` | No | The agent records drift with a CLI call; the CLI gives the Scope drift question (its header and options are already in the view: `flow.py:2850` `drift_info`, `runview.ts:57`) |
| 11 | Nobody answered (gate, reason, name, Blocking) | `driver.ts:286, 300, 310, 382` | No | End the drive as saved (`done`), not a hand back: a session with no person cannot answer either |
| 12 | A before call failed; no agent started; `state init` failed; a CLI step failed; a Blocking answer call failed | `driver.ts:346, 384, 421, 435, 448, 323, 494, 499` | To diagnose | Stop with the CLI's own FAIL line as a question ("Retry, Save for later"); a model adds nothing the line does not say |
| 13 | Bounds and defects: question round 6, 120 waits, same after calls, 300 turns, no action, unknown action, a throw | `driver.ts:284, 359, 362, 458, 338, 392, 456, 142-145` | No | Stop as saved, with the reason |
| 14 | `/temper:fix` while a run is active | `driver.ts:489` | No | The restart question |

Left as true hand backs: 7a, 7c, the pull request and Pipeline fix of 5, and 7d until an agent takes it. Each is one
step, so each can return.

## 3. How a hand back could return to the driver

Today it cannot: the command goes on to the page with a note (`register.tsx:583-586, 763-764`), the page says "carry
that option out ... then go on with the loop" (`commands/temper.md:43`), and the driver starts only inside
`command.run` (`register.tsx:722-770`).

| Way | Needs | Cost and risk |
|---|---|---|
| A. No hand back: the driver launches an agent for the step | `$.agent.spawn` (on the list); a brief per step kind; the CLI names the agent | Fits the directory rules. The agent cannot ask the person (the host has no question dialog in a subagent: platform report 3), so it does not fit 7a |
| B. One step, then stop | `commands/temper.md:24-28, 43` and `commands/fix.md`: after a `chose` or `discuss` note, do that one thing and end the turn with "type /temper:temper". The driver already takes up an active run on the bare command (`register.tsx:617`) | One keystroke per hand back. No new call. The model must obey "stop"; the session guard holds it meanwhile |
| C. The mod runs the command again | `$.command.run` from the main session's `turn.complete` ([host]: "called from a command.run hook, it would wait on the turn this hook is holding ... run it from a later event (turn.complete)"); a marker in `$.store` (run id and step); a bound on re entries | The directory held the plugin for exactly this call from 9.6.4 to 9.7.2 (`CHANGELOG.md:886-889`). Only if owner decision 6 drops the directory |

Recommended: A where an agent can do the step, B for the rest, C not planned.

## 4. "Ids, not text"

### 4.1 Where text is the key today [code]

- Verdicts by printed text: `-> FAIL` (`go.py:109`; `driver.ts:261, 432`), `NEXT: `, `is parked`, ` task gate N `
  (`driver.ts:80-82`), ` panel x ` (`:431`).
- Option kinds by label or `do` text: `More options` (`driver.ts:290`), `^Ask the accept question` (`:291`), `Cancel`
  (`:301, 311`), `Carry forward` (`:383`). Step kinds by English (`driver.ts:215-216`).
- An agent's free text: `DRIFT` (`driver.ts:221`), `TASK N: stopped:` (`:427`). ASCII panels parsed back (`:88-137`).
- The audit: header, question text and label must be equal (`core/answers.ts:33, 70-76`); the session's question
  (`core/session.ts:208-215`), its agent launch (`:193-206`) and a person only call (`core/rules.ts:461`).

### 4.2 What to add, all inside version 1

| Where | Add | Note |
|---|---|---|
| `scripts/flow.py` `opt()` (`:459-481`), `question()` (`:492-507`) | `id` per question and option, `kind` per question, `recommended: true`, `needs: {kind, ...}` in place of a `do` sentence, step objects `{kind: call or show-report or note or model}` | `move` is already an enum (`flow.py:58-59`) and already in the view. `run_id` and `step` are already on every ask (`:501`) |
| `scripts/go.py` | pass `id`, `kind`, `move`, `recommended`, `needs` through `slim()` (`:41-55` drops every key not in `SLIM_KEYS`, `move` included); a verdict field per call run; a `kind` on `error` (`:92, 101, 112, 120`); a launch key and optional `effort` on each agent | Without this the driver never sees an id |
| The CLI's verdict commands (`gate`, `task gate`, `group gate`, `integrate`) | one machine line or exit code that says "a verdict was recorded" | Replaces four text patterns |
| `core/runview.ts` | read the new fields | The parser reads fields by name and ignores the rest (`:105-130`), so an old mod reads a new view. The version check does not need to move (`:150`) |
| `core/driver.ts` | select by `kind`, `id` and `needs`; record by question id | The label stays the key inside one known question, because `$.ui.ask` returns the label (`register.tsx:540-541`) |
| `core/answers.ts`, the decision book | keep `question id` and `option id` with each decision | For a dialog the conversation raised, text stays the join: the result is keyed by question text (`answers.ts:56-63`). Ids cannot replace that match; they can make it one lookup |
| Fixtures | regenerate; **split first** | `view-fixtures.ts` is 259,060 bytes, 3,084 under the 256 KiB cap (`scripts/quality-check.sh:21-27`), and holds 642 option entries: an id on each passes the cap. A third module, or views moved to `view-fixtures-2.ts`, in the same change (`scripts/selftest/make-view-fixtures.sh`, `temper-cases-8.sh:455-458`) |
| e2e | traces by option id (`scripts/e2e/loop.ts:94, 169`) | So a label change does not move 23 scenarios |

Three defects sit in this area and are confirmed at the head: the Context check is never parsed (the CLI writes
`context_check.question` as an object, `flow.py:2340-2341`; the mod reads it as the text, `runview.ts:132-137`); the
typed answer cap is 100 (`answers.ts:81`); the fix branch (`driver.ts:502`).

## 5. The guard: what exists only for a model in the main session

| Part | Lines | Why | May go when |
|---|---|---|---|
| `core/session.ts` | 283 | "a cheaper model for the session cannot leave the script" (`:1-12`) | No model turn runs in the main session during a run: every way in is driven (today doors, run words, a second request and `/temper:fix` with a run active go to the conversation: `register.tsx:611-619, 723-741`) and no hand back is left. A continued agent's notification turn (section 1.3) keeps it needed |
| The kept request and `featureWhy` | `register.tsx:410-418, 429-431, 452-457, 742-746, 828-834`; `session.ts:217-255` | A session summarised the request | The driver passes it whole (`driver.ts:345`) |
| The skill window | `register.tsx:405-427, 820-824`; `session.ts:61-79` | Lets a skill's questions past the question rule | With the question rule |
| `next.agents` and the named agents memory | `runview.ts:48-50`; `flow.py:2800-2808, 2858` | The launch rule across a reload | With the launch rule |
| The hand back words | `register.tsx:580-586`; `commands/temper.md:24-28, 42-43` | To pass a run to a model | When a hand back is one named step |
| The text match of answers | `core/answers.ts`, `core/decisions.ts`, `adapter.ts` book | To prove the person chose, not the model that asked | Under the driver the answer comes from `$.ui.ask` and the calls run by `$.process.spawn`, which is no tool call. It stays for the report's decisions and for any conversation carried run |

What does not go: `core/rules.ts`, `core/shell.ts`, `core/paths.ts` (1,271 lines). They judge the stage agents, which
stay models with Bash (`register.tsx:784-788`): stage write tables, the CLI's files, `--no-verify`, `core.hooksPath`,
and the person only calls (`rules.ts:476-497`), which an agent must never run.

## 6. The risk of leaning on the mod

- The API is early access "and can change" (`docs/mod.md:147-150`). The mod reaches five fields by casts
  (`register.tsx:731, 755, 786, 790, 805-806`) and relies on a `$` call having no time limit (`:463-466`).
- It loads only on Claude Code 2.1.287 or later (`core/config.ts:31`), draws and asks only in a terminal or the
  desktop Code tab, and has no person to ask in `claude -p` or a cloud session (`docs/mod.md:134-145`). An
  organization can switch it off (`docs/mod.md:152-162`).
- [ran] On this host the hooks modules of installed plugins wait on a rollout flag
  (`tengu_plugin_hooks_modules`, `mod-debug.log:177`). So whether a user has the mod is the host's decision.
- The plugin directory accepts hooks, mods and scripts "only from Verified organizations" (`CHANGELOG.md:202-203`).
- **The share of users with the mod: not determined, and not determinable from the product** (no telemetry:
  `docs/trust.md:7`). The plan must not assume one.

What the plan must guarantee for a run without the mod:

1. Every structural gain is in the CLI: fewer questions (`auto` actions), verdicts in place of errors, repair in
   place, the budget. `temper go` runs `auto` and mechanical `work` inside the CLI for both carriers
   (`scripts/go.py:95-117`), so two approvals hold without the mod. Only the cost of the relay differs ($0.28 to $0.97
   and 22 to 59 turns a run today; fewer stops mean fewer turns).
2. One contract, `temper go`'s output, for `commands/temper.md` and `core/driver.ts`; CI keeps failing when the flow
   with the mod differs from the flow without it (`scripts/e2e/run.ts:27-31`).
3. Continuing an agent is an option of the carrier, never the only path: the CLI always gives the fresh launch too.
   A conversation has SendMessage itself (platform report 2), so the same step is open to it.
4. No promise rests on the mod: the CLI's verdicts, the commit hook and the ledger are the floor (`docs/trust.md:62-72`).
   Without the mod nothing checks that a person answered; that is today's state and stays.

## 7. If the driver cannot continue an agent

The next best is the one that already exists: the agent runs its own gate before it returns and repairs in its own
turn. Which briefs do this today [code]:

| Agent | Runs its gate and fixes before returning | Line |
|---|---|---|
| Intent | yes, `gate intent` | `agents/intent.md:141` |
| Plan | yes, `gate plan` (the preflight runs inside it, holding an Opus turn open) | `agents/plan.md:60` |
| Design | yes, `gate design` | `agents/design.md:24` |
| Build (stage agent, fix pass, record pass) | yes, `gate build` | `agents/build.md:89` |
| Fix (`/temper:fix`) | yes, `gate build` | `agents/fix.md:55` |
| Check agent | yes, `gate check` | `agents/check.md:54` |
| Build task | runs `task gate N` but is told to **stop and return** when it fails; a new agent takes the retry | `agents/build-task.md:13-14` |
| Group fix agent | runs the group's Validate until it passes; the CLI runs the group gate after | `agents/build.md:28-35`; `flow.py:2059-2063` |
| Review | no: it changes no code and the person loops a finding back | `agents/review.md:30-31` |
| Acceptance, env, plan review, pipeline, rca | no gate of their own, or told never to run it | `agents/env.md:54`, `agents/plan-review.md:88`, `agents/pipeline.md:10`, `agents/rca.md:38` |

So for 3e and 5b the mod free form is: the fix agent (Review or Check finding) and the Build task agent run the narrow
check that failed and repair until it passes or their own bound is spent, before they return. It needs brief edits
(`agents/build-task.md:13-14`, `agents/build.md`, a recheck call that prints only the open rows) and the CLI's attempt
count to accept more than one gate run per launch. Continuation by `$.session.send` is then an extra for the case the
fault is found after the agent returned (a later gate, a person's note), on hosts that have it.

---

## 8. The smallest change, in order

1. **Verdicts** (2g). `scripts/temper`: `group gate` and `integrate` print one marker line after a verdict is
   recorded. `scripts/go.py:108-109`: a call with the marker is a verdict. `core/driver.ts:261, 432` and `:80-82`:
   read the marker (one helper). `commands/temper.md`: the same rule for the conversation.
2. **Small defects on the driver's path**: Cancel at the accept question (`driver.ts:291-296`), nobody answered ends as
   saved (`:286, 300, 310, 382`), the fix branch and the two raw git calls become `temper` subcommands
   (`driver.ts:502`; `flow.py:631, 1818, 2207-2208`).
3. **Ids** (1e, 7c first half): `flow.py` `opt()` and `question()`, `go.py` `slim()`, `runview.ts`, `driver.ts`,
   `answers.ts`; split and regenerate the fixtures; e2e traces by id.
4. **Closed hand back kinds, each one step** (2g second half): `needs` kinds in `flow.py`; the driver routes typed
   text (note and `state redo`), typed fills, DRIFT from a CLI record; an agent for the small change and the depth
   review; `commands/temper.md` and `commands/fix.md` stop after one handed step (way B).
5. **Continue an agent** (decides 3e, 4d, 4e), only after an owner decision on the directory and the minimum version:
   `register.tsx` (a `continue` port over `$.session.send`, ids in `$.store`, a wait that counts finishes),
   `driver.ts` (one effect), `go.py` and `flow.py` (`continue_of` on an agent entry, with the fresh launch beside it),
   `scripts/check-mod-calls.sh`, `core/session.ts` (hold the notification turn), a capability gate.
6. **Shrink the guard** (7c second half): after every way into a run is driven; remove the kept request, the skill
   window and the launch memory; keep `session.ts` while any model turn can run in the main session.

## 9. Not determined

- `$.session.send` at 2.1.287; the minimum version a continued agent would need.
- Whether the notification turn after a continued agent can be dropped, and what it does in an interactive terminal.
- Whether an agent can be continued after the session was restarted, and how long the host keeps its transcript.
- The host's bound on spawns running at once.
- Whether the mod's own `tool.call` hook sees the driver's `$.agent.spawn` (the mod report left this open; I did not test it).
- The share of users with the mod.
