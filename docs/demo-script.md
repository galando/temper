---
title: Demo script
nav_order: 9
---

# Demo script

A 60 to 90 second walkthrough of Temper with the mod loaded. It uses the project in
`demo/password-reset`. The recording is made from `demo/temper.tape`; this page is the
shot list for the voice or captions, and for the desktop app part the tape cannot film.

## Before you record

1. Install VHS, then confirm `claude --version` prints 2.1.287 or later and that you are
   signed in.
2. From the root of a Temper clone, run `vhs demo/temper.tape`. It writes the GIF into
   `demo/out/`, a folder that git ignores. Copy the result into the README image folder
   yourself. The tape is never run in CI. It costs tokens and needs an authenticated
   session, so expect a few takes.
3. For the light and dark screenshots, run `bash demo/make-screens.sh`. It writes into
   `demo/out/` as well.
4. For the game shot, run `vhs demo/game.tape`. It sends no prompt to Claude.
5. Record the desktop app part by hand (see shot 6).

## Shot list and script

Total about 80 seconds. Times are targets, not promises.

| Shot | Time | On screen | Say or caption |
|---|---|---|---|
| 1. The promise | 0:00 to 0:08 | The README title, then a terminal at the prompt in `demo/password-reset` | Claude cannot write code before you approve the intent. |
| 2. Intent | 0:08 to 0:22 | `/temper:temper Add password reset...`, the phase bar with Intent current, a drafted intent with criteria | Temper starts with the intent. Six phases are always visible: Intent, Plan, Build, Review, Check, Fix. |
| 3. A denial | 0:22 to 0:32 | The prompt "edit src/users.js now", then the refusal text ending in "Next:" | Ask for code too early and the write is refused, with the next step. This is enforced by a hook, not by a polite request. |
| 4. Approve with a key | 0:32 to 0:44 | Press 1 on the Intent band, then 1 on the Plan band | One key approves. Plan lists the files it may touch. |
| 5. Build and the pane | 0:44 to 1:05 | `/temper:temper pane`, the criteria checklist ticking, a failing test then a passing one | Build starts with a failing test. The pane shows each criterion as it passes. Touch a file outside the plan and Temper asks: add to plan, revert, or allow once with a reason. |
| 6. Desktop app | 1:05 to 1:15 | The Code tab of the desktop app with the same band and the same denial | The same mod runs in the desktop app. |
| 7. Review, Check, done | 1:15 to 1:25 | Review findings, Check passing, `git commit` allowed, `.temper/report.md` | Review and Check follow. When Check passes, commit is allowed and the report records every override and decision. |
| 8. A game while you wait (10 s, optional) | 1:25 to 1:35 | Run `/temper:temper play` (or press `8` while Claude works), press `s`, jump a block with `w`, then press `q` | Claude is busy and you wait? Play Temper Run. A banner tells you when a phase is ready. Press q to go back. |

All six phases appear: Intent (shot 2), Plan (shot 4), Build (shot 5), Review and Check
(shot 7), and Fix (say it in shot 7: a failing check sends the run to Fix, with a limit of
three loops).

## Putting the video on GitHub

A GIF inside the repository renders in the README with a normal image link. A video does not
work that way:

- A repository relative link to an `.mp4` does not play inline on github.com. It shows as
  a plain link.
- To get an inline player, upload the `.mp4` through the GitHub web editor, or drag and
  drop it into an issue or pull request comment. GitHub turns it into a
  `github.com/user-attachments/...` URL. Put that URL on a line of its own in the README
  and GitHub renders it as a player.

## What was not verified

- The tape has not been run. The Sleep times are estimates and will need tuning.
- The game tape has not been run. The game was verified by hand on the terminal only, with the
  keyboard (s, w, q). It exists on the terminal and the desktop app only.
- The desktop app shot depends on how you load a local plugin folder into the desktop
  app, which the author did not verify (see `docs/mods-testing.md`).
- The `user-attachments` behaviour above is described from how GitHub works today. It was
  not tested from this repository.

## Desktop screenshot and the video (yours to record)

The terminal GIF and the six terminal screenshots are regenerated with VHS (`vhs demo/temper.tape`
and `bash demo/make-screens.sh`) into `demo/out/`. The desktop app cannot be recorded that way, so
two images are left for you.

1. Open the Claude desktop app, choose the Code tab, and open a copy of `demo/password-reset`
   prepared with `bash demo/demo-seed.sh` (it creates `/tmp/pr-demo`). Load the Temper clone as a
   plugin folder for that session; how a local plugin folder is loaded in the desktop app is not
   verified here, see the desktop section of `docs/mods-testing.md`.
2. Run `/temper:temper mode full`, take a screenshot in light and again in dark, and save them as
   `desktop-light.png` and `desktop-dark.png`, and put them in the README image folder next to
   the other mode images.
3. Add one more row of two Markdown images (dark, then light) to the table under "The three
   modes" in the README. Do not use raw HTML: the plugin directory does not render it.

