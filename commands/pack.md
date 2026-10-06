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
Nothing here writes into the plugin folder, and nothing here reads or writes the user's
home settings. Nothing here reads Claude Code's own files in the home folder either (its
plugin list, its plugin folders, or the skills and commands kept there). The one home
folder path Temper reads is its own global pack folder, `~/.claude/packs`.

## Step 1: Discover Packs

Read `.claude/temper.config` packs section (in the project). Three tiers:
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

Then run **Stale Guard Commands** below, and print its one line when it finds any.

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

The guardrails pack works through settings hooks, not through `packs:`. When the
selection turns `guardrails` on, run **Guardrails: Enable** for it; when it turns it off,
run **Guardrails: Disable**. Each shows its change and asks before writing.

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

The guardrails pack's guard scripts run as hooks in a project settings file. Hooks in a
settings file get no CLAUDE_PLUGIN_ROOT variable, so each command gets the plugin
folder written into it.

1. **Check first.** `.claude/temper.config` must exist; when it does not, stop and say
   "No .claude/temper.config here. Run /temper:init first." When the project folder is
   the home folder, stop and say in one line: "The project folder is your home folder,
   whose .claude settings are your own settings; Temper does not change them. Run this
   from a project folder." The plugin folder must not hold a single quote, a double
   quote, a backslash, a dollar sign, a backtick or a line break, because each command
   puts it in double quotes and the stale check below tests it in single quotes; when it
   does, stop and point the user to the manual copy in the Install section of
   `${CLAUDE_PLUGIN_ROOT}/packs/guardrails/rules.md`.
2. **Pick the file.**
   ```
   AskUserQuestion:
     question: "Which project settings file should hold the guardrails hooks?"
     options:
       - label: ".claude/settings.local.json (Recommended)"
         description: "Personal: only you, on this machine. The commands hold this machine's plugin folder, so this file is the right home for them."
       - label: ".claude/settings.json"
         description: "Shared: committed with the project. The commands still hold this machine's plugin folder, so a teammate whose plugin sits elsewhere sees them as stale."
     multiSelect: false
   ```
   The other project settings file is the one not picked. Both are handled below:
   the picked file gets the commands, and the Temper guard entries in the other file
   are removed in the same change, so no earlier entry is left behind there.
3. **Build the entries.** Read `${CLAUDE_PLUGIN_ROOT}/packs/guardrails/settings-guardrails.json`
   and take its `hooks` object (skip `_comment`). In every `command`, replace the
   CLAUDE_PLUGIN_ROOT variable (its dollar sign, braces and name) with the plugin folder,
   and put the whole script path in double quotes. The first command then reads exactly
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/guards/block-secrets.sh"`.
4. **Merge, in memory first.** When the picked file exists but is not valid JSON, stop
   and say so: never rewrite a file you cannot parse. When it is missing, start from
   `{}`. Remove every **Temper guard entry** (defined below) from its `hooks`, so an
   earlier entry is replaced instead of doubled, then drop any matcher block whose
   `hooks` list is left empty and any event whose list is left empty. Then, for each
   event and matcher block from step 3: when the file already has a block for that event
   with the same `matcher` (two blocks with no matcher count as the same), append the new
   hooks to that block's `hooks` list; otherwise append the block to that event's list,
   adding the event when it is missing. Keep every other key, block and hook as it was.
   Then read the other project settings file, when it exists. When it is valid JSON,
   remove every Temper guard entry from it the same way, and also drop its `hooks` key
   when it is left empty. When it is not valid JSON, leave it untouched and say so in
   step 5.
5. **Show and confirm.** Show, for each of the two files, each Temper guard entry that
   will be removed, and, for the picked file, each command that will be added. When the
   picked file is `.claude/settings.local.json`, run
   `git check-ignore -q .claude/settings.local.json` first. When it exits 1 (git does
   not ignore the file, so a commit could carry this machine's plugin folder), the
   question offers to add the line `.claude/settings.local.json` to the project's
   `.gitignore`: "Apply the change and add the file to .gitignore (Recommended)" /
   "Apply the change only" / "Cancel". Otherwise (it exits 0, or 128 outside a git
   repository) the question is "Apply the change" / "Cancel". On Cancel, change nothing
   and stop.
6. **Write.** Write each changed file back with 2-space indents. When the user chose to,
   append `.claude/settings.local.json` on a line of its own to the project's
   `.gitignore` (create the file when it is missing). Then add `guardrails` to `packs:`
   in `.claude/temper.config` (an old `hooks` entry becomes `guardrails`; when
   `guardrails` is already there, leave the list as it is).
7. **Report** in at most three lines: the picked file and how many guard commands it now
   holds, and how many Temper guard entries were removed from the other file; that a
   plugin upgrade which moves the plugin folder leaves these commands pointing at a
   missing script, which `/temper:pack` and `/temper:init` then offer to rewrite; and
   that the commit gate `/temper:init` installs is separate and still the only gate on a
   raw `git commit`. If the new hooks do not run in this session, the user can open the
   `/hooks` menu or start a new session.

## Guardrails: Disable

1. When the project folder is the home folder, say in one line that its .claude
   settings are the user's own settings, which Temper does not change, and stop.
   Otherwise read the project settings files that exist, `.claude/settings.json` and
   `.claude/settings.local.json`, and nothing else. A file that is not valid JSON: say
   so and leave it untouched.
2. Find every Temper guard entry in them. When there is none and `packs:` lists neither
   `guardrails` nor `hooks`, say "Guardrails are not on in this project." and stop.
3. Show, for each file, the commands that will be removed, and the `packs:` change. Then
   `AskUserQuestion`: "Remove them" / "Cancel". On Cancel, change nothing and stop.
4. Delete those hooks, drop any matcher block and any event left empty, and drop the
   `hooks` key itself when it is left empty. Keep everything else and write each changed
   file back with 2-space indents. Remove `guardrails` (or an old `hooks` entry) from
   `packs:` in `.claude/temper.config`. Report in one line.

## Temper Guard Entries

A **Temper guard entry** is a hook (one object in a `hooks` list) whose `command` names
one of these script files: `block-secrets.sh`, `protect-regression-test.sh`,
`block-protected-paths.sh`, `block-uncommitted-gate.sh`, `confirm-override.sh`,
`block-forbidden-imports.sh`, `run-formatter.sh`, `stage-marker.sh`,
`verify-stage-gate.sh`. The last two now run only as the plugin's own hooks, so an
earlier settings entry for them is removed and never added back. Take the script path
from the command (the text inside the double quotes, or else the word after `bash`) and
decide in this order:

1. The path lies under the current plugin folder: a Temper guard entry. This holds
   even when the plugin folder lies inside the project folder, and when the project
   folder is the plugin folder itself.
2. The path ends in `/scripts/`, one folder name, `/` and that script file, and lies
   outside the project folder: a Temper guard entry. This covers earlier plugin
   versions, earlier plugin folders and the guard scripts folder of versions before
   9.6.5. A path that starts with the CLAUDE_PLUGIN_ROOT variable counts as outside the
   project folder: a settings hook gets no such variable, so its path starts at the root
   of the disk.
3. Anything else (a relative path, a path through the CLAUDE_PROJECT_DIR variable, or a
   path inside the project folder) is the user's own copy (the way the guardrails pack
   extends a denylist) and is never a Temper guard entry: leave it alone.

## Stale Guard Commands

Used by Step 1 and by `/temper:init`. Skip it, printing nothing, when the project folder
is the home folder, or when the current plugin folder holds a character that step 1 of
**Guardrails: Enable** refuses (no rewrite could be offered then). In
`.claude/settings.json` and `.claude/settings.local.json`, a Temper guard entry is stale
when its script file does not exist: it names a folder an earlier plugin version used
(such as the guard scripts folder of versions before 9.6.5), or it still holds the
CLAUDE_PLUGIN_ROOT variable itself (a settings hook gets no such variable, so that path
starts at the root of the disk). Take the script path from the command and check it with
`test -f '<path>'`. Never run a path that holds a quote, a dollar sign, a backtick or a
line break: count it as stale. When any entry is stale, say in one line: "{file}: {N}
Temper guard commands point at a missing script. Rewrite them with the current plugin
folder?" On yes, run steps 1 and 3 to 7 of **Guardrails: Enable** with that file as the
picked file; step 5 shows every change, in both files, before writing.
