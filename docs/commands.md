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
| `/temper:temper report` | Write `.temper/report.md` now |
| `/temper:temper pr` | Ask Claude for a pull request description from the report |
| `/temper:temper mode <full\|minimal\|off>` | Change how much Temper draws |
| `/temper:temper enforcement <on\|off>` | Turn denials on or off |
| `/temper:temper pane` | Open or close the pane. A bare `/temper:temper` does the same while a run is active. |
| `/temper:temper play` | Open or close the Temper Merge game. Only you can open it. Terminal and desktop app only. |
| `/temper:temper help` | List these |

These 17 words are reserved: `status`, `timeline`, `approve`, `next`, `back`, `override`, `accept`,
`drift`, `pause`, `resume`, `report`, `pr`, `mode`, `enforcement`, `pane`, `play` and `help`.

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
Plan"), one sentence that says what key 1 does and what happens next ("1 Make the plan. Claude
writes the plan: which files change and the steps. Then you approve it."), the six phases as chips
(a check mark for done, a filled chip for the phase you are in, plain chips for upcoming phases, a
redo mark after a back step), and buttons: up to three actions on `1`, `2` and `3`, `Skip with a
reason` on `9` and `More` on `0`. Key `9` moves the focus to a reason field below the buttons; Enter
records the skip with that reason, and an empty reason is refused (the subcommand is still
`/temper:temper override <reason>`). The pane repeats this with the intent title, the acceptance
criteria ("what must be true") and a checklist, and it shows a short line under every action (10
words at most); its `0` expands the full action list, whose entries use the letters `a`, `b`, `c`
and so on. Under about 100 columns (for example while the
pane is docked) the band uses a compact form without borders. `minimal` shows the chips only.

### Each phase

Key `1` is the main action. It changes when the phase is ready to move on. When a passing check
already exists, key 1 says "Approve the intent" or "Approve the plan" at once, with no extra check.
Key `9` is "Skip with a reason" everywhere and always asks for a reason. Key `0` (`More`) shows every action. It appears only when
the phase has more actions.

| Phase | Writes allowed | Keys |
|---|---|---|
| Intent | `intent.md` only | 1 Approve the intent (when the check passes), otherwise Check the intent. 2 Ask me questions. 3 Edit the intent. 0 Save my request. |
| Plan | `intent.md`, `plan.md`, `tasks.md`, `design.md` and new decision records | 1 Approve the plan (when the check passes), otherwise Make the plan. 2 Show the files. 3 Try another plan. 0 Split the tasks, Go back to Intent. |
| Build | The files in the plan, test files and the spec folder | 1 Start the next task, or Send to review when the tasks are done. 2 Run the tests. 3 Show the changes. |
| Review | The spec folder only, unless a fix for that file is active | 1 Start the review, or Fix the problems when findings exist. 2 Review again. 3 Show the changes. In the pane, per finding: Fix, Accept, Explain. |
| Check | The spec folder only. `git commit` stays refused until Check passes. | 1 Run the checks, or Finish the run when every check passes. 2 Run failed checks again. 3 Show the failures. |
| Fix | The failing files | 1 Fix the failures. 2 Fix the findings. 3 Go back to checks. At the limit: Make a new plan, Skip with a reason, Take over. |

A write outside the Build plan raises scope drift. You can add the file to the plan, revert it, or
allow it once with a reason. Each choice is logged. After three failed fix loops (set with
`fix.max-loops`) Temper stops and offers the three choices in the last row.

### The game

Temper Merge is a small puzzle for the time Claude works. It is optional. It is turn based, so it
needs no timing. The board is 4 by 4 and holds metal pieces. Slide all pieces with `w` (up),
`a` (left), `s` (down) and `d` (right). Two equal pieces that touch merge into one piece of double
value, and you score that value. A new piece (2, sometimes 4) appears after each move that changed
the board. The pieces get hotter as the value grows: 2 dark gray, 4 gray, 8 dull red, 16 red, 32
orange red, 64 orange, 128 amber, 256 yellow, and 512 and more white on a hot background. Make a
white hot 512 piece. You may keep playing after that. The game ends when no move changes the board.

- While a phase works, Temper offers the game in three places, in full mode: the band
  (`8: Play while you wait`, a normal button like 2 and 3), the pane (Actions list, key 8) and the
  prompt hint on the terminal ("Press 8 to play while you wait."). The offer goes away when Claude
  stops. Temper never opens the game by itself and never takes the keyboard until you press 8 or
  run the command.
- Open it with `8` at the empty prompt or with `/temper:temper play`. The same command closes it.
  Only you can open it. Claude cannot.
- The setting `game` has three values: `on` (the default: the offers and the command), `command`
  (the command only, no offers) and `off` (nothing; the command answers "The game is off. Set game
  to on in /config.").
- The pane asks for the keyboard when it opens. The Buttons are `w` Up, `a` Left, `s` Down, `d` Right,
  `r` New game and `q` Quit (Esc also leaves). They have hotkeys, so no mouse is needed. The text
  when it opens is always "The game is open. Press w a s d to slide the pieces, r for a new game, q
  or Esc to leave." If no key reaches the game within 3 seconds, it draws one dim line: "No keys yet?
  Press Ctrl+X, then Tab, to give the game the keys." The line goes away when a key arrives. After a
  click on the game, the arrow keys also slide the pieces.
- The board and the score stay when you leave. The next `8` or `/temper:temper play` goes on with
  the same game. `r` starts a new one.
- At the end you see "No more moves. Score 1240. Press r for a new game. q or Esc leaves." A 512
  piece shows "White hot! You made 512. You can keep playing."
- The game shows a banner when a phase is ready or changes, so you do not miss an approval.
- It keeps your best score in the plugin store (written once when a game ends or a 512 is made).
  The score does not change any gate. The board is kept in the plugin state, not in a file.
- The board is 29 columns wide and 12 rows tall, so it fits a 36 column pane and plays at 80 columns.
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
