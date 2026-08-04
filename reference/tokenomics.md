---
description: "Retired in v7 — token optimization is now the prompt diet itself, not a set of runtime levers"
---

# Token Optimization Insights (retired, v7.0.0)

Through v6.x, Temper ran three configurable runtime levers — prompt-cache read-ordering
(`tokens.cache`), adaptive pipeline depth (`tokens.adaptive-depth`), and tiered feedback
loops (`tokens.loops`) — plus a model-routing config block (`models.*`) selecting a tier
per stage. All of it is gone in v7.

**Why:** those levers were themselves ~9,000 lines of prompt describing an algorithm an
LLM had to execute correctly on every run — the least trustworthy place to put logic with
exactly one correct output. v7's token-efficiency strategy is simpler and more honest:
delete the prompt mass instead of hinting at cache behavior the API layer never promised
to honor.

**What replaced each lever:**

| v6.x lever | v7 replacement |
|---|---|
| `models.routing` / `models.tiers` (config-driven model per stage) | `model:` frontmatter in `agents/{stage}.md`, resolved by `temper model` — declarative, no resolution algorithm (see below) |
| `tokens.cache` (prompt-cache read-ordering hints) | Nothing — the plugin's own prompts are ~85% smaller; there's much less to re-read |
| `tokens.adaptive-depth` (reduced pipeline for trivial changes) | Retired — see `reference/plan.md` Phase 6 note. It traded a small saving for a weaker plan gate |
| `tokens.loops` (inline / fix-mode / full loop cost tiers) | Every feedback loop is a normal stage re-launch — see `reference/orchestrator-patterns.md` → "Feedback Loop Patterns" |
| `observability.json` token/cost/latency estimates | The evidence ledger (`.temper/evidence/`, `.temper/gates.json`) — only mechanically-recorded facts, no cost estimation |

## What v8 gave back: a flat `models.{stage}` override

v7 was right that `models.routing`/`models.tiers` had to go — it was a *resolution
algorithm* a prompt had to execute correctly on every run, and that is the least
trustworthy place for logic with one correct output. But collapsing it to frontmatter
also meant a project could not change a stage's model without editing plugin-owned files,
which comes up every time a new model generation ships.

v8 splits those two things. Defaults still live in `agents/{stage}.md` frontmatter — one
source of truth, nothing to drift. An optional flat `models.{stage}` key in
`.claude/temper.config` overrides one, and `temper model <stage> | --all` does the lookup
in bash: config override if present, frontmatter otherwise. The orchestrator makes one
`temper model --all` call per run and substitutes the values. No tiers, no routing table,
no algorithm in prose — the thing v7 deleted stays deleted.

## The one remaining lever

If you're tuning token spend on your own project, the highest-leverage move is still the
oldest one: keep `intent.md`/`tasks.md`/`plan.md` and pack rules lean, since those are
read by every stage agent. Pack `phases:` frontmatter is the other half of that — a pack
that declares the stages it applies to stops being loaded by the ones it doesn't.
