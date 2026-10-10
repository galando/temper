# Trust

Markdown, a mod written in TypeScript, about 4,400 lines of auditable bash (the CLI and the guard scripts) whose
inline Python parses and writes JSON and computes the gate requirements, and four Python scripts (about 1,000
lines, standard library only). Temper itself makes no network calls, sends no telemetry and adds no packages. The
committed artifacts (intent, plan, design, gate ledger and diff) are the audit trail, in the same commits as the code.

## What Temper runs and changes

Temper's scripts run locally with `bash`, `git` and `python3`, and write only inside your project and its git
folder. Apart from the mod's plugin store, Temper reads only one place in your home folder: its global pack
folder `~/.claude/packs`, if you made one. A pack's link targets come from the skills and commands your session lists.

- **Plugin hooks.** The plugin's hooks file registers two classic hooks and the mod module.
  `UserPromptSubmit` runs `scripts/guards/stage-marker.sh`, which notes which gate a standalone
  stage command owes. `Stop` runs `scripts/guards/verify-stage-gate.sh`, which can ask Claude to
  keep working (at most twice per stage) until that gate has a verdict. Both fail open.
- **Git hook.** On the first run `scripts/guards/install.sh` writes a `pre-commit` hook (a secret scan of the staged
  files, then `temper gate commit`) to `temper-gate/pre-commit` in the repository's git folder and points
  `core.hooksPath` at that folder, so every worktree runs it. It never writes into a folder named `hooks`. When git
  would stop running other hooks (in `.git/hooks`, Temper's older folder, or husky's or lefthook's folder), it leaves
  that setting and prints a path-free line for your hook, with a hint; 9.6.5's line still counts. After a move of the
  repository, the next `/temper` points the setting at the new place. Unset it before adding the pre-commit framework
  or lefthook. To remove, unset it, drop any Temper line, delete `temper-gate` and any 9.6.5 `temper-pre-commit`.
- **Your toolchain.** Build and check run the test, lint and type check commands of your stack (detected,
  or set in `check.commands.*` in `.claude/temper.config`) and record their exit codes as evidence.
- **Optional tools already on your machine.** OCR (open code review) is off by default. With `tools.ocr.mode`
  set to `auto` or `require` and `ocr` on your `PATH`, `/temper:review` uses it, and `ocr` sends the diff to
  the provider you set up. Temper adds no tool; the guardrails pack and autonomy run only when you ask.
- **Guardrails pack (opt in).** `/temper:pack enable guardrails` asks for the project's `.claude/settings.json`
  or `.claude/settings.local.json`, shows the change and, once you confirm, adds the guard hooks with the plugin
  folder's absolute path written in; `/temper:pack disable guardrails` removes them. `/temper:pack` and
  `/temper:init` offer to fix a guard path that no longer exists. They never touch the settings in your home folder.
- **Sharing a plan.** Share HTML review publishes the plan review only as a Claude artifact, after you confirm.
