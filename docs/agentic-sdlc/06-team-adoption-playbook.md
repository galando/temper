# 06 — Team adoption playbook

How to make Temper the default daily workflow for a whole team/organization — written with
a large, production-stakes org (e.g. Booking) in mind.

> The goal is **not** a training course. It's making the disciplined path the **path of
> least resistance**, so the easy way to ship is also the agentic-engineering way. The
> paper's principle: *AI amplifies the engineering culture it lands in.* Build the culture
> into the harness, then teach lightly.

---

## First: draw the spectrum line per project

Make the vibe-vs-agentic boundary explicit in team norms and in each repo's
`.claude/temper.config`:

| Project type | Mode | Config posture |
|---|---|---|
| Production / payments / shared services | **Agentic engineering** | Full `/temper`; eval gate on; hooks on; `block-on: [critical, task_success]` |
| Features in established codebases | Structured AI-assisted | Full `/temper`; standard gates |
| Prototypes / spikes / internal tools | Vibe coding OK | `/temper:build` or plain prompting; don't pay the agentic tax |

The config **is** the contract — reviewed in PRs like any code.

---

## The six adoption levers (ranked by leverage)

### Lever 1 — Golden-path repo template 🥇
Ship a service template (Backstage / cookiecutter) with `.claude/` pre-wired:
- `temper.config` tuned for production (eval gate on, hooks on, model tiers set to your
  model access),
- the **hooks pack installed** (`scripts/hooks/install.sh`) so secrets are blocked on day one,
- your org convention packs enabled.

New repos start agentic **by default**; nobody configures anything. This does more than any
doc or workshop.

### Lever 2 — Make the gate a merge requirement, not a suggestion
In CI, require a green `/temper:check` + an eval pass for production repos. When "evalset +
green eval" gates merge, people learn the workflow because it's the only way through —
exactly how test-coverage gates already train teams. *(Note: a headless/CI mode is a current
gap — see ch. 07, gap #2 — and is a prerequisite for fully automating this.)*

### Lever 3 — A one-page daily-loop cheatsheet
Most people only need:
```
/temper "<ticket>"   → walk the gates → commit
/temper              → resume
/temper:fix          → RCA a bug
/temper:status       → quality / cost / drift
```
Plus the eval rule of thumb: **write `expected` + `must_not` before you build.** Keep it to
one screen.

### Lever 4 — Champions + real-work pairing (not lectures)
- 1–2 **champions per tribe** who've shipped 3+ features through `/temper` and own the
  team's packs/evalsets.
- Onboard on a **real ticket**, not a sandbox — *"building one agent end to end teaches more
  than reading about a hundred."* 30 minutes pairing on the person's own work beats a
  workshop.
- Recurring 30-min "review the AI's output together" sessions to teach the **failure modes**
  of generated code (hallucinated deps, the 80%/20% edge cases) — the skill that matters now.

### Lever 5 — Context as code, owned by people
`temper.config`, pack `rules.md`, and evalsets are reviewed in PRs with named owners. When
the agent does something wrong, the fix is **a new rule or eval**, not a Slack complaint.
The adaptive-learning loop then promotes recurring review findings into pack rules — the
team's knowledge compounds.

### Lever 6 — Make adoption visible (for leaders)
Use `/temper:status` data to track per team: % features through the full pipeline, eval
pass-rate trend, cost/feature, drift flags. Report it like any engineering-health metric.
What gets measured gets adopted.

---

## Mapping to the paper's leader/org guidance

| Paper says (leaders) | Lever |
|---|---|
| Make context engineering first-class, owned by named engineers | Lever 5 |
| Set the bar at the eval, not the demo | Levers 2, 6 + ch. 05 |
| Reshape review for AI-generated code; train on failure modes | Lever 4 |
| Distinguish prototyping from production in team norms | "Spectrum line" section |
| Plan for hybrid human+agent teams | Levers 1–6 (the workflow itself) |
| Hire/develop for judgment, not implementation | Lever 4 culture |

---

## A realistic 30-day → 8-week ramp

| Weeks | Focus | Outcome |
|---|---|---|
| 1–2 | Pilot tribe + golden template; champions ship real tickets through `/temper` | Proof on real work |
| 3–4 | Author evalsets for critical paths; eval gate on; hooks org-wide | Verification is real |
| 5–6 | Codify org conventions into packs; reconcile model tiers with model access | Context-as-code in place |
| 7–8 | Roll to adjacent tribes via template + champions; flip CI gate on for prod repos | Self-sustaining adoption |
| Ongoing | `/temper:status` adoption dashboard; packs/evals curated as code | Compounding quality |

---

## The mindset shift to teach (one sentence)

> Your job moves from **writing the code** to **specifying intent, writing the eval, and
> judging the output** — Temper handles the rest.

---

## Common failure modes (and the fix)

| Symptom | Likely cause | Fix |
|---|---|---|
| "It's slower than just coding" | Used on trivial work where vibe coding fits | Apply the spectrum line; reserve `/temper` for real features |
| Evals always pass, no signal | Vague `expected`, no `must_not`, uncalibrated judge | Tighten cases; calibrate judge (ch. 07 #4) |
| People skip the pipeline | It's optional | Make it the merge gate (Lever 2) |
| Config drifts across repos | Hand-copied | Golden template + a managed pack channel (ch. 07 #6) |
| Reviewers rubber-stamp AI code | No training on AI failure modes | Lever 4 review sessions |
