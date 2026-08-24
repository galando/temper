---
title: Context Hygiene
nav_order: 7
---

# Context Hygiene

Temper's prompts are context you pay for on every run, and so are the `CLAUDE.md` files
and packs it touches in your project. This page is what Temper does about that, and what
you should do in the projects you run it on.

The reference point is Anthropic's
[new rules of context engineering for Claude 5 generation models](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models)
(July 2026), which reports removing over 80% of Claude Code's own system prompt with no
measurable loss on coding evals. The six shifts it names — rules to judgment, examples to
better tool interfaces, everything-upfront to progressive disclosure, repeated
instructions to tool descriptions, manual memory to auto-memory, simple specs to rich
references — all have a direct reading for a plugin like this one.

## Run `/doctor` on your own project

Claude Code ships `/doctor` (`claude doctor` from a shell) to rightsize your skills and
`CLAUDE.md` files. Run it on any project where you use Temper, and especially after
accepting Check's config suggestions — those write into `CLAUDE.md`/`AGENTS.md`, so an
unattended stream of accepted suggestions is exactly the kind of file `/doctor` exists to
catch. Temper never edits those files without showing you the suggestion at the Check
gate first, but it also can't tell you when the file as a whole has grown past useful.

## What Temper does on its own prompt surface

**Outcome briefs, not choreography.** v8 rewrote the prompt surface to state what a stage
must produce and the handful of rules a strong model would not derive on its own —
`reference/plan.md` went from 1,086 lines to 224 this way. A
[controlled A/B on Opus 5](evidence/opus5-plan-prompt-ab.md) put the saving at 48% of the
cost per Plan run with equal blast-radius recall. Hard rules survive where a gate
mechanically checks them, and nowhere else.

**Briefs are self-contained; orchestrators relay.** Every stage runs as an isolated
Agent subprocess launched from a small `agents/{stage}.md` brief, and (v9.1) the brief
carries everything the subprocess needs — including the summary box it returns — so a
clean context never reads the 20KB orchestrator file to fetch an 8-line template. The
orchestrator prints the returned box verbatim rather than restating formats, and
`commands/fix.md` launches its stages through the same briefs instead of inlining its
own copies of their prompts (22.9KB → 7.1KB in v9.1).

**Opt-in features load on opt-in.** Autonomous Continuation's mechanics live in
`reference/autonomy.md` (v9.2), read only when a project sets `autonomy.enabled: true` —
the default interactive run pays a five-line stub, not the feature. The same shift
dieted `reference/review.md` from 19.6KB to 13.6KB: what survived is policy a reviewer
would not derive alone (severity floors, filter bypasses, memory thresholds); what left
was choreography.

**Standalone commands can borrow the subprocess isolation.** `stages.subprocess: true`
makes `/temper:plan` through `/temper:check` run in the same clean `agents/{stage}.md`
subprocess the unified `/temper` uses, returning only the summary box and gate verdict
to your session — the default stays inline, because mid-stage interactivity is the
point of running a stage standalone.

**Rules live in the CLI, not in prose.** Every gate verdict is computed by
`scripts/temper` from an evidence ledger. A prompt that restated gate logic would be a
second copy to drift; instead the prompts quote the gate function or point at it. Same
for model selection: `temper model --all` resolves it, so no stage prompt has to reason
about which model it should be.

**Packs declare their phases.** A pack's `rules.md` opens with frontmatter naming the
stages it applies to:

```yaml
---
phases: [build, review, check]
---
```

`all` (or an absent block, for third-party packs) means every stage. `[]` means no stage
loads it — `packs/hooks/rules.md` uses this, because it documents bash hooks that enforce
themselves at edit- and commit-time and has nothing a stage agent can act on. Declaring
phases is the cheapest progressive-disclosure win available to a pack author: rules only
reach the stages that can use them.

**No generated advice blocks in `CLAUDE.md`.** Temper's own `.claude/CLAUDE.md` used to
carry a regenerated "Token Optimization Insights" section — standing advice like "prefer
Sonnet for simple tasks", "run `/compact` after turn 28", "Grep first, saves ~1%",
re-injected into every session. Advice that generic is judgment the model already
applies, and a ~1% saving does not pay for the block that describes it. It's gone, and
`validate-docs.sh` fails if it comes back. Token optimization as a set of runtime levers
is a [retired system](https://github.com/galando/temper/blob/main/docs/history/tokenomics.md).

## Writing a pack for Claude 5

- **Declare `phases:`.** See above.
- **Skip the worked examples.** A pack that shows the same test written three times in
  three stacks is teaching a Claude 5 model something it knows, in the most expensive
  format available. State the rule; let it write the test.
- **Keep "never" for demonstrable failure modes.** `packs/security/rules.md` says never
  concatenate user input into SQL, and that earns its imperative — it maps to a BLOCK
  gate and a real vulnerability class. A "never" that just encodes a style preference
  costs context and competes with the user's actual instructions.
- **Say it once.** If a rule is already enforced by a hook or a gate, the pack should
  describe the enforcement, not repeat the instruction.
