# Draft: Capture an Idea as an Intent

The page of the word `draft` of `/temper:temper` (`/temper:temper draft <idea>`). It turns an idea, a ticket or an
incident finding into `.temper/specs/{slug}/intent.md` with `Status: draft`, and stops there: no run is started. The
originator (who may not be the implementer, or an engineer at all) describes the problem in their own words; the
draft is what a product owner reads, and what a later `/temper:temper "<feature>"` takes up.

A run's own Intent stage still writes intent.md when none exists. The word is for the split of capture now and build
later, so the idea's author, its date and its history live in version control from the moment it is real. A draft
captured here is what the run's Intent stage later takes as its input.

```
/temper:temper draft handlers spend a third of call time on status-only queries
/temper:temper draft JIRA-4521      # fetch the ticket, capture it as intent
```

The interview runs here, in the main session: it asks the person, so no agent runs it.

1. **Understand the problem, not the solution.** Read the idea (tell a ticket key such as `JIRA-123`, a GitHub issue
   such as `#123` and free text apart). Fetch every source the request links (ticket, merge or pull request, doc)
   read only and record each under `### Context Sources` (`consulted:`, `unavailable:` or `none:`). Then interview
   with the full question bank: current and desired behaviour, scope and non-goals, acceptance, blocking and deferred
   decisions. One probe is mandatory: *"what business outcome or risk does each criterion address?"* (the `Why:`
   line). Ask only where the uncertainty changes the outcome: no fixed round count, one question at a time, with
   `AskUserQuestion`. No formal language is required of the originator; producing structure is your job, not theirs.
   Write every answer into `### Decisions` at once, as `{question} -> {answer} ({who decided}, {date})`. **Never
   write card data or personal data into the intent**: name the ticket instead.
   When a ticket key is linked, prefix the slug with the key as typed (`{KEY}-{slug}`, for example
   `PROJ-123-login`). A slug is letters (either case), digits, '.', '_' or '-', starts with a letter or digit, and has
   no '..' or '/': a later run passes it to `state init`, which refuses anything else.
   **Soft source words:** never turn a source "should" or "may" into "must" in silence. Ask the originator whether
   the source means required or optional and record the answer in `### Decisions`. With no answer yet, keep the
   source wording (marked `(source: ...)`) and add a Blocking Open Question.

2. **Write the draft** to the project's `.temper/specs/{slug}/intent.md` from
   `${CLAUDE_PLUGIN_ROOT}/templates/intent.md`:
   - Header: `**Author:**` (a name the person typed, else `the person`; never ask git or the system for a name or
     email), `**Status:** draft`, `**Created:**`, `**Ticket:**` if one was given, `**Complexity:**` (a first guess).
   - Fill **Problem** (who is affected, current and desired with one concrete example, facts apart from
     assumptions), **Success Criteria** (stable `AC-NN` ids, each `[required]` or `[optional]`, each with `Why:` and
     `Validate:` lines), **Constraints** (each `(source: ...)` or `(proposed)`), **Scope and Non-goals**, and **Open
     Questions** (each labeled `Blocking:` or `Deferred:`: carrying a question forward honestly beats resolving it by
     guess).
   - **Write no Scenarios and pick no architecture.** Plan derives the scenarios from the measured blast radius
     (`${CLAUDE_PLUGIN_ROOT}/reference/plan.md`). Leave `## Scenarios (BDD)` empty, never a placeholder `Scenario:`
     block: the check gate wants a passing test for every `Scenario:` line and cannot tell a placeholder from a real
     one.

3. **Let the originator correct it.** Show the draft, apply their corrections, show it again. The artifact is theirs;
   you drafted it.

4. **Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate intent --spec-path .temper/specs/{slug}`** at the end, and fix
   any FAIL (an empty or placeholder Problem, no real criteria, a missing Status value, a should, may, might or
   possibly in a criterion or constraint with no `(source: ...)` marker): the same floor the run's Intent gate
   applies. `--spec-path` is required: the word never runs `temper state init`, and with no spec path the gate refuses
   to guess (a usage error, no verdict). While a run of another feature is active, the gate prints its rows and says
   `not recorded`: the draft's verdict never stands for that run. Fix the FAIL rows all the same. The session that
   typed the word owes this gate (ADR 0005): the stop hook holds the session until it ran, PASS or FAIL.

5. **Commit it** (`AskUserQuestion`): "Commit intent.md (Recommended)": stage and commit in two separate calls
   (`git add .temper/specs/{slug}/`, then `git commit -m "docs(intent): capture {slug} (draft)"`), so the commit
   hook sees the artifacts staged. When the project ignores `.temper/specs/` in git, skip the commit with a one line
   note that the draft stays local, never `git add -f`. / "Leave uncommitted": the file stays; say what was written
   where.

6. **Report** the path, the status and the way on: a later `/temper:temper "{slug}"` finds the folder by its
   `intent.md`, takes the draft as its Intent input (building on it, never writing over it), and the person accepts
   it with the plan at the approval, which sets `Status: accepted`.

| Status | Written by | Meaning |
|---|---|---|
| `draft` | this word | captured, waiting for review |
| `accepted` | the approval of a run's plan | a person accepted it into the build |
| `completed` | the commit step | built: the change is committed, not always released |

No stage moves on from a draft without a person accepting it, as at every other gate of Temper.
