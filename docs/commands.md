---
title: Commands Reference
nav_order: 3
---

# Commands Reference

## `/temper` (Unified Command)

**The one command for the full SDLC.**

```text
/temper:temper "add login feature"
/temper:temper "JIRA-123"
/temper:temper                        # Resume or continue the current run
```

> **The short form.** `/temper` is an interactive shortcut that may not resolve in every
> surface: in `claude -p` and CI it does not. Type the full name `/temper:temper`, for
> example `claude -p '/temper:temper "add login feature"'`. All other commands
> (`/temper:plan`, `/temper:build`, etc.) already use their full form. With the mod loaded
> and enforcement on, such a headless run stops at the first gate, because only a person in
> an interactive session can approve; with enforcement off it runs on (see [Subcommands](#subcommands)).

**What it does:**

Runs the full software development lifecycle with stage gates:

```
INTENT → (gate) → PLAN → (gate) → BUILD → (gate) → REVIEW → (gate) → CHECK → (gate) → COMMIT
```

The **Intent gate comes first and is deliberately cheap**: you approve (or correct) the
Problem, success criteria, and constraints before any exploration or architecture work
spends tokens — an intent correction at this gate costs words; the same correction
after Plan costs the whole plan, because every downstream artifact is derived from the
intent. Trivial requests (a typo, a one-liner) skip it automatically.

**Stage Gates:**

At each stage, you see a nice summary and choose to proceed:

```
┌─────────────────────────────────────────────────────────────┐
│ 📋 PLAN COMPLETE — Add Login Feature                        │
├─────────────────────────────────────────────────────────────┤
│ 🎯 INTENT                                                   │
│    Problem: Users can't access protected routes             │
│    Success: JWT auth with role-based access                 │
│    Scenarios: 5 (4 unit, 1 integration)                     │
│                                                             │
│ 📁 FILES: 3 create, 2 modify                                │
│ ⚡ RISK: Medium (touches auth layer)                        │
│                                                             │
│ ✅ Ready to build? [Y/e(dit)/n]                             │
└─────────────────────────────────────────────────────────────┘
```

| Response | Action |
|----------|--------|
| **Continue to Build** | Proceed, context clears, next stage begins |
| **Walk through step by step** | Interactive walkthrough: each section explained in detail |
| **Grill Me** | Socratic challenge mode — adversarial questions that stress-test your plan |
| **Open HTML review** | Browser-based review with inline comments (Google Doc-style) |
| **Share HTML review** | Publish the same review as a Claude artifact so other people can comment by link, and their comments come back automatically. Without the Artifact tool it offers Open HTML review instead. Asks before anything leaves your machine |
| **Save for later** | Stop, save state, resume later with `/temper:temper` |
| **Other** | Type a change request, edits applied, gate re-appears |

**Review Gate Additional Options:**

| Response | Action |
|----------|--------|
| **Fix all & continue to Check** | Apply all fixes, proceed to validation |
| **Architecture Depth Review** | Module-depth analysis: seams, adapters, locality, leverage, deletion test |

**Check Gate Additional Options:**

| Response | Action |
|----------|--------|
| **Commit** | Commit with conventional message |
| **Review config suggestions** | Review CLAUDE.md/AGENTS.md suggestions based on what was built |

**Context Management:**

Each stage gate clears context and loads only what's needed:

| Stage | What's Loaded | Size |
|-------|---------------|------|
| PLAN | Full codebase (via subagent) | Large (temp) |
| BUILD | tasks.md + intent.md | ~5-10KB |
| REVIEW | Changed files only | ~20-50KB |
| CHECK | Nothing new | 0KB |

### Subcommands

The short form `/temper` is an interactive shortcut that may not resolve in every surface;
`/temper:temper` always works, and the mod's own messages use it. When the first word
after the command is one of these, Temper handles it instead of starting a run. Any other first word is a feature description, as before.

| Subcommand | What it does |
|---|---|
| `/temper:temper status` | Where the run stands: phase, task, criteria passed, loop count |
| `/temper:temper timeline` | The phases the run went through |
| `/temper:temper approve` | Approve the current phase (Intent or Plan). Only you can do this. |
| `/temper:temper next` | Move on when the phase has passed its gate |
| `/temper:temper back <phase> <reason>` | Go back. Every later phase needs a fresh verdict. |
| `/temper:temper override <reason>` | Skip the current phase once. A reason is required and is recorded. |
| `/temper:temper accept <id> <reason>` | Accept a review finding with a reason |
| `/temper:temper drift <add\|revert\|allow> <reason>` | Decide a pending scope drift |
| `/temper:temper pause`, `/temper:temper resume` | Hand the run over to you, take it back |
| `/temper:temper report` | Show the run report (the mod keeps it in its plugin store, not in a file) |
| `/temper:temper pr` | Ask Claude for a pull request description from the report |
| `/temper:temper mode <full\|minimal\|off>` | Change how much Temper draws |
| `/temper:temper enforcement <on\|off>` | Turn denials on or off |
| `/temper:temper pane` | Open or close the pane. A bare `/temper:temper` does the same while a run is active. |
| `/temper:temper play` | Open or close the Temper Run game. Only you can open it. Terminal and desktop app only. |
| `/temper:temper discuss <text>` | Send a message about the step you are at. The same as key 4 (Discuss). It changes no phase. |
| `/temper:temper continue <stage>` | The Temper bar sends this after you chose Continue. Claude then does the "On Continue" steps of that stage as the original `/temper` writes them (status flip, `state advance`, the feature branch, the commit of the approved artifacts) and launches the next stage. The mod records nothing for it. |
| `/temper:temper help` | List these |

These 19 words are reserved: `status`, `timeline`, `approve`, `next`, `back`, `override`, `accept`,
`drift`, `pause`, `resume`, `report`, `pr`, `mode`, `enforcement`, `pane`, `play`, `discuss`, `continue` and `help`.

Decisions (`approve`, `override`, `accept`, `drift`, `back`) count only when you type
them or press the button yourself. Claude cannot create one. With the mod loaded the
subcommands are handled by the mod; without it the same words are handled by the prompt
based command, so they work on every surface.

With the mod loaded and enforcement on, a decision word that does not come from an
interactive session is refused, with a note that decisions need one: press the bar, or type
`/temper:temper approve` in the prompt box. So a headless `claude -p` run stops at the first
gate, because only a person in an interactive session can approve. With enforcement off the
mod accepts a decision from any origin and records where it came from, and a headless run
goes on.

### Modes

With Claude Code 2.1.287 or later, the Temper mod draws a phase bar, a pane and a few
other elements, and refuses writes that do not belong to the current phase. Two settings
control it, and both can be changed while a session runs:

| Setting | Values | Effect |
|---|---|---|
| `uiMode` (`/temper:temper mode`) | `full`, `minimal`, `off` | `full` draws the bar with action buttons, the pane, toasts, suggestions, the spinner text, the turn line, the hint and the question header. `minimal` draws the phase bar only, with no buttons. `off` draws nothing. |
| `enforcement` (`/temper:temper enforcement`) | `on`, `off` | `on` refuses out of phase writes and an early `git commit`. `off` keeps the drawing only. |

Denials and subcommands work in every mode. The first interactive `/temper:temper` asks once
which mode you want. If your organization locked a mode, `/temper:temper mode` says so and does
not change it. See the README section "Where enforcement works" for what is and is not
covered.

### The phase bar and its keys

In `full` mode the band above the prompt shows `TEMPER`, the step in plain words ("Step 2 of 6:
Plan"), one sentence that says what key 1 does and what happens next ("1 Continue to Build. The
plan is checked. Build opens and Claude starts building."), the six phases as chips
(a check mark for done, a filled chip for the phase you are in, plain chips for upcoming phases, a
redo mark after a back step), and buttons: up to three actions on `1`, `2` and `3`, `Discuss` on
`4`, `Skip with a reason` on `9` and `More` on `0`. Key `9` moves the focus to a reason field below
the buttons; Enter records the skip with that reason, and an empty reason is refused (the subcommand
is still `/temper:temper override <reason>`). The pane repeats this with the intent title, the
acceptance criteria ("what must be true") and a checklist, and it shows a short line under every
action (10 words at most).

Key `0` (`More`) shows a numbered menu of the other options, in the band above the phase chips and in
the pane, with the line "More actions. Press the number shown." The menu takes the place of the main
buttons, so its numbers are `1` to `9` (a letter would type into the prompt box), and `0` says
"Fewer" and goes back. A choice from the menu runs and closes the menu. Under about 100 columns
(for example while the pane is docked) the band uses a compact form without borders. `minimal`
shows the chips only.

### One flow, two views

The bar is the same choices as the questions, without typing. The orchestrator
(`commands/temper.md`) still runs every stage with its own brief and the CLI still judges every
check. With the Temper mod loaded the orchestrator does not ask its gate question a second time: it
prints the stage panel and the check result, and waits ("Waiting for you. Use the Temper bar, or
type /temper:temper approve (or back, override, pause), or type a change."; minimal and off modes draw
no buttons, so there you type the word). Pressing Continue records your decision, asks Claude to mirror it in the CLI
state, and then runs `/temper:temper` with no arguments, which is the orchestrator's own Resume: it
starts the next stage in its own subagent. Without the mod nothing changes and the orchestrator asks
its questions as before.

The bar holds only the options the original orchestrator has, plus Discuss, Play and Skip with a
reason. The table is one to one. Everything else (show the files, run the tests, show the changes,
write the PR text, go back a phase) you can still ask for by typing; the subcommands stay.

| Original option (`commands/temper.md`) | Temper bar button |
|---|---|
| Continue to {next} (Recommended) | `1` Continue to {next} (at a Build checkpoint: `1` Continue with task N) |
| Loop back to {upstream} | `1` when the check failed (it asks for a reason); under `0` More at the Build completion gate and at Review |
| Override and continue | `9` Skip with a reason |
| Save for later | `0` More, Save for later (pauses the run; Resume when paused). At Done: `2` |
| Grill Me | `2` or `3` where the phase has no better option, else `0` More, Grill me |
| Teach Me | `3` (or `2` at the Build completion gate), else `0` More, Teach me |
| Walk through step by step | `2` at Plan |
| Open HTML review | `3` at Plan |
| Architecture Depth Review | `2` at Review |
| Review config suggestions | `2` at Check, only when `config-suggestions.json` exists |
| Change (Build checkpoint) | `2` at a Build checkpoint: a draft "Change this task: " in the prompt box |
| Stop (Build checkpoint) | `3` at a Build checkpoint |
| Commit | `1` when the run is done |
| Other (a change request) | `4` Discuss: a draft "Discuss this step: " in the prompt box |

Discuss and Change only put a draft in the prompt box. You type the rest and press Enter. Nothing
moves and no event is written. If a dialog or the game holds the keys, the toast says "Close the
pane, then type your message." Claude answers the message; if it asks for a change, Claude makes
the change, runs the check again, and waits for you again.

### Each phase

Key `1` is the main action. It follows the check result the CLI wrote: Continue to the next phase when
the check passed, Loop back to the phase before when it failed, and Start or Run the phase when there
is no result yet (the orchestrator runs the stage and its check itself). In Build every task is its own
checkpoint: while tasks are open, key 1 says "Continue with task N". Key `4` is Discuss everywhere.
Key `9` is "Skip with a reason" everywhere and always asks for a reason. Key `0` (`More`) shows the rest.

| Phase | Writes allowed | Keys |
|---|---|---|
| Intent | `intent.md` only | 1 Start Intent, or Continue to Plan. 2 Grill me. 3 Teach me. More: Save for later. |
| Plan | `intent.md`, `plan.md`, `tasks.md`, `design.md` and new decision records | 1 Run Plan, Loop back to Intent, or Continue to Build. 2 Walk through step by step. 3 Open HTML review. More: Grill me, Teach me, Share HTML review, Save for later. |
| Build, checkpoint (tasks are open) | The files in the plan, test files and the spec folder | 1 Continue with task N. 2 Change. 3 Stop. More: Grill me, Teach me, Save for later. |
| Build, completion | The same | 1 Continue to Review, or Loop back to Plan when the check failed. 2 Teach me. 3 Grill me. More: Loop back to Plan, Save for later. |
| Review | The spec folder only, unless a fix for that file is active | 1 Run Review, Loop back to Build, or Continue to Check. 2 Architecture depth review. 3 Grill me. More: Teach me, Loop back to Build, Save for later. In the pane, per finding: Fix, Accept, Explain. |
| Check | The spec folder only. `git commit` stays refused until Check passes. | 1 Run Check. 2 Review config suggestions (only when the file exists), else Grill me. 3 Teach me. More: Save for later. |
| Fix | The failing files | 1 Fix the failures. 2 Fix the findings. 3 Continue to Check. At the limit: Loop back to Plan, Skip with a reason, Save for later. |
| Done | Nothing is blocked | 1 Commit (Claude commits and does not push). 2 Save for later. |

A write outside the Build plan raises scope drift. You can add the file to the plan, revert it, or
allow it once with a reason. Each choice is logged. After three failed fix loops (set with
`fix.max-loops`) Temper stops and offers the three choices in the last row.

### The game

Temper Run is a small runner game for the time Claude works. It is optional. Ember, a small dragon,
runs on the spot in a forge hall, like the dinosaur in a browser. Iron anvils and buckets of cold water
come from the right: press `w` to jump over them. Hammers fly through the air at head height: press
`s` to duck under a low one (a high one flies over you). The floor and the far wall scroll, sparks
drift by, and the wall warms from dark gray to deep red as the score rises (heat 1 to 5, one level
for every 400 points, shown as bars). At every 100 points Ember flashes yellow and a banner says
"Hot! 100". The top right shows `HI 00155  00032`: the best score and the score.

It is made to be fair and easy to play:
- A jump takes about 0.9 seconds. A jump pressed up to 250 ms before the landing is remembered and
  fires on the landing. A duck lasts 0.8 seconds, and a jump cancels it.
- The hit boxes are smaller than the pictures, so a near miss is a miss.
- The first obstacle arrives after 2.5 seconds. The game keeps a gap between obstacles that you can
  always clear at the current speed, and it never asks for a jump and a duck too close together.
- A help line, "Press w to jump. Press s to duck.", shows for the first 4 seconds of a run.

- While a phase works, Temper offers the game in three places, in full mode: the band
  (`8: Play while you wait`, a normal button like 2 and 3), the pane (Actions list, key 8) and the
  prompt hint on the terminal ("Press 8 to play while you wait."). The offer goes away when Claude
  stops. Temper never opens the game by itself and never takes the keyboard until you press 8 or
  run the command.
- Open it with `8` at the empty prompt or with `/temper:temper play`. The same command closes it.
  Only you can open it. Claude cannot.
- The setting `game` has three values: `on` (the default: the offers and the command), `command`
  (the command only, no offers) and `off` (nothing; the command answers "The game is off. Set game
  to on in /config."). Off also reads `false`, `no`, `0`, `disabled` and `none`. On also reads
  `true`, `yes` and `1`. Any other value, a typo for one, is on and shows no message.
- The pane asks for the keyboard when it opens. The Buttons are `w` Jump, `s` Duck, `r` Run (it says
  Run again after a game over) and `q` Quit (Esc also leaves). They have hotkeys, so no mouse is
  needed. The text when it opens is always "The game is open. Press r to run, w to jump, s to duck,
  q or Esc to leave." If no key reaches the game within 3 seconds, it draws one dim line: "No keys
  yet? Press Ctrl+X, then Tab, to give the game the keys." The line goes away when a key arrives.
  After one click on the game, Space and the Up arrow jump and the Down arrow ducks, with no wait.
- At the end you see Ember fallen, "Game over. Your forge went cold." and "Press r to run again. q or
  Esc leaves." A score above the best shows "New record. The forge is hot."
- The game shows a banner when a phase is ready or changes, so you do not miss an approval.
- It keeps your best score in the plugin store (written once for each game over). The score does not
  change any gate. A press of a Button is one counter in the plugin state; the clock writes nothing.
- The picture is 9 rows of coloured half blocks, as wide as the pane allows (36 to 72 columns). It
  fits an inline pane at 80 columns. Ember is 8 pixels (4 rows) tall.
- It exists on the terminal and the desktop app only. On the VS Code extension and on mobile the
  command prints a short text and nothing else happens.
- Refusals still apply while the game is open.

---

## `/temper:intent`

Capture an idea as a draft `intent.md` — the artifact that starts the pipeline —
without starting the pipeline.

```bash
/temper:intent "handlers spend a third of call time on status-only queries"
/temper:intent "JIRA-4521"
/temper:intent                # interview from scratch
```

**What it does:**

- Interviews the originator the way an analyst would (scope, affected users,
  constraints, what better looks like) — no formal language required of them
- Writes `.temper/specs/{slug}/intent.md` with `Status: draft`, the author (from git
  config), Problem, measurable Success Criteria, Constraints, Target Users, and Open
  Questions — **no scenarios and no architecture**; those are Plan's job, derived from
  the measured blast radius later
- Keeps criteria and constraints firm: `temper gate intent` fails a draft that uses
  should, may, might, or possibly in one, unless the line carries a `(source: ...)`
  marker (the hedge belongs to the source). A source "should" or "may" is never turned
  into "must" without asking the originator; the answer goes into `### Decisions`
- Offers to commit the draft, so author, timestamp, and revision history live in
  version control from the moment the idea is real

**Who flips `Status:`** — `draft` (this command) → `accepted` (the human's Continue at
`/temper`'s **Intent gate**; the plan gate only in a standalone `/temper:plan` run,
where it's the first human gate to review the intent) → `completed` (the commit step).
A later `/temper:temper "{slug}"` presents the draft at its Intent gate and builds on it,
never overwrites it. A `temper bands` breach drafts intents in exactly the same shape
(see `/temper:status`).

---

## `/temper:check`

Stack validation and quality status.

```bash
/temper:check
```

**What it does:**

- Auto-detects your tech stack
- Finds test, build, and lint commands
- Reports current quality status

**Output:**

```
🔍 Detecting stack...
✅ Detected: React + TypeScript
   • Build: npm run build
   • Test: npm test
   • Lint: npm run lint

📊 Quality Status:
   • Coverage: 78%
   • TypeScript errors: 0
   • Lint warnings: 2
```

---

## `/temper:plan`

Plan with blast radius analysis, mermaid diagrams, and interactive walkthrough.

```bash
/temper:plan "feature description"
```

**What it does:**

- Analyzes which files will be affected
- Identifies dependencies and risk areas
- Generates mermaid architecture diagrams (flowchart, sequenceDiagram, etc.)
- Derives BDD scenarios from requirements + blast radius — **before architecture**
- Builds architecture from scenarios — every file traces to a behavior or infrastructure need
- Generates intent.md with structured success criteria + Gherkin scenarios (medium+ complexity)
- Detects parallel tasks for optimized ordering
- Offers interactive step-by-step plan walkthrough with Q&A at each section

**Example:**

```bash
/temper:plan "add password reset"
```

**Output:**

```
🔍 Blast Radius Analysis

📦 Affected Files: 8
   • src/auth/PasswordResetService.ts (CREATE)
   • src/auth/AuthController.ts (MODIFY)
   • src/email/EmailService.ts (MODIFY)

🔗 Dependencies: 4
   • Email delivery
   • Token generation
   • Rate limiting

⚠️  Risk Areas: 2
   • Token expiration handling
   • Email delivery failures

📝 Generated: intent.md
   Success criteria (3):
     ✓ Users can reset password without support → validate: scenario
     ✓ Reset completes in under 2 minutes       → validate: manual
     ✓ Support tickets decrease 30%              → validate: metric

   Scenarios (5): 3 happy, 1 error, 1 edge case
     Scenario: Successful password reset
     Scenario: Expired token rejected
     Scenario: Rate limiting enforced
     ...

📋 Plan: 5 steps (6 scenario-traced, 2 infrastructure)

## Task 1 — Create PasswordResetService [SEQUENTIAL]
  → Scenario: "Successful password reset"
  → Test: PasswordResetService.test.ts

## Task 2 — Add reset endpoint [SEQUENTIAL: after Task 1]
  → Scenario: "Successful password reset", "Expired token rejected"
  → Test: AuthController.test.ts

## Task 3 — Update email templates [PARALLEL: with Task 4]
  → Infrastructure: required by PasswordResetService

## Task 4 — Add rate limiting [PARALLEL: with Task 3]
  → Scenario: "Rate limiting enforced"
  → Test: RateLimiter.test.ts
...
```

**Note:** Tasks marked `[PARALLEL: with Task X]` can run concurrently since they touch different files.

---

## `/temper:design`

System design for complex/medium features. Auto-skipped for simple or trivial features.

```bash
/temper:design
```

**What it does:**

Produces a system design document (`design.md`) with:

- **Architecture overview** — System components and data flow
- **API contracts** — Request/response shapes, endpoint changes
- **Database changes** — Schema changes, migration strategy
- **Integration points** — External system connections, error handling
- **Decision log** — Architectural decisions with rationale (ADRs)

**When it runs:**

Automatically included in the `/temper` pipeline when:
- `phases.design: true` in temper.config (default)
- AND complexity is `medium` or `complex`

**Config:**

```yaml
phases:
  design: true    # Set false to always skip design stage
```

---

## `/temper:build`

Build with TDD + quality gates.

```bash
/temper:build
```

**What it does:**

- Executes the plan step by step
- Tests derived from intent.md scenarios (RED → GREEN)
- Runs tests after each step
- Scenario coverage gate: every scenario must have a passing test
- Blocks on quality gate failures
- Tracks coverage
- Resumes from checkpoint if interrupted

**Workflow:**

```
🚧 Building...

Step 1/5: Create PasswordResetService
  📋 From scenario: Successful password reset
  ✅ Write test: test_successful_reset
  ✅ Implement
  ✅ Tests pass (4/4)
  ✅ Coverage: 92%

Step 2/5: Add reset endpoint
  📋 From scenario: Expired token rejected
  ✅ Write test: test_expired_token
  ✅ Implement
  ✅ Tests pass (6/6)
  ⚠️  Coverage: 74% (threshold: 80%)
  🔧 Adding more tests...
  ✅ Coverage: 82%

Step 3/5: Email integration
  ✅ Write tests
  ✅ Implement
  ✅ Tests pass (8/8)
  ✅ Coverage: 88%

...

📊 Scenario Coverage Gate:
   ✅ Successful password reset → test_successful_reset (PASS)
   ✅ Expired token rejected → test_expired_token (PASS)
   ✅ Rate limiting enforced → test_rate_limiting (PASS)
   ✅ Invalid email format → test_invalid_email (PASS)
   ✅ Non-existent user → test_nonexistent_user (PASS)

   Coverage: 5/5 scenarios ✅

✅ Build complete
   • Steps: 5/5
   • Tests: 18 passing
   • Coverage: 86%
   • Time: 4m 32s
```

**Resume from Checkpoint:**

If your build is interrupted, Temper saves progress and offers to resume:

```
📁 Found .temper/build-state.json
   Last completed: Task 3/5
   Started: 2026-03-10 14:32

Resume from Task 4? [Y/n] > Y

🚧 Resuming from Task 4...

Step 4/5: Add rate limiting
  ✅ Tests already written
  ✅ Implement
  ...
```

---

## `/temper:review`

Code review with confidence scoring.

```bash
/temper:review
```

**What it does:**

- Analyzes changed files
- Checks against enabled packs
- Validates intent: success criteria (IDD) + scenario coverage (BDD)
- Scores confidence of findings
- Suggests improvements
- Diff-aware: focuses on changed lines
- Catches N+1 queries and performance issues

**Output:**

```
📊 Review Results

Files reviewed: 6
Issues found: 4
Confidence: 91%

🔴 HIGH (Confidence: 96%) [REGRESSION]
   Missing rate limiting on password reset endpoint
   └─ AuthController.ts:89 (CHANGED)
   → Suggestion: Add rate limiting middleware

🔴 HIGH (Confidence: 89%) [NEW ISSUE]
   N+1 query pattern: DB call inside loop
   └─ UserRepository.java:45 (CHANGED)
   → Suggestion: Use batch fetch or JOIN query

🟡 WARN (Confidence: 78%) [NEW ISSUE]
   Method 'processReset' exceeds 30 lines
   └─ PasswordResetService.ts:112 (CHANGED)
   → Suggestion: Extract helper methods

🟢 INFO (Confidence: 65%) [PRE-EXISTING]
   Consider extracting magic number to constant
   └─ TokenService.ts:23 (UNCHANGED)
   → Suggestion: EXPIRATION_HOURS = 24

📊 Intent Validation (IDD): 2/3 mechanically validated
   Problem: Users unable to reset passwords without support
   ✅ Users can reset password → validate: scenario → test_successful_reset PASS
   ✅ Reset completes in < 2 min → validate: manual → requires human review
   📊 Support ticket reduction → validate: metric → post-deploy monitoring required

📊 Scenario Coverage (BDD): 5/5 ✅
   ✅ Successful password reset → test_successful_reset (PASS)
   ✅ Expired token rejected → test_expired_token (PASS)
   ✅ Rate limiting enforced → test_rate_limiting (PASS)
   ✅ Invalid email format → test_invalid_email (PASS)
   ✅ Non-existent user → test_nonexistent_user (PASS)

✅ All tests passing
✅ No security pack violations
```

**Issue Classifications:**

- **REGRESSION** — Code that was working, now broken by your change
- **NEW ISSUE** — Problem introduced by this change
- **PRE-EXISTING** — Issue existed before (lower priority)

**External Engine: open-code-review:**

OCR is off by default. When you set `tools.ocr.mode` to `auto` or `require` and the `ocr` CLI is on your `PATH`, `/temper:review` runs a second defect-detection pass (probed in Step 1, merged in Step 2). OCR handles line-level defects; Temper keeps intent validation, security analysis, and architecture depth.

| Config Key | Default | Description |
|------------|---------|-------------|
| `tools.ocr.mode` | `off` | `off` (never invoke), `auto` (use if available), `require` (block if missing) |
| `tools.ocr.replace-defect-subagent` | `true` | Drop generic defect hunting from Temper subagents when OCR is active |
| `tools.ocr.timeout` | `10` | Minutes before OCR invocation is killed |

**Evidence labels:**

- `[OCR]` — Finding from the OCR engine alone
- `[OCR+TEMPER]` — Both engines independently found the same issue (file + line +/-2 + category match). Confidence boosted: min(0.95, max(a,b) + 0.15)

**Modes:**

| Mode | OCR available | OCR missing | OCR fails at runtime |
|------|--------------|-------------|---------------------|
| `auto` | Run + dedupe | Skip with a one-line notice | Warn + degrade |
| `require` | Run + dedupe | BLOCK, saying where to find OCR's install steps | Warn + degrade |
| `off` (default) | Never invoke | Never invoke | Never invoke |

---

## `/temper:fix`

Root cause analysis + structured fix.

```bash
/temper:fix "issue description"
```

**What it does:**

- Analyzes root cause of the issue
- Creates fix plan
- Implements with tests

**Example:**

```bash
/temper:fix "JIRA-123: Users can't reset password"
```

**Output:**

```
🔍 Root Cause Analysis

Issue: Password reset emails not being sent

Investigation:
  1. Checked email service logs → No errors
  2. Checked token generation → Working
  3. Checked queue → Messages stuck

Root Cause: Queue consumer crashed at 2:34 AM
  → Consumer not auto-restarting

📋 Fix Plan:
  1. Add health check to queue consumer
  2. Implement auto-restart on failure
  3. Add alerting for queue depth

🔧 Implementing...

✅ Fix applied
   • Files changed: 3
   • Tests added: 2
   • Regression risk: Low
```

---

## `/temper:init`

One-command project setup. It is idempotent, so it is safe to re-run. It never overwrites an existing config. It never writes into a folder named `hooks`, so it never writes over a git hook of yours or of another tool: when pointing git at the Temper hook would switch such a hook off, it keeps the Temper hook in the repository's git folder and shows you one line to add to your hook, with a one line hint (see "When you already have a pre-commit hook" below).

```bash
/temper:init
```

**What it does:**

- Seeds `.claude/temper.config` from the bundled default (if absent; an existing config is left untouched, with a note about any retired blocks in it)
- Scaffolds `.temper/` (the gate ledger, overrides log, feedback-loop registry)
- Writes the **native commit gate**, the pre-commit hook that blocks `git commit` while any gate is red, to `temper-gate/pre-commit` in the repository's git folder (the folder `git rev-parse --git-common-dir` names, which git never commits and every linked worktree shares), and points the repository's `core.hooksPath` at that folder, so git runs it in every worktree. A submodule's hook goes in its own git folder. When `.git/hooks` holds hooks git would then stop running, or `core.hooksPath` already names another tool's folder, setup still writes the Temper hook to `temper-gate/pre-commit` but leaves `core.hooksPath` as it is, shows you the line to add and the hint, and goes on without the commit gate until you add it.
- Checks `.claude/settings.json` and `.claude/settings.local.json` in the project for a Temper guard command that does not run an existing script in the current plugin folder (a path from before 9.6.5, when the guard scripts were in another folder, or the folder of an earlier plugin version) and asks whether to replace those commands with the current guardrails set, showing the change first. It never reads or writes the settings in your home folder.

**Where the hook lives.** The installer writes the Temper hook to `temper-gate/pre-commit` in the repository's git folder, through a new file moved into place, and runs `git config --local core.hooksPath` with that folder's absolute path. Git then runs that hook in every worktree, and `git rev-parse --git-path hooks/pre-commit` names it. The installer never writes into a folder named `hooks`: not `.git/hooks`, not the folder `git rev-parse --git-path hooks` names, and not a `core.hooksPath` folder that is not Temper's. It reads the hooks there only to decide. Once `core.hooksPath` is set, git runs the hooks of that folder and no longer those in `.git/hooks`, so the installer sets it only when `.git/hooks` holds no hook git would then stop running: no executable hook under one of git's hook names (an older Temper `pre-commit` does not count, and the installer then says you can delete it) and no `pre-commit.bak.<timestamp>` that an older installer set aside. When `core.hooksPath` already points at the folder, running the installer again makes the hook current, for example after a plugin upgrade moves the plugin folder. When it holds Temper's older folder (`.git/hooks-temper`, which `--global` set from 5.5.0 to 9.6.4, `.git/temper-git-hooks`, which it set in 9.6.5, or the `temper-gate` folder of where the repository used to be before it was moved or renamed), the installer points it at `temper-gate` and prints a note, unless that folder holds other hooks git runs (`git lfs install` writes its hooks into the folder `core.hooksPath` names); then it leaves the value, as it does for `.git/hooks`, and the `pre-commit` there needs the line below. The `--global` option is still accepted and now does what the default does, with a note.

**After you move the repository.** `core.hooksPath` holds an absolute path, so every worktree finds the folder. Moving or renaming the repository, or a folder above it, leaves it naming the old place, and git runs no pre-commit hook until the installer runs again. Your next `/temper:temper` checks the hook and runs the installer, which points `core.hooksPath` at the new place; you can also run `/temper:init`.

**When you already have a pre-commit hook.** When `.git/hooks` holds hooks git would stop running (yours, a `commit-msg` hook, git-lfs's `pre-push`, the pre-commit framework's or lefthook's), or `core.hooksPath` names another tool's folder (husky's `.husky/_`, lefthook, a team's folder), the installer leaves `core.hooksPath` and every one of those hooks as they are. It writes only the Temper hook to `temper-gate/pre-commit` in the repository's git folder and prints this line between its BEGIN and END lines:

```sh
_temper_rc=$?; [ "$_temper_rc" -eq 0 ] || exit "$_temper_rc"; _temper_hook="$(git rev-parse --git-common-dir)/temper-gate/pre-commit"; [ ! -f "$_temper_hook" ] || bash "$_temper_hook" || exit 1
```

The line holds no path of this machine, so it is safe to commit, and it keeps your hook's own result wherever it sits: when the command before it failed, it exits with that status, and otherwise it runs the Temper hook and fails only when that hook blocks. Its FAIL line says why the installer did not point git at the Temper hook (for hooks in `.git/hooks`, it names them), and its hint says where the line goes:

| Your hook | Where the line goes |
|---|---|
| husky (a hooks folder in `.husky`) | `.husky/pre-commit`, which is safe to commit |
| the pre-commit framework | a local hook in `.pre-commit-config.yaml` (repo: local, language: system, pass_filenames: false, always_run: true) with the entry `sh -c '<the line>'`, which the hint prints in full; the framework runs that entry with no shell |
| lefthook, which writes its hook again | a pre-commit command in `lefthook.yml` that runs the line |
| a `pre-commit` from an older Temper (in `.git/hooks` next to other hooks, in Temper's older folder, or in a team folder) | in place of all of its lines, after `#!/bin/sh`; git still runs that hook, so the installer warns about it and shows its stale plugin path |
| any other hook | its start or its end; create the file, executable, if it does not exist |

Once your hook holds the line, with no line before it that starts with `exit` or `exec`, and git can run it (it is executable; for husky v9, husky's own hook in `.husky/_` must be there and executable instead, so run `npx husky` in a fresh clone), running the installer again makes the Temper hook current, says your hook calls it, and exits 0. For the pre-commit framework and lefthook, their config file at the repository's top holding the line outside a comment counts the same way; the installer reads only its text, so a `stages` or `skip` setting there can still keep the line from running. The line that 9.6.5 printed, which runs `temper-pre-commit` in the git folder, still counts: the installer then makes that file current too. When an `exit` or `exec` line comes first, the line never runs, and the installer refuses and says to move it above that line. When the installer refuses before it knows the git folder, it writes nothing and prints the Temper hook's own lines instead, in a subshell, so that their exits end only the subshell and your hook's own result is kept.

**Adding a hook tool later.** The pre-commit framework and lefthook work in `.git/hooks`, so run `git config --unset core.hooksPath` before you install one. The next `/temper:temper` or `/temper:init` then finds that tool's hook, keeps the Temper hook and prints the line to add, with the hint for that tool.

An older Temper version may have left a hook that was not its own as `pre-commit.bak.<timestamp>` in `.git/hooks`. When one is there, the installer warns, names it and says how to get it back: move it back to `pre-commit` in git's own hooks folder and add the line between BEGIN and END in the installer's output to it (when a `pre-commit` of yours is there now, it says to add the old hook's lines to that file instead).

**To remove the hook**, run `git config --unset core.hooksPath` when it points at the `temper-gate` folder, remove the Temper line from your own hook if you added one, and delete the `temper-gate` folder in the git folder (and any `temper-pre-commit` that 9.6.5 left there). The installer prints these steps.

**You usually don't run it by hand.** Your first `/temper:temper "…"` in a project that is not set up does all of this automatically. The optional edit-time guardrails are a separate step: `/temper:pack enable guardrails` (see [Guardrails](#guardrails)).

---

## `/temper:pack`

Manage quality packs: view, toggle, quick-create a launcher pack, configure links and phases, or build a new pack.

```text
/temper:pack
/temper:pack enable guardrails
/temper:pack disable guardrails
```

**What it does:**

- Shows every pack it finds, from three places: the project's `.claude/packs` folder, your global
  pack folder `~/.claude/packs`, and the 8 built-in packs. A project pack shadows a global one of
  the same name, and a global one shadows a built-in one.
- Lets you toggle packs on/off, quick-create a launcher pack, set a pack's link and phases, or build a new pack
- Turns the guardrails pack's guard hooks on or off (see [Guardrails](#guardrails))
- Asks whether to replace a Temper guard command in the project settings that does not run an existing script in
  the current plugin folder with the current guardrails set (it shows the change first)

**Output:** a Quality Pack Manager panel (its exact shape is in `reference/pack.md`, under
"Step 1: Discover + Display") with one row per pack, filled from what it found, and a last line
`N packs total (X enabled, Y disabled)`. The columns:

| Column | What it shows |
|--------|---------------|
| NAME | The pack's name |
| STATUS | `ON` when the pack is in `packs:`, otherwise `OFF` |
| PHASES | The phases that load the pack (`all` when none are set) |
| LINK | The pack's `plugin://` or `skill://` link, if it has one |
| CONNECTED | Whether that link target was found |

**Options:**

| Option | What it does |
|--------|-------------|
| **Toggle packs on/off** | Select packs to enable or disable. Turning `guardrails` on or off runs Guardrails enable or disable, which shows its change and asks first. |
| **Quick-create launcher pack** | Wrap a skill or command as a BLOCK-level pack in the project's `.claude/packs` folder. |
| **Configure pack (link, phases)** | Set the link target or the phases of an existing pack. |
| **Done** | Exit. To open the full pack builder instead, choose **Other** and describe the pack. |

**Link targets.** A launcher pack or a link points at a skill or command. The choices are the
skills and commands this Claude session lists (a plugin's show as `plugin:item`) and the
project's own commands and skills in `.claude/commands` and `.claude/skills`. A
`plugin://name` link counts as connected when the session lists a skill or command of that
plugin, and a `skill://name` link when the session lists that skill or the project has it.
Temper reads no Claude Code file to find them.

**The full pack builder** (choose **Other**, then describe the pack):

```
🔍 Scanning codebase...

Found patterns:
  • Constructor injection (92% of classes)
  • DTO pattern (100% of APIs)
  • Structured logging (78% of services)

Questions:

1. I see you use DTOs for all API responses.
   Should this be a BLOCK rule?
   [Yes/No/Skip] > Yes

2. Constructor injection is common but not universal.
   Make it mandatory?
   [Yes/No/Skip] > Yes

Generating pack...

✅ Created: .claude/packs/company/rules.md

   • BLOCK rules: 2
   • WARN rules: 3
   • SUGGEST rules: 4
   • Status: ENABLED
```

### Guardrails

The guardrails pack adds edit-time guard hooks: secret blocking, protection of the regression test
and of frozen paths, the in-agent commit gate, an approval prompt before an override, a forbidden
import check and auto-format. They are off until you turn them on.

The secret check scans only what a call adds: the content of a Write, the new text of an Edit
(each new text of a MultiEdit) and the command of a Bash call. So an edit that removes a secret,
or the command that unstages one, is not refused. The staged files are scanned only by the native
`pre-commit` hook, at commit time.

`/temper:pack enable guardrails`:

1. Refuses, in one line, when the project folder is your home folder (its settings files would
   then be your user settings), or when the plugin folder's path holds a character that cannot sit
   safely in a quoted command: a quote, a backslash, a dollar sign, a backtick or a line break.
2. Asks which project settings file to use: `.claude/settings.local.json` (personal, the default,
   because each command holds this machine's plugin folder) or `.claude/settings.json` (shared with
   your team; a teammate whose plugin sits in another folder sees those commands as stale). When you
   pick `.claude/settings.local.json` and git does not ignore it, it offers to add it to `.gitignore`.
3. Shows the change it will make, in both project settings files: the entries it adds to the file
   you picked, and any earlier Temper guard entry it removes from either file.
4. When you confirm, merges the hook blocks of the pack's `settings-guardrails.json` into that
   file. A hook in a settings file gets no CLAUDE_PLUGIN_ROOT variable, so each command is written
   out in full: `bash`, a space, then in double quotes the plugin's absolute folder followed by
   `/scripts/guards/` and the guard's script name, such as `block-secrets.sh`. The merge is
   additive: your other hooks stay, and an earlier Temper guard entry is replaced instead of added
   a second time.
5. Adds `guardrails` to `packs:` in `.claude/temper.config`.

`/temper:pack disable guardrails` removes the Temper guard entries from both project settings
files and the `guardrails` entry from `packs:`.

A Temper guard entry is a hook command that names one of the guard scripts (`block-secrets.sh`,
`protect-regression-test.sh`, `block-protected-paths.sh`, `block-uncommitted-gate.sh`,
`confirm-override.sh`, `block-forbidden-imports.sh`, `run-formatter.sh`, `stage-marker.sh` or
`verify-stage-gate.sh`) under the current plugin folder, under the guard scripts folder of
an older version or an older plugin folder outside the project, or through a path that starts with
the CLAUDE_PLUGIN_ROOT variable. A command that runs your own copy of one of these scripts (a
relative path, a path through `CLAUDE_PROJECT_DIR`, or a path inside the project) is yours, and
Temper never touches it.

A plugin upgrade moves the plugin folder, and a guard command written before it then points at a
folder that is gone or out of date. `/temper:pack` (the list) and `/temper:init` check both project
settings files for a Temper guard command that does not run an existing script in the current
plugin folder, including a path from before 9.6.5, and ask whether to replace those commands with
the current guardrails set (the change is shown first).

The pack does not add the stage gate pair (`stage-marker.sh` and `verify-stage-gate.sh`): the
plugin's own hooks already run them. `/temper:pack` and `/temper:init` never read or write the
settings in your home folder. The commit-time layer is the native `pre-commit` hook, which
`/temper:init` installs.

---

## `/temper:status`

Quality metrics dashboard.

```bash
/temper:status
```

**What it does:**

- Shows current quality metrics
- Tracks trends over time
- Highlights hotspots

**Output:**

```
📊 Temper Status Dashboard

Project: my-service
Stack: Spring Boot
Packs: quality, tdd, security, company

📈 Metrics (Last 30 days)
   • Reviews run: 47
   • Issues found: 23
   • Auto-fixed: 18
   • Coverage: 78% → 84% ↑

🔥 Hotspots
   • UserService.java — 4 issues (complexity)
   • OrderProcessor.java — 3 issues (coupling)

📚 Learning (planned)
   • Pattern detected: "Missing null check"
   → Suggestion: Add to company pack

⏱️ Technical Debt
   • Coverage gaps: 2 modules
   • TODOs: 12 (3 critical)
   • Deprecated: 1 dependency
```

**Control bands (closing the loop):** the dashboard also runs `temper bands` — a
deterministic drift check of the metric history against rolling mean ± k·sigma bands
(config: `bands:` in `.claude/temper.config`). `1sigma` logs, `2sigma` means
diagnose, and a `3sigma`/`propose`-tier breach offers to draft the breach as a
Stage-1 `intent.md` for `/temper` to pick up — evidence in, ordinary gates out.
Dismissals are the tuning signal (3+ on one metric → widen the window or retire the
metric). `temper bands` is also runnable headless with no dashboard at all — exit 1 on
a breach — from **any** scheduler (cron, Jenkins, GitLab CI, GitHub Actions; temper
ships no platform-specific wiring on purpose, see `examples/workflow/README.md`),
which is what lets the loop begin and end without a person starting it.
