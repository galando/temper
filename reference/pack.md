---
description: "Manage quality packs: view, toggle, create, quick-create launchers, configure links and phases"
---

# Pack: Quality Pack Manager

**Goal:** Show every quality pack's status, phase scoping, and link health; let the user
toggle packs, quick-create a launcher pack, configure links/phases, or run the full
interactive builder.

## Pack Resolution: Three-Tier System

Higher tier shadows lower, by name:

```
.claude/packs/{name}/rules.md     project-local (highest), in the project
~/.claude/packs/{name}/rules.md   global
the built-in files listed below   built-in (lowest), in the plugin
```

The built-in tier is exactly these files (see Built-in Packs for what each does), and
nothing else from the plugin:

```
${CLAUDE_PLUGIN_ROOT}/packs/quality/rules.md
${CLAUDE_PLUGIN_ROOT}/packs/tdd/rules.md
${CLAUDE_PLUGIN_ROOT}/packs/security/rules.md
${CLAUDE_PLUGIN_ROOT}/packs/git/rules.md
${CLAUDE_PLUGIN_ROOT}/packs/performance/rules.md
${CLAUDE_PLUGIN_ROOT}/packs/api-design/rules.md
${CLAUDE_PLUGIN_ROOT}/packs/architecture-depth/rules.md
${CLAUDE_PLUGIN_ROOT}/packs/guardrails/rules.md
```

Every stage reads this live at phase start (no cache): read the project and global pack
folders plus the built-in files above, keep the highest-priority `rules.md` per name,
filter to packs whose `phases` is `all` or contains the current phase (resolved as
below), read `temper.config` for enabled/link overrides. A project or global pack name
is lowercase letters, digits and hyphens only; skip any other folder.

**Old name:** the guardrails pack was called `hooks` before v9.6.5. A `packs:` entry
named `hooks` means `guardrails`: treat it exactly as a `guardrails` entry, and when
`/temper:pack` writes the `packs:` list back, write `guardrails`.

## Pack Configuration Schema

```yaml
packs:
  - quality                              # simple form == { name: quality }
  - name: tdd
    phases: [build]                      # restrict to one or more phases
  - name: security
    phases: [review, check]
  - name: api-standards
    link: plugin://my-api-linter         # or skill://name
```

Available phases: `plan`, `design`, `build`, `review`, `check`, `fix`. A `packs:` entry is
either a bare string (simple form) or a mapping with `name` (required), `phases`, `link`
(default none).

**Where `phases` comes from, in precedence order** — a pack is loaded for a phase if the
first of these that exists says so:

1. **`phases` on the `packs:` entry** in `temper.config` — the project's explicit choice,
   and it wins.
2. **`phases:` frontmatter in the pack's own `rules.md`** — the author declaring which
   stages the pack has anything to say to. Built-in packs all declare one; `tdd` is
   `[build, review, check, fix]`, `security` is `all`. The declarations themselves are
   the source of truth — read the frontmatter, not this sentence, if they ever disagree
   (the plugin's own validator checks their syntax).
3. **`all`** — no declaration anywhere, so it loads everywhere. This is the
   backwards-compatible default for a third-party pack written before frontmatter existed.

`all` in either place means every phase. An **empty list (`[]`) means no phase loads it** —
that's a real value, not a missing one. The guardrails pack's rules.md
(`${CLAUDE_PLUGIN_ROOT}/packs/guardrails/rules.md`) uses it: the file documents bash
guard scripts that enforce themselves at edit- and commit-time, so there is nothing in
it for a stage agent to apply, and loading it into all five stages was ~140 lines of
pure cost.

## Pack-Plugin/Skill Linking

A pack with a `link:` includes the linked resource's content in the AI's prompt context
alongside its own `rules.md`, whenever the pack loads for an active phase — context
injection, not code execution.

- `plugin://{name}` — read `~/.claude/plugins/installed_plugins.json`, verify the
  install path exists on disk.
- `skill://{name}` — resolve in order: the project's `.claude/skills/{name}/SKILL.md` →
  `~/.claude/skills/{name}/SKILL.md` → the exact path `pack-discover.py` printed for
  that skill (its third field) → the project's `.claude/commands/{name}.md`
  (command-based fallback) → the exact path `pack-discover.py` printed for that
  command. First match wins. Never build a path from a plugin folder and a name: an
  installed plugin's file is only ever the path the script printed, and the script
  never lists Temper itself.

**Health:** `connected: true/false/null` (no link configured). If a link target is
missing, the pack's own rules still load — show a warning, never block work over a
removed plugin.

## Execution

### Step 1: Discover + Display

Read the three tiers (above: the project and global pack folders, plus the built-in
files listed there), merge with `.claude/temper.config`, then show:

```
+--------------------------------------------------------------------------+
| PACK — Quality Pack Manager                                              |
+--------------------------------------------------------------------------+
|  NAME            STATUS  PHASES     LINK                CONNECTED        |
|  {name}           {on}    {phases}   {link}              {found/missing} |
|  ...                                                                     |
|  N packs total (X enabled, Y disabled)                                   |
+--------------------------------------------------------------------------+
```

Populate every row from real scan data — never a hardcoded example row.

### Step 2: Action

```
AskUserQuestion:
  question: "What would you like to do?"
  options:
    - label: "Toggle packs on/off"
    - label: "Quick-create launcher pack"
      description: "Wrap a plugin or skill as a BLOCK-level pack. No codebase scan."
    - label: "Configure pack (link, phases)"
    - label: "Done"
      description: "Use 'Other' to request the full interactive pack builder."
  multiSelect: false
```

**Toggle:** multi-select `AskUserQuestion` listing every pack with its current status;
write the selected set back to `packs:` in `.claude/temper.config` (keep each entry's
`link`/`phases` if it had them); return to Step 2.

### Step 3: Quick-Create Launcher Pack

**Discover targets:** run `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/pack-discover.py`
(bounded, deduplicated, one correct answer for a given filesystem — see the script's own
header for its output contract: 4 pipe-separated fields, `TYPE|name|path|description`,
`TYPE` one of `SKILL`/`CMD`/`PLUGIN`/`LOCAL_CMD`/`GLOBAL_CMD`). Filter out any target
already linked to an existing pack (check every pack's `link:` in `temper.config`). Only
show targets that actually appeared in the script's output — never fabricate an entry.

Group by `TYPE` and show via `AskUserQuestion`, 4 options per page (3 targets + "More
targets..." when more than 4 remain; the last page uses all 4 slots for targets).

User picks a target, then types a pack name via "Other". The name must be lowercase
letters, digits and hyphens only (no `/`, no `..`); ask again for any other name. Write
the project's `.claude/packs/{name}/rules.md` (in the project, never under
`$CLAUDE_PLUGIN_ROOT`):

```markdown
# {Pack Name}
> Launcher pack — enforces {type}://{name}

## Mandatory Rules (BLOCK if violated)
- MUST use {type}://{name} for all work
- MUST follow all instructions defined by the linked resource
- MUST NOT bypass or ignore the linked resource's rules
```

Add `{ name: {pack-name}, link: {type}://{name} }` to `temper.config`'s `packs:`, report
the launcher pack's location + link + severity, return to Step 2.

### Step 4: Configure Pack (Link, Phases)

Pick a pack, then "Set link target" (same discovery + selection as Step 3) / "Set phase
scoping" (`AskUserQuestion`: All phases / build only / review+check / "Other" free-text
for a custom combination) / Both. Update `temper.config`, return to Step 2.

### Step 5: Full Interactive Pack Builder ("Other" → "add new pack")

1. **Scan** — launch an Explore subagent across API design, data access, error
   handling, testing, code style, security, git/workflow; for each area return the
   dominant pattern with an example `file:line`, its consistency (`X/Y files`), and any
   competing alternative.
2. **Interview** — present findings, ask 5-10 `AskUserQuestion`s about what should
   become a rule. On a genuine conflict (two patterns within 20% prevalence), ask which
   wins: Pattern A / Pattern B / "Allow both, document when" / "Defer".
3. **Generate** the project's `.claude/packs/{name}/rules.md` (same name rule as Step 3:
   lowercase letters, digits and hyphens only; never under `$CLAUDE_PLUGIN_ROOT`) with `## Mandatory Rules (BLOCK)`, `##
   Quality Rules (WARN)`, `## Conventions (SUGGEST)`, `## Architectural Constraints
   (BLOCK)` sections populated from the interview.
4. Add the pack to `temper.config`, report, return to Step 2.

### Step 6: Done

Show the final `packs:` configuration and exit.

## Pack Rules Format

```markdown
# {Pack Name}
## Mandatory Rules (BLOCK if violated)
- Rule that stops the build if broken
## Quality Rules (WARN if violated)
- Rule that flags but doesn't block
## Conventions (SUGGEST improvements)
- Nice-to-have patterns
```

## Built-in Packs

| Pack | Purpose | Default Levels |
|---|---|---|
| `quality` | Method length, DRY, naming, complexity | WARN / SUGGEST |
| `tdd` | RED-GREEN-REFACTOR, scenario coverage | BLOCK / WARN |
| `security` | OWASP Top 10, secrets management | BLOCK / WARN |
| `git` | Conventional commits, branch naming | WARN / SUGGEST |
| `performance` | N+1 detection, pagination, Core Web Vitals | WARN |
| `api-design` | Additive extension, idempotency, naming | WARN |
| `architecture-depth` | Module depth: seams, adapters, locality, leverage | WARN |
| `guardrails` | Install guide for the edit-time and commit-time guard scripts (old name `hooks`); `phases: []`, so no stage loads it | BLOCK (enforced by the scripts) |
