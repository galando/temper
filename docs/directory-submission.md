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

## Check by hand

- [ ] `claude plugin validate --strict .` passes.
- [ ] `claude plugin test .` passes.
- [ ] The version in `plugin.json` matches the top entry of `CHANGELOG.md`.
- [ ] The README images load on the GitHub page (open the page and look). The repo holds no
      image since 9.6.5, so they load by URL.
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
- Tests, lint and git run through Claude's own tools and permissions.
- The optional game keeps one number, the best score, in the plugin store.

## What the listing shows

The directory builds the listing from `plugin.json` and the README. It has no other form fields
for marketing. These facts come from the Anthropic plugin documentation and from what the
directory reported on earlier versions.

| Listing part | Where it comes from | What Temper does |
|---|---|---|
| Icon | The `icon` field in `plugin.json`, a path to an image file in the plugin | None in 9.6.5. The repo holds no image, so `plugin.json` has no `icon` field and the card shows the plain plug icon. From 9.5.0 to 9.6.4 it was an orange T on a dark square. |
| Short description | The `description` field. A card cuts it after about 100 characters. | The first sentence says the outcome: "Claude cannot write code before you approve the intent." |
| Page text | The README | The first screen has the outcome, an image with alt text and the install steps. |
| Links | Link fields in `plugin.json`. The directory reported `documentationUrl`, `supportUrl` and `privacyPolicyUrl` as unrecognized fields. | None in 9.6.5: `plugin.json` has no link fields, only `homepage` and `repository` (the GitHub page). The README links the docs site and the privacy page, and the privacy page goes in the form. |
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
| The game's file path, scripts it cannot confirm leave the mod unchanged | Code: see the 9.6.4 and 9.6.5 entries in `CHANGELOG.md`. Keep `module:` a fixed string outside JSX (cleared on 9.6.4). Since 9.6.5 no script, command, config or instruction names a file of the mod, the plugin's hooks file or the mod's tests, even to read it (9.6.4 still had `check-original-options.sh` read the action table, and it was flagged). The folders that shared the name "hooks" with the mod's were renamed: the guard scripts are in `scripts/guards/` and the pack is `guardrails`. Every plugin path is written out in full after the root: no `..`, no wildcard, no placeholder, no second variable. Checks of the mod go in its TS tests, which import it. |
| Prompts, commands, settings, hooks the mod uses | The README section "What the mod reads and writes". Change it in the same commit as the code. |
| Tool calls, `config.set`, `command.run`, an agent spawn in the mod's test suite | Temper's fake engine (built on Claude Code's test kit) and one test's stub spawn. Not reported on 9.6.4, once the README described them. |
| Fields the directory does not recognize | Removed in 9.6.5: `documentationUrl`, `supportUrl` and `privacyPolicyUrl`, and `icon` with the images. |
| Images, credentials, download and run text | Since 9.6.5 the repo holds no image; the README loads its pictures by URL. The rest is text in docs, tests and the Bash guard's patterns, explained in notes for the reviewer. |

## What is not verified

- Which categories and fields a given directory asks for. Use the form as it is today.
- The organization policy cases are tested with a simulated guard only (see the README).
