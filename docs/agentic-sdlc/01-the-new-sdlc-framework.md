# 01 — The New SDLC: the framework

A faithful summary of _The New SDLC With Vibe Coding (Day 1)_ — the mental models this
whole guide builds on.

---

## The core shift: from syntax to intent

For most of computing history, programming was translation: understand the problem, design
a solution, render it in syntax. AI collapses the syntax step. Developers increasingly
**express what they want**; the machine handles implementation; the human supplies intent,
architecture, and judgment.

As of early 2026 the paper cites: ~85% of professional developers use AI coding agents, 51%
daily, ~41% of new code is AI-generated. This isn't a future state — it's the present.

> _"The most profound shift in software engineering… is the transition from writing code to
> expressing intent, and trusting intelligent systems to translate that intent into working
> software."_

---

## The spectrum: vibe coding → agentic engineering

Not a binary — a spectrum. The differentiator is **not whether you use AI**; it's **how
much structure, verification, and human judgment surround the AI's output**.

| Dimension | Vibe coding | Structured AI-assisted | Agentic engineering |
|---|---|---|---|
| Intent spec | Casual prompts | Detailed prompts + examples | Formal specs, arch docs, memory files |
| Verification | "Does it seem to work?" | Manual testing, spot checks | **Automated tests, CI/CD gates, LM judges** |
| Codebase understanding | Minimal | Selective review | Comprehensive architecture review |
| Error handling | Paste error back to AI | Human diagnoses, AI fixes | Agents self-diagnose in bounds; humans own architecture |
| Appropriate scope | Prototypes, scripts | Features in established codebases | **Production, team-scale systems** |
| Risk profile | High (disposable code) | Moderate | Low (systematic verification) |

**Applied tip from the paper:** position depends on stakes. A weekend prototype can be pure
vibe coding. A production API handling financial transactions demands agentic engineering.

> _"Telling a CTO that your team is vibe coding their payment processing system will, and
> should, raise alarm bells."_

---

## The single biggest differentiator: verification

Two mechanisms work together:

- **Tests** verify the deterministic parts: input → expected output. Checked by code.
- **Evals** verify the non-deterministic parts: did the agent take the right trajectory,
  choose the right tools, produce output that meets the bar? Checked by labelled datasets,
  scoring rubrics, and **LM judges**.

> _"Without both, the practice is always vibe coding, regardless of how sophisticated the
> prompts are."_

Two kinds of eval:
- **Output evaluation** — the final artifact (does it compile, pass, satisfy intent?).
- **Trajectory evaluation** — the full sequence of tool calls and intermediate reasoning.
  A fluent output that skipped its verification steps is more dangerous than one with a
  visible error.

---

## Context engineering: the real skill

Quality of AI output depends less on clever prompts than on the **quality of context**. Six
types of context:

1. **Instructions** — role, goals, operational boundaries.
2. **Knowledge** — retrieved docs, diagrams, domain data.
3. **Memory** — short-term session logs + long-term persistent state.
4. **Examples** — few-shot demonstrations, codebase reference patterns.
5. **Tools** — precise definitions of APIs/scripts/services the agent can call.
6. **Guardrails** — hard constraints, formatting rules, safety validations.

**Static vs dynamic context** is a first-class architectural trade-off:
- **Static** (always loaded): system instructions, rule files (`AGENTS.md`, `CLAUDE.md`),
  global memory. Expensive — every token is present every interaction.
- **Dynamic** (on demand): skill instructions triggered by task match, tool results, RAG
  documents, windowed history. Efficient — you pay only when needed.

**Agent Skills** are the key pattern: portable packages of procedural knowledge loaded via
**progressive disclosure** (lightweight metadata at startup → full instructions on match →
deep reference only when needed). They solve context rot, lack of procedural memory,
multi-agent overhead, and cross-tool portability.

> _"The question isn't 'how do I trick the AI into writing good code?' It's 'what would a
> new team member need to know to contribute effectively, and how do I encode that?'"_

---

## The new SDLC, phase by phase

AI compresses the cycle **unevenly**: implementation drops from weeks to hours, while
requirements, architecture, and verification remain human-paced.

| Phase | What changes |
|---|---|
| Requirements & planning | Requirements become a *conversation* that produces spec + prototype simultaneously |
| Design & architecture | Stays human-centric (trade-offs); AI implements decisions once made |
| Implementation | Writing → reviewing, guiding, verifying. (METR: experienced devs sometimes *slower* due to verification overhead) |
| Testing & QA | Output **and** trajectory eval; tests/evals become how you *communicate intent* |
| Code review & deployment | AI as first-pass reviewer; AI-aware pipelines (health, rollback, risk prediction) |
| Maintenance & evolution | Legacy code becomes navigable; migrations/modernizations that "never happened" become feasible |

---

## The factory model

The developer's primary output is **not code — it's the system that produces code**:

- Specifications and context that define what to build
- Agents that translate specs into implementation
- Tests and quality gates that verify correctness
- Feedback loops that route failures back to agents
- Guardrails that constrain agents to safe behavior

> _"A factory manager does not assemble every widget by hand. They design the assembly line
> and ensure quality control."_ Success = giving agents **success criteria**, not
> step-by-step instructions.

---

## Harness engineering: what surrounds the model

`Agent = Model + Harness`. The model is one input. The harness is everything else:

- **Instructions & rule files** — `AGENTS.md`, `CLAUDE.md`, skill files, sub-agent prompts.
- **Tools** — functions, MCP servers, APIs, plus the prose telling the model when to use them.
- **Sandboxes & execution environments** — where code runs, what it can reach.
- **Orchestration logic** — sub-agent spawning, model routing, hand-offs.
- **Guardrails / hooks** — *deterministic code* at lifecycle points (e.g. block a commit
  with a hard-coded password).
- **Observability** — logs, traces, evals, cost/latency metering; detect drift.

**The harness across the SDLC:** Configure (requirements/arch) → Run (implementation) →
Feedback loop (test/QA) → Observe (review/deploy/maintain).

> _"Most agent failures, examined honestly, are configuration failures."_ On Terminal Bench
> 2.0, one team moved an agent from outside the Top 30 to the Top 5 by changing **only the
> harness** — no model change.

---

## Developer roles: conductor vs orchestrator

- **Conductor** — hands-on, real-time. In the IDE, guiding each change. Good for complex
  logic, debugging, unfamiliar code. Risk: becomes a throughput bottleneck.
- **Orchestrator** — async, higher abstraction. Define goals, assign to agents, review
  results. Good for well-defined tasks, migrations, test generation.

Orchestrator skills: **specification, decomposition, evaluation, system design.**

---

## The 80% problem

AI generates ~80% of a feature fast; the last 20% — edge cases, error handling, integration
points, subtle correctness — needs deep context current models often lack. Errors have
evolved from syntax mistakes to **conceptual failures** (wrong business-logic assumptions,
missing edge cases) that "look right" and may pass basic tests. The winning posture: use AI
for well-specified implementation; reserve human attention for ambiguity, trade-offs, and
verification.

---

## The economics: CapEx vs OpEx

- **Vibe coding = low CapEx, high OpEx.** Near-zero setup, but compounding costs: token
  burn from unverified prompt loops, a maintenance tax on inconsistent code, and security
  remediation.
- **Agentic engineering = high CapEx, low OpEx.** Upfront investment in schemas, tests,
  and structured context; dramatically lower marginal cost to ship and maintain.

Two levers:
- **Context engineering as a financial lever** — dense, high-signal context (a precise
  `AGENTS.md`, guardrails) raises first-pass success and avoids costly retry loops.
- **Intelligent model routing** — frontier models for requirements/architecture/initial
  implementation; smaller/cheaper models for test generation, review, CI/CD monitoring.

---

## Where to start (the paper's own advice)

**Individuals:** set up `AGENTS.md`; install skills; make one repetitive workflow your first
agent; **write tests and evals before the code**; review every shipped line; keep core
skills sharp.

**Leaders:** make context engineering first-class (config reviewed in PRs, owned by named
engineers); **set the bar at the eval, not the demo** (require eval coverage with explicit
rubrics); reshape code review for AI output; separate prototyping from production; plan for
hybrid human+agent teams; hire for judgment.

---

## Three durable principles

1. **Structure scales, vibes don't.**
2. **AI amplifies your engineering culture** — strengths *and* weaknesses.
3. **The human role is evolving, not diminishing.**

> _"Generation is solved. Verification, judgment, and direction are the new craft."_
