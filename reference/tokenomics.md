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
| `models.routing` / `models.tiers` (config-driven model per stage) | Fixed `model:` frontmatter in `agents/{stage}.md` — declarative, no resolution algorithm |
| `tokens.cache` (prompt-cache read-ordering hints) | Nothing — the plugin's own prompts are ~85% smaller; there's much less to re-read |
| `tokens.adaptive-depth` (reduced pipeline for trivial changes) | Retired — see `reference/plan.md` Phase 6 note. It traded a small saving for a weaker plan gate |
| `tokens.loops` (inline / fix-mode / full loop cost tiers) | Every feedback loop is a normal stage re-launch — see `reference/orchestrator-patterns.md` → "Feedback Loop Patterns" |
| `observability.json` token/cost/latency estimates | The evidence ledger (`.temper/evidence/`, `.temper/gates.json`) — only mechanically-recorded facts, no cost estimation |

If you're tuning token spend on your own project, the highest-leverage move is still the
oldest one: keep `intent.md`/`tasks.md`/`plan.md` and pack rules lean, since those are
read by every stage agent. There is no other lever to pull.
