# Plan: open-code-review (OCR) Integration — Phase 1

**Status:** Proposed
**Target version:** 5.2.0
**Upstream project:** [alibaba/open-code-review](https://github.com/alibaba/open-code-review) (Apache-2.0, ~5.9k stars)

---

## 1. Goal and Non-Goals

### Goal

Integrate the `ocr` CLI as an optional external review engine inside `/temper:review`, following the same pattern Temper already uses for code-review-graph and semgrep: **detect → use if available → degrade gracefully if not**.

When OCR is available, it takes over **line-level defect detection** (NPE, thread-safety, XSS, SQL injection, rule-based defects) — the thing its deterministic file-bundling + production-tuned prompts do best. Temper keeps what OCR cannot do: intent validation (IDD), scenario coverage (BDD), confidence scoring, architecture depth, cross-file consistency, and the review memory / learning loop.

### Non-Goals (explicitly out of Phase 1)

- **No rules bridge** (compiling Temper packs into OCR's `rule.json`) — that is Phase 2.
- **No vendoring or forking** of OCR. We orchestrate the CLI; we ship zero OCR code.
- **No OCR in `/temper:check`** — review stage only for Phase 1.
- **No MCP wrapper** — OCR is invoked via Bash like the project test runner.

### Why CLI, not OCR's Claude Code plugin

OCR ships its own plugin (`/open-code-review:review`). We deliberately integrate the **CLI** instead, because:
1. The plugin is an interactive slash command — it can't be composed into Temper's pipeline, merged with Temper findings, or routed through review memory.
2. `ocr review --format json --audience agent` is designed exactly for machine consumption by agents/CI.
3. Users who want OCR standalone can still install its plugin independently; nothing conflicts.

---

## 2. Background Facts (verified against upstream docs)

| Fact | Value |
|------|-------|
| Install (npm) | `npm install -g @alibaba-group/open-code-review` |
| Install (binary) | GitHub Releases (`macOS arm64/x64, Linux x64/arm64, Windows`) |
| Review command | `ocr review [--from ref] [--to ref] [--commit sha]` |
| Machine output | `--format json` + `--audience agent` |
| Preview (no LLM calls) | `ocr review --preview` — lists files it would review |
| Concurrency / timeout | `--concurrency N` (default 8), `--timeout M` minutes (default 10) |
| Extra context | `--background "text"` |
| Custom rules | `--rule file.json` > `.opencodereview/rule.json` > `~/.opencodereview/rule.json` > built-in |
| LLM config | OCR requires its own LLM endpoint config (URL + API key + model) before it can run |
| License | Apache-2.0 — compatible with Temper's MIT for orchestration (we link/invoke, we don't redistribute) |

> **Known unknown #1 — JSON schema.** OCR's docs state `--format json` is machine-readable but do not publish the field schema. Implementation task T1 below captures the schema empirically and pins parsing defensively.
>
> **Known unknown #2 — uncommitted changes.** OCR reviews refs/commits (`--from/--to/--commit`). Whether it supports a dirty working tree is undocumented. Phase 1 default: **OCR runs only on committed ranges**; for uncommitted diffs Temper notes "OCR skipped (uncommitted changes)" and runs its full own review. T1 verifies actual behavior and relaxes this if supported.

---

## 3. Design

### 3.1 Division of labor

| Concern | Owner when OCR available | Owner when OCR absent |
|---------|--------------------------|----------------------|
| Line-level defects (NPE, injection, thread-safety, logic bugs) | **OCR** | Temper review subagents |
| Performance anti-patterns (N+1, pagination, sync I/O) | Temper (unchanged) | Temper |
| Security hot path tracing + semgrep SAST | Temper (unchanged) | Temper |
| AI-code detection (hallucinated APIs, missing wiring) | Temper (unchanged) | Temper |
| Intent validation (IDD), scenario coverage (BDD) | Temper (unchanged) | Temper |
| Architecture depth, cross-file consistency | Temper (unchanged) | Temper |
| Confidence filtering, review memory, learning | Temper — OCR findings flow through it | Temper |

**Cost control rationale:** OCR makes its own LLM API calls. Without the takeover rule, users pay for two LLM reviews of the same diff. With it, the generic defect-hunting portion of Temper's subagent prompt is dropped when OCR runs, so total spend stays roughly flat while defect detection improves.

### 3.2 Evidence label

OCR findings are **LLM-generated**, so they are *not* `[PROVEN]` (that label is reserved for deterministic tool output like semgrep). Phase 1 introduces a fourth label:

- **`[OCR]`** — finding produced by the open-code-review engine. Independent second LLM opinion with deterministic file selection.
- When an `[OCR]` finding and a Temper subagent finding **independently agree** (dedupe match, see 3.5), the merged finding is labeled **`[OCR+TEMPER]`** and gets a confidence boost — two independent reviewers agreeing is real signal.

### 3.3 Configuration (`.claude/temper.config`)

```yaml
tools:
  mode: auto              # existing — unchanged semantics, now also governs ocr
  label-findings: true    # existing
  ocr:
    mode: auto            # auto | off | require
                          #   auto:    use ocr if installed+configured, else skip silently
                          #   off:     never invoke ocr
                          #   require: fail review with actionable error if ocr unavailable
    replace-defect-subagent: true   # when ocr runs, Temper subagents drop generic
                                    # defect hunting (cost control); false = run both
    timeout: 10           # minutes, passed as --timeout
    concurrency: 8        # passed as --concurrency
    extra-args: ""        # escape hatch, appended verbatim
```

Defaults make the feature **zero-config**: nothing changes for users without `ocr` installed; users with `ocr` installed get it automatically (`mode: auto`).

### 3.4 Severity and confidence mapping

OCR severity → Temper severity (final mapping confirmed in T1 once JSON schema is captured; expected values shown):

| OCR severity | Temper severity | Default confidence |
|--------------|-----------------|--------------------|
| critical / blocker | CRITICAL | 0.85 |
| major / high | HIGH | 0.80 |
| minor / medium | MEDIUM | 0.75 |
| info / suggestion | LOW | 0.70 |

OCR does not emit a confidence score, so we assign the defaults above. They sit at/above the default `confidence-threshold: 0.7`, meaning OCR findings surface by default but **remain suppressible** by user threshold config and by review-memory noise reduction.

### 3.5 Dedupe and cross-validation

After OCR findings are parsed and Temper subagent findings collected, before Step 4 filtering:

1. **Match rule:** same file AND line within ±2 AND same category family (security/logic/performance/quality).
2. **On match:** merge into one finding — keep the more detailed description, take `max(severity)`, set `confidence = min(0.95, max(conf_a, conf_b) + 0.15)`, label `[OCR+TEMPER]`.
3. **No match:** keep both findings with their own labels.
4. Security-category findings keep the existing rule: **always bypass confidence filtering**.

### 3.6 Review memory integration

`[OCR]` findings flow through the existing `.temper/review-memory.json` pipeline unchanged:
- Dismissed OCR patterns count toward noise-reduction suppression (5+ dismissals → auto-suppress).
- Accepted OCR patterns count toward rule suggestions (3+ accepts at 70%+).
- Memory entries record `source: "ocr"` so `/temper:status` can report per-engine accept/dismiss rates.

This is the differentiator of the combination: OCR alone has no cross-session memory; Temper gives it one.

### 3.7 Failure handling matrix

| Condition | `mode: auto` behavior | `mode: require` behavior |
|-----------|----------------------|--------------------------|
| `ocr` not on PATH | Skip silently; full Temper review runs | BLOCK: "ocr required but not installed — npm install -g @alibaba-group/open-code-review" |
| `ocr` present, LLM not configured (probe via `ocr review --preview` exit code / stderr) | Skip with one-line notice; full Temper review | BLOCK with OCR's own config instructions |
| Working tree dirty (uncommitted diff) | Skip OCR with notice; full Temper review | Same notice; does NOT block (not an availability failure) |
| OCR exits non-zero or times out | Warn, discard partial output, full Temper review | Warn + BLOCK is wrong here — degrade with prominent warning (tool ran but failed ≠ tool unavailable) |
| JSON parse failure | Fall back: include OCR's raw text output as an unstructured `[OCR]` appendix section; full Temper review still runs | Same |

Rule of thumb (matches existing pack-link behavior): **a missing/broken external tool must never block work in `auto` mode.**

---

## 4. File-by-File Implementation Spec

Every change below names the exact file and insertion point.

### 4.1 `.claude-plugin/reference/review.md`

This is the core change. Four edits:

**(a) Step 1 "Gather Context" — add detection** (after item 5 "Read review memory"):

```
# 5.5 Detect ocr CLI (open-code-review)
# - Read tools.ocr.mode from temper.config (default: auto)
# - If mode != off: run `command -v ocr` and `ocr --version`
# - If found: probe readiness with `ocr review --preview --from <base> --to <head>`
#   (no LLM calls). Non-zero exit or config error => not ready.
# - Record: ocr_status = ready | not-installed | not-configured | skipped-dirty-tree
```

**(b) Progressive Loading Map** — add row: `Step 2.5 (OCR engine run) | Optional | ocr_status == ready`.

**(c) New Step 2.5: "Run OCR Engine (if ready)"** — inserted between Step 2 (parallel subagents) and Step 3 (intent validation). Contents:

```
1. Determine diff range (same range as Step 1):
   committed:   ocr review --from HEAD~1 --to HEAD
   PR branch:   ocr review --from <merge-base> --to HEAD
   uncommitted: SKIP (ocr_status = skipped-dirty-tree), note in summary
2. Invoke:
   ocr review --from <base> --to <head> --format json --audience agent \
     --timeout {tools.ocr.timeout} --concurrency {tools.ocr.concurrency} \
     --background "{one-line feature summary from intent.md, if present}" \
     {tools.ocr.extra-args}
   Run via Bash with timeout = (tools.ocr.timeout + 2) minutes.
3. Parse JSON output -> findings list (file, line, severity, category,
   description, suggestion). On parse failure: fallback per failure matrix.
4. Map severities + assign confidence (table in plan §3.4).
5. Label every finding [OCR].
6. Dedupe against subagent findings (rule in plan §3.5) -> [OCR+TEMPER] merges.
7. Append merged list to the issues collection consumed by Step 4 filtering.
```

**(d) Step 2 subagent prompt — conditional takeover.** Wrap the generic defect/performance checklist sections of the subagent prompt with:

```
IF ocr_status == ready AND tools.ocr.replace-defect-subagent == true:
  OMIT the generic logic-defect hunting and PERFORMANCE ANTI-PATTERN sections
  from subagent prompts. Subagents focus on: pack-rule enforcement, security
  hot paths, AI-code detection, architectural drift, test gaps.
  (OCR owns line-level defect + generic perf detection for this run.)
ELSE: full prompt as today.
```

Note: MCP SECURITY SCAN (semgrep), SECURITY HOT PATH REVIEW, and AI-CODE DETECTION blocks are **never** omitted.

### 4.2 `.claude-plugin/reference/status.md`

- **Step 1.5 "Detect MCP Tool Availability"** → rename to "Detect External Tool Availability"; add detection item 3: `ocr: command -v ocr && ocr --version` (CLI probe, not MCP).
- **Dashboard template (~line 139)**: rename section header `MCP TOOLS` → `EXTERNAL TOOLS`; add line `ocr (open-code-review): {ready/not installed/not configured}` and, when review memory has OCR entries, `ocr accept rate: {N}% ({accepted}/{total})`.

### 4.3 `.claude/temper.config`

Add the `tools.ocr` block from §3.3 (commented defaults, consistent with existing file style).

### 4.4 `docs/recommended-setup.md`

Add **"3. open-code-review (Line-Level Defect Engine)"** section (renumber "Verify Everything Works" and "Configuration" sections accordingly):
- What it adds (table row: line-level defects `[HEURISTIC]` → `[OCR]` engine findings).
- Install: npm command + binary release link.
- LLM config pointer to OCR's own docs (we do not duplicate their config instructions — link, don't copy, so we don't go stale).
- Verify: `ocr review --preview` in the project; then `/temper:status` shows `ocr: ready`.
- Troubleshooting table rows: not installed / not configured / dirty tree skip.

### 4.5 `README.md`

- "Recommended Setup" section: add OCR as the third optional tool (3 lines + link to recommended-setup.md — keep it short; README weight reduction is handled by the growth plan, not here).
- Evidence label list: add `[OCR]` / `[OCR+TEMPER]` to the labels documented in the v3.1.0 section.

### 4.6 Cursor parity — `.cursor/commands/temper-review.md` and `.cursor/commands/temper-status.md`

Mirror edits 4.1(a)(c)(d) and 4.2 into the Cursor command files (same content, conversational-gate phrasing per existing Cursor adaptations). Update `scripts/install-cursor.sh` manifest only if it pins file hashes (verify during implementation; current script downloads by path, so likely no change).

### 4.7 `docs/commands.md` and `docs/review.md` (docs site)

Add a short "External engine: open-code-review" subsection under the review command documenting `tools.ocr` config keys and the `[OCR]`/`[OCR+TEMPER]` labels.

### 4.8 `CHANGELOG.md` + version

- Entry under `## [5.2.0]`: feature description, config keys, no breaking changes.
- Bump via `scripts/version-bump.sh` (updates `plugin.json`, `marketplace.json`, CLAUDE.md version line — verify script coverage during implementation).

---

## 5. Task Breakdown (ordered)

| # | Task | Output | Depends on |
|---|------|--------|-----------|
| T1 | **Empirical schema capture.** Install `ocr` in a scratch repo with a seeded bug; run `ocr review --commit <sha> --format json --audience agent`; save raw output as `docs/plans/fixtures/ocr-output-sample.json`; document observed fields + severity values; test dirty-tree behavior; pin minimum OCR version (record `ocr --version`) | Schema doc + fixture + final §3.4 mapping | — |
| T2 | review.md edits 4.1(a)–(d) | Core integration | T1 |
| T3 | status.md edits 4.2 + temper.config 4.3 | Detection + dashboard | T1 |
| T4 | Docs: recommended-setup.md, README.md, docs/commands.md, docs/review.md | User-facing docs | T2, T3 |
| T5 | Cursor parity 4.6 | Feature parity | T2, T3 |
| T6 | Manual test matrix (below) executed on a fixture project | Test evidence in PR description | T2–T5 |
| T7 | CHANGELOG + version bump + release | v5.2.0 | T6 |

### Manual test matrix (T6)

| Scenario | Expected |
|----------|----------|
| `ocr` not installed, `mode: auto` | Review identical to v5.1.0; no errors; status shows `not installed` |
| `ocr` installed + configured, committed diff with seeded NPE | `[OCR]` finding at correct file:line; Temper subagent prompt omitted generic defect section |
| Same bug found by both engines | Single `[OCR+TEMPER]` finding, boosted confidence |
| Uncommitted diff | "OCR skipped (uncommitted changes)" notice; full Temper review |
| `ocr` installed, LLM unconfigured | One-line notice; full Temper review |
| `mode: require`, `ocr` missing | Review blocks with install instructions |
| `mode: off`, `ocr` installed | OCR never invoked |
| OCR JSON parse forced to fail (corrupt output) | Raw-text appendix fallback; review completes |
| Dismiss same OCR pattern 5× | Pattern auto-suppressed via review memory |

---

## 6. Risks

| Risk | Mitigation |
|------|-----------|
| OCR JSON schema changes between releases | Pin minimum version in detection; defensive parsing + raw-text fallback; fixture file lets us diff schema on OCR upgrades |
| Double LLM spend | `replace-defect-subagent: true` default; documented in config comments |
| OCR latency inflates review time | OCR runs in parallel with Temper subagents; hard timeout; `--concurrency` exposed |
| Findings overlap creates noise | Dedupe rule §3.5 + existing confidence threshold + review memory |
| License concerns | Apache-2.0 invoked-as-CLI; nothing redistributed; no notice obligations triggered |
