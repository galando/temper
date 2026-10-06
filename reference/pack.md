---
description: "Manage quality packs: view, toggle, create, quick-create launchers, configure links and phases, enable or disable the guardrails hooks"
---

# Pack: Quality Pack Manager

**Goal:** Show every quality pack's status, phase scoping, and link health; let the user
toggle packs, quick-create a launcher pack, configure links/phases, or run the full
interactive builder; and merge or remove the guardrails pack's hooks in a project settings
file.

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

- `plugin://{name}`: connected when this session lists a skill or a slash command of
  that plugin (Claude Code shows each one as `{name}:{item}`). When the pack loads, use
  that plugin's listed skills and commands through Claude Code itself (the Skill tool
  loads a skill); never open the plugin's files.
- `skill://{name}`: connected when this session lists a skill or a slash command called
  `{name}`, or when `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/pack-discover.py"` prints a
  `LOCAL_SKILL` or `LOCAL_CMD` row with that name. Resolve in this order, and the first
  match wins: the project's `.claude/skills/{name}/SKILL.md` (a `LOCAL_SKILL` row), then
  the skill or command this session lists (load it with the Skill tool), then the
  project's `.claude/commands/{name}.md` (a `LOCAL_CMD` row, the command based
  fallback).

`pack-discover.py` reads only two folders of the project, `.claude/skills` and
`.claude/commands`, and prints one `TYPE|name|path|description` row per skill or
command there (`TYPE` is `LOCAL_SKILL` or `LOCAL_CMD`). Link targets from plugins, and
from the user's own skills and commands in the home folder, come only from the skills
and slash commands this Claude session lists. Nothing here reads a file of Claude Code:
not its plugin list, not its plugin folders, and not the skills and commands folders in
the home folder. The one home folder path Temper reads is its own global pack folder,
`~/.claude/packs` (the global tier above).

**Health:** `connected: true/false/null` (no link configured). If a link target is
missing, the pack's own rules still load — show a warning, never block work over a
removed plugin.

## Execution

### Arguments

`/temper:pack enable guardrails` runs **Guardrails: Enable** and `/temper:pack disable
guardrails` runs **Guardrails: Disable** (both in Guardrails Hooks below), then stops.
With no argument, or any other, start at Step 1.

### Step 1: Discover + Display

First stop, as in Guardrails Hooks, Enable step 1 (a) and (b), in the home folder and
wherever the temper CLI refuses the folder, since later steps write the project's
`.claude` folder. Then read the three tiers (above: the project and global pack folders,
plus the built-in files listed there), merge with `.claude/temper.config`, then show:

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

Then run the stale guard check (Guardrails Hooks below). When it finds a stale entry,
ask its question, as a question of its own, after the box and before Step 2.

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
`link`/`phases` if it had them); return to Step 2. The guardrails pack works through
settings hooks, not through `packs:`: turning it on runs **Guardrails: Enable**, and
turning it off runs **Guardrails: Disable**, each of which asks before writing.

### Step 3: Quick-Create Launcher Pack

**Gather targets:** run `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/pack-discover.py"` for
the project's own skills and commands (bounded, deduplicated, one correct answer for a
given project; 4 pipe-separated fields, `TYPE|name|path|description`, `TYPE` one of
`LOCAL_SKILL`/`LOCAL_CMD`), and add the skills and slash commands this session lists (a
plugin's item shows as `{plugin}:{item}`; leave out Temper's own `temper:` items; a
plugin with at least one listed item is also offered once as `plugin://{name}`). Filter
out any target already linked to an existing pack (check every pack's `link:` in
`temper.config`). Only show targets that the script printed or the session lists, and
never fabricate an entry.

Group by `TYPE` and show via `AskUserQuestion`, 4 options per page (3 targets + "More
targets..." when more than 4 remain; the last page uses all 4 slots for targets).

User picks a target, then types a pack name via "Other". The name must be lowercase
letters, digits and hyphens only (no `/`, no `..`); ask again for any other name. Write
the project's `.claude/packs/{name}/rules.md` (in the project, never in the plugin
folder):

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
   competing alternative. Its prompt carries this line, with the plugin folder written
   in place of the CLAUDE_PLUGIN_ROOT variable: "Plugin folder: the folder that holds
   ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path with /scripts/temper taken off);
   wherever the brief or a reference page writes the CLAUDE_PLUGIN_ROOT variable, use
   this folder."
2. **Interview** — present findings, ask 5-10 `AskUserQuestion`s about what should
   become a rule. On a genuine conflict (two patterns within 20% prevalence), ask which
   wins: Pattern A / Pattern B / "Allow both, document when" / "Defer".
3. **Generate** the project's `.claude/packs/{name}/rules.md` (same name rule as Step 3:
   lowercase letters, digits and hyphens only; never in the plugin folder) with
   `## Mandatory Rules (BLOCK)`, `## Quality Rules (WARN)`, `## Conventions (SUGGEST)`,
   `## Architectural Constraints (BLOCK)` sections populated from the interview.
4. Add the pack to `temper.config`, report, return to Step 2.

### Step 6: Done

Show the final `packs:` configuration and exit.

## Guardrails Hooks

The guardrails pack's guard scripts run as hooks in a project settings file, never in
the user's home settings: Temper never reads or writes those. Hooks in a settings file
get no CLAUDE_PLUGIN_ROOT variable, so each command carries the plugin folder itself,
in double quotes. The plugin folder is the folder that holds
`${CLAUDE_PLUGIN_ROOT}/scripts/temper` (that path with /scripts/temper taken off). Nothing
here writes into it: Enable and Disable stop first in the home folder, in an installed
copy of the plugin and in a folder inside the plugin folder.

**Guardrails: Enable.**

1. Check, in this order. (a) The project folder must not be the home folder, whose
   `.claude` settings are the user's own settings (otherwise say so in one line and
   stop). (b) Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper status`; when it prints a line
   that starts with `FAIL: run temper from a project folder` (the home folder, an
   installed copy of the plugin, or a folder inside the plugin folder), show that line
   and stop. Any other result, `FAIL: no intent.md to report on` among them, means go
   on. (c) `.claude/temper.config` must exist (otherwise: "Run /temper:init first").
   (d) The plugin folder must not hold a single quote, a double quote, a backslash, a
   dollar sign, a backtick or a line break (otherwise point the user to the manual copy
   in the Install section of `${CLAUDE_PLUGIN_ROOT}/packs/guardrails/rules.md`).
2. `AskUserQuestion`: `.claude/settings.local.json` (personal; the default and the
   recommended option, because each command holds this machine's plugin folder) or
   `.claude/settings.json` (shared, committed with the project; a teammate whose plugin
   sits in another folder sees those commands as stale). The file not picked is the
   other project settings file, and it is handled too (step 4).
3. Read `${CLAUDE_PLUGIN_ROOT}/packs/guardrails/settings-guardrails.json`, take its
   `hooks` object, and in every `command` put the plugin folder in place of the
   CLAUDE_PLUGIN_ROOT variable, with the script path in double quotes:
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/guards/block-secrets.sh"` with the real folder
   written in.
4. Merge in memory. A picked file that is not valid JSON is never rewritten (say so and
   stop); a missing one starts as `{}`. Remove every Temper guard entry first (each line
   `guard-entries.py` prints, current or stale, names one; see the stale guard check), so
   an earlier one is replaced instead of doubled, and drop matcher blocks and events left
   empty. Then append each new hook to the block with the same event and `matcher` (no
   matcher on both counts as the same), or append the block to its event. Every other
   key, block and hook stays as it was. In the other project settings file, when it
   exists and is valid JSON, remove every Temper guard entry the same way (and a `hooks`
   key left empty); when it is not valid JSON, leave it untouched and say so.
5. Show, for both files, the entries that will be removed, and the commands that will be
   added to the picked file. When the picked file is `.claude/settings.local.json`, run
   `git ls-files --error-unmatch .claude/settings.local.json` first. When it exits 0,
   git tracks the file and a `.gitignore` line would not keep it out of commits: offer
   no line, and say that `git rm --cached .claude/settings.local.json` stops tracking
   it. Otherwise, when `git check-ignore -q .claude/settings.local.json` exits 1 (git
   does not ignore it), offer to add that line to the project's `.gitignore`: "Apply
   the change and add the file to .gitignore (Recommended)" / "Apply the change only" /
   "Cancel". In every other case ask "Apply the change" / "Cancel".
6. On Apply, write each changed file (2-space indents), add the `.gitignore` line when
   chosen (only when no line of `.gitignore` already reads exactly
   `.claude/settings.local.json`), and add `guardrails` to `packs:` (an old `hooks`
   entry becomes `guardrails`).
7. Report the picked file and its number of guard commands, the entries removed from the
   other file, that a plugin upgrade moves the plugin folder and the commands then point
   at an old or missing copy of the guard scripts (the check below then offers to
   replace them), and that the commit gate `/temper:init` installs is separate.

**Guardrails: Disable.** Not in the home folder (say so and stop: those are the user's
own settings), and not where `${CLAUDE_PLUGIN_ROOT}/scripts/temper status` refuses the
folder (as in Enable step 1b). Read `.claude/settings.json` and
`.claude/settings.local.json` (those that exist; a file that is not valid JSON is left
untouched). Show every Temper guard entry in them (each line `guard-entries.py` prints
names one) and the `packs:` change, ask "Remove them" / "Cancel", then delete those
hooks, drop matcher blocks, events and a `hooks` key left empty, write each changed file
back, and remove `guardrails` (or an old `hooks` entry) from `packs:`. No entry and no
`packs:` entry: say "Guardrails are not on in this project."

**Temper guard entry:** a hook whose `command` names `block-secrets.sh`,
`protect-regression-test.sh`, `block-protected-paths.sh`, `block-uncommitted-gate.sh`,
`confirm-override.sh`, `block-forbidden-imports.sh`, `run-formatter.sh`,
`stage-marker.sh` or `verify-stage-gate.sh`. The last two run only as the plugin's own
hooks now, so an earlier settings entry for them is removed and never added back. Decide
from the script path in the command, in this order: (1) a path under the current plugin
folder is a Temper guard entry, also when the plugin folder lies inside the project
folder or is the project folder (a git checkout of Temper); (2) a path that ends in
`/scripts/`, one folder name, `/` and that script file, and lies outside the project
folder, is a Temper guard entry
(earlier versions and earlier plugin folders, including the guard scripts folder of
versions before 9.6.5; a path that starts with the CLAUDE_PLUGIN_ROOT variable counts as
outside, because a settings hook gets no such variable); (3) anything else, a relative
path, the CLAUDE_PROJECT_DIR variable or a path inside the project folder, is the user's
own copy and is left alone.

**Stale guard check** (Step 1 here, and `/temper:init` step 5): skipped when the project
folder is the home folder, or when the current plugin folder holds a character Enable
step 1 refuses. Otherwise run, from the project folder,
`python3 "${CLAUDE_PLUGIN_ROOT}/scripts/guard-entries.py"`. It reads only the two project
settings files, applies the Temper guard entry rules above, and prints one
`FILE|EVENT|MATCHER|SCRIPT|STATUS` line per Temper guard entry (a matcher can hold `|`,
so read FILE and EVENT from the left and SCRIPT and STATUS from the right). STATUS is
`current` when the script lies under the current plugin folder and the file exists, and
`stale` otherwise: a script outside the current plugin folder, existing or not (Claude
Code keeps an earlier version's folder for a while after an upgrade, and those commands
go on running that old copy), a missing script, or a path that still holds the
CLAUDE_PLUGIN_ROOT variable. Decide from its output only. Exit 2 means it refused (print
nothing more); exit 1 means it named an unreadable settings file on stderr, and the
other file's lines still count. When any line says `stale`, ask as a question of its
own: "{file}: {N} Temper guard commands run an old or missing copy of the guard scripts.
Replace them?", with the options "Replace them with the current guardrails set (shows the
change first)" (the whole current set is written in place of every Temper guard entry in
both files, so a guard removed earlier comes back) / "Not now". `{file}` is the file the
stale lines are in; when both have one, name both and pick `.claude/settings.local.json`.
On the first option, run Enable steps 1 and 3 to 7 with that file as the picked file
(step 5 shows the change in both files and asks again). On "Not now", change nothing.

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
| `guardrails` | Install guide for the edit-time and commit-time guard scripts (old name `hooks`); `phases: []`, so no stage loads it, and `/temper:pack enable guardrails` merges its hooks into a project settings file | BLOCK (enforced by the scripts) |
