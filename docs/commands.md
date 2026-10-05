---
title: Commands Reference
nav_order: 3
---

# Commands Reference

## `/temper` (Unified Command)

**The one command for the full SDLC.**

```bash
/temper "add login feature"
/temper "JIRA-123"
/temper --resume              # Resume from checkpoint
```

> **Headless / non-interactive (`claude -p`, CI):** the bare `/temper` alias is only
> registered in interactive sessions. Use the fully-qualified name instead:
> `claude -p '/temper:temper "add login feature"'`. All other commands
> (`/temper:plan`, `/temper:build`, etc.) already use their fully-qualified form and
> are unaffected.

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
| **Share HTML review** | Publish the same review so other people can comment by link: a Claude artifact (comments come back automatically) or, without one, a secret Gist (comments come back by paste). Asks before anything leaves your machine |
| **Save for later** | Stop, save state, resume later with `/temper` |
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

The short form `/temper` works only when no other plugin has a command with the same
name; `/temper:temper` always works, and the mod's own messages use it. When the first word
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
type a change."). Pressing Continue records your decision, asks Claude to mirror it in the CLI
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
A later `/temper "{slug}"` presents the draft at its Intent gate and builds on it,
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

When the `ocr` CLI is installed, `/temper:review` automatically runs a second defect-detection pass during Step 2.5. OCR handles line-level defects; Temper keeps intent validation, security analysis, and architecture depth.

| Config Key | Default | Description |
|------------|---------|-------------|
| `tools.ocr.mode` | `auto` | `auto` (use if available), `off` (never invoke), `require` (block if missing) |
| `tools.ocr.replace-defect-subagent` | `true` | Drop generic defect hunting from Temper subagents when OCR is active |
| `tools.ocr.timeout` | `10` | Minutes before OCR invocation is killed |
| `tools.ocr.concurrency` | `8` | Max concurrent file reviews by OCR |
| `tools.ocr.extra-args` | `""` | Additional CLI flags passed to `ocr review` |

**Evidence labels:**

- `[OCR]` — Finding from the OCR engine alone
- `[OCR+TEMPER]` — Both engines independently found the same issue (file + line +/-2 + category match). Confidence boosted: min(0.95, max(a,b) + 0.15)

**Modes:**

| Mode | OCR available | OCR missing | OCR fails at runtime |
|------|--------------|-------------|---------------------|
| `auto` | Run + dedupe | Skip silently | Warn + degrade |
| `require` | Run + dedupe | BLOCK with install instructions | Warn + degrade |
| `off` | Never invoke | Never invoke | Never invoke |

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

One-command project setup. Idempotent — safe to re-run; never overwrites an existing config or an existing non-Temper git hook.

```bash
/temper:init
```

**What it does:**

- Seeds `.claude/temper.config` from the bundled default (if absent; an existing config is left untouched, with a note about any retired blocks in it)
- Scaffolds `.temper/` (the gate ledger, overrides log, feedback-loop registry)
- Installs the **native commit gate** — the pre-commit hook that blocks `git commit` while any gate is red (backs up a prior non-Temper hook first)

**You usually don't run it by hand** — your first `/temper "…"` in an un-set-up project does all of this automatically. Optional edit-time guardrails are a separate `/temper:pack enable hooks`.

---

## `/temper:pack`

Manage quality packs: view, toggle, or create new ones.

```bash
/temper:pack
```

**What it does:**

- Shows all defined packs with enable/disable status
- Lets you toggle packs on/off
- Create new custom packs by scanning your codebase

**Output:**

```
┌─────────────────────────────────────────────────────────────┐
│ PACK — Quality Pack Manager                                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  PACK                     STATUS    RULES                    │
│  ─────────────────────── ──────── ───────────────────────── │
│  quality                   ON      BLOCK: 3, WARN: 5       │
│  tdd                       ON      BLOCK: 2, WARN: 4       │
│  security                  ON      BLOCK: 6, WARN: 2       │
│  git                       ON      WARN: 4, SUGGEST: 4     │
│  company                   OFF     BLOCK: 4, WARN: 3       │
│                                                             │
│  5 packs total (4 enabled, 1 disabled)                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**Options:**

| Option | What it does |
|--------|-------------|
| **Toggle packs** | Enable or disable packs via multi-select |
| **Add new pack** | Scan codebase, interview about conventions, generate custom pack |
| **Done** | Exit pack manager |

**Adding a new pack:**

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
