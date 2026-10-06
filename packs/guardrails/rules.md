---
phases: []
---

# Guardrails Pack

**Version:** 2.0.0
**Last Updated:** 2026-07-19

Deterministic safety net for Temper. Unlike the model-driven advisory checks in
review/check, these guard scripts are plain bash: they block on a *detected* violation with a
non-model exit code and no-op when their inputs are absent. They are the determinism layer.

**`phases: []` is deliberate.** This file is install-and-behaviour documentation read by
`/temper:pack` and by humans — there is nothing here for a stage agent to apply, because
enforcement happens in bash at edit- and commit-time whether or not any prompt mentions
it. Loading it into Plan/Build/Review/Check would spend context on instructions no stage
can act on.

**v7:** the commit-time gate is now the CLI's commit gate, `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit`. It reads
the evidence ledger written by every stage (`${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence add`) and computes PASS/FAIL
per gate, rather than checking a single `build-state.json` stage field. `verify-tests-ran.sh`
is kept as a fallback for a project that installed only this pack, without the CLI.

**Plugin-shipped subset (v8):** the standalone-stage gate pair (`stage-marker.sh` and
`verify-stage-gate.sh`) ships in the plugin's own hooks file, so every install of the
Temper plugin, `--plugin-dir` or marketplace, gets that guarantee with **no settings
merge and no pack enablement**. Enabling this pack adds the other guards: secrets,
protected paths, the regression test, the override prompt, the formatter, imports and
the in-agent commit gate. The settings blocks never list the stage-gate pair, so it runs
once per event.

## Install

There are **two** layers, and both are needed for the full guarantee:

### 1. In-agent layer: project settings hooks (Edit, Write, Bash)

```
/temper:pack enable guardrails
```

This asks which project settings file to use: `.claude/settings.local.json` (personal,
the default, because each command holds this machine's plugin folder) or
`.claude/settings.json` (shared with everyone who works on the project; a teammate whose
plugin sits in another folder sees those commands as stale). It shows the change, and on your confirmation merges the hook blocks of
`${CLAUDE_PLUGIN_ROOT}/packs/guardrails/settings-guardrails.json` into that file. Hooks in a
settings file get no CLAUDE_PLUGIN_ROOT variable, so each command written there is the
word `bash`, a space, and then, in double quotes, the plugin's absolute folder followed by
`/scripts/guards/` and the script's file name. Temper never reads or writes your home
settings, so the command refuses to run when the project folder is your home folder, and
it refuses an installed copy of the plugin and a folder inside the plugin folder too (it
asks the temper CLI, which refuses those folders). When you pick
`.claude/settings.local.json` and git neither tracks nor ignores that file, the same
confirmation offers to add it to the project's `.gitignore` (once: a line that is already
there is not added again), and this machine's plugin folder stays out of commits once git
ignores the file. A `.gitignore` line does not stop git from committing a file it already
tracks, so for a tracked file no line is offered and the confirmation says that
`git rm --cached .claude/settings.local.json` stops tracking it.

The blocks fire when the **agent** edits or writes files (block-secrets, the regression
test guard and the protected paths guard on every Edit/Write, then the import check and
the formatter after it) or runs Bash (block-secrets, the commit gate and the override
prompt on every Bash call; the commit-gate check is a no-op unless the command is a
`git commit`). The merge is additive: it keeps your other hooks, and it replaces an
earlier Temper guard entry instead of adding a second one. A Temper guard entry is a
hook command that names one of the guard script files, under the current plugin folder,
or under an earlier plugin folder or the guard scripts folder of versions before 9.6.5
outside your project. The same change removes the Temper guard entries from the other
project settings file, so none is left behind there. A copy of a guard script inside
your project, or one named through a relative path or the CLAUDE_PROJECT_DIR variable,
is yours and is never touched. It also adds `guardrails` to `packs:`. To uninstall, run
`/temper:pack disable guardrails`: it removes the Temper guard entries from both project
settings files and the `packs:` entry.

The commands hold the plugin folder as it was when you enabled the pack. A plugin upgrade
moves that folder, and the commands then run an old or missing copy of the guard scripts
(Claude Code keeps an earlier version's folder for a while after an upgrade, so the old
copy can go on running). `/temper:pack` and `/temper:init` list the Temper guard entries
with `${CLAUDE_PLUGIN_ROOT}/scripts/guard-entries.py`, which reads only the two project
settings files and marks an entry stale when its script lies outside the current plugin
folder or does not exist. When one is stale, they ask, as a question of its own, whether
to replace them with the current guardrails set: the whole current set is written, after
the change is shown, in place of every Temper guard entry in both files.

To copy the blocks by hand instead, take the `hooks` object of
`${CLAUDE_PLUGIN_ROOT}/packs/guardrails/settings-guardrails.json` and, in every command, put
the plugin's absolute folder (the folder that holds `scripts/guards`) in place of the
CLAUDE_PLUGIN_ROOT variable, in double quotes as above.

### 2. Commit-time layer — native git pre-commit hook (REQUIRED for deterministic blocking)

Claude Code's `settings.json` has **no `PreCommit` event** — only `PreToolUse`,
`PostToolUse`, `Stop`, `Notification`, `SubagentStop`, `PreCompact`, `SessionStart`,
`SessionEnd`, `UserPromptSubmit`. A `settings.json` block therefore **cannot** deterministically
block a raw `git commit`. The only gate that fires on every commit — agent-driven or not —
is a real git hook. Install it:

```
bash "${CLAUDE_PLUGIN_ROOT}/scripts/guards/install.sh"           # writes pre-commit in git's hooks folder
bash "${CLAUDE_PLUGIN_ROOT}/scripts/guards/install.sh" --global  # writes .git/temper-git-hooks/pre-commit
```

Run it from the project's folder, or let `/temper:init` run it for you. Without `--global`
it asks git where hooks go and writes the `pre-commit` file there (the file
`git rev-parse --git-path hooks/pre-commit` prints): the repository's hooks folder, or the
folder an existing `core.hooksPath` names (husky and lefthook set one, and git then ignores
the default hooks folder) when that folder lies inside the repository or inside the
repository's own git folder. In a linked worktree or a submodule git names the hooks
folder of the repository's own git folder, which the worktrees share: when that folder
already holds a current Temper hook, the installer says it is already installed for this
worktree and exits 0; otherwise it installs there. A relative `core.hooksPath` through
`.git` names a folder that cannot exist in a linked worktree or a submodule (`.git` is a
file there), so the installer refuses it there and points to `--global`.

`--global` runs in the main checkout. It writes `.git/temper-git-hooks/pre-commit` and sets
the repository's `core.hooksPath` to the absolute path of that folder, so every linked
worktree of the repository uses the same hook. It refuses when `core.hooksPath` is already
set to another folder (replacing it would switch the hooks there off; the default mode
installs into that folder instead). It also refuses when `.git/hooks` holds an executable
hook that git would stop running once `core.hooksPath` is set: any hook git knows by name
(`pre-commit`, `commit-msg`, `pre-push`, `post-checkout` and the rest, as git-lfs and
Gerrit install them), except a Temper `pre-commit`. It names those hooks and says to run
the installer without `--global`.

A `core.hooksPath` that is absolute and ends in `/.git/temper-git-hooks` but is not this
repository's own folder is Temper's own `--global` setting from where the repository used
to be, before it was moved or renamed; git then runs no pre-commit hook. `--global`
replaces it and prints a note naming the old value. The default mode refuses it and says
to run the installer with `--global` to point it here, or to unset `core.hooksPath`.

A Temper hook is stale when the CLI path embedded in it no longer exists, as after a
plugin upgrade moves the plugin folder; a stale hook fails open, and re-running the
installer writes the current path.

The installed `pre-commit` runs `block-secrets.sh` on the staged content (read from git's
index, which is what the commit records), then `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit`,
and blocks (exit 1) on a detected secret or a FAILing commit gate (any upstream gate not
PASS and not explicitly overridden via `${CLAUDE_PLUGIN_ROOT}/scripts/temper override`). An
absent guard script or CLI degrades to no-op. When the CLI refuses an unsafe `.temper`
folder (exit 3: a path it keeps run state in is a symlink), the hook blocks the commit
while a run is active (`.temper/build-state.json` exists, as a file or a link), showing
the CLI's reason and saying to remove the symlink; with no run active it prints a
one-line warning and lets the commit through.

The installer never writes over a `pre-commit` hook that is not Temper's (husky,
lefthook, the pre-commit framework, a hand-rolled one), and never writes a hook file git
tracks (husky v5 to v8 keep `.husky/pre-commit` in git, and so does a team's `.githooks`
folder). It refuses instead, and it does the same when `core.hooksPath` lies outside the
repository. First it writes the full Temper hook to the file `temper-pre-commit` in the
repository's own git folder (the folder `git rev-parse --git-common-dir` names, which git
never commits; never the plugin folder), through a new file moved into place. Then it
prints a FAIL line, says where it kept the Temper hook, prints one line between a BEGIN
and an END line, then a one-line hint, and exits 1. The line is:

```sh
_temper_rc=$?; [ "$_temper_rc" -eq 0 ] || exit "$_temper_rc"; _temper_hook="$(git rev-parse --git-common-dir)/temper-pre-commit"; [ ! -f "$_temper_hook" ] || bash "$_temper_hook" || exit 1
```

It holds no path of this machine, so it is safe in a tracked file. It keeps the host
hook's own result wherever it sits: when the command before it failed, it exits with that
status; otherwise it runs the Temper hook and fails only when that hook blocks. The hint
says where the line goes. husky: `.husky/pre-commit`. The pre-commit framework: a local
hook in `.pre-commit-config.yaml` (repo: local, language: system, pass_filenames: false,
always_run: true) whose entry runs the line. lefthook, which writes its hook again: a
pre-commit command in `lefthook.yml` that runs the line. Any other hook: its start or its
end. A refusal that comes before the installer knows the git folder writes nothing and
prints the Temper hook's own lines instead, in a subshell, so that their exits end only
the subshell and the host hook's own result is kept.

A hook of your own counts as calling Temper when it holds that exact line with no line
before it that starts with `exit` or `exec` (for husky v9 that hook is
`.husky/pre-commit`). The installer then makes `temper-pre-commit` current, says the hook
calls it, and exits 0. When an `exit` or `exec` line comes first, the line never runs: the
installer refuses and says to move it above that line. An older Temper hook is replaced by
one that holds the current paths; the warning about its old path says it was failing open
only when that path no longer exists. An older installer moved a hook that was not
Temper's aside as `pre-commit.bak.<timestamp>`, and git does not run that file: when one
sits next to the hook, the installer names it in a warning and says how to bring it back
(move it back to `pre-commit` and add the line between the BEGIN and END lines to it; the
installer writes `temper-pre-commit` first, so that line works). Every refusal prints a
FAIL line, never a bare shell error.

> **This two-layer split is the determinism guarantee.** Layer 1 catches secrets at
> edit-time inside the agent; layer 2 catches them at commit-time, deterministically,
> independent of the agent. Without layer 2, the pack's headline SC-8 guarantee
> ("commit with a hard-coded secret blocked deterministically") is unreachable.

## Degradation Contract (Critical)

Every hook in this pack follows two non-negotiable rules:

1. **Absent script → no-op.** If the guardrail script a hook names is missing, the hook
   event must `exit 0` and block nothing. Missing tooling never blocks a commit.
2. **Internal error → fail-open (exit 0).** A bug or unexpected input in the script itself
   must NOT block the workflow. Only a *detected violation* (secret, forbidden import, check
   not green) is the fail-closed path.

The single fail-closed path for each script is documented below. Everything else is fail-open.

## Hook Catalog

| Script | Event | Default action | Fail-closed when |
|--------|-------|----------------|------------------|
| `${CLAUDE_PLUGIN_ROOT}/scripts/guards/block-secrets.sh` | PreToolUse / native pre-commit | **BLOCK** | As an in-agent hook: the text the call adds (Write content, the new text of an Edit or MultiEdit, a Bash command) matches a secret pattern. As the native pre-commit hook: the staged content of a file (read from git's index) matches one. Patterns: AWS `AKIA...`, GitHub `gh[ps]_...`, private-key header, `sk-ant-...` / `sk-proj-...` / OpenAI legacy |
| `${CLAUDE_PLUGIN_ROOT}/scripts/guards/block-forbidden-imports.sh` | PostToolUse | **warn** (no-op by default) | An edited file imports a name on the explicit denylist (empty by default) |
| `${CLAUDE_PLUGIN_ROOT}/scripts/guards/protect-regression-test.sh` | PreToolUse (Edit\|Write) | **BLOCK** | A /temper:fix run edits the regression test it recorded at RED (`state.regression_test`) — the fix loop's own check must not be weakened by the agent running it |
| `${CLAUDE_PLUGIN_ROOT}/scripts/guards/block-protected-paths.sh` | PreToolUse (Edit\|Write) | **BLOCK** (no-op by default) | The edited file matches a `protect: paths:` pattern in temper.config (generated classes, frozen packages) — enforced at edit time, every mode, not just at the autonomous commit gate |
| `${CLAUDE_PLUGIN_ROOT}/scripts/guards/confirm-override.sh` | PreToolUse (Bash) | **ASK** | The command invokes `${CLAUDE_PLUGIN_ROOT}/scripts/temper override`: it emits `permissionDecision: "ask"` so a human explicitly approves the one command that clears a FAIL gate; the override entry itself records the git identity (`by`) |
| `${CLAUDE_PLUGIN_ROOT}/scripts/guards/run-formatter.sh` | PostToolUse (Edit\|Write) | **format** (no-op by default) | Never blocks — runs `format: cmd:` from temper.config on each edited file so drift never accumulates; a formatter failure is a stderr warning, not a gate |
| `${CLAUDE_PLUGIN_ROOT}/scripts/guards/block-uncommitted-gate.sh` | PreToolUse (Bash) | **BLOCK** | The agent runs `git commit` and `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit` FAILs (in-agent mirror of the native hook, below). A CLI refusal of an unsafe `.temper` folder (exit 3) blocks while a run is active (`.temper/build-state.json` exists, as a file or a link) and says to remove the symlink; with no run active it is a one-line warning, not a block |
| `${CLAUDE_PLUGIN_ROOT}/scripts/guards/stage-marker.sh` | UserPromptSubmit (plugin hook, always on) | **no-op** (records only) | Never: it writes `.temper/pending-stage.json` when a `/temper:intent`, `/temper:plan`, `/temper:design`, `/temper:build`, `/temper:review` or `/temper:check` prompt is submitted, and blocks nothing |
| `${CLAUDE_PLUGIN_ROOT}/scripts/guards/verify-stage-gate.sh` | Stop (plugin hook, always on) | **BLOCK** | A standalone stage session tries to end while `.temper/gates.json` has no verdict (PASS *or* FAIL both satisfy it) for the marked stage (see `${CLAUDE_PLUGIN_ROOT}/docs/decisions/0005-deterministic-stage-gate-enforcement.md`). Fails open after 2 refusals |
| `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit` | native pre-commit | **BLOCK** | Any stage's evidence-backed gate is not PASS and has no recorded `${CLAUDE_PLUGIN_ROOT}/scripts/temper override` |
| `${CLAUDE_PLUGIN_ROOT}/scripts/guards/verify-tests-ran.sh` | native pre-commit (fallback) | **BLOCK** | `.temper/build-state.json` shows the latest `check_complete` absent or failed — used only when the temper CLI isn't present |
| `${CLAUDE_PLUGIN_ROOT}/scripts/guards/install.sh` | n/a (installer) | **install** | Wires block-secrets + `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit` into a native git `pre-commit` hook (the deterministic commit gate) |

### block-secrets.sh

Conservative, high-precision pattern set (favor false-negatives over false-positives — a
broad pattern that blocks legitimate commits is a DX DoS). Detected patterns:

- AWS access key IDs: `AKIA[0-9A-Z]{16}`
- GitHub tokens: `gh[ps]_[0-9A-Za-z]{36}`
- Private key headers: `-----BEGIN ... PRIVATE KEY-----`
- Anthropic live API keys: `sk-ant-[A-Za-z0-9_-]{50,}`
- OpenAI project keys: `sk-proj-[A-Za-z0-9_-]{40,}`
- OpenAI service-account keys: `sk-svcacct-[A-Za-z0-9_-]{40,}`
- OpenAI legacy live keys: `sk-[A-Za-z0-9]{48}` (exact length)

> A bare `sk-[20+]` is deliberately **not** matched — it false-positives on documentation
> and fixture strings. Vendor-specific formats only.

What it scans depends on how it runs. As an in-agent hook (the tool call arrives as JSON
on standard input) it scans only what the call adds: the content of a Write, the new text
of an Edit or a MultiEdit, or the command of a Bash call. So a secret already staged never
blocks the calls that would remove it, and an Edit that takes a secret out passes. Only
the native pre-commit hook scans the staged files, and it reads their staged content from
git's index (what the commit records), not the copy in the work tree.

On match: `exit 2` (blocks), naming the matched text and where it was found: at commit,
the staged file that holds it; as an in-agent hook, the text the tool call adds. On no
match: `exit 0`.
On any internal error: `exit 0` (fail-open). To extend the denylist, copy the script into
your project, add your regexes to the copy's `patterns` array, and point your own
settings.json hook at the copy. Never edit the installed plugin: an upgrade replaces it.

### protect-regression-test.sh

The fix loop's self-protection. `/temper:fix` writes a regression test that must fail
before the fix (RED) and records its path with `${CLAUDE_PLUGIN_ROOT}/scripts/temper state set regression_test
<path>`. From that moment until the run's state is cleared, any agent Edit/Write
targeting that file exits 2 — the agent fixing the code cannot also weaken the check on
that code. The block message names the deliberate human release valve
(`${CLAUDE_PLUGIN_ROOT}/scripts/temper state set regression_test ""`), so a genuinely-wrong test is a person's edit
to unlock, never the fixing agent's. Outside a fix run (or with no recorded test):
no-op. Internal errors: fail-open, per the contract above.

### block-forbidden-imports.sh

Checks edited files' import statements against a configurable denylist. The denylist defaults
to **empty** → warn-only / no-op. Set `TEMPER_FORBIDDEN_IMPORTS` (colon-separated) to enable
blocking, e.g. `TEMPER_FORBIDDEN_IMPORTS="eval:child_process.exec"`. Exit 2 only on an explicit
denylist match; otherwise exit 0. (v9 fix: the hook now reads the edited file from the
PostToolUse stdin payload (`tool_input.file_path`) — it previously read only the never-set
`CLAUDE_FILE_PATH` env var plus staged files, which made it inert on in-agent edits.)

### block-protected-paths.sh

The playbook-classic build-time guardrail: paths in `protect: paths:` (temper.config) are
frozen at **edit time**, for every mode — generated classes, a legacy `v1/` package,
migrations without a ticket. Same folder-name pattern shape as `autonomy.park-on-touch`,
read via `${CLAUDE_PLUGIN_ROOT}/scripts/temper config get` (the same parser every gate uses). Empty/absent list → no-op.
Unfreezing is a human's config edit — the block message says exactly that.

### confirm-override.sh

The ASK tier, the third hook mode after allow and block. `${CLAUDE_PLUGIN_ROOT}/scripts/temper override` is the one
command that clears a FAIL gate, and it used to be reachable by the agent with nothing
deterministic in between. This hook emits Claude Code's `permissionDecision: "ask"` for any
Bash command invoking it, putting an explicit human approval click between an agent and its
own approval route; `cmd_override` additionally records the approver's git identity in the
`by` field of every overrides.json entry. Separation of duties, enforced at the exact seam
where it used to be prompt-only.

### run-formatter.sh

Runs the project's configured formatter (`format: cmd:`, with `{file}` substituted) on each
edited file, so formatting drift never accumulates across a long session. There is no
fail-closed path: a formatter failure warns on stderr and the edit stands. Absent config →
no-op.

### The commit gate (the temper CLI)

Refuses a commit if any stage's evidence-backed gate isn't PASS and has no recorded
override. Reads the project's evidence ledger (written by `${CLAUDE_PLUGIN_ROOT}/scripts/temper evidence add` throughout
the pipeline) and `.temper/gates.json` (the last-computed verdict per stage); prints the
specific unmet requirement(s). `${CLAUDE_PLUGIN_ROOT}/scripts/temper override <stage> --reason "..."` records a human
override. It stays visible in `${CLAUDE_PLUGIN_ROOT}/scripts/temper report` and the final summary, and it does not erase
the FAIL. See `${CLAUDE_PLUGIN_ROOT}/docs/getting-started.md` for the full CLI reference. Absent `.temper/`
state → `exit 0` (degrade; a repo not running `/temper` for this commit is never blocked).

### verify-tests-ran.sh (fallback)

Used only when the temper CLI isn't present. Reads `.temper/build-state.json`; if the
latest stage is not `check_complete` (or check failed), `exit 2` with "run /temper:check".
Missing/unreadable state → `exit 0` (fail-open).

## Beyond the Commit Fence: Approval Gates (example, not wired by default)

Every hook above is a **guardrail** — it allows or blocks with no human involved.
The third mode is an **approval gate**: the hook *asks*, deterministically, by
refusing until a named human authorization exists. Temper's own fence ends at
`git commit` (it never pushes, merges, or deploys), so no pack wires one — but the
pattern is the same script shape, and `${CLAUDE_PLUGIN_ROOT}/examples/gates/production-gate.sh`
is a copy-paste starting point (copy it into your project first): a PreToolUse (Bash) hook that blocks `deploy`+`production`
commands until `RELEASE_APPROVAL` names an approver and change ticket, explaining the
route to approval in its block message. Two placement rules from hard experience:

- An approval gate belongs at the **release boundary**, never in the build phase — a
  human prompt mid-build puts a person back on the critical path of every parallel
  session.
- A gate individual engineers must not be able to switch off belongs in **managed
  settings** (owned by an org admin), not the repo's `.claude/settings.json` — a
  repo-level hook can be edited by anyone who can commit.

## Extending the Denylists

- Secrets: copy `block-secrets.sh` into your project, add regexes to the copy's `patterns`
  array, and point your own settings.json hook at the copy. Never edit the installed plugin.
- Imports: set `TEMPER_FORBIDDEN_IMPORTS` in your environment or settings.json `env` block.
- Gate requirements are fixed in the plugin. Propose a change upstream (see
  `${CLAUDE_PLUGIN_ROOT}/CONTRIBUTING.md`) rather than editing the installed copy.

## Mandatory Rules (BLOCK if violated)
- Never commit a credential matching a known secret pattern (deterministic block via block-secrets.sh)
- Never commit while any stage gate is FAIL and unoverridden (deterministic block via `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit`)

## Quality Rules (WARN if violated)
- Avoid importing known-dangerous modules (eval, child_process.exec) — warn-by-default, block only on explicit denylist
