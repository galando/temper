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
- [ ] The README images load on the GitHub page (open the page and look).
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
- The mod reads files under `.temper/` in your project and writes no file. It keeps its records in
  its own plugin store.
- Tests, lint and git run through Claude's own tools and permissions.
- The optional game keeps one number, the best score, in the plugin store.

## What the listing shows

The directory builds the listing from `plugin.json` and the README. It has no other form fields
for marketing. These facts come from the Anthropic plugin documentation.

| Listing part | Where it comes from | What Temper does |
|---|---|---|
| Icon | The `icon` field in `plugin.json`, a path to an image file in the plugin | An orange T on a dark square, 256 by 256 pixels, in the `.claude-plugin` folder. Before 9.5.0 the field was missing, so the card showed the plain plug icon. |
| Short description | The `description` field. A card cuts it after about 100 characters. | The first sentence says the outcome: "Claude cannot write code before you approve the intent." |
| Page text | The README | The first screen has the outcome, an image with alt text and the install steps. |
| Links | `documentationUrl`, `supportUrl` and `privacyPolicyUrl` in `plugin.json` | The docs site, the GitHub issues page and the privacy page. |
| Search words | The `keywords` field | Words a person types: sdlc, tdd, code-review, guardrails, quality-gates. |
| New versions | The tracked branch. Raise `version` in `plugin.json` with every release. | Set up the GitHub push webhook in the developer portal so a merge reaches the listing without waiting for the schedule. |

You cannot apply for the Verified label or for a place in the directory. Anthropic decides both
during review. What you control is a clean review (no held files, no unclear behavior), a clear
listing and a smooth first install.

## What the directory holds, and why

The directory scans every file of the tracked branch (`main`) as plugin code, the test suite
included, and names one sample location for each kind of finding. Its reader is not the one in
`claude plugin validate`, so a fix cannot be checked offline: the validator passing proves only that
Claude Code itself accepts the plugin.

| Kind of finding | Answered by |
|---|---|
| This plugin includes a mod | Always a reviewer. Nothing in the code clears it. |
| The game's file path, the scripts that name the mod's folders | Code: see the 9.6.4 entry in `CHANGELOG.md`. Keep `module:` a fixed string outside JSX, and keep scripts out of `hooks/temper-mod/`. |
| Prompts, commands, settings, hooks the mod uses | The README section "What the mod reads and writes". Change it in the same commit as the code. |
| Tool calls, `config.set`, `command.run`, an agent spawn in `tests/mod/` | The fake engine of the test kit. The README says so; a reviewer confirms. |
| Images, credentials, download and run text | Notes for the reviewer: the images are plain, and the rest is text in docs, tests and the Bash guard's patterns. |

## What is not verified

- Which categories and fields a given directory asks for. Use the form as it is today.
- The organization policy cases are tested with a simulated guard only (see the README).
