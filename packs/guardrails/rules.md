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
bash "${CLAUDE_PLUGIN_ROOT}/scripts/guards/install.sh"   # writes temper-gate/pre-commit in the git folder, sets core.hooksPath
```

Run it from the project's folder, or let `/temper:init` run it for you. It writes the hook
to `temper-gate/pre-commit` in the repository's git folder (the folder
`git rev-parse --git-common-dir` names, with symlinks followed; git never commits it, and
every linked worktree of the repository shares it), through a new file in that folder moved
into place, executable. Then it runs `git config --local core.hooksPath` with the absolute
path of that folder, so git runs that hook in every worktree of the repository, and
`git rev-parse --git-path hooks/pre-commit` names it. `--global` is still accepted and does
the same as the default, with a note on stderr.

The installer never writes into a folder named `hooks`: not `.git/hooks`, not the folder
`git rev-parse --git-path hooks` names, and not a `core.hooksPath` folder that is not
Temper's own. It reads the hook files there only to decide. Its only writes are the
`temper-gate` folder and its `pre-commit`, the `core.hooksPath` setting above, and the file
`temper-pre-commit` in the git folder, which it rewrites only when a hook of yours holds the
line Temper 9.6.5 printed (below).

With `core.hooksPath` unset, git runs the hooks in `.git/hooks` (the `hooks` folder of the
repository's git folder, which linked worktrees share); once it is set, git stops running
them. So the installer first reads `.git/hooks`. When that folder holds an
executable hook under any of git's hook names (`pre-commit`, `commit-msg`, `pre-push`,
`post-checkout` and the rest, as git-lfs, Gerrit, the pre-commit framework and lefthook
install them) other than a `pre-commit` that is an older Temper hook, or a
`pre-commit.bak.<timestamp>` that an older installer set aside, it leaves `core.hooksPath`
unset and keeps the hook. When `.git/hooks/pre-commit` calls the Temper hook (the line
below), it says so and exits 0; otherwise it refuses and names those hooks. With none of
them there, it sets `core.hooksPath`; when an older Temper hook sits at
`.git/hooks/pre-commit`, it notes that git no longer runs that file and that you can
delete it.

With `core.hooksPath` already set: when it points at the `temper-gate` folder, the
installer makes the hook current and exits 0 (it says when it updated the plugin paths in
it). When it holds Temper's older folder (the relative `.git/hooks-temper` that `--global`
set from 5.5.0 to 9.6.4, the `.git/temper-git-hooks` that `--global` set in 9.6.5, an
absolute path that ends in either, or the `temper-gate` folder of where the repository used
to be, before it was moved or renamed), the installer points it at `temper-gate` and prints
a note naming the old value. When that older folder holds other hooks git runs (`git lfs
install` writes its hooks into the folder `core.hooksPath` names), pointing it elsewhere
would stop them, so the installer leaves it, keeps the hook, and treats the `pre-commit`
there as the host hook below. A value that stays is set to this repository's own older folder
by its absolute path: a relative one, which a linked worktree cannot reach, or an absolute one of
another place, as after a move or a copy. When that folder is the
`temper-gate` folder of another repository that is still there (this one is a copy), the
installer refuses with a hint to point `core.hooksPath` at this repository's own folder; it
never tells you to change that repository's hook. Any other folder (husky's `.husky/_` or `.husky`,
lefthook, a team's `.githooks`) belongs to another tool: the installer never writes there
and keeps the hook. The host hook is the `pre-commit` file in that folder (for husky's
generated `.husky/_` folder, `.husky/pre-commit`); when it calls the Temper hook, the
installer says so and exits 0, and otherwise it refuses.

A Temper hook is stale when the CLI path embedded in it no longer exists, as after a
plugin upgrade moves the plugin folder; a stale hook fails open, and re-running the
installer writes the current path into the kept hook. A `pre-commit` from an older Temper
that git still runs (next to other hooks in `.git/hooks`, in Temper's older folder, or in
another tool's folder, where Temper 9.6.4 and 9.6.5 wrote it) is not written: the refusal
warns that git runs it in place of the kept hook, shows its stale path, and the hint says
to replace all of its lines with `#!/bin/sh` and the line below. A `pre-commit` that holds only
`#!/bin/sh` and that line runs nothing but the kept hook, so it does not count as a hook that would
stop running: once the other hooks next to it are gone, the next run points `core.hooksPath` at
`temper-gate`. When a hook an older installer set aside sits next to a `pre-commit` of yours that
git runs, the warning says to add its lines to that file, not to move it over it.

`core.hooksPath` holds an absolute path, so every worktree finds the folder. Moving or
renaming the repository, or a folder above it, leaves it naming the old place, and git then
runs no pre-commit hook until the installer runs again (`/temper` checks the hook on every
run and runs it). With this pack enabled, the in-agent commit gate below still blocks the
commits the agent makes in the meantime.

The installed `pre-commit` runs `block-secrets.sh` on the staged content (read from git's
index, which is what the commit records), then `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit`,
and blocks (exit 1) on a detected secret or a FAILing commit gate (any upstream gate not
PASS and not explicitly overridden via `${CLAUDE_PLUGIN_ROOT}/scripts/temper override`). An
absent guard script or CLI degrades to no-op. When the CLI refuses an unsafe `.temper`
folder (exit 3: a path it keeps run state in is a symlink), the hook blocks the commit
while a run is active (`.temper/build-state.json` exists, as a file or a link), showing
the CLI's reason and saying to remove the symlink; with no run active it prints a
one-line warning and lets the commit through. It skips the gate in the home folder and in
a repository inside the plugin's own folder: a folder above the repository whose `scripts`
folder is a real folder (not a symlink) and the same folder as the one that holds the CLI
the hook runs. A link to the CLI planted above a repository does not pass that test.

When the installer refuses, it prints a FAIL line, says where it kept the Temper hook,
prints one line between a BEGIN and an END line, then a one-line hint, and exits 1. The
line is:

```sh
_temper_rc=$?; [ "$_temper_rc" -eq 0 ] || exit "$_temper_rc"; _temper_hook="$(git rev-parse --git-common-dir)/temper-gate/pre-commit"; [ ! -f "$_temper_hook" ] || bash "$_temper_hook" || exit 1
```

It holds no path of this machine, so it is safe in a tracked file. It keeps the host
hook's own result wherever it sits: when the command before it failed, it exits with that
status; otherwise it runs the Temper hook and fails only when that hook blocks. The hint
says where the line goes. husky: `.husky/pre-commit`. The pre-commit framework: a local
hook in `.pre-commit-config.yaml` (repo: local, language: system, pass_filenames: false,
always_run: true) with the entry `sh -c '<the line>'`, which the hint prints in full (the
framework runs a system hook's entry with no shell, and the line holds no single quote).
A hook from an older Temper: all of its lines replaced with `#!/bin/sh` and the line.
lefthook, which writes its hook again: a
pre-commit command in `lefthook.yml` that runs the line. Any other hook: its start or its
end (create that file, executable, if it does not exist). A refusal that comes before the
installer knows the git folder writes nothing and prints the Temper hook's own lines
instead, in a subshell, so that their exits end only the subshell and the host hook's own
result is kept.

A hook of your own counts as calling Temper when it holds that exact line, or the exact
line Temper 9.6.5 printed (the same, with `temper-pre-commit` in place of
`temper-gate/pre-commit`), with no line before it that starts with `exit` or `exec` (for
husky v9 that hook is `.husky/pre-commit`), and git can run it: a hook that is not executable
is refused with a `chmod +x` hint. husky's `.husky/pre-commit` needs no execute bit, since
husky's own hook in `.husky/_` runs it with `sh`, but that hook must be there and executable
(run `npx husky` in a fresh clone). For the pre-commit framework and lefthook, their config file
at the repository's top (`.pre-commit-config.yaml`, `lefthook.yml` and its other names) holding
the line outside a comment counts too; the installer reads only its text, so a `stages` or
`skip` setting there can still keep the line from running. When husky's `.husky/_` folder holds a `pre-commit` from an older Temper, git
runs that in place of husky's own, so the installer refuses and says to run `npx husky` first.
The installer then makes the kept hook current
(for the 9.6.5 line it also rewrites `temper-pre-commit` in the git folder with the current
hook), says the hook calls it, and exits 0. When an `exit` or `exec` line comes first, the
line never runs: the installer refuses and says to move it above that line. An older
installer moved a hook that was not Temper's aside as `pre-commit.bak.<timestamp>`, and git
does not run that file: when one is in `.git/hooks`, the installer names it in a warning and
says how to bring it back (move it back to `pre-commit` in git's own hooks folder and add the
line between the BEGIN and END lines to it). Every refusal prints a FAIL line, never a bare shell error.

A hook tool you add later needs `core.hooksPath` unset first: the pre-commit framework
refuses to install while it is set, and lefthook installs into the folder it names, which is
Temper's. So run `git config --unset core.hooksPath` before you install one. The next
`/temper` or `/temper:init` then keeps the Temper hook and prints the line to add to that
tool's hook. If a tool has already written its `pre-commit` into Temper's folder, the
installer never writes over it: it refuses and says how to move it out.
To uninstall, run `git config --unset core.hooksPath` (when it points at the `temper-gate`
folder), remove the Temper line from your own hook if you added one, and delete the
`temper-gate` folder in the git folder (and any `temper-pre-commit` that 9.6.5 left there). The
installer prints these steps.

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
| `${CLAUDE_PLUGIN_ROOT}/scripts/guards/install.sh` | n/a (installer) | **install** | Wires block-secrets + `${CLAUDE_PLUGIN_ROOT}/scripts/temper gate commit` into a native git `pre-commit` hook (the deterministic commit gate), kept in `temper-gate` in the repository's git folder with `core.hooksPath` pointing at that folder; it never writes into a folder named `hooks` |

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
