# Platform strategy — what temper is, where it runs, and in what order

**Status:** Decision doc · **Date:** 2026-07-24 · **Current version:** v7.0.1
**Adjudicates:** PR #71 (vendor-neutral adapters + security posture) vs PR #72 (v7.1 roadmap)
**Audience:** maintainer

---

## Where temper actually stands

| Signal | Value |
|---|---|
| Stars / forks / issues | 13 / 0 / 0 |
| Age | ~4.5 months |
| Maintainers | 1 |
| Prompt corpus (`commands/` + `reference/` + `packs/` + `skills/` + `agents/`) | ~10,900 lines |
| Deterministic spine (`scripts/temper`) | 922 lines |
| External users who have filed anything | 0 |

The engineering is well ahead of the distribution. Nothing in the backlog is
bottlenecked on *capability*; everything is bottlenecked on **nobody knowing this
exists** and **nobody having numbers**. Any roadmap item that does not move one of
those two is, right now, a rounding error.

That single table decides most of what follows.

---

## The asset, stated precisely

Temper has one thing no prompt-space competitor can copy:

> The process is impossible to skip, and there is machine-checkable evidence it ran.

Superpowers (~170k stars, in Anthropic's marketplace) is a methodology expressed as
skills. Every line of it is copyable by anyone with a text editor. Temper's gate
verdicts are computed by a CLI from an evidence ledger and enforced by a **native git
pre-commit hook**. That is a different category of thing.

**The strategically important property of the spine is one nobody has written down
yet: it is already vendor-neutral, and always was.**

`scripts/temper` is bash + python3 stdlib, zero network. `scripts/hooks/install.sh`
installs a real git hook into the *repository*. Neither has any idea which agent wrote
the code — Claude Code, Codex, Cursor, Gemini, Aider, or a human typing by hand. The
enforcement layer ports to every vendor at a cost of **zero adapters**.

What is genuinely Claude-Code-specific is only the *orchestration*: `Agent`
subprocesses for per-stage context isolation, `AskUserQuestion` gates, per-stage model
selection. That is the part PR #71 spends 13.5k lines porting — and it is the part
that cannot be ported, only degraded.

---

## Decision 1 — Is "best agentic SDLC plugin" worth pursuing? Yes, but the gap is not features

The v7 spine is a real, defensible position. The work to reach "best" is not more
surface area; it is:

1. **Make the headline claims true.** `scripts/temper:807` is
   `design) reqs_json='[]'; all_pass=1` — an unconditional PASS. The README says every
   gate verdict is computed from evidence, never asserted. For one of six stages that is
   currently false. Separately, `/temper:init` only *recommends* the commit hook, so the
   flagship "physically blocks `git commit`" guarantee does not exist until a user runs a
   second command most will not run.
2. **Publish numbers.** The `evals/` harness (seeded-defect fixtures, three-tier
   verification, discriminance proofs) is already the most rigorous thing in this
   ecosystem and it is currently pointed inward as a regression suite. A published
   temper-vs-bare-Claude-Code table is the only asset here that survives being copied.
3. **Be findable.** Anthropic's official plugin directory shipped 2026-05-22; community
   submissions are open. The repo already has a submission kit (commit `22ea1a2`).

PR #72 says exactly this, and its ordering (integrity → engagement → benchmark) is
right. **Adopt PR #72's plan.**

### On "adopted by Anthropic" — calibrate the goal

Anthropic does not acquire community plugins. The realistic ceiling is: listed in the
community directory → passes stricter review → earns the **Anthropic Verified** badge →
possibly referenced or featured. Superpowers is in the marketplace and is still a
community plugin.

What actually moves that needle: a working submission, passing strict manifest
validation (already in CI), a credible **security posture** (the directory launch
explicitly flagged unverified-MCP risk — a threat model and no-network guarantee are
directly on-message), and evidence the thing works. Multi-vendor support is neutral at
best for this specific goal, since it is a Claude Code directory. **Do not do
multi-vendor for Anthropic. Do it for users, or not at all.**

---

## Decision 2 — Is multi-AI support worth it? Yes in principle, no in the shape PR #71 built

### The market fact that settles the design

`AGENTS.md` is a Linux Foundation (AAIF) standard — Anthropic is a founding member —
read natively by 30+ agents including Codex, Cursor, Gemini CLI, Copilot, Zed,
Windsurf, Devin, and Jules; 60k+ repos. There is already a cross-vendor instruction
surface. It is one file.

### The correct architecture: three layers, not three forks

| Layer | Content | Ports to | Cost |
|---|---|---|---|
| **1. Spine** | `scripts/temper`, `scripts/hooks/`, `.temper/` ledger | Every agent and no agent. Repo-level, not agent-level. | **Already done.** Zero adapters. |
| **2. Neutral contract** | One generated `AGENTS.md` fragment: the gate protocol, the evidence commands, when to run which stage | Codex, Cursor, Gemini, Copilot, Zed, Aider, Windsurf, … | ~100 lines, one source of truth |
| **3. Deep integration** | Claude Code plugin — subagent isolation, `AskUserQuestion` gates, per-stage models | Claude Code only | Already done. Keep full fidelity. |

This delivers "supports any AI" for roughly **1%** of PR #71's line count, because it
ships the *uncopyable* part everywhere and stops trying to ship the *unportable* part
anywhere.

PR #71 inverts this. It ports the prompts (the copyable part) and, as built, drops the
spine (the uncopyable part).

### Specific problems with PR #71 as built

1. **The spine does not travel.** The Codex plugin root is `adapters/codex/`, which
   contains only `skills/`, a manifest, and a README — no `scripts/temper`, no
   `scripts/hooks/`. `scripts/adapters/lib.sh`'s `gate_epilogue()` emits the bare
   repo-relative string `scripts/temper evidence add …` into every generated skill,
   with no resolution mechanism. `scripts/validate-adapters.sh` checks that manifest
   paths resolve *inside this repo*; nothing checks that the CLI is reachable from an
   installed plugin root. So on the vendors where the differentiator matters most, the
   generated skills instruct the model to invoke a binary that is probably not there —
   and the failure mode is a model narrating gate verdicts instead of computing them,
   which is precisely the thing v7 was built to stop.
2. **Never verified to load — by temper's own standard.** The check gate **FAILED and
   was overridden**; the two untraced scenarios are "does this actually activate in
   Codex" and "does this actually activate in Cursor." The PR body carries both as
   unchecked manual follow-ups. A project whose entire pitch is "no verdict without
   evidence" should not ship 13.5k lines of vendor surface on an overridden gate.
3. **The corpus gets forked 4×.** `fix` alone now exists as `commands/fix.md`,
   `adapters/codex/skills/temper-fix/SKILL.md`,
   `adapters/cursor/skills/temper-fix/SKILL.md`, and
   `adapters/gemini/commands/temper/fix.toml` — ~490 lines each, near-identical but not
   identical (the codex and cursor copies differ). Every future prompt edit becomes a
   4-way regeneration and a 4-way review, for one maintainer, before the benchmark that
   would justify any of it exists.
4. **It is Tier 2 everywhere it lands.** No `design`, no `pack`, no `eval` on
   Codex/Cursor; no unified command. Three more surfaces to support, each a degraded
   version of the product, each generating issues against a solo maintainer.
5. **It reverses a deliberate decision.** Cursor was archived at v6.0.1 on purpose
   (CHANGELOG v5.2.1 platform strategy). PR #71 un-archives it and adds two more.
6. **Upstream is still moving.** The Codex plugin marketplace launched 2026-03, but
   self-serve publishing to the official directory was still "coming soon" as of
   2026-05. Adapters written against a schema that is not finished will need rewriting.

### What PR #71 got genuinely right — and should be kept

The security half is good work and is on-message for the directory submission:
`SECURITY.md`, `docs/security/{threat-model,data-flow,pinned-install}.md`, the
**no-network CI guard** over `scripts/temper` and `scripts/hooks` (this makes the
"never phones home" claim mechanical rather than asserted), and release provenance —
source tarball, checksums, SHA-pinned build attestation, verified with a live dry-run.

It also found and fixed **two real bugs** in `scripts/generate-cursor.sh`: a
`python3 - <<'PY'` heredoc that consumed the script's own stdin, so every
`.cursor/rules/*.mdc` body was silently empty; and a bash 3.2 `set -u` crash on
empty-array expansion. Both are legitimate finds and should land regardless.

---

## Recommendation

### Split PR #71

**Merge now (new PR, security half only):** `SECURITY.md`, `docs/security/*`, the
no-network CI guard, `release.yml` provenance changes, and the two
`generate-cursor.sh` bug fixes. This is mergeable today, needs no vendor verification,
and strengthens the directory submission.

**Park (close with the reasoning recorded):** `adapters/{codex,cursor,gemini}`,
`scripts/generate-{codex,cursor-plugin,gemini}.sh`, `scripts/adapters/lib.sh`,
`scripts/validate-adapters.sh`, `.agents/plugins/marketplace.json`,
`.cursor-plugin/`. The work is not wasted — it is the reference implementation for
when the gate reopens. Reopen on **either** trigger:
- a real user asks for a specific vendor (not hypothetically — an issue with a name on
  it), **or**
- the benchmark is published and the ports can arrive carrying numbers.

**Merge PR #72** (docs only, zero risk) and execute it in order.

### Then, in this order

| # | Work | Why now |
|---|---|---|
| 1 | **Item 1 integrity fixes** — real `gate_design()`, `/temper:init` installs the hook, `temper config lint` | The README's central claim is false in two places. Fix before any marketing push; benchmarking a system whose own gates do not meet its bar is marketing, not evidence. |
| 2 | **Security half of #71** | Mergeable today; directly serves the directory submission. |
| 3 | **Submit to Anthropic's community plugin directory** | Free, already prepped, and it is the actual distribution channel. Do it the day item 1 lands. |
| 4 | **Item 3 benchmark** (temper vs bare Claude Code, N=5, FP scoring on clean fixtures, tokens + wall-clock) | The only asset that survives being copied, and the only thing that converts 13 stars into adoption. Largest lift in the plan, correctly so. |
| 5 | **Item 2 auto-engagement** | Cheap; closes the "waits to be summoned" gap. Order vs. 4 is flexible. |
| 6 | **Vendor-neutral, rebuilt** — generated `AGENTS.md` fragment + a documented `temper init --standalone` that installs CLI + git hook with no plugin at all | Now the pitch is "temper's gates work with whatever agent you use, and here are the numbers." One file, one source of truth, no Tier 2 support burden. |

### The one-line version

The spine already runs anywhere; the prompts never will. Ship the spine everywhere via
`AGENTS.md`, keep full fidelity only on Claude Code, and do it **after** the benchmark
— because the reason to support Codex and Cursor is to bring them a proven result, not
a third copy of the same prose.

---

## Sources

- [AGENTS.md / AAIF standard adoption](https://www.morphllm.com/agents-md-guide) ·
  [cross-tool portability](https://codex.danielvaughan.com/2026/05/27/agent-instruction-files-agents-md-claude-md-cross-tool-portability-codex-cli/)
- [Anthropic official plugin directory (2026-05-22)](https://github.com/anthropics/claude-plugins-community) ·
  [directory + unverified-MCP risk framing](https://www.techtimes.com/articles/317139/20260525/claude-code-plugins-get-official-directory-anthropic-flags-unverified-mcp-risks.htm)
- [Codex plugin marketplace launch](https://winbuzzer.com/2026/03/31/openai-launches-plugin-marketplace-codex-enterprise-controls-xcxwbn/) ·
  [distribution mechanics](https://codex.danielvaughan.com/2026/04/11/codex-marketplace-plugin-distribution/)
- [obra/superpowers](https://github.com/obra/superpowers)
