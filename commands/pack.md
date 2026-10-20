---
description: "Manage quality packs: view, toggle, quick-create launchers, configure links & phases, enable or disable the guardrails hooks"
argument-hint: "[enable guardrails | disable guardrails]"
---

# Pack: Quality Pack Manager

## Arguments: $ARGUMENTS

- `enable guardrails`: run **Guardrails: Enable** below, then stop.
- `disable guardrails`: run **Guardrails: Disable** below, then stop.
- Empty, or anything else: start at Step 1, the interactive manager.

**Plugin folder:** the folder that holds ${CLAUDE_PLUGIN_ROOT}/scripts/temper (that path
with /scripts/temper taken off). Wherever a reference page writes the CLAUDE_PLUGIN_ROOT
variable, use this folder. If that file does not exist, stop and say "Cannot locate the
Temper plugin folder. Reinstall the plugin." Never search the disk for another copy.
Nothing here writes into the plugin folder, and nothing here opens a Claude Code
settings file, the project's or the home folder's: the interactive manager and both
guardrails procedures stop first in the home folder, in an installed copy of the plugin
and in a folder inside the plugin folder (step 1a and 1b of **Guardrails: Enable**).
Nothing here reads Claude Code's own files in the home folder either (its plugin list,
its plugin folders, or the skills and commands kept there). The one home folder path Temper reads is its own global pack folder,
`~/.claude/packs`.

## Step 1: Discover Packs

First check the project folder as in step 1a and 1b of **Guardrails: Enable**, and stop
the same way: the steps below can write the project's `.claude/temper.config` and its
`.claude/packs` folder. Then read `.claude/temper.config` packs section (in the project).
Three tiers:
- project-local (highest priority): each folder in the project's `.claude/packs` folder
  that holds a `rules.md`
- global: each folder in `~/.claude/packs` that holds a `rules.md`
- built-in (lowest): exactly these files, nothing else from the plugin:
  - `${CLAUDE_PLUGIN_ROOT}/packs/quality/rules.md`
  - `${CLAUDE_PLUGIN_ROOT}/packs/tdd/rules.md`
  - `${CLAUDE_PLUGIN_ROOT}/packs/security/rules.md`
  - `${CLAUDE_PLUGIN_ROOT}/packs/git/rules.md`
  - `${CLAUDE_PLUGIN_ROOT}/packs/performance/rules.md`
  - `${CLAUDE_PLUGIN_ROOT}/packs/api-design/rules.md`
  - `${CLAUDE_PLUGIN_ROOT}/packs/architecture-depth/rules.md`
  - `${CLAUDE_PLUGIN_ROOT}/packs/guardrails/rules.md`

Deduplicate by name (highest tier wins). A `packs:` entry named `hooks` (the guardrails
pack's old name) means `guardrails`. For each pack: read rules.md header, check enabled status, read `phases` and `link` from config.

## Step 2: Display Pack Table

Build the table dynamically from discovered packs. Do NOT use hardcoded example rows.

Format each row using actual data:
- **NAME** — pack name from config
- **STATUS** — `ON` if in packs list, `OFF` if not
- **PHASES** — from config (show `all` if not specified)
- **LINK** — from config (show `—` if none)
- **CONNECTED**: `found` or `missing`, and blank when there is no link. A
  `plugin://{name}` link is found when this session lists a skill or a slash command of
  that plugin, shown as `{name}:{item}` in the skills and commands Claude Code gives
  you. A `skill://{name}` link is found when this session lists a skill or a slash
  command called `{name}`, or when `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/pack-discover.py"` prints a
  `LOCAL_SKILL` or `LOCAL_CMD` row with that name (see Step 5a). Decide it from that list
  and those rows only: never read a file of Claude Code or of another plugin to check a
  link.

Example structure (populate with real data only) — the panel format is owned by
`${CLAUDE_PLUGIN_ROOT}/reference/pack.md` → "Step 1: Discover + Display"; render exactly that box, never a
second, different shape here:

## Step 3: AskUserQuestion (max 4 options)

```
AskUserQuestion:
  question: "What would you like to do?"
  options:
    - label: "Toggle packs on/off"
      description: "Select packs to enable or disable."
    - label: "Quick-create launcher pack"
      description: "Wrap a plugin or skill as a BLOCK-level pack."
    - label: "Configure pack (link, phases)"
      description: "Set link target or phase scoping for an existing pack."
    - label: "Done"
      description: "Exit. Use 'Other' for full interactive pack builder."
  multiSelect: false
```

## Step 4: Toggle Packs

Multi-select AskUserQuestion with all packs. Update `.claude/temper.config` `packs:` list. Return to Step 3.

The guardrails pack works through settings hooks the user adds, not through `packs:`
alone. When the selection turns `guardrails` on, run **Guardrails: Enable** for it, which
prints the entries to add; when it turns it off, run **Guardrails: Disable**, which says
which entries to remove.

## Step 5: Quick-Create Launcher Pack

**5a: Gather the linkable targets.** They come from two places, and from nothing else:

1. The project's own skills and commands. Run the discovery script:

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/pack-discover.py"
   ```

   Each line is `TYPE|name|path|description`, deduplicated and in a fixed order:
   `LOCAL_SKILL` for each skill folder in the project's `.claude/skills` folder and
   `LOCAL_CMD` for each command file in the project's `.claude/commands` folder, each
   with its own frontmatter description. The script reads only those two project
   folders.
2. The skills and slash commands this session lists, the ones Claude Code gives you:
   those of the installed plugins (a plugin's item shows as `{plugin}:{item}`) and the
   user's own. Take each item's name and its own description from that list, and leave
   out Temper's own items (`temper:`). Never read Claude Code's files to find more
   targets: not its plugin list, not its plugin folders, and not the skills and
   commands folders in the home folder.

**Filter:** remove any target already linked to an existing pack (check `link:` values
in `temper.config`).

Use these display labels:
- a skill this session lists → `Skill` (links as `skill://{name}`)
- a slash command this session lists → `Command` (links as `skill://{name}`)
- a plugin with at least one listed item, shown once by its name → `Plugin` (links as
  `plugin://{name}`)
- `LOCAL_SKILL|` → `Project Skill` (links as `skill://{name}`)
- `LOCAL_CMD|` → `Project Command` (links as `skill://{name}`)

Group and display by type:
```
Skills:
  1. frontend-design:frontend-design — Frontend design skill for UI/UX
  ...

Commands:
  5. commit-commands:commit — Create a git commit
  ...

Plugins:
  8. context7 — Up-to-date library docs
  ...

Project Skills:
  9. ...

Project Commands:
  10. ...
```

**Important:** Only show targets that the script printed or this session lists. Do NOT fabricate entries.

Show via AskUserQuestion (max 4 at a time, use "More targets..." to paginate).

**5b:** User picks target, types pack name via "Other". The name must be lowercase letters, digits and hyphens only (no `/`, no `..`); ask again for any other name. Generate `rules.md` in a folder of that name inside the project's `.claude/packs` folder (in the project, never in the plugin folder) with BLOCK-level enforcement. Update `temper.config`. Return to Step 3.

## Step 6: Configure Pack

Select pack → choose "Set link" or "Set phases" or both.

**Set link:** Gather the targets as in Step 5a. Show them. Update config.
**Set phases:** Show phase options (all, build, review+check, or type custom via "Other"). Update config.

Return to Step 3.

## Step 7: Full Interactive Pack Builder

> Read `${CLAUDE_PLUGIN_ROOT}/reference/pack.md` → "Step 5: Full Interactive Pack Builder" section for the codebase scan + interview + generation methodology.

This is the ONLY step that requires loading the reference doc. All other steps are self-contained above.

## Guardrails: Enable

The guardrails pack's guard scripts run as hooks in a project settings file. Temper never
opens, reads or writes a Claude Code settings file: it prints the entries, and the user
adds them. Hooks in a settings file get no CLAUDE_PLUGIN_ROOT variable, so each printed
command holds the plugin folder itself.

1. **Check first, in this order.**
   a. When the project folder is the home folder, stop and say in one line: "The project
      folder is your home folder, whose .claude settings are your own settings. Run this
      from a project folder."
   b. Run `${CLAUDE_PLUGIN_ROOT}/scripts/temper status`. When it prints a line that
      starts with `FAIL: run temper from a project folder`, the CLI refused this folder
      (the home folder, an installed copy of the plugin, or a folder inside the plugin
      folder): stop and show that line, because nothing here may write there. Any other
      result, `FAIL: no intent.md to report on` among them, means go on.
   c. `.claude/temper.config` must exist; when it does not, stop and say "No
      .claude/temper.config here. Run /temper:init first."
2. **Print the entries.** Run:
   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/scripts/guardrails-snippet.py"
   ```
   It reads one file, the plugin's own `packs/guardrails/settings-guardrails.json`, and
   prints its `hooks` object as JSON, with the plugin folder written into every command
   and the script path in double quotes: the first command reads
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/guards/block-secrets.sh"` with the real folder
   written in. When it exits 2 it refused (the plugin folder holds a quote, a backslash,
   a dollar sign, a backtick or a line break, or the snippet cannot be read): show its
   one line, point the user to the manual copy in the Install section of
   `${CLAUDE_PLUGIN_ROOT}/packs/guardrails/rules.md`, and stop.
3. **Show it and say where it goes.** Show the printed JSON in one fenced block, and
   under it, in at most four lines: add these entries to the `hooks` object of
   `.claude/settings.local.json` (personal, recommended, because each command holds this
   machine's plugin folder) or `.claude/settings.json` (shared, committed with the
   project, so a teammate whose plugin sits elsewhere gets commands that point at a
   missing folder), appending each block to its event's list; replace any **Temper
   guard entry** (below) the file already holds, so none is doubled; and keep
   `.claude/settings.local.json` out of commits. Never open, read or write either
   settings file in this command, and never offer to: the user adds the entries.
4. **Turn the pack on.** Add `guardrails` to `packs:` in `.claude/temper.config` (an old
   `hooks` entry becomes `guardrails`; when `guardrails` is already there, leave the list
   as it is).
5. **Report** in at most three lines: that a plugin upgrade moves the plugin folder, so
   the added commands then point at an old or missing copy of the guard scripts, and
   `/temper:pack enable guardrails` prints the current ones again; that the commit gate
   `/temper:init` installs is separate and still the only gate on a raw `git commit`;
   and that new hooks may need the `/hooks` menu or a new session before they run.

## Guardrails: Disable

1. Stop in the home folder and wherever the CLI refuses the folder, as in steps 1a and
   1b of **Guardrails: Enable**.
2. When `packs:` in `.claude/temper.config` lists `guardrails` (or an old `hooks`
   entry), show that change, then `AskUserQuestion`: "Remove guardrails from packs:" /
   "Cancel". On Cancel, change nothing and stop; otherwise remove the entry. When it
   lists neither, say "Guardrails are not on in this project's temper.config."
3. Either way, say in at most two lines that the guard hooks live in the project's
   settings files, which Temper does not open: to stop them, the user removes each
   **Temper guard entry** (below) from `.claude/settings.local.json` and
   `.claude/settings.json`.

## Temper Guard Entries

A **Temper guard entry** is a hook (one object in a `hooks` list) whose `command` runs
one of these script files from a Temper plugin folder: `block-secrets.sh`, `protect-regression-test.sh`, `block-protected-paths.sh`,
`block-uncommitted-gate.sh`, `confirm-override.sh`, `block-forbidden-imports.sh`,
`run-formatter.sh`, `stage-marker.sh` and `verify-stage-gate.sh`. The last two
now run only as the plugin's own hooks, so an earlier settings entry for them can go,
and the snippet never prints them again. A command that runs a copy of one of those
scripts from inside the project (a relative path, a path through the CLAUDE_PROJECT_DIR
variable, or a path in the project folder) is the user's own copy, the way the
guardrails pack extends a denylist, and stays.
