# Plan: Temper Growth & Adoption ("Part 2")

**Status:** Proposed
**Companion to:** [ocr-integration-phase1.md](ocr-integration-phase1.md) — the OCR integration is the launch anchor for this plan.

Each item below states **what**, **why**, and a gap-free **how** (exact steps, files, commands, templates). Items are ordered by ROI; §12 gives the sequenced 4-week schedule.

---

## 1. Platform Strategy & Complexity Budget

**The guiding principle for everything below:** Temper's goal is to be one of the best **Claude Code** SDLC plugins — not a multi-IDE framework. Depth on one platform beats shallow parity on two. Every feature proposal must pass a complexity test: *does this make the Claude Code experience better, or does it make Temper bigger?*

### Decision: Cursor support is frozen at the v5.1 feature set

Temper's defining capabilities — nested subagents, `AskUserQuestion` gates, MCP tool integration, and the planned hooks-based deterministic layer (§6) — are Claude Code-native. Cursor gets a degraded approximation, and maintaining the mirror (22 rules + 9 commands per release) is the single largest recurring cost in the project. We keep the doorway, stop paying the tax.

**Freeze semantics:**
- Cursor support stays installed, documented, and working at the v5.1 feature set.
- Bug fixes to existing `.cursor/` files: yes. New-feature mirroring: no.
- New capabilities ship Claude Code-first and reach Cursor only if trivially portable (judgment call, default no).
- **Unfreeze criteria** (revisit, don't religion): sustained demand (≥ 5 distinct users requesting parity via issues) or a community co-maintainer volunteering to own the `.cursor/` mirror.

**Concrete changes (all "full parity" claims must go — they become false the moment v5.2 ships):**

1. `README.md` — Cursor install section: replace "Full feature parity with Claude Code v5.0.0" with: *"Cursor support is stable at the v5.1 feature set. New capabilities ship Claude Code-first — see [Platform Strategy](docs/plans/growth-plan.md#1-platform-strategy--complexity-budget)."*
2. `docs/index.html` (GitHub Pages landing) — four parity claims to update (see §4 for the full landing refresh):
   - line ~830 hero copy: "The AI discipline layer for Claude Code and Cursor" → "The AI discipline layer for Claude Code (Cursor: stable v5.1 tier)"
   - line ~859: "Full feature parity with Claude Code." → "Stable v5.1 feature set."
   - lines ~902–903 "Cursor IDE Parity" card → retitle "Cursor IDE (stable tier)", body states the freeze + link
   - line ~1263: same replacement as ~859
3. `docs/getting-started.md` and any other doc claiming parity: `grep -ri "parity" docs/ README.md CHANGELOG.md` and fix every hit (CHANGELOG history entries stay untouched — they were true at the time).
4. `CHANGELOG.md` v5.2.0 entry: note the freeze explicitly so it's an announced decision, not a silent drift.
5. CI: the `cursor-parity` job in §7 is **informational/warn-only** — it reports drift, never blocks.
6. OCR Phase 1: Cursor mirror task removed from the companion plan (done — its §4.6 now documents the non-mirror).

**Simplicity rule going forward (applies to the whole roadmap):** prefer removing/consolidating over adding. Each new capability needs (a) a config kill-switch, (b) a one-line description a newcomer understands, and (c) no new runtime dependency. If a feature can't meet all three, it doesn't ship.

---

## 2. README Rewrite (highest-conversion fix)

**Why:** The README is ~820 lines structured as accumulated release notes ("What's New in v5.1.0 / v5.0.0 / v3.1.0 / v3.0.0"). A visitor decides to star in ~60 seconds; they currently hit a wall of history before seeing a demo or install command.

**How:**

1. Create the new structure in this exact order, target **≤ 300 lines**:
   1. Title + tagline + badges (keep current).
   2. **Demo GIF** (from §3) — directly under the tagline, before any prose.
   3. **The 30-second pitch** — 4 sentences max: problem (AI ships happy-path code), mechanism (intent.md contract + gates), proof (one number from §5 once available).
   4. **The killer story** — the existing "Missing Edge Case" rate-limiting example, condensed to ~15 lines. Lead with it; it is the best content in the current README.
   5. **Install** — Claude Code commands first; Cursor install kept but with the §1 freeze wording.
   6. **Commands table** — the existing 9-row table, each row linking to `docs/commands.md`.
   7. **How it works** — one diagram (the existing intent.md ASCII tree) + 3 short paragraphs (IDD/BDD/TDD), each linking to a full page under `docs/`.
   8. **Optional power-ups** — 4-line table: code-review-graph, semgrep, open-code-review → link to `docs/recommended-setup.md`.
   9. Links footer: docs, changelog, contributing, license.
2. **Move, don't delete.** Migrate displaced content:
   - All "What's New in vX" sections → already in `CHANGELOG.md`; verify nothing exists only in README (diff each section against CHANGELOG; copy any orphaned detail in).
   - Deep IDD/BDD/TDD methodology → new `docs/methodology.md` (docs site nav_order after getting-started).
   - "Real Findings" examples beyond the lead story → seed content for the evidence gallery (§5).
3. **Acceptance check:** a person who has never seen Temper can answer "what is it / does it work / how do I install" from the rendered README without scrolling past the commands table. `wc -l README.md` ≤ 300.

---

## 3. Demo Assets (show, don't describe)

**Why:** There is one static dashboard PNG. Quality tooling sells on seeing the catch happen.

**How:**

1. **Tool:** [vhs](https://github.com/charmbracelet/vhs) (scriptable → reproducible → re-recordable every release). Fallback: asciinema + agg for GIF conversion.
2. **Script the scenario** (`docs/assets/demo.tape`): in the playground repo (§9), run `/temper "add password reset"` pre-arranged so the scenario-coverage gate catches the missing rate-limit test, writes the failing test, implements, passes. Trim to ≤ 90 seconds; speed up typing 2×; pause 2s on the gate output and the `Scenario Coverage: 4/5 → 5/5` moment.
3. **Output:** `docs/assets/demo.gif` (≤ 10 MB so GitHub renders inline) + an `.mp4` for social posts. Commit the `.tape` file so the demo is regenerated per release, never stale.
4. Embed at README position §2.1.2 and on the GitHub Pages landing page (§4).
5. **Acceptance check:** GIF autoplays on the GitHub repo page; the catch moment is legible on mobile width.

---

## 4. GitHub Pages Landing Refresh (`galando.github.io/temper`)

**Why:** The landing page (`docs/index.html`, served via `pages.yml`) is the click-through destination from every listing, post, and the awesome-list entry. It currently makes parity claims that the freeze invalidates (§1), has a hand-coded fake-terminal demo instead of the real one, and predates the OCR story.

**How (single pass over `docs/index.html` + `docs/index.md`):**

1. **Fix the four parity claims** — exact lines and replacement copy specified in §1.2.
2. **Hero section:** replace the static `.hero-demo` fake-terminal markup with the real demo GIF/`.mp4` from §3 (same asset, no second recording). Keep the styled frame; swap the contents.
3. **Version freshness:** the page hard-codes feature lists per version ("v5.0.0", "22 rules"). Add a "What's new" card driven by the latest CHANGELOG heading and update it as part of the release checklist (add a line item to `scripts/version-bump.sh` output reminding of `docs/index.html`) — low-tech but eliminates the recurring staleness this page has shown (git history: parity card already needed a fix once).
4. **New OCR card:** under the integrations/features grid, add "Engine-grade review: orchestrates Alibaba's open-code-review" card linking to `docs/recommended-setup.md` (ship together with v5.2.0).
5. **Evidence link:** once §5 tier 1 exists, add a "Real catches" section linking 3 gallery entries — the landing page's job is proof, not feature enumeration.
6. **Install section:** mirror the README's §2 ordering (Claude Code first, Cursor with freeze wording).
7. **Acceptance check:** rendered page contains zero occurrences of "parity" (`grep -ci parity docs/index.html` = 0), shows the real GIF, and states the current version. Verify via the `pages.yml` deploy preview after merge.

---

## 5. Published Evidence ("does it actually catch bugs?")

**Why:** OCR's pitch is "millions of defects found at Alibaba." Temper currently argues from architecture, not results. Evidence beats adjectives.

**How (two tiers — ship tier 1 first):**

1. **Tier 1 — Caught-bug gallery (1–2 days):**
   - Location: `docs/evidence/` in-repo (keeps stars consolidated).
   - Format per entry (`docs/evidence/NNN-short-slug.md`): the feature request given to Claude, what vanilla Claude Code produced (commit link in playground repo), what Temper's gate flagged (verbatim output), the fix. 10 entries target; the three "Real Findings" from the README are entries 001–003.
   - Each entry must be **reproducible**: playground repo branch per entry, exact prompt recorded.
2. **Tier 2 — Seeded-bug benchmark (1 week, after launch):**
   - Take 20 tasks across the 6 supported stacks; for each, run the same prompt twice (vanilla Claude Code vs. `/temper`), same model, fresh session.
   - Score: did the implementation include the known-required edge cases (rate limit, error path, regression guard)? Binary per case, pre-registered checklist written **before** running, committed first (prevents cherry-picking accusations).
   - Publish as `docs/evidence/benchmark.md` with a results table and the full methodology + prompts. Honest reporting including losses — credibility comes from the misses being listed.
3. Add the headline number to README §2.1.3 once tier 2 exists.

---

## 6. Deterministic Layer (the biggest product fix)

**Why:** Temper is almost entirely markdown instructions; the failure mode of prompt-driven pipelines is the model silently skipping steps (the "Progressive Loading Map" exists to fight exactly this). OCR's core architectural insight — deterministic layer for hard constraints, agent layer for judgment — applies directly. Deterministic behavior → consistent demos → trust. **This also serves the simplicity goal (§1): each script replaces pages of prompt instructions with one Bash call, shrinking the markdown surface.**

**How:**

1. **Convert these prompt-steps to scripts** (shipped in `scripts/lib/`, invoked by the reference docs via one Bash call each, replacing multi-step prompt instructions):
   | Script | Replaces | Output |
   |--------|----------|--------|
   | `detect-stack.sh` | temper-core stack detection prose | JSON: `{stack, test_cmd, lint_cmd, build_cmd}` |
   | `pack-discovery.py` | pack.md three-tier scan + link resolution (the Python snippets already half-exist in pack.md) | `.temper/pack-manifest.json` |
   | `diff-fingerprint.sh` | review.md Step 1.5 hunk classification (git diff parsing + keyword risk signals are pure string work) | fingerprint JSON |
   | `scenario-coverage.sh` | build.md coverage gate test-name ↔ scenario matching | checklist JSON |
   - Rule: scripts do **extraction and matching**; Claude keeps **judgment** (what a finding means, severity, suggestions). No LLM calls in scripts; no network; stdlib only (bash/python3) so the plugin stays dependency-free.
2. **Enforce gates with hooks** instead of asking the model to remember them. Ship an optional `hooks/` directory + install instructions:
   - `PreToolUse` (matcher: `Bash` with `git commit`): block commit if `.temper/` has an active spec whose coverage gate hasn't passed (`scenario-coverage.sh --check` exit code). Configured via `.claude/settings.json` hooks block — document exact JSON in `docs/recommended-setup.md`.
   - `Stop` hook: if a `/temper` pipeline stage is mid-flight (stage state file present), emit a reminder payload listing the unfinished gate.
   - Hooks are opt-in (a `scripts/install-hooks.sh` that merges into `.claude/settings.json` after showing the diff) — never silently modify user settings.
   - Hooks are Claude Code-only by nature — a concrete payoff of the §1 freeze: no Cursor workaround needed.
3. **Sequencing note:** do this incrementally, one script per minor release, demo-recorded each time (§3's `.tape` makes regressions visible). Each conversion must delete at least as many prompt lines as it adds elsewhere (complexity budget, §1).

---

## 7. CI Quality Gates for the Plugin Itself

**Why:** Workflows today are only `pages.yml` + `release.yml`. A green test badge on a plugin repo is rare and credible.

**How — one new workflow `.github/workflows/validate.yml`** (on: push, pull_request):

| Job | Tool | What it checks | Blocking? |
|-----|------|----------------|-----------|
| `links` | `lycheeverse/lychee-action` | Every relative link in `*.md` (README, docs/, .claude-plugin/reference/) resolves; external links checked weekly via scheduled run, not per-PR (flaky-network insulation) | yes |
| `manifest` | `python3 -c` script | `plugin.json` parses; every path in `commands[]`/`skills[]` exists; version matches latest CHANGELOG heading and marketplace.json | yes |
| `config-schema` | python3 + PyYAML | `.claude/temper.config` and every YAML block in docs parse; keys are in the documented set | yes |
| `markdown` | `DavidAnson/markdownlint-cli2-action` with relaxed ruleset (line-length off) | Structural lint only | yes |
| `cursor-frozen-tier` | bash | `.cursor/` files unchanged except explicit fixes (diff against the v5.1 tag) + `install-cursor.sh` still produces 22 rules + 9 commands against a temp dir (override curl base URL via env var — add that env var to the script) | **no — informational** (per §1 freeze: drift is reported, never blocks) |

Add the workflow badge to README badges row. Acceptance: red CI on a PR that deletes a referenced command file; the cursor job goes yellow/notice, never red.

---

## 8. Listings & Distribution

### 8a. awesome-claude-code — exact process

The list is [hesreallyhim/awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code). **You do not open a PR.** Submissions are issue-based; the repo's own automation turns approved issues into list entries.

Step-by-step:

1. Go to the repo → **Issues** → **New issue** → choose the **resource submission** template.
2. Fill the fields:
   - **Display Name:** `Temper`
   - **Category / Sub-Category:** pick the closest from the template's dropdown (the list curates "skills, hooks, slash-commands, agent orchestrators, applications, and plugins" — Temper fits the plugins/workflow-orchestrator categories; pick from what the form actually offers).
   - **Primary Link:** `https://github.com/galando/temper`
   - **Author Name / Link:** `galando` / GitHub profile
   - **License:** MIT
   - **Description:** 1–2 sentences. Suggested: *"Quality-gate SDLC plugin: derives BDD scenarios before architecture, enforces scenario-driven TDD, and validates intent with confidence-scored review — catches the edge cases AI-generated code skips."*
   - **How it works / Example / Specific Prompts:** paste the rate-limit catch story + `/temper "add password reset"` as the example prompt.
3. Tick the mandatory checkboxes — and make sure they are actually true before submitting:
   - resource not already submitted (search existing issues for "temper" first),
   - **over one week since first public commit** (satisfied — Temper has months of history),
   - all links working and publicly accessible,
   - **you have no other open issues in that repo** (one submission at a time — close/finish any prior one),
   - the human-verification checkbox.
4. After submission, automation validates links and applies `resource-submission` / `validation-passed` labels; then a maintainer approves. If the validation bot flags a broken link, fix and reply on the issue — don't open a second issue.
5. **Timing:** submit *after* §2 (README), §3 (GIF), and §4 (landing page) land — the maintainer and everyone browsing the list clicks through to the README and landing page.

### 8b. Other directories (same pattern: read their CONTRIBUTING first, one submission each)

- Community plugin directories/marketplaces that index `marketplace.json`-compatible repos (e.g., claude-plugins directories that appeared around the plugin marketplace launch) — search current options at submission time; the ecosystem moves fast.
- `travisvn/awesome-claude-skills` — Temper's standalone skills (grill-me, context-engineering, source-driven-development) each qualify individually; three separate listings = three doorways.
- Add GitHub **topics** to the repo (Settings → topics): `claude-code`, `claude-code-plugin`, `ai-code-review`, `tdd`, `bdd`, `code-quality`, `llm-agents`. Topics drive GitHub's own search/explore traffic; this takes two minutes and is pure upside. (Note: `cursor` topic dropped per §1 positioning — Claude Code-first.)

### 8c. The OCR back-link (highest-leverage single listing)

After Phase 1 ships: open a PR to `alibaba/open-code-review` adding a Temper example to their `examples/` directory / integration docs ("Using ocr inside a quality-gate pipeline"), per their CONTRIBUTING.md. Their README lists integration methods; a mention there puts Temper in front of 5.9k-star traffic. Keep the PR small (one doc/example file), entirely in their format, and genuinely useful to *their* users.

---

## 9. Playground Repo (lower time-to-aha)

**Why:** `/plugin install temper` is easy, but a first run happens on the user's own repo with their own stakes. A sandbox gives the "gate catches the bug" moment in two minutes, risk-free.

**How:**

1. New repo `galando/temper-playground`: a small Express+TS (most common stack) app with auth, a `README` whose entire body is: install Temper, run `/temper "add password reset"`, watch the coverage gate catch the rate-limit gap.
2. Pre-bake `.claude/temper.config` and a `CLAUDE.md` so zero setup is needed.
3. Branches `evidence/NNN-*` double as the reproducibility backing for §5's gallery — one repo serves both purposes.
4. Link it from README install section ("try it on the playground first"), from the landing page (§4), and use it as the recording set for §3.

---

## 10. Launch Content

**Why:** Releases without narrative don't travel. The OCR integration is a story: "Temper 5.2 orchestrates Alibaba's open-code-review."

**How:**

1. **One launch, multiple surfaces, same week** (after §§2, 3, 4, 8a are done):
   - **Show HN:** title "Show HN: Temper – quality gates for AI-generated code (now orchestrating Alibaba's open-code-review)". First comment: the honest origin story + the rate-limit catch + link to evidence gallery. Post Tue–Thu, morning US time.
   - **r/ClaudeAI** and **r/ExperiencedDevs** (the latter only with the evidence angle, not a product pitch — that community punishes promotion without data).
   - **X/Twitter thread:** the demo GIF as the first tweet, the catch story as the thread, repo link last.
2. **Comparison content** (converts long-tail search): two docs-site pages — "Temper vs. plain Claude Code" (use tier-1 evidence) and "A full quality stack: Temper + semgrep + open-code-review". Honest about what plain Claude Code does fine without Temper.
3. Rule for all of it: every claim links to a reproducible evidence entry (§5). No unverifiable numbers.

---

## 11. Community Operations

**Why:** Maintainer responsiveness is often the tiebreaker for a star, and always for adoption.

**How:**

1. `.github/ISSUE_TEMPLATE/`: `bug_report.yml` (asks for Temper version, Claude Code version, stack, the gate output), `feature_request.yml`, plus `config.yml` pointing questions to Discussions. Enable GitHub Discussions.
2. Seed **5 `good first issue`s** that are genuinely small: e.g., one stack file each for missing stacks (Django, Rails, .NET), a pack rules.md contribution, a docs fix. Label them and link from CONTRIBUTING.md.
3. Response SLA for yourself: first reply within 48h, even if just "looking into it". Stale issues get a label + honest close, not silence.
4. Pin a "Roadmap" issue mirroring CHANGELOG's planned phases (OCR Phase 2 rules bridge, deterministic layer rollout) — visible direction signals a living project. Include the §1 platform strategy so the Cursor freeze is discoverable, not buried.

---

## 12. Sequencing (4 weeks)

| Week | Work | Gate to next week |
|------|------|-------------------|
| 1 | OCR Phase 1 T1–T4 (companion plan) • Playground repo (§9) • GitHub topics (§8b) | OCR docs + integration edits done |
| 2 | OCR T5–T6 → **release v5.2.0** (incl. Cursor freeze announcement, §1) • README rewrite (§2) • Demo GIF (§3) • Landing page refresh (§4) • Evidence tier 1, ≥ 5 entries (§5) | README ≤ 300 lines, GIF renders, landing page has zero "parity" claims |
| 3 | **Launch week:** awesome-claude-code submission (§8a) • Show HN + Reddit + X (§10) • OCR upstream example PR (§8c) • issue templates + good-first-issues live (§11) | — |
| 4+ | CI validate.yml (§7) • Evidence tier 2 benchmark (§5) • Deterministic layer, first script (§6) — then one §6 script per minor release | — |

Rationale for the order: integration gives the launch a story; README+GIF+landing+evidence make the story land; listings and posts only after the landing page converts; the deterministic layer is the long-term moat and runs continuously after — shrinking complexity (§1) as it goes.
