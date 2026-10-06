---
title: Directory submission
nav_order: 10
---

# Directory submission

This page lists what to check before you submit Temper to a plugin directory, and what to
type in the form. Run `bash scripts/validate-directory.sh` first. It checks the rules that a
script can check.

## What the script checks

| Rule | Why |
|---|---|
| The README has no raw HTML | The directory page does not render it. Use Markdown only. |
| The README has an Install heading and a "What the mod reads and writes" heading | A reader must see how to install it and what it touches. |
| A plain text line of the phases comes before the Mermaid diagram | Some pages do not draw Mermaid. |
| Every image has alt text | Accessibility. |
| No text file names the bundled assets folder outside a link target | Image files may move. |
| No `options` key in `plugin.json` or `marketplace.json` | A settings field with options stops the plugin loading before Claude Code 2.1.271. |
| `plugin.json` has a description, keywords and a version | The listing uses them. |
| `marketplace.json` lists the same plugin | The names must match. |
| A LICENSE file exists | The directory shows the license. |
| No shell or Python script writes into a path with a folder named `hooks` | Git's hook folders share that name with the plugin folder that holds the mod, and the directory holds a plugin whose scripts write there. The rule catches a write whose own words name the folder, also through `git rev-parse` in a `$( )` span, a `cd` into the folder or a variable set to such a path; a name built from pieces is for review. |

## Check by hand

- [ ] `claude plugin validate --strict .` passes.
- [ ] `claude plugin test .` passes.
- [ ] The version in `plugin.json` matches the top entry of `CHANGELOG.md`.
- [ ] The README images load on the GitHub page (open the page and look). Since 9.6.5 the repo
      holds no image but the listing icon (since 9.6.6), so they load by URL.
- [ ] The hero GIF shows the real mod.
- [ ] The privacy page is public: https://galando.github.io/temper/privacy.html
- [ ] You tried the install steps in a clean folder: `/plugin marketplace add galando/temper`,
      then `/plugin install temper`.

## Text for the form

Short description (one sentence):

> Gates for AI written code: Claude cannot write code before you approve the intent.

Long description:

> Temper adds an approval gate to AI coding. You approve the intent, then the plan. Build starts
> with a failing test. Review and Check follow. A small CLI computes every gate verdict from an
> evidence ledger, and a red gate blocks git commit. On Claude Code 2.1.287 or later a mod refuses
> writes that do not belong to the current phase, draws a phase bar, and keeps a report of the run.

Data and permissions, in plain words:

- No network calls and no telemetry.
- The mod reads `.claude/temper.config`, the run files under `.temper/` and `.git/HEAD` in your
  project, and writes no file. It keeps its records in its own plugin store.
- Outside the project and the mod's plugin store, Temper reads only its own global pack folder,
  `~/.claude/packs`, and no key, login or Claude Code file.
- Tests, lint and git run through Claude's own tools and permissions.
- The commit gate installer writes only in the repository's git folder: the Temper hook in
  `temper-gate/pre-commit`, the file `temper-pre-commit` when a hook of yours holds the line
  Temper 9.6.5 printed, and the repository's `core.hooksPath` setting, which it points at
  that folder (or, for Temper's older relative folder that must stay, at that folder's absolute
  path). It never writes into a folder named `hooks` (git's own or another tool's), so it
  never writes over a hook of yours: when git would stop running one, it leaves `core.hooksPath`
  as it is and prints one line for your hook to run the Temper hook.
- The optional game keeps one number, the best score, in the plugin store.

## What the listing shows

The directory builds the listing from `plugin.json` and the README. It has no other form fields
for marketing. These facts come from the Anthropic plugin documentation and from what the
directory reported on earlier versions.

| Listing part | Where it comes from | What Temper does |
|---|---|---|
| Icon | `.claude-plugin/icon.png`, or the `icon` field in `plugin.json`: a square PNG or JPEG of 512 to 2048 px, under 2 MB. The directory takes it only the first time the plugin is saved or submitted in the developer portal. | Since 9.6.6 `.claude-plugin/icon.png`, 1024 px: an orange T on a dark rounded square, the only image in the repository. `plugin.json` has no `icon` field. 9.6.5 had none; from 9.6.0 to 9.6.4 a 256 px icon, below the size the directory asks for. |
| Short description | The `description` field. A card cuts it after about 100 characters. | The first sentence says the outcome: "Claude cannot write code before you approve the intent." |
| Page text | The README | The first screen has the outcome, an image with alt text and the install steps. |
| Links | Link fields in `plugin.json`. The directory reported `documentationUrl`, `supportUrl` and `privacyPolicyUrl` as unrecognized fields. | None since 9.6.5: `plugin.json` has no link fields, only `homepage` and `repository` (the GitHub page). The README links the docs site and the privacy page, and the privacy page goes in the form. |
| Search words | The `keywords` field | Words a person types: sdlc, tdd, code-review, guardrails, quality-gates. |
| New versions | The tracked branch. Raise `version` in `plugin.json` with every release. | Set up the GitHub push webhook in the developer portal so a merge reaches the listing without waiting for the schedule. |

You cannot apply for the Verified label or for a place in the directory. Anthropic decides both
during review. What you control is a clean review (no held files, no unclear behavior), a clear
listing and a smooth first install.

## What the directory holds, and why

The directory scans every file of the tracked branch (`main`) as plugin code, the test suite
included, and names sample locations (often only one) for each kind of finding. Its reader is not the one in
`claude plugin validate`, so a fix cannot be checked offline: the validator passing proves only that
Claude Code itself accepts the plugin.

| Kind of finding | Answered by |
|---|---|
| This plugin includes a mod | Always a reviewer. Nothing in the code clears it. |
| The game's file path, scripts it cannot confirm leave the mod unchanged | Code: see the 9.6.4, 9.6.5 and 9.6.6 entries in `CHANGELOG.md`. Keep `module:` a fixed string outside JSX (cleared on 9.6.4). Since 9.6.5 no script, command or instruction names a file of the mod, the hooks file or a file of the mod's tests, even to read it (9.6.4 still had `check-original-options.sh` read the action table, and it was flagged), and docs and history describe them by role. Two files name them because they must: the plugin's hooks file loads the mod, and `tsconfig.mod.json` includes the mod's tests folder whole for the type check, which reaches every mod file through the tests' imports. Folders that shared a name with one of the mod's were renamed: the guard scripts are in `scripts/guards/`, the pack is `guardrails`, and the OCR notes are in `docs/plans/ocr-notes/`. Git's hook folders (`.git/hooks`, a `core.hooksPath` folder) share the name of the folder that holds the mod, and git's name cannot change, so since 9.6.6 the commit gate installer writes into no folder named `hooks`: it keeps its hook in `temper-gate/pre-commit` in the repository's git folder and points `core.hooksPath` at that folder, and it only reads git's hook folders. No test writes into one either: a test that needs hooks of the user's in git's default folder runs a copy of the installer that reads a folder named `default-gate` instead, and `scripts/validate-directory.sh` fails when a shell or Python script writes into, removes from, moves, links or makes a path with a folder named `hooks` in its own words, also through `git rev-parse` in a `$( )` span, a `cd` into the folder or a variable set to such a path (a name built from pieces is for review). Every plugin path is written out in full after the root, in every tracked file, tests and history included: no `..`, no wildcard, no placeholder, no second variable. Since 9.6.6 the installer holds no variable for the plugin folder by itself, only its own scripts folder or a file, plus fixed text, and decides "inside the plugin" by finding its own scripts folder above a path (a real folder, the same one by device and inode); no script builds the root variable from pieces (9.6.6 dropped the `validate-plugin.sh` rule that did). Commands, briefs and skills write the root in the braced form, the only one Claude Code fills in, followed by a tracked file. Review keeps the paths in that form and keeps names of the mod's files out. No script opens a file of the mod. Outside Temper's own repository nothing Temper runs writes into the plugin folder: the CLI refuses to run when a path it keeps run state in (the `.temper` folder, its evidence, specs and archive folders, its state files, the active spec folder) is a symlink, refuses the home folder, and refuses an installed copy of the plugin as a project. Checks of the mod go in its TS tests, which import it. |
| Prompts, commands, settings, hooks the mod uses | The README section "What the mod reads and writes". Change it in the same commit as the code. |
| Tool calls, `config.set`, `command.run`, an agent spawn in the mod's test suite | Temper's fake engine (built on Claude Code's test kit) and one test's stub spawn. Not reported on 9.6.4, once the README described them. |
| Fields the directory does not recognize | Removed in 9.6.5: `documentationUrl`, `supportUrl` and `privacyPolicyUrl`, and the `icon` field (the icon is the file `.claude-plugin/icon.png` since 9.6.6). `types` stays: Claude Code's own validator needs it for the mod's `$.state` keys. |
| Images, credentials, download and run text | Since 9.6.5 the repo holds no image but the listing icon (`.claude-plugin/icon.png`, since 9.6.6); the README loads its pictures by URL. Since 9.6.5 Share HTML review publishes only as a Claude artifact, and OCR (which sends the diff to the provider you set up) is off unless you turn it on. Temper reads no key or login, and the check stage reads no `.env` file. Apart from the mod's plugin store, it reads one place in the home folder, its own global pack folder `~/.claude/packs`, and no Claude Code file; the README's "What Temper runs and changes" says so. The mod reads the `/config` list and changes only its own two settings, through Claude Code and on your command, as the README's "What the mod reads and writes" says. `/temper:pack` takes link targets from the skills and commands the session lists and from the project's own `.claude/commands` and `.claude/skills`, not from Claude Code's plugin list. Of the Claude Code settings, `/temper:pack` and `/temper:init` read only the project's `.claude/settings.json` and `.claude/settings.local.json`, and the guardrails pack writes one of them only after you confirm. The install steps are slash commands in a text block. The docs describe the optional tools (code-review-graph, Semgrep, open-code-review) in words, with links to their own install pages. Other text of this kind is in test inputs, the Bash guard's patterns and the CI workflow (which installs Claude Code and TypeScript from npm on GitHub's runners to run the checks), explained in notes for the reviewer. |

## What is not verified

- Which categories and fields a given directory asks for. Use the form as it is today.
- The organization policy cases are tested with a simulated guard only (see the README).
