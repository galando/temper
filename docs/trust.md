# Trust

Markdown, a mod written in TypeScript, about 7,100 lines of auditable bash (the CLI and the guard scripts) whose
inline Python parses and writes JSON and computes the gate requirements, and ten Python scripts (about 3,600
lines, standard library only). Temper itself makes no network calls, sends no telemetry and adds no packages. The
committed artifacts (intent, plan, design, gate ledger and diff) are the audit trail, in the same commits as the code.

## What Temper runs and changes

Temper's scripts run locally with `bash`, `git` and `python3`, and write only inside your project and its git
folder. Apart from the mod's plugin store, Temper reads only one place in your home folder that git does not
name: its global pack folder `~/.claude/packs`, if you made one. Through git it reads the hooks folder your git
config names, which may be in your home folder; it reads no name or email from git (an accepted intent or an
override records that the person decided it at the gate). It reads no key, login, transcript, settings or other
Claude Code file. A pack's link targets come from the skills and commands your session lists.

- **Plugin hooks.** The plugin's hooks file registers two classic hooks and the mod module.
  `UserPromptSubmit` runs `scripts/guards/stage-marker.sh`, which notes that a `/temper:intent`
  session owes an intent gate (the other stage commands are doors into `/temper` and owe none).
  `Stop` runs `scripts/guards/verify-stage-gate.sh`, which can ask Claude to
  keep working (at most twice per stage) until that gate has a verdict. Both fail open.
- **Git hook.** On the first run `scripts/guards/install.sh` writes a `pre-commit` hook (a secret scan of the staged
  files, then `temper gate commit`) to `temper-gate/pre-commit` in the repository's git folder and points
  `core.hooksPath` at that folder, so every worktree runs it. The hook runs the gate of every project the commit
  touches: the top of the repository, and each folder above a staged file that holds a `.temper` folder (a project
  below the top, such as a package of a monorepo); a moved file counts at its old place and at its new one. It never
  writes into a folder named `hooks`. When git
  would stop running other hooks (in `.git/hooks`, Temper's older folder, or husky's or lefthook's folder), it leaves
  that setting and prints a path-free line for your hook, with a hint; 9.6.5's line still counts. After a move of the
  repository, the next `/temper` points the setting at the new place. Unset it before adding the pre-commit framework
  or lefthook. To remove, unset it, drop any Temper line, delete `temper-gate` and any 9.6.5 `temper-pre-commit`.
- **Your toolchain.** Build and check run the test, lint and type check commands of your stack (detected,
  or set in `check.commands.*` in `.claude/temper.config`) and record their exit codes as evidence. A grouped
  Build runs each task's declared test command in its worktree, the way your shell would.
- **Its own commits.** In a grouped Build the CLI commits each task's declared files in its worktree and merges
  them, as plain `git commit` and `git merge` calls that use git's own identity and settings (signing too, when
  you turned it on). Before one, it asks git only whether an identity is set (an exit status; git guesses none
  from your system account), and uses the fixed `Temper <temper@localhost>` when none is.
- **Optional tools already on your machine.** OCR (open code review) is off by default. With `tools.ocr.mode`
  set to `auto` or `require` and `ocr` on your `PATH`, `/temper:review` uses it, and `ocr` sends the diff to
  the provider you set up. Temper adds no tool; the guardrails pack and autonomy run only when you ask.
- **Guardrails pack (opt in).** `/temper:pack enable guardrails` prints the guard hooks, with the plugin
  folder's absolute path written in, for you to add to the project's `.claude/settings.local.json` or
  `.claude/settings.json`; `/temper:pack disable guardrails` says which to remove. Temper never opens a Claude Code
  settings file, the project's or your home folder's.
- **Sharing a plan.** Share HTML review publishes the plan review only as a Claude artifact, after you confirm.

## Temper is not a sandbox

Temper keeps a cooperating Claude on the path and makes every skip visible; it does not stop a Claude
that is set on getting around a gate. Four things hold: the CLI computes every verdict and refuses to
leave a stage whose check failed unless you skipped it with a reason; the native `pre-commit` hook
blocks a commit while a gate fails; you decide each gate in the question dialog; and the mod, when it is
loaded, refuses a move only you may make until you answered, a write onto Temper's own files, and
`--no-verify` or a changed `core.hooksPath`. The mod reads a Bash command as plain text, so a call hidden
in a variable, a string another program runs, a script on disk or a commit the hook does not check
(`git merge`, `cherry-pick`, git plumbing) gets through. [The mod](mod.md#what-the-guard-checks-and-what-it-does-not)
lists these limits, and the mod's tests hold each one, so the docs cannot claim more than the code does.
