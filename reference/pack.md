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
.claude/packs/{name}/rules.md           project-local (highest)
~/.claude/packs/{name}/rules.md         global
$CLAUDE_PLUGIN_ROOT/packs/{name}/rules.md   built-in (lowest)
```

Every stage reads this live at phase start (no cache): scan all three tiers (excluding
`stacks/`), keep the highest-priority `rules.md` per name, filter to packs whose `phases`
is `all` or contains the current phase, read `temper.config` for enabled/link overrides.

**No manifest cache.** A cached-scan JSON file was documented in earlier versions but
never implemented — the live scan reads a dozen small `rules.md` files, milliseconds
against any real problem here. The doc was fiction; it's removed rather than built.

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

`phases` omitted or `all` → active every phase. Available phases: `plan`, `design`,
`build`, `review`, `check`, `fix`. A `packs:` entry is either a bare string (simple form)
or a mapping with `name` (required), `phases` (default `all`), `link` (default none).

## Pack-Plugin/Skill Linking

A pack with a `link:` includes the linked resource's content in the AI's prompt context
alongside its own `rules.md`, whenever the pack loads for an active phase — context
injection, not code execution.

- `plugin://{name}` — read `~/.claude/plugins/installed_plugins.json`, verify the
  install path exists on disk.
- `skill://{name}` — resolve in order: `.claude/skills/{name}/SKILL.md` →
  `~/.claude/skills/{name}/SKILL.md` → `{plugin}/skills/{name}/SKILL.md` →
  `.claude/commands/{name}.md` (command-based fallback) →
  `{plugin}/commands/{name}.md`. First match wins.

**Health:** `connected: true/false/null` (no link configured). If a link target is
missing, the pack's own rules still load — show a warning, never block work over a
removed plugin.

## Execution

### Step 1: Discover + Display

Scan the three tiers (above), merge with `.claude/temper.config`, then show:

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

**Discover targets:** run `python3 $CLAUDE_PLUGIN_ROOT/scripts/pack-discover.py`
(bounded, deduplicated, one correct answer for a given filesystem — see the script's own
header for its output contract: 4 pipe-separated fields, `TYPE|name|path|description`,
`TYPE` one of `SKILL`/`CMD`/`PLUGIN`/`LOCAL_CMD`/`GLOBAL_CMD`). Filter out any target
already linked to an existing pack (check every pack's `link:` in `temper.config`). Only
show targets that actually appeared in the script's output — never fabricate an entry.

Group by `TYPE` and show via `AskUserQuestion`, 4 options per page (3 targets + "More
targets..." when more than 4 remain; the last page uses all 4 slots for targets).

User picks a target, then types a pack name via "Other" (lowercase, hyphens). Write
`.claude/packs/{name}/rules.md`:

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
3. **Generate** `.claude/packs/{name}/rules.md` with `## Mandatory Rules (BLOCK)`, `##
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
