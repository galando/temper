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
| No text file names the bundled assets folder outside a link target | Image files may move. Tapes and screenshots write into `demo/out/`. |
| No `options` key in `plugin.json` or `marketplace.json` | A settings field with options stops the plugin loading before Claude Code 2.1.271. |
| `plugin.json` has a description, keywords and a version | The listing uses them. |
| `marketplace.json` lists the same plugin | The names must match. |
| A LICENSE file exists | The directory shows the license. |

## Check by hand

- [ ] `claude plugin validate --strict .` passes.
- [ ] `claude plugin test .` passes.
- [ ] The version in `plugin.json` matches the top entry of `CHANGELOG.md`.
- [ ] The README images load on the GitHub page (open the page and look).
- [ ] The hero GIF shows the real mod. The game picture is a placeholder until you record
      `demo/game.tape`.
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
> writes that do not belong to the current phase, draws a phase bar, and writes a report.

Data and permissions, in plain words:

- No network calls and no telemetry.
- The mod reads and writes files under `.temper/` in your project. It never edits your code.
- Tests, lint and git run through Claude's own tools and permissions.
- The optional game keeps one number, the best score, in the plugin store.

## What is not verified

- Which categories and fields a given directory asks for. Use the form as it is today.
- The organization policy cases are tested with a simulated guard only (see the README).
