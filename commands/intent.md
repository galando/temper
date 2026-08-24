---
description: "Capture an idea as a draft intent.md — the artifact that starts the pipeline, without starting it"
argument-hint: "<idea-in-your-own-words | JIRA-123 | #456>"
---

# Intent: Capture an Idea as an Artifact

**Goal:** Turn an idea, a ticket, or an incident finding into a committed
`.temper/specs/{slug}/intent.md` with `Status: draft` — and stop there. This is the
entry point for work that isn't ready to build yet: the originator (who may not be the
implementer, or an engineer at all) describes the problem in their own words; the
committed draft is what a product owner reviews and what `/temper` later picks up.

`/temper`'s own Intent stage (and standalone `/temper:plan`) still creates intent.md
when none exists — this command exists for the capture-now-build-later split, so the
idea's author, timestamp, and revision history live in version control from the moment
it's real. A draft captured here is exactly what the pipeline's Intent gate later
presents for acceptance.

## Usage

```
/temper:intent "handlers spend a third of call time on status-only queries"
/temper:intent "JIRA-4521"      # fetch the ticket, capture it as intent
/temper:intent                  # no argument — interview from scratch
```

## Execution

1. **Understand the problem, not the solution.** Read `$ARGUMENTS` (detect
   Jira/GitHub/free-text the same way `/temper:plan` Phase 0 does). Then ask what an
   analyst would ask — scope, who is affected, what better looks like, what is out of
   scope — via `AskUserQuestion`, max 2-3 concrete rounds. No formal language is
   required of the originator; producing structure is your job, not theirs.

2. **Write the draft** to `.temper/specs/{slug}/intent.md` using
   `$CLAUDE_PLUGIN_ROOT/templates/intent.md`:
   - Header: `**Author:**` (from `git config user.name` / `user.email`),
     `**Status:** draft`, `**Created:**`, `**Ticket:**` if one was given.
   - Fill **Problem**, **Success Criteria** (measurable, each with a `Validate:`
     type), **Constraints**, **Target Users**, and **Open Questions** (every
     unresolved point from step 1 — carrying a question forward honestly beats
     resolving it by guess).
   - **Do not write Scenarios or pick an architecture.** BDD scenarios are derived
     from the measured blast radius at Plan time (`reference/plan.md`), not at
     capture time. Leave the Scenarios section as the template's placeholder.

3. **Run `$CLAUDE_PLUGIN_ROOT/scripts/temper gate intent`** and fix any FAIL (empty
   Problem, no criteria, missing Status header) — the same deterministic floor the
   pipeline's Intent gate applies.

4. **Let the originator correct it.** Show the draft; apply their corrections; re-show.
   The artifact is theirs — you drafted it.

5. **Gate** (`AskUserQuestion`): **"Commit intent.md (Recommended)"** — stage then
   commit in two separate calls (`git add .temper/specs/{slug}/`, then `git commit -m
   "docs(intent): capture {slug} (draft)"` — separate calls so the in-agent
   commit-gate hook sees the artifacts already staged and its artifact-only carve-out
   passes them). If the project gitignores `.temper/specs/`, skip the commit with a
   one-line note that the draft stays local-only — never `git add -f`. Author and
   timestamp join the record; review/acceptance happens wherever this repo reviews
   commits. / **"Start /temper now"** — commit as above, then hand straight into the
   full pipeline with this intent as input. / **"Leave uncommitted"** — the file
   stays; say what was written where.

6. **Report** the path, the status, and the pickup route: a later `/temper "{slug}"`
   finds the draft, presents it at its Intent gate (building on it, never overwriting),
   and flips `Status: draft → accepted` when the human accepts there.

## Lifecycle (who flips Status)

| Status | Written by | Meaning |
|---|---|---|
| `draft` | this command (or a bands-breach draft via `/temper:status`) | captured, awaiting review |
| `accepted` | the Intent gate's human "Continue" (`/temper`'s Stage 0; the plan gate in standalone `/temper:plan`) | a person accepted it into build |
| `completed` | the commit step | shipped |

No stage advances on a draft without a human accepting it — same rule as every other
temper gate.
