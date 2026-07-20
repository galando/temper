# Token Efficiency (retired, v7.0.0)

Through v6.x this page documented three runtime levers — prompt-cache read-ordering,
adaptive pipeline depth, and tiered feedback loops — plus a `models.*` routing config
selecting a model tier per stage. All of it is gone in v7.

**Why:** those levers were themselves a large slice of Temper's own prompt mass,
describing an algorithm an LLM had to execute correctly on every run — exactly the kind
of logic v7's design rule forbids in prompt-space: *no feature ships in prompt-space if
it has exactly one correct output.* v7's token-efficiency strategy is simpler and more
honest: delete the prompt mass instead of hinting at cache behavior the API layer never
promised to honor. `commands/temper.md` alone went from 1,353 to 363 lines.

**What replaced each lever:**

| v6.x lever | v7 replacement |
|---|---|
| `models.routing` / `models.tiers` | Fixed `model:` frontmatter in `agents/{stage}.md` |
| `tokens.cache` (prompt-cache read-ordering) | Nothing needed — the prompts themselves are ~85% smaller |
| `tokens.adaptive-depth` (reduced pipeline for trivial changes) | Retired — see `reference/plan.md` Phase 6 note |
| `tokens.loops` (inline / fix-mode / full loop tiers) | Every feedback loop is a normal stage re-launch |
| `observability.json` cost/latency estimates | The evidence ledger (`.temper/evidence/`, `.temper/gates.json`) — only mechanically-recorded facts |

Full rationale: [`docs/plans/v7-deterministic-spine.md`](plans/v7-deterministic-spine.md).
Reference-level detail: `reference/tokenomics.md` and `reference/pricing.md` in the
plugin sources.
