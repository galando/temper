# Temper & the Agentic SDLC — Complete Guide

> A consolidated, end-to-end record of how Temper enables the "new SDLC" described in
> _The New SDLC With Vibe Coding (Day 1)_ (Osmani, Saboo, Kartakis, May 2026): the
> framework, the mapping, the plan, what shipped in **v5.6.0**, how to use it day to day,
> how to roll it out to a team, and what's still missing.

**Audience:** engineers, tech leads, and engineering managers adopting agentic engineering.
**Temper version documented:** 5.6.0
**Status:** Living document.

---

## Why this guide exists

The paper's thesis: software engineering is shifting **from writing code to expressing
intent**, and the discipline that separates *vibe coding* from *agentic engineering* is
**how much structure, verification, and human judgment surround the model** — what the
paper calls the **harness**. The developer's real output becomes the *system that builds
software* (the **factory model**).

Temper is a concrete implementation of that harness for Claude Code (and Cursor). This
guide is the single place that ties the idea to the tool: the concepts, the gap analysis,
the implementation that closed those gaps, and the practical playbooks for using and
scaling it.

---

## How to read this

| # | Chapter | Read it when you want to… |
|---|---------|---------------------------|
| 01 | [The New SDLC — the framework](./01-the-new-sdlc-framework.md) | Understand the paper's model: spectrum, harness, factory, context engineering, economics |
| 02 | [Temper as the harness — the mapping](./02-temper-as-the-harness.md) | See exactly which Temper mechanism implements each idea in the paper |
| 03 | [The plan: Phase 0 → 1 → 2](./03-the-plan-phases.md) | Review what was planned (gaps first, then verification, then economics) |
| 04 | [Implementation status (v5.6.0) — verified](./04-implementation-status-v5.6.0.md) | Confirm what actually shipped, with the verification evidence |
| 05 | [Using eval](./05-using-eval.md) | Learn how to author, run, and read evals day to day |
| 06 | [Team adoption playbook](./06-team-adoption-playbook.md) | Roll Temper out so it becomes everyone's default daily workflow |
| 07 | [Remaining gaps — v5.7 hardening](./07-remaining-gaps-v5.7-hardening.md) | Know what's still missing and what to harden before scaling |

---

## Executive summary (TL;DR)

1. **The bar for production is agentic engineering, not vibe coding.** The differentiator is
   verification (tests **and** evals), guardrails, and human judgment over architecture.
2. **Temper implements the harness across the SDLC:** `plan → design → build → review →
   check → eval → commit`, each an isolated agent subprocess, with quality gates, scoped
   rule packs, feedback loops, context engineering, and observability.
3. **The original gap analysis found six promise-vs-reality issues** (Phase 0). All were
   closed in v5.3.0; verification (evals + deterministic hooks) shipped in v5.5.0;
   economics & observability (model routing + measured telemetry + drift + economics panel)
   shipped in v5.6.0. **Verified against `main`.**
4. **Eval is the keystone capability.** It is the verification layer between check and
   commit that the paper insists on: *"Without both [tests and evals], the practice is
   always vibe coding."*
5. **Adoption is an engineering-culture problem, not a training problem.** Make the
   disciplined path the path of least resistance (golden-path template, CI gates,
   context-as-code, champions).
6. **Six gaps remain** in v5.6.0 — most urgently, the deterministic hooks have no tests and
   no headless/CI mode exists. These should be hardened before scaling to a whole org.

---

## Document conventions

- **Paths** are clickable references into the repo, e.g. `.claude/commands/eval.md`.
- **Severity** uses 🔴 (blocker) / 🟠 (important) / 🟡 (nice-to-have).
- Quotes in _italics_ attributed to "the paper" are from _The New SDLC With Vibe Coding
  (Day 1)_.
