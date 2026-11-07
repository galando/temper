---
description: "Capture an idea as a draft intent.md, the artifact that starts the pipeline, without starting it"
argument-hint: "<idea-in-your-own-words | JIRA-123 | #456>"
---

# Intent: Capture an Idea as an Artifact

**Goal:** turn an idea, a ticket or an incident finding into a `.temper/specs/{slug}/intent.md`
with `**Status:** draft`, and stop there. This is the entry point for work that is not ready to
build yet: the originator (who may not be the implementer, or an engineer at all) describes the
problem in their own words; the draft is what a product owner reviews and what `/temper` later
picks up.

**First output, once per conversation:** "Temper Markdown edition: Claude applies the
checklists and you decide; no program enforces them here."

**Plugin folder:** `${CLAUDE_PLUGIN_ROOT}`. The template is `templates/intent.md` and the
checklist is the Intent section of `reference/gates.md`, both in that folder.

## Usage

```
/temper:intent "handlers spend a third of call time on status-only queries"
/temper:intent "JIRA-4521"      # fetch the ticket, capture it as intent
/temper:intent                  # no argument: interview from scratch
```

## Steps

1. **Understand the problem, not the solution.** Read `$ARGUMENTS` (tell a ticket key such as
   `JIRA-123`, an issue such as `#123` and free text apart). Fetch every source the request
   links, read only, and record each under `### Context Sources` (`consulted:`, `unavailable:`
   or `none:`). Then interview, one question at a time with AskUserQuestion, only where the
   uncertainty changes the outcome: current and desired behavior, scope and non-goals,
   acceptance, the outcome after release, blocking and deferred decisions. Two probes are
   mandatory: "what business outcome or risk does each criterion address?" (the `Why:` line)
   and "who acts on the result, and what happens next?" (Target Users). Go through the rules
   checklist of the Intent stage (Who, When, How much, Exempt, States, Where it shows,
   Exceptions) for what the request leaves open. Write every answer into `### Decisions` at
   once, as `{question} -> {answer} ({who decided}, {date})`. Never write card data or personal
   data into the intent; reference the ticket.

   **Soft source words:** never turn a source "should" or "may" into "must" silently. Ask
   whether it means required or optional and record the answer; with no answer yet, keep the
   source wording marked `(source: ...)` and add a Blocking Open Question.

   **The slug:** letters, digits, `.`, `_` or `-`, starting with a letter or digit, no `..` or
   `/`. With a ticket key, prefix it as typed: `PROJ-123-login`.

2. **Write the draft** to `.temper/specs/{slug}/intent.md` from the template: `**Author:**` (a
   name the person typed, else `the person`; never ask git or the system), `**Status:** draft`,
   `**Created:**`, `**Ticket:**` when given, `**Reviewer:**` when named, `**Complexity:**` (a
   first guess). Fill Problem, Success Criteria (`AC-NN`, `[required]` or `[optional]`, `Why:`,
   `Validate:`), Constraints, Scope and Non-goals, Target Users, Open Questions (each `Blocking:`
   or `Deferred:`), Assumptions, Rules covered and Decisions. **Write no scenarios and pick no
   architecture**: Plan derives scenarios from the measured blast radius.

3. **Walk the Intent checklist** and fix every FAIL row (an empty Problem, no real criteria, a
   missing header value, a soft word without a source marker, an unlabeled question). Show the
   rows.

4. **Let the originator correct it.** Show the draft, apply their corrections, show it again.
   The artifact is theirs; you drafted it.

5. **Gate.** Ask header `Temper gate`, question "The draft intent for {slug} is written,
   checklist {result}. What now?", options:
   - "Commit intent.md": `git add .temper/specs/{slug}/intent.md`, then in a separate Bash call
     `git commit -m "docs(intent): capture {slug} (draft)"`. When the project ignores
     `.temper/`, skip the commit and say the draft stays local; never `git add -f`.
   - "Start /temper now": commit as above, then invoke the Skill tool with `temper:temper` and
     the feature; the pipeline picks this draft up at its Intent stage.
   - "Leave uncommitted": the file stays; say where it is.

6. **Report** the path, the status and how it is picked up: a later `/temper:temper "{slug}"`
   finds the draft, builds on it (never overwrites it), and sets `Status: accepted` when the
   person accepts it at the Intent gate.

## Lifecycle

| Status | Written by | Meaning |
|---|---|---|
| `draft` | this command | captured, waiting for review |
| `accepted` | the person's "Continue to Plan" at the Intent gate | accepted into build |
| `completed` | the commit step | the change is committed, not necessarily released |

No stage moves on a draft without a person accepting it.
