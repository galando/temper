# Changelog

All notable changes to Temper are documented here. The plugin version lives in
`.claude-plugin/plugin.json`.

## v9.6.7: no script names a hooks folder, no plugin root variable in tests, no bundled image

The directory's report on 9.6.6 (878248e) held it for five reasons. Four are for a reviewer ("This
plugin includes a mod", the prompts the mod submits, the slash commands it runs, the settings it
sets); the README section "What the mod reads and writes" describes each. The fifth, that it
"couldn't confirm that the mod stays the same", named `scripts/guards/install.sh`,
`scripts/selftest/temper-cases-1.sh` and `temper-cases-2.sh`. It does not say which lines it
held. The same report names nine files for one note, so the three are most likely all it held, and
`temper-cases-3.sh`, which read git's hooks folder as the first two did, passed. That points at
what only the named files had. In the installer: a path that ended in a folder named `hooks`, a
wildcard over that folder, and a path built under each folder above a repository. In the first two
test files: the plugin root variable, a link to the plugin folder, and output pointed into it. This
release removes all of them, and every other path to a folder named `hooks` in a script, so neither
reading of the report is left open.

**No script names a path with a folder named `hooks`.** Git's hook folders share that name with
the plugin folder that holds the mod, and the three scripts the directory held all built or read
such a path, though none of them wrote there any more.
- The installer asks git for its own hooks folder (`git rev-parse --git-path hooks`) instead of
  building a path that ends in that folder name, and its comments name no such path.
- The tests name none either: where a case showed that the installer writes nothing in git's own
  hooks folder, it now shows that the installer writes nothing in the whole git folder but
  Temper's own `temper-gate` (a listing before and after), which is the stronger check.
- The installer refuses a `core.hooksPath` that leads into the plugin's own folder before it reads
  anything there, and builds Temper's older folders from fixed names, never from the value.
- A new rule 10 in `scripts/validate-directory.sh` fails on any shell, Python or workflow file that
  names a path with a folder named `hooks`, read or write, comments included. Run on 878248e, it
  fails on the three files the directory named and on two more test files, so it is stricter than
  the directory.

**The installer lists no folder by wildcard and builds no path under a folder it climbs to.**
- It found the hooks an older installer set aside with a wildcard after a variable
  (`"$1"/pre-commit.bak.*`), over git's hooks folder among others. It now lists the folder with
  `find` and matches each name. The remedy asks for no wildcard, and a script held in 9.6.3
  scanned a computed folder with a wildcard too.
- It told the plugin's folder by building `<folder>/scripts/guards` under each folder above a
  path, and its hook built `<folder>/scripts` the same way. Both now compare each folder with the
  plugin's own folder by device and inode, as the guard scripts and the CLI do, and build no path
  under it. A link planted above a repository still cannot pass for the plugin, because the
  folders compared are taken with every symlink followed.
- A new rule 11 in `scripts/validate-directory.sh` fails on a wildcard after a variable in any
  shell, Python or workflow file, comments included. Run on 878248e, it fails on the installer,
  `temper-cases-2.sh` and `temper-cases-4.sh` (the last was not held, so it is stricter than the
  directory). Neither test uses a wildcard there now: one lists the files with `git ls-files`,
  the other copies the folder whole.

**No test names the plugin root variable.** The guard-entries case takes the pack's own hook
command from `packs/guardrails/settings-guardrails.json` (as an entry copied by hand has it), the
confirm-override case takes the CLI's spelling from `commands/temper.md`, and the check that the
CLI and the guard scripts never read the variable takes its name from `scripts/guard-entries.py`.
Each case checks that what it took is the braced root form. No test lists plugin files by
wildcard, links the plugin folder itself, or points a script's output into it.

**No bundled image.** The 1024 px icon that 9.6.6 added holds the plugin for review, as a bundled
image did in 9.3.3. It could not become the listing icon either: the directory takes an icon only
the first time a plugin is saved or submitted, and adding or changing it later does not change the
listing (its own note on 9.6.5 says so). Temper was first submitted without one, and the developer
portal has no upload for it. The icon leaves the repository, and no text names an image file of the
repository.

**The report of a finished run can be read again.** Since 9.6.2 the mod keeps the run report in its
plugin store instead of writing `.temper/report.md`, but `/temper:temper report` answered "There is
no report to show" as soon as the Commit steps cleared the run state, so a finished run's report
could no longer be read; 9.6.0 kept the file. With no run active, `report` now shows the report kept
last in the project (a report file an older Temper wrote counts too), and says there is none only
when nothing is kept. It decides on a fresh read of the run, so a turn cut short after the clear,
or a run started since, cannot make it show or keep the wrong report, and a run held from memory
(its state file gone) is shown, marked as such, but not kept. A run the commit gate completes is
remembered as done, so once it is cleared its Done report is shown, not the phase before. Seven mod
tests drive it, two through a whole run to Done and its `state clear`; the ones for the stale cases
fail without the fix.

**A run held from memory stays enforced after a decision.** When a run's state file goes missing,
the mod keeps enforcing the last known run (as the README says). A decision word or button in that
state (approve, next, back, override, accept) made the mod take an empty snapshot as current, so
until the next refresh the phase rules let writes through and Claude was told no run was active;
the commit gate still held. The mod now keeps the held run after a decision and draws it. This is
older than 9.6.7; the review of this release found it. A new mod test fails without the fix.

**A hook tool's own hook is never written over.** lefthook, installed after Temper, writes its
`pre-commit` into the folder `core.hooksPath` names, which is Temper's `temper-gate` folder (it
renames Temper's hook to `pre-commit.old`). The next `/temper` then ran the installer, which wrote
over lefthook's hook with no copy and said the hook "was updated"; 9.6.0 always kept a copy before
it wrote. Now a `pre-commit` in Temper's folder that is not Temper's, a file or a link to one, is
never written over: the installer refuses, prints no line to add (the line runs the hook kept in
that folder), and says how to move it out, unset `core.hooksPath` and install the tool's hooks
again. It names any other hook git runs from that folder (Git LFS writes its hooks there too),
since those stop running once `core.hooksPath` is unset. A link to a Temper hook, or to nothing,
is replaced as before, never written through. The docs no longer say lefthook installs into git's
own hooks folder. Ten new installer cases cover it; the ones that refuse fail without the fix. The selftest runner also gives every case an empty standard input,
so a hook a case runs with no input of its own never waits on an open terminal.

**Changed in 9.6.5 and not said then** (found by the same audit; each is deliberate and stays):
the check stage's live scenario level no longer picks the most recently changed spec folder when
no run names one, and skips that level instead; a review rule you promote goes into the project's
copy of the pack (`.claude/packs/<name>/rules.md`), which from then on stands in for the built-in
pack, so later plugin updates to that pack's rules do not reach the project; the formatter hook no
longer formats a file outside the project folder; `temper evidence list` needs `--stage`.

`scripts/plan_review.py` (the HTML plan review) runs on Python 3.7 and 3.8 again, as in 9.6.0: 9.6.5
had used a string call that needs Python 3.9.

No test pairs a host with something that looks like a credential: the curl case in the validator's
selftest and a fake pre-commit framework hook carry no URL, and the file the secret scan's case
writes its fake key into is named `1:notes.txt`.

## v9.6.6: nothing writes into a hooks folder, readable test files, a listing icon

The directory's report on 9.6.5 (3f7df41) held it for six reasons. This release answers the two
that code can answer: a file the directory could not inspect, and two scripts it could not confirm
leave the mod the same (one reason, named for both files). The other four ("This plugin includes a
mod", the prompts the mod submits, the slash commands it runs, the settings it sets) go to a
reviewer; the README section "What the mod reads and writes" describes each of them.

**Files the directory could not inspect.** `scripts/selftest/test-temper.sh` had grown to 265 KB,
above the 256 KB the directory reads. Its cases now live in four files next to it, each well under that limit
(`temper-cases-1.sh` to `temper-cases-4.sh`), which the runner sources in order.

**The mod stays the same.**
- `scripts/validate-plugin.sh` no longer has the rule that checked plugin paths in every file: it
  assembled the plugin root variable from pieces, which the directory read as pointing at the plugin
  root. Its tests, which built the bad forms at run time, went with it, and
  `scripts/guard-entries.py` recognizes an older entry that names the root variable by the bare name.
  The test lines that name the root variable now write it in the braced form, followed by a tracked
  file and ended by a quote or a space, and no test sets or unsets the variable. The comments in the
  config template and the guardrails settings file no longer run a plugin path into a comma or a
  full stop.
- `scripts/guards/install.sh` wrote into git's folders named `hooks` (`.git/hooks`, or another
  tool's `core.hooksPath` folder), the same name as the plugin folder that holds the mod. It now
  never writes into a folder named `hooks`. It keeps Temper's hook as `temper-gate/pre-commit` in the
  repository's git folder and points `core.hooksPath` at that folder, so every worktree runs it. When
  that would stop other hooks from running (an executable hook in `.git/hooks`, another tool's
  `core.hooksPath`, or other hooks in Temper's older folder), it leaves the setting alone and prints
  the one line to add to your own hook, with a hint for husky, lefthook and the pre-commit framework
  (for the framework, the exact entry: `sh -c '<the line>'`); the line 9.6.5 printed still counts.
  `--global` now does the same as the default.
- The test files, now readable, wrote into `.git/hooks` too, about 80 times. None does now. A case
  that needs hooks of the user's in git's default folder runs a copy of the installer whose one
  `HOOKS_DIR` line names a folder called `default-gate`, and a case where git must run the user's
  hook sets `core.hooksPath` to a folder of its own. The fake older plugin's `scripts/hooks` folder
  is now `scripts/old-guards`. A new rule in `scripts/validate-directory.sh` fails when a shell or
  Python script, tests included, writes into, removes from, moves, links or makes a path with a
  folder named `hooks` in its own words, also through `git rev-parse` in a `$( )` span, `${NAME}`
  or its default, a `cd` or `pushd` into the folder (on the same line, or alone on a line before), or
  a variable (shell, or Python in a `.py` file) set to such a path earlier in the file; a name built
  from pieces is left to review.
- The installer holds no variable for the plugin folder by itself: it builds the CLI and guard paths
  from its own scripts folder. It decides whether a path is inside the plugin by finding its own
  `scripts/guards` folder above that path, and the hook it writes decides it by finding its CLI's
  `scripts` folder: real folders (not symlinks), the same folder by device and inode. A link planted
  above a repository therefore cannot skip the gate, and cannot stop an install either.

**Upgrades from older installs.**
- With nothing else in `.git/hooks` that git runs, an older Temper hook there stays where it is;
  git no longer runs it, and the installer says you can delete it.
- An older `--global` setting (`.git/hooks-temper` from 5.5.0 to 9.6.4, `.git/temper-git-hooks` from
  9.6.5) and the `temper-gate` folder of where a repository used to be are pointed at the current
  `temper-gate` folder, with a note, unless that folder holds other hooks git runs (`git lfs install`
  writes its hooks into the folder `core.hooksPath` names): then the setting stays, as for
  `.git/hooks`. A value that stays is set to this repository's own older folder by its absolute
  path, with a note: a relative value, since git takes it from each worktree's top and a linked
  worktree would run nothing, and an absolute value of another place, as after a move or a copy. When that folder is the `temper-gate` folder of another repository that is still there
  (a copy of a repository), the installer never tells you to change its hook, which is that
  repository's own; the hint is to point `core.hooksPath` at this repository's folder.
- When git still runs a `pre-commit` from an older Temper (next to other hooks in `.git/hooks`, in
  Temper's older folder, or in a team folder where 9.6.4 and 9.6.5 wrote it), the installer does not
  write it. Its refusal warns that git runs that hook in place of the kept one, shows the stale plugin
  path it carries, and the hint says to replace all of its lines with `#!/bin/sh` and the line. A
  `pre-commit` that holds only those two lines does not count as a hook that would stop running, so
  once the other hooks next to it are gone, the next run points `core.hooksPath` at `temper-gate`.
- A hook an older installer set aside as `pre-commit.bak.<timestamp>` is named on its own, not among
  the hooks git would stop running, since git does not run it. When a `pre-commit` of yours that git
  runs sits next to it, the warning says to add its lines to that file instead of moving it back over
  it.
- `core.hooksPath` holds an absolute path, so every worktree finds the folder. Moving or renaming the
  repository leaves it naming the old place, and git runs no pre-commit hook until the installer
  runs again; the next `/temper` checks the hook and runs it, which points the setting at the new
  place.
- husky's `.husky/_` folder holding a `pre-commit` from an older Temper (9.6.4 wrote over husky's
  own there) is refused: git runs that hook in place of husky's, so `.husky/pre-commit` never runs.
  The hint says to run `npx husky`, then add the line to `.husky/pre-commit`.
- A hook that holds the line counts only when git can run it: one that is not executable is refused
  with a `chmod +x` hint. husky's `.husky/pre-commit` needs no execute bit, since husky's own hook in
  `.husky/_` runs it with `sh`, but that hook must be there and executable (a fresh clone has none
  until `npx husky` or `npm install`). For the pre-commit framework and lefthook, a config file at
  the repository's top (`.pre-commit-config.yaml`, `lefthook.yml` and its other names) that holds
  the line outside a comment counts as installed; the installer reads only its text, so it says
  that a `stages` or `skip` setting there can still keep the line from running.
- The uninstall steps name the `temper-pre-commit` file that 9.6.5 may have left.
- A hook tool that installs into `.git/hooks` later (the pre-commit framework refuses while
  `core.hooksPath` is set) needs `core.hooksPath` unset first; the next `/temper` or `/temper:init`
  then prints the line to add.

**The mod.** While a run is active, the mod refuses a change to `.git/temper-gate` (the folder and
its hook), to `.git/temper-pre-commit`, or to Temper's older folders `.git/hooks-temper` and
`.git/temper-git-hooks` (git still runs hooks from one when the installer leaves `core.hooksPath` on
it) exactly as it refuses one to `.git/hooks`, and its refusal names the Temper commit hook.

**A listing icon.** A 1024 px PNG in the manifest folder: the orange T on a dark rounded square that
earlier versions showed at 256 px, below the 512 px the directory asks for. (9.6.7 took it out again:
a bundled image holds the plugin for review.)

Notes the directory listed that need no change: the credential note on `plugin.json` (a reviewer
confirms it; the mod reads Claude Code's `/config` list only to find its own two rows), the `types`
field (Claude Code's own validator needs it for the mod's `$.state` keys), and the download-and-run
notes, which sit in docs, history, test inputs, the mod's detection code and the CLI's migration of a
stage name that a v7.0.x run left behind.

## v9.6.5: nothing points at the mod, every plugin path written out, no images

The directory's report on 9.6.4 held it for five reasons. Three ask for README text the 9.6.4 README
already gives (the prompts the mod submits, the two commands it runs, the two settings it sets) and
one ("This plugin includes a mod") always goes to a reviewer. The fifth, "The directory couldn't
confirm that the mod stays the same after it's checked", named three new sample files. This release
clears that kind of finding across the whole plugin, not only in the samples, and answers the notes
it can. Three review rounds before release (independent checks of every tracked file, the new code,
the docs and the instruction text, and a real install driven through the Claude CLI) found more;
every one of those is fixed here too.

**Nothing points at the mod or its hooks file.**
- The guard scripts moved to `scripts/guards/`, and the hooks pack is now the guardrails pack
  (`packs/guardrails/`, settings snippet `settings-guardrails.json`); a `packs:` entry named `hooks`
  still means it. No folder but the mod's own is called `hooks`; the OCR notes moved to
  `docs/plans/ocr-notes/` and the shell test suites to `scripts/selftest/`, so no folder shares a
  name with one of the mod's test folders.
- No script, command, instruction or doc names a file of the mod, the hooks file or a file of the
  mod's tests; history entries name them by role. The two files that must name the mod still do: the
  hooks file loads it, and `tsconfig.mod.json` includes the mod's tests folder whole for the type
  check (one ordinary test there imports the hooks module, which reaches every file of the mod). The
  checks that read the mod moved into its TS tests, which import what they check.
- Every plugin path is fixed text after the root: no `..`, no wildcard, no placeholder, no second
  variable. Every plugin file a script opens is its plugin folder plus fixed text, a file git lists
  as tracked, or a name checked against a fixed list or pattern. The CLI and every guard script
  that needs the plugin folder find it by a literal suffix of their own location after following
  their own symlinks, and such a guard script reached any other way does nothing; the dev scripts take their own
  folder as it is. No environment variable moves it (`validate-directory.sh` lost its folder
  override), and `CDPATH` is cleared first.

**The plugin folder in instruction text.** Claude Code fills in the plugin folder only where a
command, brief or skill writes the braced form of the CLAUDE_PLUGIN_ROOT variable, and the Bash tool
does not set that variable. 9.6.4 wrote it without braces and fell back on a search of the disk; with
the search gone, a real install of the 9.6.5 draft could not find its CLI. Now:
- Every command, brief, skill, reference page, pack and template writes the braced form, with each
  path after it written out in full, and every instruction that runs the CLI names it by that full
  path (no bare `temper`, no alias). The guard scripts' messages and the mod's prompts and refusals
  name the CLI by its full path too.
- Each stage subagent's launch prompt names the plugin folder, and each brief, the orchestrator and
  `reference/orchestrator-patterns.md` ("The plugin folder") say that the variable in a page read
  with the Read tool means that folder, written out in full in a command.
- `validate-plugin.sh` checks every tracked file: it fails on the unbraced form, on a braced root with
  no path after it, on `..` or any of `[ ] < > ( ) { } * ? $ | %` after it, and on a path that is not
  a tracked file (a folder does not count). Test inputs that need a bad form build it while the test
  runs.

**No write can reach the plugin folder.** The one exception is developing Temper on its own
repository (the plugin folder is a git work tree whose top level is that folder): there the run
state goes in its `.temper/`, and `install.sh` writes only in its git folder. An installed copy is
never a project. Inside or not is decided by file identity, not by path text, so a second spelling
of the folder (a case-insensitive disk, a bind mount, a doubled slash) changes nothing.
- `scripts/temper` checks every stage name against a fixed list before it builds a path, checks the
  slug of `state init` and any `spec_path` it stores, no longer honours a `TEMPER_DIR` override, and
  reads the evidence files by name instead of a glob. Before this, a crafted stage name could
  overwrite a file outside `.temper/`. It refuses to run from a folder inside the plugin folder or
  from the home folder, and refuses (exit 3) when a path it keeps run state in is a symlink (the
  `.temper` folder, its evidence, specs and archive folders, its state and evidence files, the active
  spec folder and its gate ledger), so no write can follow a link out of the project. While a run is
  active the commit hooks block on that refusal and say to remove the link; with no run they pass
  with a warning. `config`, `model` and the help text only read, so they still answer.
- A slug (for `state init`, a bug, a ticket key prefix) is letters of either case, digits, `.`, `_`
  and `-`, starting with a letter or digit, with no `/` and no `..`. A 9.6.4 run named like
  `PROJ-123-login` keeps working. When `state archive`, `state clear` or `state init` cannot archive
  the gate ledger (a `spec_path` that is not `.temper/specs/<slug>`, or a spec folder that is a link),
  they say so instead of skipping it silently.
- Two places in the CLI handed a value to Python as program text (the coverage threshold check and
  `temper report`); both now pass it as an argument, so a crafted threshold can no longer run code
  and `temper report` works from a project folder whose name holds a quote.
- `install.sh` asks git where the hook goes (`git rev-parse --git-path hooks`): the repository's
  hooks folder, a `core.hooksPath` folder inside the repository or its git folder, or, in a linked
  worktree or a submodule, the shared hooks folder of the repository's own git folder (a second run
  there says it is already installed). It never writes over a pre-commit hook that is not Temper's,
  never writes a file git tracks, and never writes into a `core.hooksPath` folder outside the
  repository. Then it keeps Temper's hook as `temper-pre-commit` in the repository's git folder
  (never committed) and prints one line to add to your own hook, between BEGIN and END marker lines,
  with a hint for husky, lefthook and the pre-commit framework; `/temper:init` and the first
  `/temper` run show it in a code block. The line holds no path of this machine, so it is safe in a
  tracked husky file, and it keeps your hook's own result wherever it sits. A later run sees the line,
  refreshes the kept hook, and refuses a line that sits after an `exit` or `exec`. An older Temper
  hook is replaced, and a backup an older version left is named, with how to restore it. With
  `--global` it sets `core.hooksPath` to the absolute `temper-git-hooks` folder in the repository's
  git folder, so linked worktrees use it too; it refuses when `core.hooksPath` names another folder
  or `.git/hooks` holds a hook git would stop running (a `commit-msg` or a `pre-push`, for example),
  and it repairs its own setting after the repository moved.
  It follows every symlink before it creates anything, refuses a target that leads outside the
  repository and its git folder or into the plugin folder, refuses a repository inside the plugin
  folder, ignores every `GIT_*` variable, and writes through a temporary file, so a linked
  `pre-commit` is replaced, never written through. Every refusal prints a FAIL line and what to add.
  The hook holds the full paths of the CLI and the two guard scripts as plain text, fails open when
  python3 is missing (the secret scan still runs), and skips the gate in a repository inside the
  plugin folder or at the home folder.
- `block-secrets.sh` as an agent hook scans only what a call adds (the written text, an edit's new
  text, a Bash command); only the commit hook scans what is staged, from the index, and names the
  file. Before, one staged secret refused every later call, including the one that would unstage it,
  and a secret staged and then removed from the working copy got committed.
- `run-formatter.sh` never formats a file inside the plugin folder, and passes the file name to
  `format.cmd` as an argument: before, a file whose name held shell text ran that text.
- `plan_review.py` refuses an output inside the plugin folder (its own `.temper/` excepted in the
  plugin's own repository). `stage-marker.sh` and `verify-stage-gate.sh` do nothing in a folder
  inside the plugin folder, in an installed copy, or through a `.temper` folder or marker that is a
  symlink, and the stage gate log is now `.temper/stage-gate.log`. `block-uncommitted-gate.sh`
  skips a repository inside the plugin folder.
- The config reader takes off one pair of matching quotes around a whole value only, so a
  `format.cmd` that ends in `"{file}"` keeps its closing quote.

**The Bash guard.** A shell, `source` or `.` that reads its program from standard input is refused
like a pipe into a bare shell, in any spelling of the path: `/dev/stdin`, `/dev/./stdin`, `/dev/fd/N`,
`/proc/self/fd/N` and the like, a relative path read against the folder the command moved to, a
variable of any name length, a startup file given with `--rcfile` or `--init-file` or through
`BASH_ENV` or `ENV`, and `xargs` running a shell with no visible program. An interpreter that reads
its program from standard input is refused only when the program names the Temper script. A redirect
from `/dev/null` or a `<` inside quotes no longer counts as feeding a shell. A refused call whose
Temper subcommand is written as a variable now says that, instead of claiming it holds a decision
word, and a write to an unknown `.temper` path gets the run folder's reason. Which calls are refused
is otherwise unchanged.

**The mod's prompts and the trivial path.** The prompts the mod submits on a press (Stop, Commit,
the plan review buttons) and the next step in its refusals name the CLI and the plugin's files by
the full path the mod already knew, so they work in a fresh session; Commit names the slash command.
The trivial exit works with the mod on: it allows `state clear` only for a run that never left
Intent (no completed stage, no verdict or override, none of `intent.md`, `plan.md`, `tasks.md` and
`design.md` in the spec folder, and no advance or loop back recorded), since such a run has nothing
to lose. With enforcement off, a decision word from any origin, a `claude -p` run included, is
accepted and its origin recorded; with enforcement on, only a person in an interactive session
decides, and the refusal says so.

**The guardrails pack works.** Hooks in a settings file get no plugin folder, so the merged guard
commands ran nothing. `/temper:pack enable guardrails` now asks which project settings file to use
(`.claude/settings.local.json` by default, since each command holds this machine's folder, with an
offer to add it to `.gitignore` when git neither ignores nor tracks it; or `.claude/settings.json`),
shows the
change, and on confirmation writes each guard command with the plugin's absolute folder in double
quotes, replacing any earlier Temper guard entry in either file. `/temper:pack disable guardrails`
removes them from both. `/temper:pack` and `/temper:init` run `scripts/guard-entries.py`, which reads
only the two project settings files and lists the Temper guard commands that point anywhere but the
current plugin folder (a path from before 9.6.5, or an earlier plugin version's folder), and then ask
whether to replace them with the current set. A guard command that names its script through the
project is the user's own copy and is never touched. The two stage gate hooks left the settings
block: the plugin's own hooks already run them, so they fired twice. The guardrails pack never reads
or writes the settings in your home folder, and refuses the home folder, an installed copy of the
plugin and a folder inside it as the project.

**Gates, commands and checks.**
- The intent gate no longer counts the second line of a placeholder as content, and a missing Status
  header no longer prints Python's `None` in its rows.
- `/temper:init` no longer reports a flat `models:` block (the live override for each stage) as retired;
  only the v6 `models.routing` and `models.tiers` keys are.
- The `Temper enforcement: off (UI only)` line has its own first sentence ("turned off by the user"),
  said once in the main conversation: stage briefs no longer guess, since a subagent never sees the
  mod's line. The gate's waiting line names the typed `/temper:temper` words, since minimal and off
  modes draw no buttons.
- Each brief returns one panel, with everything the orchestrator reads inside it or on a plain line
  after it; step references in the commands point at steps that exist; a plan review note goes into
  `plan.md`, never into the CLI's state file; `/temper:fix` stages named paths and commits in a second
  call.
- The check stage decides whether it runs against production from a config key and file names only;
  it never opens a `.env` file.
- `validate-panels.py` and `validate-docs.sh` again fail on a brief or command file that
  `plugin.json` does not list.

**Notes the directory listed.**
- No image ships in the repository: the README and the website (its social preview included) load
  their pictures by permanent links to an earlier commit, and `plugin.json` has no `icon` field, so
  the directory card shows the default icon. Test data names no image file.
- `plugin.json` drops `documentationUrl`, `supportUrl` and `privacyPolicyUrl`, which the directory
  reported as unrecognized; each option is marked as not sensitive. `types` stays: Claude Code's own
  validator needs it for the mod's `$.state` keys.
- Credentials and Claude Code files: Share HTML review shares only through a Claude artifact (the
  fallback that used the GitHub command line's login is gone). The OCR reviewer is off by default and
  runs only when `tools.ocr.mode` is `auto` or `require` (a missing key reads as off; a project config
  that already says `auto` keeps it on). Pack discovery reads no Claude Code file: it lists only the
  project's own commands and skills, and links to plugin and personal skills and commands come from
  the list the Claude session already shows. Outside the project, Temper's scripts read only its own
  global pack folder, `~/.claude/packs`; the mod reads its plugin store and Claude Code's `/config`
  list and sets its own two settings, as the README says. Test inputs, docs and history show no
  command that reads the user's keys, logins or Claude Code files.
- Download and run: install steps are slash commands; other tools' installs are described in words
  with a link to the tool's own page; `npx` lines say `--no-install`; docs, comments and test inputs
  describe the guard's patterns in words where a literal adds nothing; the guard's detection itself
  is unchanged. The CI workflow installs its own tools. The unused Jekyll files (`docs/Gemfile`,
  `docs/_config.yml`) and the website step that restored an image nothing links are gone.
- The mod's comments name no engine call the mod does not make, and its message text no longer
  spells one shell builtin; the three places in the Bash guard that detect that builtin keep it. The
  mod now fails open, and says so, on the stage name a v7.0.x run left behind, until the CLI's next
  call rewrites it.
- The throwaway spec files under `.temper/specs/` are no longer tracked, as `.gitignore` intends.
- Docs: the README quick start leads with `/temper:temper` (the short form may not resolve in every
  surface) and states the real size of the bash and Python code, how the commit hook is installed
  and removed, that a headless run stops at the first gate while enforcement is on, and which toasts
  appear; `docs/commands.md` and `docs/packs.md` match the OCR
  method and the real `/temper:pack` options; getting started no longer offers a copy step that
  installed nothing; the plan review page says nothing leaves the machine before you confirm the share.

Kept on purpose: "This plugin includes a mod" and "Uses hooks" describe what Temper is. The mod
still submits prompts, runs `/temper:temper` and sets its two settings, each on your press or
command, as the README says.

## v9.6.4: the directory's holds, answered in code and in the README

The directory held 9.6.3 with twelve reasons. This release changes the code where a change can clear
a reason, and answers the rest in the README's "What the mod reads and writes", rewritten against the
code. Gates, commands, agents and what the mod does do not change.

- **The game's Client.** "Mod loads a file whose path the directory couldn't read" stayed on two
  spellings (9.6.2 drew `<Client module=... />`, 9.6.3 called `Client({...})` inside the tree), both
  flagged at `const { Client, Box, Button } = $.ui.resolve(e)`. The game module is now imported
  statically (the import also types its props), and the Client element is made in a plain statement
  outside the tree, on the element table itself: `$.ui.resolve(e).Client(...)`, with the key `game`,
  the game module's path as fixed text, and the props. These are the two remedies the directory
  names. `claude plugin validate` reads the same surface module as before, and the game draws the
  same. One real change: the hooks module now also loads the game module (with its runner and art
  files) when it starts. Their top level only defines constants and functions, so nothing acts, but
  a load error in those files now stops the hooks module, not just the game pane.
- **The three scripts the directory named** ("The directory couldn't confirm that the mod stays the
  same after it's checked"). `scripts/check-mod-calls.sh` reads only the validator's output: its
  scan of the game file, through a computed folder and a wildcard, is gone: `$` is not defined in a
  surface module, so the mod's type check fails on an engine call written as `$.` there. It now
  checks every `calls:` line the validator prints, not only the first. `scripts/check-known-limits.sh`
  no longer names the known limits test and reads its two files by fixed paths. The approval gate
  example moved to `examples/gates/` (its old folder shared the name "hooks" with the mod's) and no
  longer names the guard scripts' folder or a wildcard over it.
- **README, "What the mod reads and writes", rewritten from the code.** It named 5 of the mod's 11
  hook events; it now covers every hook, every file the mod reads, its session state (readable by
  other plugins) and its store, what each prompt and refusal holds, the `temper:phase` system prompt
  section, the two settings and when they change, the two commands and when they run, its one tool
  call (the question dialog), the game's surface module, and what the test suite's fake engine does.
  It corrects two statements: the config is `.claude/temper.config`, not a `.temper/` file, and no
  path outside the plan goes into a prompt (it goes into the refusal and the question). A prompt the
  mod submits is a turn of your session, marked as from the Temper plugin. The gate and bar table
  moves to Commands, where a full copy already was, and other sections say the same in fewer lines,
  so the README stays within 300 lines.
- **The test world says what it is.** Temper's fake engine declares itself test only code, and its
  `config.set` stand in says why a test answers that call.
- **Trust:** the README now says the `pre-commit` hook goes where your `core.hooksPath` points, if you
  set one, and that check commands are detected for your stack unless `check.commands.*` sets them.

Held by design: "This plugin includes a mod" always goes to a reviewer. The findings that point into
the mod's test suite come from Temper's fake engine (built on Claude Code's test kit), which answers
tool calls, `config.set` and `command.run`, and from one test that stubs an agent spawn. The README
explains both.

## v9.6.3: the game's Client is called with its path as fixed text

The directory still read "Mod loads a file whose path the directory couldn't read" on 9.6.2, at the
line where `Client` is taken from `$.ui.resolve(e)`. The game pane wrote `<Client module="..." />`
as JSX, which compiles to a call of `h` that is handed `Client`. It is now a direct call of
`Client` with the key `game`, the game module's path as fixed text and the props, the form the
mods guide uses, so the fixed path stands in the call itself. Nothing else changes.

## v9.6.2: the mod writes no file, runs only fixed commands, and loads its game by a fixed path

The directory held 9.6.1 by policy. This release removes the causes it can point at in the mod's own
code. Gates, commands and agents do not change.

- **The mod writes no file.** The directory blocks a mod that writes a file at a path it cannot read
  ("Mod writes a file that other tools run or obey"). The decision events and the run report are
  now kept in the mod's own plugin store (`$.store`, keys `vf:<path>`), and the mod reads them back
  as if they were files. Event files that a 9.6.0 or 9.6.1 run wrote are still read, so a run in
  progress keeps its history. The store keeps the 40 most recent folders and drops older ones
  (`$.store.delete`, a new reviewed call; `fs.write` is gone).
- **`/temper:temper report` shows the report** instead of writing `.temper/report.md`. The pull
  request line now says "/temper:temper report shows the report."
- **Every command the mod runs is fixed text.** `/temper:temper continue <stage>` is written out once
  for each stage (`continue intent` to `continue check`) at the call, and the Resume is
  `/temper:temper` with no arguments.
- **The game's `Client` comes straight from `$.ui.resolve(e)`,** so the directory can read the game
  module's fixed path (finding at line 1123).
- **README.** The version badge shows the version from `plugin.json` (it showed the latest GitHub
  release); `scripts/version-bump.sh` updates it and the GitHub page's version. "What the mod reads
  and writes" says the mod writes no file.
- **No global is read.** The 60 ms wait before `build-state.json` is read again uses `$.clock.sleep`
  (a new reviewed call) instead of `setTimeout` taken from `globalThis`, and the session id no longer
  uses the global random source (the finding "a form that can hide what its code does", in the mod's
  adapter, line 287). The reviewed list is 24 calls.
- **`scripts/check-mod-calls.sh` fails on a cut `calls:` line.** Claude Code shortens a note over
  1000 characters, which could hide a call. All toasts now go through one helper, so the line is
  short again.

## v9.6.1: clears the plugin directory validation of 9.6.0

The directory's validator stopped on the mod's register module and held 9.6.0. This release
fixes each finding it marked "Needs you" and adds the README text it asks for. No change to gates,
commands or agents.

- **`h` and `on` are no longer used as names.** Two arrow function parameters in the register module
  were named `h`, the name JSX compiles to, and `showMore` had a parameter named `on`, the name of
  the registration function. They are now `step`, `decision` and `expanded`.
- **`config.set` names its key as fixed text.** `/temper:temper mode` writes
  `{ key: 'temper.uiMode', value: value }` and `/temper:temper enforcement` writes
  `{ key: 'temper.enforcement', value: value }`, so the directory can read which setting changes.
- **The mod no longer changes an agent spawn.** `reviewerModel` was applied by an `agent.spawn` hook
  that passed a changed event on. Now the spawn is not hooked at all: a `turn.step` hook gives the
  steps of the Temper review agent the reviewer model, and `$.agent.list()` (read only) tells which
  steps belong to that agent. The reviewed call list is 23 calls (`agent.list` added in
  `scripts/check-mod-calls.sh` and `docs/mods-plan.md` section 2.7).
- **README.** "What the mod reads and writes" now says which commands the mod runs and when, which
  settings it sets, what goes into the prompts it submits and the `temper:phase` section, what the
  `tool.call`, `command.run` and classic hooks do, where it writes, why the mod's adapter reads
  `setTimeout` from `globalThis`, and that the mod's tests are not loaded.
- **The demo is removed.** The `demo/` folder (the sample project, the seed and run scripts, the VHS
  tapes), `docs/demo-script.md`, the "Try the demo" section of the README and the unused demo styles
  of the GitHub page are gone. `docs/mods-testing.md` now starts the manual test in any small project.
- **Test files the directory read as mod source.** The four fixtures of the mod's tests are
  one string per source line instead of one long line, and the zero width space in
  one of the mod's review tests is written as `\u200b`.

## v9.6.0: the Temper mod, and four CLI additions it needs

### The mod (Claude Code 2.1.287 or later)

- A new mod, loaded through a `modules` entry next to the existing hooks in the plugin's
  hooks file. It refuses Write, Edit and NotebookEdit outside the current
  phase's paths, refuses `git commit` until Check passes (or is overridden), refuses
  forged approvals (writes to the events folder, `.temper/gates.json`, `.temper/status.json`
  or `.temper/overrides.json`, and decision CLI calls without a matching human decision),
  and adds a `temper:phase` section to every request so Claude knows the phase, with the
  line `Temper enforcement: active`.
- Phase history is stored as one event file per decision under
  `.temper/specs/<name>/events/`, written once with a unique name. Verdicts and criteria
  status are only read from the CLI's files. Going back invalidates every later phase, and a
  phase needs a fresh verdict after it was invalidated.
- `/temper` gains reserved subcommands: `status`, `timeline`, `approve`, `next`, `back`,
  `override <reason>`, `accept`, `drift`, `pause`, `resume`, `report`, `pr`, `mode`,
  `enforcement` and `pane`. Any other first word still reaches the prompt based command.
  Decisions count only from the person. The same words are handled in prose when the mod is
  absent.
- Scope drift: an edit outside the plan's files asks you to add it to the plan, revert it,
  or allow it once with a reason, and logs the choice. After the configured number of failed
  Check to Fix loops (default 3) the run stops and offers replan, override or hand over.
- A phase bar above the prompt (six phases, up to three actions on keys 1, 2 and 3,
  override on 9, all actions on 0), a pane with a live criteria checklist, the spinner text
  `Building · criterion 2 of 5`, a hint tail, a question header, a line under each answer,
  suggestions that are never submitted, and one toast per phase change.
- Three modes, `full`, `minimal` and `off`, switched live with `/temper mode`. A separate
  `/temper enforcement on|off` controls the refusals. Both are plugin settings (`uiMode`,
  `enforcement`); a value locked by an administrator is reported, not changed. The first
  interactive `/temper` asks once.
- An optional game, Temper Run, for the time Claude works, in the spirit of the browser dinosaur
  game. Ember, a small dragon drawn in half block pixel art, runs on the spot in a forge hall. Jump
  (`w`) over iron anvils and buckets of cold water, duck (`s`) under flying hammers. The floor
  scrolls, sparks drift, the wall warms from dark gray to deep red with the heat (levels 1 to 5), and
  at every 100 points Ember flashes yellow and a banner says "Hot! 100". It is made to be fair: a jump
  pressed up to 250 ms before the landing is remembered, hit boxes are smaller than the pictures, and
  the obstacle generator keeps gaps that a bot with a slow hand can always clear. While a phase works,
  the band (`8: Play while you wait`), the pane and the prompt hint offer it; key `8` or
  `/temper:temper play` (a new reserved word, 17 in all) opens it. It never opens by itself. The pane
  takes the keyboard when it opens: `r` runs, `q` or Esc leaves, with no mouse. It runs on the
  terminal and the desktop app only, keeps a best score, shows a banner when a phase is ready, and
  never weakens a refusal. The plugin setting `game` is `on` (offers and command), `command` (command
  only) or `off`.
- User text of the mod is written in Simplified Technical English, and every label says its
  result: "Make the plan", "Approve the plan", "Start the next task", "Skip with a reason". Each
  action has a one line description in the pane, the step reads "Step 2 of 6: Plan", and one
  sentence under the bar says what key 1 does and what happens next. Every refusal ends with a
  "Next:" step. Follow up prompts to Claude are short and end with "Do this now. Reply with one
  short line." They name the full path of the Temper script in the plugin folder, so Claude does not
  try a path that does not exist in the project.
- One flow, two views. The bar is the same choices as the orchestrator's gate questions, with the
  same words, and the orchestrator no longer asks its question a second time when the mod is active
  (the system prompt has `Temper enforcement: active`): it prints the stage panel and the check
  result, then waits for the bar or for a message you type. Key 1 follows the check result:
  "Continue to Build", "Loop back to Plan", "Start Intent" or "Run Plan"; at Build every task is its
  own checkpoint ("Continue with task 2"). Key 4 is **Discuss**, the original "Other": it puts a draft
  in the prompt box. Key 0 (**More**) opens a numbered menu above the phase chips (digits 1 to 9,
  because a letter would type into the prompt box): Save for later, Grill me, Teach me, Open HTML
  review, Architecture depth review, Review config suggestions, Stop, Go back, Show the timeline,
  Write the PR text. A finished run offers Commit. After a decision a button asks Claude to mirror it
  in the CLI state and then runs `/temper:temper` with no arguments (the orchestrator's Resume), so
  the next stage starts in its own subagent with its own brief. New reserved word `discuss` (18 in
  all). Two reviewed calls are added: `command.run` (`prompt.submit` refuses a text that starts
  with a slash) and `prompt.fill`; the list is 22 calls.
- Security fixes from the second review: the Bash classifier reads the Temper script structurally
  and fails closed (a link, copy, glob, variable, substitution, launcher, interpreter or `source`
  that could run a decision call is refused); `evidence accept` is matched to its stage; two
  parallel calls cannot spend one human decision; the plugin folder path is decoded before it is
  checked; the game accepts only a real number as a score; the `game` setting reads `false`, `no`,
  `0`, `disabled` and `none` as off; the demo seed never removes a folder that is not its own.
- One source of truth. Bug fixed: after Build, "Continue to Review" moved the bar but the mirror call
  `state advance build_complete review` was refused, because only advances out of Intent and Plan counted
  as the person's decision. Every advance now does. The CLI state (`build-state.json`) is now the truth for
  where the run is: the phase on the bar and in every deny comes from `next_stage`; events only say who
  decided. A choice that the CLI has not recorded shows one line ("Temper state: the run is at Build. Your
  last choice is not recorded yet. Press 1 to record it."), and key 1 ("Record my choice") submits the
  mirror prompt again for the same decision. A decision is spent only after its call ran without an error.
  A reload, /clear, a deleted or corrupted events folder cannot move a run backward. When the mod cannot
  tell where the run is (unreadable state, an unknown next stage) it blocks nothing and writes nothing; when
  the CLI looks reset while later checks passed, phase rules do not block writes. With the bar active the
  orchestrator never runs `state init`, `clear`, `archive` or `loop` on its own, and a failed Resume
  Validation stops instead of picking Start over. New tests: an end to end test of the mod (a full run
  against a fake CLI with chaos between steps) and the mirror commands against the real CLI in
  `scripts/tests/test-temper.sh`.
- The orchestrator does its own "On Continue" steps. Continue no longer sends a mirror prompt of the
  mod: the button records the decision and runs `/temper:temper continue <stage>` (a new reserved word,
  19 in all). The orchestrator then does what the original `/temper` writes for that stage: the status
  flip, `state advance`, the feature branch, the commit of the approved artifacts, and launches the next
  stage. Before, the branch was never created and the Build checkpoint commits were refused. The mod's
  commit rule now defers to the same facts as `temper gate commit`: an artifact only commit (every staged
  file under `.temper/specs/`) passes in every phase, a Build checkpoint commit passes on the run's branch
  with a green test run, and a refusal says why (for example the branch). The project root is fixed at the
  first session start and kept in `$.state`: Claude's `cd`, or a hot reload in another folder, can no longer
  make the mod read another folder's `.temper`.
- Original only. The Temper bar holds only the options the original `/temper` asks (Continue to, Loop
  back to, Grill me, Teach me, Walk through step by step, Open HTML review, Architecture depth review,
  Review config suggestions, Change, Stop, Save for later, Commit), plus Discuss, Play and Skip with a
  reason. Removed from the buttons: Ask me questions, Edit the intent, Make the plan, Show the files,
  Try another plan, Split the tasks, Run the tests, Show the changes, Review again, Run failed checks
  again, Show the failures, Write the PR text, Show the timeline, Save my request, Go back to, Pause the
  run. The subcommands stay. Done offers Commit and Save for later. `scripts/check-original-options.sh`
  and the action tests refuse any other label.
- Third security review (#39 to #48). While a run is active, a Bash command that names the script and
  hides what it runs (`$'..'`, `${..}`, `$(..)`, a launcher, a script written then run, a shell given a process substitution)
  is refused, and plain readers (`sed -n`, `awk '/x/'`, `nl`, `grep`, `pytest -k`) stay allowed. Names are
  compared without regard to case, `ln` of Temper state is refused, and every `state advance` and
  `state set next_stage` needs the person's decision or the exact next stage after a passed check.
  `git cherry-pick`, `merge`, `revert`, `am`, `commit-tree`, `rebase --continue`, a merging `pull` and
  a `git -c alias` count as commits while the commit gate is open. A decision button locks while it runs
  and ignores a stale press. The README says plainly what a text reader cannot see.
- The demo is smooth: the demo seed script seeds the Plan step with an accepted intent and a
  written plan (both checks pass), the demo run script starts there, and `demo/temper.tape` is a
  15 to 20 second hero with no waiting scene.
- `.temper/report.md` is written when a run completes: phases, overrides, accepted findings,
  scope drift decisions with reasons, and criteria status.
- Optional and off by default: a model or effort per phase (`phaseModels`, for example
  `build=sonnet:high`) and a reviewer model (`reviewerModel`).
- The mod calls only the reviewed set listed in `docs/mods-plan.md` section 2.7: no
  `process`, `http` or `env`. `scripts/check-mod-calls.sh` enforces it in CI, which now also
  runs `claude plugin test`, `claude plugin validate --strict` and the type check on
  Claude Code 2.1.287.

### The bar and the CLI agree on Loop back, Skip and Commit

- **Commit** at Done tells the orchestrator to do the Commit steps of `commands/temper.md` (gate
  commit, intent Status completed, `state archive`, stage the diff and the spec artifacts, one
  commit, then `state clear`). The mod never clears or archives the state. When the CLI state is
  gone after the run was Done, the bar shows no run; it never goes back to Intent. (When it is gone
  in the middle of a run, the run stays enforced: see the hardening section below.)
- **Loop back** is a loop of the CLI. The mirror message runs `state loop <from> <to>` (the budget
  `loops.max-per-type` and the evidence of the redone stages) and then `state set next_stage`. The
  guard lets `state loop` through only while the person's own back decision waits. The Feedback Loops
  section of `commands/temper.md` describes this path, and says what to do on `BLOCKED`.
- **Skip with a reason** is the person's go-ahead for that stage. The bar sends `continue <stage>`
  after the skip, and the guard lets that stage's `state advance` through (also out of Intent and
  Plan) until a later step back. Before this, the orchestrator was refused after a skip at Plan.
- A medium or complex run whose project never set `phases.design: true` may go from Plan straight
  to Build; the guard accepts both next stages unless the config says design is on. When design is
  on and a call names the wrong next stage, the refusal now says which stage is next instead of
  sending the model back to the person for a decision that was already made.
- While the CLI is at its design stage after the plan approval, the bar no longer says "Temper
  state looks reset".
- At the design check, Continue sends `continue design` (not `continue plan`) and spends the person's
  approval, so it no longer stays pending.
- `git add .temper/specs/x/ 2>&1` no longer counts `2>&1` as a staged path, so the artifact only
  commit that follows is not refused as a code commit. A commit that fails (an index lock) keeps the
  staged list for the retry.
- `build-state.json` is read again when a read sees an empty or cut file (the CLI rewrites it in place),
  so the bar no longer says "No Temper run is active" for a moment at Done.
- A failed Check that loops through Fix and returns to Check keeps a verdict that was written while
  the run was in Fix, so the person is not sent through the same check run again.
- **Share HTML review** has a button (in the Plan More menu). Open HTML review points at
  `reference/plan-review.md` and `scripts/plan_review.py` instead of filling the template by hand.

### Hardening after a fourth review (tests in the mod's hardening test file)

A read only review traced nine findings by hand. Each one got a failing test through the real guard first.
Real exploits, fixed: 1 (a shell fed a program on stdin through a pipe, the script name split by quotes), 2, 3, 4,
5, 6, 7, 8, and the fail open catch of 9. Not an exploit as traced: a quote split verb in a plain call
(`scripts/te""mper ov""erride`), a glob in a stdin program, and running the output of an echo as commands were refused before; the tests stay.

- A shell, `eval` or `source` that is given a program the text does not show is refused while a run is
  active (a pipe from an unknown command, a file or `/dev/stdin`, a process substitution, a `-c` string built
  by a substitution, and a shown program that hides a word with quote splits, `$`, backticks, backslashes,
  braces or globs). Quote and backslash splits are removed before the script name and the decision words are
  looked for. Shell setup idioms (what a version manager or a project setup script prints) and plain heredocs stay allowed.
- A run whose `build-state.json` turns missing, unreadable or corrupt (`chmod 000`, `find -delete`, `git clean`,
  `git stash -u`) stays enforced from the last known state, with one line saying so. It ends on `/temper:temper
  enforcement off`, when the file reads again, after Done, or on a reload. `chmod`, `chown`, `chflags`, `setfacl`,
  `chattr`, `find -delete` and `-exec rm`, `xargs rm`, `git clean` and `git stash -u|-a` that can reach `.temper`
  are refused.
- A command that names a guarded file (or a glob that can stand for one) must be a plain read, or it is refused.
  This replaces the list of writers (`awk`, `sort -o`, `uniq`, `patch`, `find -fprintf`, `git checkout|restore|apply`,
  `tar`, `unzip`, `ed`, `ex`, `cp -l`, `ln -s .tem*/gates.js*`) by one rule. A comment in a command is no longer a mention.
- The artifact only commit carve-out is for a plain `git commit` of a staged set the mod understands. Unknown ways
  into the index (`git stage|mv|rm|apply --cached|update-index`, `xargs git add`, `add -p`, aliases, `checkout <tree> --`,
  `stash`, `reset`) make the set unknown. A pathspec commit, `-i`, `-o`, `merge`, `cherry-pick`, `am`, `pull`,
  `revert` and `commit-tree` never use the carve-out. `git add` paths follow `git -C` and the `cd` of the shell (carried
  across Bash calls); the comparison with `.temper/specs/` is case sensitive, as in the CLI. `--no-verify`, `-n`,
  `core.hooksPath`, writes to `.git/hooks` and `.git/config` are refused while a run is active. The Build checkpoint
  now needs a design verdict when the spec has a `design.md`, as `temper gate commit` does.
- A decision is spent by what its call changed, not by its exit status (`state advance ...; exit 1` used to give the
  decision back). A person's approval is stale once the run goes back to its stage or an earlier one.
- A skip is for the stage the run is at (at Review, `state advance plan_complete build` no longer passes), and no
  `state advance` lowers the stage. `state loop` must leave the stage the run is at and uses the back decision once.
- `.claude/temper.config` (while a run is active), `.temper/evidence/*.json`, `.temper/feedback-loops.json`, `TEMPER_DIR` and
  `TEMPER_CONFIG` are guarded; `state set command` is refused, `state set complexity` is for the open plan only, and
  `state set base_sha` only as a commit hash or `"$(git rev-parse HEAD)"` in Plan or Build.
- A guard that throws refuses Bash while a run is active (other tools pass). When no run was found at the first session
  start, the root is looked for again above the session folder until a run is seen.
- Limits left, written in the README and `docs/mods-plan.md`: a program that builds a path at run time, the names inside
  a patch or an archive, a staging done by a script or by the person before the session, a git alias of the person for
  `commit`, MCP and PowerShell file tools, and a script written in an earlier call. The native `pre-commit` hook and the
  editing tool deny stay the hard guarantees. The 22 reviewed `$` calls are unchanged.
- Tests that encoded the old behaviour were changed on purpose: a build-state that is unreadable or deleted mid-run no
  longer blocks nothing; rule tests that built a state ahead of the CLI now give the phase the CLI is at; `state set
  complexity|base_sha` are tested in the phase they are allowed in.

### CLI additions (these help without the mod too)

- `check.commands.test`, `check.commands.lint` and `check.commands.typecheck` in
  `.claude/temper.config` replace stack detection for Check when set.
- `fix.max-loops` sets the Check to Fix limit. `temper config get fix.max-loops` reads 3
  when it is unset. With the key absent, the existing `loops.max-per-type` still applies.
- `temper evidence accept --stage review --id N --reason "..."` stops the review gate counting
  a finding, keeping the row with the reason, the author and the time. An empty reason is
  refused and writes nothing.
- `temper status --json` prints per criterion `passed` or `open` with the evidence behind it,
  and `temper gate` now writes the same view to `.temper/status.json`. Failing to write it
  never changes a verdict.

### Verdict change: `temper gate intent` (drafts only)

Two requirements are new, and both apply only while the intent's Status is draft. A draft
needs an `Out of scope:` line under `Scope and Non-goals` with real text. The second
requirement, "open questions resolved", names any `Blocking` question still open on a draft in
the gate detail but does not fail it, because drafts legitimately carry them. An accepted or
completed intent skips both with a recorded PASS: a recorded
acceptance is never revisited, so existing accepted intents keep passing. The shipped template
and example carry the line.

### Intent gate: no soft words, and the soft-source-word rule

- **Verdict change.** A draft intent now fails `temper gate intent` when a Success Criteria
  statement or a Constraints bullet uses the whole word `should`, `may`, `might` or
  `possibly` (any case; words inside backtick code spans are ignored). The detail names each
  hit, joined with ` | `, for example `criterion AC-01 uses should | constraint "..." uses may`.
- A statement that carries a `(source: ...)` marker is exempt, because the hedge word belongs to
  whoever wrote the source. An accepted or completed intent skips the check with a recorded
  PASS, like every other draft only rule, so existing accepted intents keep passing.
- The Intent stage and `/temper:intent` never turn a source "should" or "may" into "must"
  silently. They ask the originator whether the source means required or optional and record
  the answer in `### Decisions`. With no answer yet they keep the source wording and add a
  Blocking Open Question.
- `templates/example-intent.md` is rewritten in short, plain sentences and shows one criterion
  that keeps a source hedge word under a `(source: ...)` marker.

### Minimum versions and old versions

- The mod needs Claude Code 2.1.287 or later. On older versions the plugin loads and runs the
  prompt based phases, and the skills say once that enforcement is off. Loading was checked on
  2.1.200 and 2.1.259; a module runs from 2.1.286 on.
- The plugin settings (`userConfig`) are plain strings and declare no `options`. A field with
  `options` stops the whole plugin loading on Claude Code before 2.1.271, so the values are
  checked in code instead (an unknown `uiMode` means `full`, an unknown `enforcement` means `on`).
- Where enforcement works, and where it does not (surfaces, organization policy, Bash being
  best effort), is written down in the README section "Where enforcement works".

### Docs

- README rewritten around the one line promise, with a phase diagram, the three modes and a
  collapsible reference for each phase. `docs/mods-testing.md` is the checklist to run the
  branch on your own machine before release. `docs/demo-script.md` and `demo/` hold the demo.

## v9.5.0, shareable plan review, stage gotchas, per-stage effort, eval suite removed

### Share HTML review at the Plan gate

- New plan gate option **Share HTML review**. With the `Artifact` tool available it
  publishes the review as a Claude artifact; reviewers comment in the page and the
  comments come back through the artifact's shared store, so nothing has to be moved
  by hand. Reviewers need Contributor access in the Share menu.
- Without the Artifact tool it offered a second sharing path, removed in 9.6.5; the local
  review (Open HTML review) is the way without it.
- Nothing leaves the machine until the user confirms where it is going. Both paths end
  in the same `review-comments.json` the local review already used.
- `templates/plan-review.html` rewritten for this: dark and light themes, no `alert()`
  or inline handlers, a Copy comments box (downloads do not work inside the Claude
  viewer), an optional reviewer name, and a shared mode that turns on only where the
  shared store exists.
- New `scripts/plan_review.py` (stdlib only): `render` fills the template
  deterministically and escapes every value (plan text containing `</script>` can no
  longer break the page), `merge` normalizes comments from one or more reviewers
  (de-duplicates by id, drops empty text, coerces unknown types). 13 new cases in
  `test-temper.sh`.

### Stage briefs

- Every `agents/*.md` brief now carries a **Gotchas** section: the mistakes each stage
  is rejected for (a gate requirement or hook), listed up front instead of discovered
  at the gate. `validate-plugin.sh` fails a brief without one.
- `effort: high` on the Review and RCA agents, where extra verification pays off. The
  other stages inherit the session's effort. `validate-plugin.sh` rejects an
  `effort` value Claude Code does not accept.

### Removed

- The `evals/` seeded-defect fixtures and the `Eval Fixtures` workflow. Its job needed a
  repository setting that was never made, so the latest nightly run
  concluded `skipped`, and it never gated a merge. `scripts/tests/test-temper.sh` still
  covers the gate logic, and the stage-gate Stop hook still enforces that the owed
  gate runs. Docs that cited the fixtures were reworded; ADRs and plans that describe
  history were left as written.

## v9.4.0 — acceptance-linked criteria, richer Intent gate, per-task Build checkpoints, panel + CLI fixes

### Acceptance criteria with stable IDs (AC-NN)

- Success Criteria now carry stable `AC-NN [required|optional]:` IDs with explicit
  `Why:` and `Validate:` links; `Covers:` ties every scenario to the criteria it
  proves. New `scripts/acceptance.py` (stdlib-only) verifies the links at plan and,
  with evidence support checks (artifact sha256 still matching, or a recorded cmd;
  latest row wins), at check.
- `temper evidence add|run` accept `--criterion AC-NN`.
- New gates: `plan` → `criteria -> validation`; `check` → `acceptance evidence`;
  `review` → `review completed` (an empty findings ledger is not a review).

### Richer Intent stage

- `templates/intent.md` rewritten (Reviewer header, Scope and Non-goals, Business
  Outcome, action-chain Target Users, labeled Open Questions, `### Decisions`,
  Source Traceability / Context Sources); `## Scenarios (BDD)` ships empty — Plan
  writes it. New `templates/example-intent.md` (gate-clean by construction).
- `temper gate intent` gains ten draft-only requirements: task context recorded
  (whole-token ticket-key match), criteria why / ids / priority / validate, target
  users action chain, open questions labeled, no duplicate question, header fields,
  no scenarios in draft. Accepted/completed intents skip with a recorded PASS.
- Intent interview discipline (bounded refine pass, accepted-intent pass, two
  mandatory probes, answers written to `### Decisions` immediately); Stage 0 reuses
  a matching committed draft instead of re-initing a spec dir.

### Plan / Build

- Scenarios are fenced ```gherkin blocks (gate `scenarios in gherkin blocks`); the
  CLI's section readers are fence-aware.
- Cross-repo code search recorded in Plan (`## Cross-Repo Search`; gate
  `cross-repo search recorded`) and Build (`code_search` in build-context.json,
  `SEARCH:` panel row).
- Build runs one task per checkpoint with a Continue/Change/Stop gate, feedback
  evidence (`checkpoint feedback answered` gate requirement), and a commit per GREEN
  scenario. `temper gate commit` gains the build-checkpoint carve-out
  (docs/decisions/0009) and `base_sha`-aware blast radius; downstream readers diff
  from `base_sha`.

### One closed panel per stage

- Every `agents/*.md` returns exactly one 76-column closed panel with titled
  sections (Review's 15-row MEDIUM/LOW cap is the sole subset exception); panel
  copies removed from `reference/*.md`. New `scripts/validate-panels.py`, wired into
  quality-check.sh and CI. `gate review` FAIL detail names each open blocking
  finding.

### CLI and hook fixes

1. **`temper gate commit` blocked every commit outside a run.** What broke: with
   `.temper/` present but no active run, the gate demanded stage verdicts that could
   never exist, so the pre-commit hook blocked unrelated commits. Root cause: the
   documented degrade-open path was never implemented — the gate read gates.json
   unconditionally. Nothing failed because the test suite never exercised a commit
   with `.temper/` present and no build-state.json. Fix: no build-state.json →
   single PASS requirement `active run`.
2. **`temper state init` inherited the previous run's overrides.** What broke: a
   stale override from run N satisfied a gate run N+1 never earned. Root cause:
   `state init` wrote only build-state.json, unlike `state clear` which archives and
   removes overrides/gates/loops/evidence. Nothing failed because no test re-inited
   over a dirty `.temper/`. Fix: init now clears like `state clear`, archiving
   non-empty overrides/gates to `.temper/archive/pre-init-*` first (an override
   carries an approver; that audit fact is kept).
3. **The pre-commit hook kept a stale plugin path.** What broke: after a plugin
   upgrade moved the install dir, the embedded path dangled and the hook failed
   open silently — every commit-gate check a no-op. Root cause: the installer
   embedded an absolute path at install time and nothing ever re-ran it. Nothing
   failed because fail-open is the hook's design for *missing* scripts, and a moved
   plugin is indistinguishable from a missing one. Fix: `install.sh` detects the
   mismatch, reports it, and always re-embeds the current path; the orchestrator
   bootstrap reinstalls on a stale path, not only a missing marker.
4. **`scripts/version-bump.sh` skipped the CHANGELOG insert silently.** What broke:
   its sed anchor never matched this CHANGELOG's `## vX.Y.Z —` shape, inserted
   nothing, and still printed success. Root cause: the script predated the current
   heading format and had no post-insert verification. Nothing failed because no
   test asserted the insert happened (the maintainer owned the entry by policy, so
   its absence looked intentional). Fix: anchor on the first `## vX.Y.Z` entry,
   insert before it (head/tail splice — awk `-v` cannot carry the multi-line
   skeleton), verify the header landed, exit 1 on no anchor; visible version
   strings synced, and a suite test fails on any stamp disagreeing with
   plugin.json. Also fixed a pre-existing bash-3.2 parse bug that had made
   `scripts/validate-docs.sh` entirely inert.

## v9.3.5 — directory listing cleanups

No behaviour change to gates, commands, or agents.

- **README**: drops the raw HTML `<div align="center">` hero wrapper — the plugin
  directory strips HTML, so it rendered as literal text. The header and badge row
  are now plain markdown (badges kept: Version, License). Removes the eval-fixtures
  badge and other `evals/` references
  from the README (the directory and its CI workflow stay — they're maintainer
  tooling, not part of the plugin surface).
- **Skills**: `temper-core`, `context-engineering`, and
  `source-driven-development` are model-invoked during stages, not user commands —
  they now declare `user-invocable: false` so they don't present as slash commands.
  `grill-me` and `teach-me` remain user-facing (offered at the plan gate), and
  `grill-me` now credits Matt's original skill (AI Hero).

## v9.3.4 — clears the last directory policy hold

- **`commands/temper.md`**: rewords one sentence about the plan-gate commit that the
  directory's scanner misread. Same instruction, no behaviour change.
- **`evals/wiring-smoke/WIRING_CHECK.md`** no longer describes `/temper:eval` as a
  command the wiring smoke test covers; since v8.0.0 it covers `plan` and `build` only,
  which is what `evals/run-wiring-smoke.sh` already does.

## v9.3.3 — clears the directory's remaining policy holds

Addresses the Claude plugin directory's second validation report. No behaviour change.

- **The website screenshot leaves the plugin tree.** The directory held the plugin for
  review because repository scripts could reach a bundled image. The GitHub Pages
  workflow now restores the screenshot from git history at deploy time, so the site
  still serves it and plugin installs are 2 MB smaller.
- **`verify-stage-gate.sh` has no here-document.** Its block message is
  printed with `printf`, byte for byte the same text as before.

## v9.3.2 — directory validation follow-ups

Addresses the Claude plugin directory's validation report. No behaviour change.

- **Plugin icon**: adds an icon for the plugin card (256 px, the website's colours).
- **`verify-stage-gate.sh` is readable end to end by the validator.** Its
  Python decision step is now an inline `python3 -c` string with every input passed as
  argv, the same form `stage-marker.sh` uses, instead of a program fed on stdin. The
  block message no longer spells out a path to another plugin file. Blocking, the
  two-block budget, fail-open and clearing behave exactly as before
  (`scripts/tests/test-temper.sh` unchanged and passing).

## v9.3.1 — ready for the Claude plugin directory

Prepares the plugin for submission to the Claude plugin directory. No behaviour change.

- **README discloses everything the plugin runs and changes**: the two plugin hooks,
  the files written under `.claude/` and `.temper/`, the git pre-commit hook install
  (and its backup of an existing hook), the project commands the stages run, the
  optional `ocr` engine that sends the diff to its configured LLM provider, the opt-in
  `settings.json` merge, and the maintainer-only `evals/` harness.
- **The plugin's hooks file**: each command now names its script by one full path under
  the plugin folder, and the ignored `matcher` on `UserPromptSubmit` and `Stop` is gone.
- **`plugin.json`**: adds `displayName`, a listing description, and points
  `author.url` at the author profile.
- Removes an unreferenced 2 MB duplicate of the website screenshot.

## v9.3.0 — a fixed finding can pass the review gate

What was wrong: `temper gate review` counted every recorded finding at a blocking
severity, fixed or not. A `/temper:fix` run that found and fixed its own critical
finding could never go green: the headless playbooks forbid an override, and deleting
the evidence is forbidden too. On top of that, `state loop` walked only the `/temper`
stage sequence, so `state loop review fix` cleared nothing, and `commands/fix.md`
never looped on a review FAIL at all. Reported as woningscout #984, reproduced on
v7.0.1, v8.0.0 and v9.2.0.

- **`temper evidence resolve --stage <s> --id <n> --fixed-by "<commit or note>"`** marks
  one recorded finding as fixed in this run. The row stays in the ledger; the gate
  stops counting it. `evidence list` now prints each row's `#id`, its severity and its
  resolver, and the review gate's detail names how many findings were resolved.
- **`state loop` clears the right evidence for a fix run.** With `command: fix` in the
  state, a loop back to `rca` or `fix` truncates `build`, `review` and `check`; a
  `/temper` run keeps its previous behaviour.
- **`commands/fix.md` loops on a review FAIL** the way `commands/temper.md` does:
  resolve what was fixed, loop back when something remains, override only on a spent
  budget. `agents/review.md` tells the stage to record then resolve, never to clear.
- Tests: new CLI assertions in `scripts/tests/test-temper.sh` covering the verb, its
  refusals, the gate's new counting, and both loop sequences.

## v9.2.0 — the prompt-audit release

Prompt surface only. No gate, state, or CLI behavior changes; 191 CLI assertions and
every validator green. Findings and rationale: a `/claude-api prompt-audit` pass over
every file that reaches a model, targeting the Claude 5 generation the stage briefs
resolve to.

- **Dangling `depth_remaining` budget removed.** `reference/review.md`, `reference/fix.md`
  and `reference/architecture-depth.md` still branched on the v5 nested-agent budget
  (ADR-0002) that v7 retired and no launch prompt passes. Each now states the rule it
  stood for: read inline by default, delegate only when the reading set is large, and a
  spawned subagent never spawns its own.
- **`skills/temper-core` no longer documents the retired `capabilities:` config block.**
  Grill Me, Teach Me, HTML Review and Config Suggestions are always offered at their
  gates (as `commands/temper.md` already said); Architecture Depth applies the
  `architecture-depth` pack's rules when it is enabled.
- **Review subagents report every finding with confidence and severity** instead of
  self-filtering to "what you'd defend"; Step 4 already filters mechanically on the
  confidence field, and current models follow a self-filter literally at the cost of
  recall. The omission bar is now concrete: pure style or naming preferences that
  violate no pack rule.
- **`skills/context-engineering` keeps its loading order and drops its numeric
  clamps** (2K lines per task, 2 import hops, ">10 turns means bloat") and its
  rationalization table; the five stage commands that cited the line budget no longer
  do. The 2-hop rule contradicted `reference/plan.md`'s measured blast radius.
- **`skills/source-driven-development` names capabilities, not tool IDs**
  (`mcp__plugin_context7_…`, `mcp__web_reader__…`), and drops its rationalization
  table; the one substantive row moved into the overview as a positive statement.
- **Version-relative narrative removed from prompts:** the v6.x/v7 story in the status
  panel (`commands/status.md`, `reference/status.md`), "what moved out of this file in
  v7" (`reference/orchestrator-patterns.md`), "the doc was fiction" (`reference/pack.md`),
  "(as of v8)" and "no loop cost tier in v7+" (`commands/temper.md`), five copies of
  "there is no separate learning file", and the tokenomics history comment in
  `.claude/CLAUDE.md` (the validator guard stays).
- **Smaller re-baselines:** the `Why not chosen` banned-phrase list in `reference/plan.md`
  becomes the positive rule with two contrasting examples; the headless RCA stage returns
  a blocker instead of an unreachable "ask the user after 3 dead ends"; Grill Me's
  `CRITICAL:` booster becomes a plain instruction with its reason; the unused 0-5
  scoring rubric in `reference/architecture-depth.md` is gone (Step 5 classifies by
  condition, and the report format never carried a score).
- **`reference/autonomy.md` gains an unattended-run guard:** the user is not watching, so
  a turn that ends on a question or a "next I'll…" stalls the pipeline; the model
  finishes the work and stops only at a park.

## v9.1.0 — the token-efficiency release

Subagent architecture completed and prompt surface cut. No gate or state behavior
changes.

- **`/temper:fix` gets the v7 treatment it missed.** `commands/fix.md` was still the
  pre-v7 shape — four hand-rolled inline agent prompts plus four inline summary-box
  templates, duplicating (and drifting from) the contracts in `agents/review.md` /
  `agents/check.md`. New `agents/rca.md` and `agents/fix.md` briefs now carry the
  RCA/Fix stage contracts (methodology pointer, evidence commands, the
  `regression_test` write-shield arming, return box); `commands/fix.md` is a lean
  orchestrator that launches all four stages via their briefs — 22.9KB → 7.1KB (−69%)
  of main-context prompt on every `/temper:fix` run, and one copy of each stage
  contract instead of two.
- **Agent briefs define the summary box they return — one box per stage.**
  `agents/intent.md` and `agents/plan.md` used to say "see `commands/temper.md`" for
  the box format — a clean-context subprocess following that pointer read the entire
  21KB orchestrator to fetch an 8-line template, defeating the isolation it was
  launched with. Every brief now carries its own return box; the orchestrators print
  the returned box verbatim instead of restating formats, and `reference/review.md` /
  `reference/check.md` no longer carry competing box templates (they list only the
  extra sub-panel lines the standalone rendering appends).
- **`reference/review.md` gets the v8 outcome-brief treatment** — 19.6KB → 13.6KB
  (−31%). Everything that survived is policy a strong reviewer would not derive alone:
  severity floors, filter bypasses (security/BLOCK/contract findings), STRONG/WEAK/
  TRIVIAL weighting, the mutation-spot-check protocol, promotion/suppression
  thresholds. What left was choreography and keyword lists. All numeric thresholds and
  the AI-code detection table (which the seeded-defect evals depend on) are unchanged.
  Unlike the v8 plan diet, this pass has no controlled A/B behind it yet — the eval
  fixtures are the regression net.
- **Autonomy loads on opt-in.** Autonomous Continuation's mechanics moved to
  `reference/autonomy.md`, read only when `autonomy.enabled: true` at the plan gate.
  The default interactive run keeps a five-line stub stating the two safety
  invariants (never auto-commits; Intent gate always interactive).
- **`stages.subprocess: true`** (new config, default `false`) runs the standalone
  stage commands (`/temper:plan`, `:design`, `:build`, `:review`, `:check`) in the
  same isolated `agents/{stage}.md` subprocess the unified `/temper` uses — only the
  summary box and gate verdict return to your session. Default stays inline:
  mid-stage interactivity is the point of standalone stages. `/temper:intent` is
  always inline (interactive capture).
- `temper model` resolves the new stages: `AGENT_STAGES` gains `rca` and `fix`
  (`model --all` now prints 8 lines; `models.rca` / `models.fix` config overrides
  work like every other stage). rca/fix remain state-sequence and model stages only —
  never gate stages; Fix evidence still gates as `build`. 191 CLI assertions green.

## v9.0.0 — the intent-gated pipeline

Breaking: the pipeline gains a stage, the commit gate gets stricter, and a subsystem
is removed — the same class of change that made v7 and v8 majors. Three threads: align
temper with Anthropic's [AI-native SDLC playbook](https://claude.com/blog/the-ai-native-sdlc-playbook),
cut install to two steps, and remove duplicated machinery. Net prompt-surface change
from the simplification alone: **−9.2%** (266KB → 242KB), with `reference/fix.md`
down 64% (517 → 143 lines). 189 CLI assertions green (up from 106); all validators pass.
Full play-by-play: `docs/ai-native-sdlc.md`.

### Breaking + migration

- **`/temper` runs intent → plan → … — a new mandatory human gate on every
  non-trivial run.** The Intent stage states the Problem/criteria/constraints and a
  human accepts them BEFORE exploration or architecture spends tokens; acceptance
  (the `Status` flip + `Accepted-by:`) moves from the plan gate to the intent gate.
- **The commit gate requires an intent verdict whenever `intent.md` exists** (and a
  design verdict whenever `design.md` exists). **Migration for an in-flight v8 run:**
  `temper gate commit` will FAIL with "intent gate — MISSING"; a v8-era `intent.md`
  also lacks the new `**Status:**` header. Add one line (`**Status:** accepted`) and
  run `temper gate intent` once — or record `temper override intent` — and commit
  proceeds. Fresh runs need nothing.
- **Adaptive learning is removed** (`learning.json`, `packs/adaptive-learning/`,
  `reference/learning.md`, the suggestion queue and learning curve — see ADR-0006).
  **Migration:** delete `adaptive-learning` from your `packs:` list if present (a
  stale entry degrades silently); a leftover `learning.json` is inert and can be
  deleted. Promotion/suppression continue unchanged from `review-memory.json`.
- `templates/spec.md` + `templates/quickstart.md` deleted (the documented
  three-artifact rule forbids them); retired-system docs moved `reference/` →
  `docs/history/`. Standalone `/temper:plan` and `/temper:intent` sessions now owe a
  gate verdict (the Stop hook holds the session until the gate ran).

### Setup is two steps

Add the plugin from its marketplace, then just `/temper "…"` — the first run
in an un-set-up project bootstraps itself (config, `.temper/` scaffold, and the native
commit gate). `/temper:init` is now that whole one-command setup (it writes the
commit hook too), kept for an explicit re-run. The old third manual step
(running the hook writer by hand) is gone from the quick-start.

### New capabilities (playbook alignment)

- **Intent is the pipeline's own first gated stage.** `/temper` now runs
  intent → plan → design? → build → review → check → commit: a cheap Intent pass
  states the Problem, criteria, and constraints (no exploration, no architecture) and
  a human accepts or corrects it at the intent gate BEFORE the expensive stages spend
  tokens — an intent correction at this gate costs words; after Plan it costs the
  plan. `temper gate intent` is the deterministic floor (Problem stated, ≥1
  criterion, Status header); the commit gate requires an intent verdict whenever the
  artifact exists; trivial requests skip the stage automatically.
- **`/temper:intent`** — capture an idea (from anyone) as a committed `Status: draft`
  intent.md without starting the pipeline; the pipeline's Intent gate later presents
  exactly that draft. The intent lifecycle (`draft` → `accepted` → `completed`) has
  named owners and is recorded (`Accepted-by:` at the intent gate).
- **`temper bands`** — deterministic control-band drift detection (rolling mean ± kσ +
  a same-side-run rule, no model) over `.temper/metrics.json`; a 2σ+ breach exits 1 and
  a 3σ breach is drafted as the next intent.md. **`temper metrics append`** feeds any
  series, including external production metrics. Closes the Maintain loop.
- **A real design gate** — `temper gate design` now requires an Areas-of-Concern
  section; the commit gate requires a design verdict when `design.md` exists.
- **`temper evidence run`** (CLI executes the command and records the exit code —
  PROVEN means machine-observed), **`temper state archive`** (a durable
  `gate-ledger.json` committed with the diff), and **overrides that record the approver**.
- **New hooks** — the fix-loop regression-test write shield, edit-time protected paths
  (`protect.paths`), auto-format (`format.cmd`), and an ASK-tier confirm-override gate.
- **REVIEW.md** repo policy support; an approval-gate example hook. Automation is
  **deliberately host-agnostic**: temper ships no CI-platform files — the review and
  closing-the-loop arcs wire into ANY CI/scheduler (GitHub Actions, GitLab, Jenkins,
  cron) as plain commands and exit codes; `examples/workflow/README.md` documents the
  contract.

### Simplification (subtraction)

- **Four memory systems → one.** The adaptive-learning subsystem (`learning.json`,
  `packs/adaptive-learning/`, `reference/learning.md`, the `suggestion_queue`,
  `learning_curve`, and `.temper/learning/suggestions/`) is removed; its promotion and
  suppression thresholds were already `review-memory.json`'s, and now live only there.
  See ADR-0006 (supersedes ADR-0001).
- **`reference/fix.md` dieted** from a v6-style 517-line step script to outcome briefs,
  keeping the debugging floor, RED-first + the write shield, lessons read/write, and the
  gate calls.
- **OCR moved behind the MCP pattern** — the inline engine section in `reference/review.md`
  is now a probe + one merge rule, with the mechanics in `docs/recommended-setup.md`,
  matching how semgrep is handled.
- **`source-driven-development`** (previously loaded by no prompt) is wired into Build —
  it catches a hallucinated API while writing, before Review has to.
- **One front door** — the README leads with the three commands you actually type
  (`/temper`, `/temper:fix`, `/temper:intent`); the standalone stage commands move to a
  collapsed "granular control" section.
- **Retired-system docs** (`tokenomics.md`, `pricing.md`) moved out of the live
  methodology dir to `docs/history/`; the orphaned `templates/spec.md` +
  `quickstart.md` (which the three-artifact rule forbids) are deleted.

### Adversarial review

The branch diff was reviewed by a multi-agent workflow (4 dimensions, adversarial
verification); all 16 confirmed findings were fixed with regression tests — among them a
command-injection hole in the first cut of `temper metrics append` (a metric value was
interpolated into Python source; now parsed across the argv boundary).

## v8.0.0 — shorter prompts, no Eval stage, leaner pipeline

Breaking: the Eval stage and its config key are removed. The prompt surface was written
for an older model generation — long, prescriptive, step-numbered. It is now outcome
briefs, 43.7% smaller, which a measured A/B shows cuts the cost of a Plan run roughly in
half while holding quality.

- **The Eval stage is gone** — agent, command, reference doc, `skills/eval-judge/`,
  `templates/evalset.json`, and the `eval:` config block, deleted rather than disabled.
  `temper gate eval` exits non-zero; Check advances straight to the commit gate.
  **Migration: nothing to do.** A stale `eval:` config block and a stale `"eval"` key in
  `gates.json` are both inert, and an in-flight run's `build-state.json` is healed in
  place on the first CLI call. Temper's own `evals/` regression harness is a different
  thing with the same name and is untouched, except that `run-wiring-smoke.sh` drops its
  probe of the removed stage.
- **Review and Check run on Sonnet**, not Haiku — the two gates carrying the most
  judgment. `haiku` no longer appears in the prompt surface.
- **The prompt surface is down 43.7%** (372,967 → 209,863 bytes); `reference/plan.md`
  alone goes from 1,086 to 224 lines, with nothing a gate checks losing its prompt-side
  instruction. **Measured, not asserted** (6 runs per arm on Opus 5, same fixture):
  a Plan run costs **$1.74 median instead of $3.37, −48%**, with equal blast-radius
  recall, slightly more scenarios, and exactly the three artifacts the gate reads in 3
  of 3 runs where the old prompt always wrote 6. It is **not** faster — 384s vs 388s.
  Data: `docs/evidence/opus5-plan-prompt-ab.md`.
- **Evidence is cleared when a stage is redone** — new `temper evidence clear`, wired
  into `temper state loop`. Fixes a long-standing bug: evidence was append-only, so
  stale rows from an abandoned run still counted toward the next gate. (A parallel
  Review+Check launch was built and reverted before release — it left Check's results
  stale when a human requested changes at the Review gate. The two stages remain
  sequential, each with its own gate.)
- **`/temper:pack` discovery is fixed and extracted** to `scripts/pack-discover.py`:
  deduplicated targets, per-command descriptions, deterministic install-path selection,
  bounded globs. The documented-but-never-written `.temper/pack-manifest.json` cache is
  removed from the docs rather than built.
- **Cursor support is removed** — the `.cursor/` export and its two scripts. A generator
  bug had silently frozen it at v6.0.1, three major versions behind; shipping it
  misrepresented what Cursor users got. It will return in a better form.

### Deterministic standalone-stage gate enforcement

Re-running `evals/run-wiring-smoke.sh` (skipped in the original v8 verification)
found that the standalone commands invoked the deterministic spine in only **1 of 3
live runs** — Plan never called `temper gate plan`, Build wrote no evidence at all, and
`temper gate commit` cannot distinguish that from a repo that never ran Temper. For a
release whose headline is "gate verdicts are computed, never asserted", that was a
release blocker, fixed in the layer where the commit gate already lives:

- **New hook pair:** `stage-marker.sh` (UserPromptSubmit) records which gate a standalone
  plan, build, review or check session owes; `verify-stage-gate.sh`
  (Stop) refuses to end the session until `.temper/gates.json` carries a verdict for it.
  Any verdict satisfies it — PASS or FAIL — because the guarantee is that the gate *ran*.
  Fail-open everywhere except that one path, with a 2-refusal loop guard.
- **Shipped with the plugin** via the plugin's hooks file (new), which fires for
  `--plugin-dir` and marketplace installs with no settings merge, and via the guard
  pack's settings snippet for the copy-paste path.
- **Gate calls moved into each command's numbered steps** (they sat in a trailing
  section the model demonstrably didn't reach) — kept as defense-in-depth so the hook
  rarely fires.
- **Proven live**: `.temper/hooks.log` from an end-to-end run shows the hook blocking a
  real skip and the model then running the gate 10 seconds later. Full record:
  `docs/decisions/0005-deterministic-stage-gate-enforcement.md`.

### Context engineering (second pass)

The prompt diet above cut length. This pass closes four places where Temper still spent
context the way a pre-Claude-5 plugin would — measured against Anthropic's
[new rules of context engineering](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models).
New doc: `docs/context-hygiene.md`.

- **The generated `TOKENOMICS` block is out of `.claude/CLAUDE.md`** — standing advice
  ("prefer Sonnet for simple tasks", "run `/compact` after turn 28", "Grep first, saves
  ~1%") re-injected into every session, for a saving smaller than the block describing
  it, duplicating judgment the model already applies. Tokenomics has been a retired
  system since v7; `validate-docs.sh` now fails if the block regenerates.
- **Pack `phases:` is real, not just documented.** No built-in pack had ever declared
  one, so every enabled pack loaded into all five stages regardless. Each now declares
  its scope in `rules.md` frontmatter, with the project's `packs:` entry still winning
  and `all` still the default when neither says. The guard pack's `rules.md` declares `[]`:
  ~140 lines of install-and-behaviour documentation for self-enforcing bash hooks, which
  no stage agent can act on, previously loaded by all of them. Narrowing is evidence-based
  and deliberately conservative: `performance` and `api-design` keep `check` because
  `reference/check.md` runs a performance-regression gate (4.9) and an API contract check
  (4.85); `tdd` and `performance` keep `fix` because `/temper:fix` loads packs and writes
  a RED regression test. `validate-plugin.sh` validates every pack's declaration against
  the real phase vocabulary — it cannot tell you a pack was narrowed too far, which stays
  a reading of the stage docs.
- **`packs/tdd/rules.md` is 207 → 69 lines.** The cut is 106 lines of the same test
  written three times (Spring Boot, React, Express) plus step-numbered RED/GREEN/REFACTOR
  procedure. The rules, the scenario-driven mapping, and the test-location table stay.
  `reference/review.md` loses its subagent arithmetic (">20 files → groups of ~10, max 3
  parallel", "spend 80% of attention on flagged hunks", "weight 80% changed lines") in
  favour of the grouping judgment plus the one constraint that actually bounds recursion,
  the depth budget.
- **New `temper model <stage> | --all`, and an optional `models.{stage}` config key.**
  v7 was right to delete `models.routing`/`models.tiers` — a resolution algorithm a
  prompt had to execute correctly every run — but collapsing it to frontmatter meant a
  project could not change a stage's model without editing plugin-owned files, which
  comes up every time a model generation ships. Defaults still live in
  `agents/{stage}.md` frontmatter (one source of truth, read directly, nothing to drift);
  config overrides one; the lookup is bash. The orchestrator makes one `temper model
  --all` call per run. No tiers, no routing table, no algorithm in prose.

## v7.0.1 — Fixes

Fix bash 3.2 override crash + state CLI correctness bugs (#69); v7.0.0: The Deterministic Spine — CLI-enforced gates, agents/, prompt diet, self-evals (#68); link Privacy Policy from landing page and README (#67); ci,docs: plugin-directory submission kit + official strict manifest validation in CI (#66)

## v7.0.0 — The Deterministic Spine

Temper's guarantees moved out of prose and into a program. Through v6.x, gate logic,
model routing, prompt-cache ordering, and loop-cost tiering were ~9,000 lines of prompt
asking an LLM to act as a deterministic interpreter — the least trustworthy place to put
logic with exactly one correct output. v7 is a breaking release built around one rule,
applied everywhere: **no feature ships in prompt-space if it has exactly one correct
output.**

- **New `scripts/temper` CLI** — a single zero-dependency bash script that owns
  `state` (build-state.json, never hand-written again), `evidence` (every claim now
  carries a command, exit code, and artifact — `--label PROVEN` is mechanically
  re-checked, not taken on faith), `gate` (`plan`/`build`/`review`/`check`/`eval`/`commit`
  — each ~20-30 lines of readable shell, PASS/FAIL with named reasons), `override`
  (a human can always proceed past a FAIL, but it's recorded, never silently erased), and
  `report` (renders the ledger). Unit-tested: `scripts/tests/test-temper.sh`, wired into
  CI.
- **The commit gate is now a program, not a promise.** The native pre-commit hook
  (`install.sh`) and a new in-agent PreToolUse hook
  (`block-uncommitted-gate.sh`) both run `temper gate commit`, so `git
  commit` is physically blocked while any upstream gate is FAIL and unoverridden. This
  is what "autonomy never commits without green gates" now *means*, mechanically, not
  just in the README.
- **New `agents/` directory** — `agents/{plan,design,build,review,check,eval}.md`, one
  file per stage with `model:` frontmatter (native, declarative) and a short contract
  (what to read, what `temper evidence`/`temper gate` calls to make). Replaces the
  Model Routing Resolution and Cache Routing Resolution algorithms.
- **Prompt diet:** `commands/temper.md` 1,353 → 363 lines; `reference/orchestrator-
  patterns.md` 979 → 327 lines — the two biggest single cuts. Both dropped only
  mechanism (routing/caching/gate-eval algorithms, the observability.json v3 telemetry
  schema, loop-cost tiering); judgment content (scenario derivation, TDD discipline,
  review taxonomy, the eval rubric, Grill Me/Teach Me) is untouched.
- **Config collapsed:** `.claude/temper.config` 211 → ~55 lines (most of it comments).
  `tokens.*`, `models.*`, `observability.*`, `capabilities.*`, and the nested-agent
  budget block are gone — replaced by either a CLI mechanism (gates, evidence) or a
  fixed good default (Grill Me/Teach Me/HTML review/Architecture Depth Review are now
  always offered at their gates; there's no toggle to turn them off, just don't pick
  them).
- **`/temper:status` drops the cost/latency/token "Economics" panel** (v6.x estimates
  with no mechanical backing) for a **Gate Ledger panel** reading `.temper/gates.json` +
  `.temper/evidence/`: only what was actually recorded.
- **Autonomous Continuation, simplified, not removed:** still opt-in, still armed only
  at the plan gate, still never commits/pushes/merges. The three-branch `gate-eval` hook
  and confidence-threshold machinery are gone — an autonomous run now just runs `temper
  gate {stage}` and auto-continues on PASS, parks on FAIL past budget. Blast-radius and
  park-on-touch checks are computed by `temper gate commit` itself.
- **`/temper:fix` updated to match:** Fix/Review/Check now record evidence and run
  `temper gate build/review/check/commit` — required so a `/temper:fix` commit isn't
  wrongly blocked by a commit hook that now checks for evidence on every commit.
- **Retired outright** (not degraded — deleted): the `tokens.*` runtime levers (prompt
  cache read-ordering, adaptive pipeline depth, loop-cost tiers), `models.*` routing
  config, the `observability.json` v2/v3 cost/latency/drift telemetry schema, the
  `capabilities.*` config toggles, and `scripts/validate-phase2.sh` /
  `scripts/validate-phase3.sh` (they asserted the byte-identity contracts this release
  retires). See `reference/tokenomics.md` and `reference/pricing.md` for what replaced
  each.
- **Cursor IDE export archived**, not regenerated per release. `.cursor/` stays at its
  v6.0.1 snapshot; `scripts/generate-cursor.sh` still runs by hand if you want it, but
  it's out of `version-bump.sh` and `release-bump.yml`. See `.cursor/README.md`.
- **Design doc:** `docs/plans/v7-deterministic-spine.md`.

**Self-verification pass (same release):** re-checked against the design doc's own
acceptance criteria and closed the real gaps that turned up:
- `temper gate check` now traces every `intent.md` scenario to a test by name
  (`--scenario` on `temper evidence add`) and names the uncovered ones in its FAIL
  detail — this is the mechanism that makes the README's rate-limiting story literally
  true, not just illustrative. It was missing at first pass; `agents/check.md` and
  `scripts/tests/test-temper.sh` updated with it.
- `temper gate plan` now requires a `## Blast Radius` section in `plan.md` for
  `medium`/`complex` changes (`temper state set complexity` records the tier).
- `.github/workflows/eval-fixtures.yml` gained a `pull_request` trigger (one fixture,
  path-filtered to `commands/`/`reference/`/`agents/`/`skills/`/`scripts/temper`) — the
  design doc called for per-PR + nightly; only nightly + on-demand shipped at first pass.
- `/temper:init` now actually greps an existing config for retired `tokens:`/`models:`/
  `observability:`/`capabilities:` blocks and reports them, instead of only describing
  that behavior in prose.
- The design doc's per-fixture "autonomy tripwire" was deliberately not added to the
  three eval fixtures — `park-on-touch` is a pure CLI property with zero model
  judgment involved, already covered by `scripts/tests/test-temper.sh` without spending
  tokens on a live run to re-prove it. Reasoning: `evals/README.md`.
- **Known gap, not closed in this pass:** the design doc's reference/ line-count target
  (~10,700 → ~1,500 total) was not hit — `commands/temper.md` (1,353→363) and
  `reference/orchestrator-patterns.md` (979→327) got the deep rewrite; the other
  reference files (`plan.md`, `review.md`, `check.md`, `build.md`, `pack.md`, `fix.md`,
  and others) only got targeted edits removing dangling references to retired config
  keys, not a line-count-reducing rewrite. Current `reference/` total: ~6,500 lines.
  This is real, disclosed scope not yet done, not a silently-missed target.

**Third pass — live baseline run, and a critical bug it found:**

- **Ran the eval suite for real** against a `v6.0.1` worktree and against this branch
  (the harness pointed at each checkout in turn, run as root inside a sandbox). Both catch **3/3**; v7's catches are
  confirmed via the evidence ledger (`temper gate` mechanically FAILing with the defect
  named), not just a transcript grep — a strictly stronger guarantee than v6.0.1 had.
  Full numbers: `evals/README.md`.
- **That live run found a real, severe bug: the standalone `/temper:plan`,
  `/temper:build`, `/temper:review`, `/temper:check`, `/temper:eval` commands never
  recorded evidence or ran gates at all.** Only `agents/*.md` (used by the unified
  `/temper` orchestrator) had the `temper evidence add`/`temper gate` instructions —
  the standalone commands, a fully documented and supported entry point, were left
  running the old prose-only methodology with no CLI involvement. Concretely: running
  `/temper:check` standalone, then `git commit`, would have hit `temper gate commit`
  seeing zero evidence for every stage and wrongly blocking the commit (or, worse,
  once `.temper/gates.json` had *some* stale PASS in it, wrongly letting a broken
  change through). Fixed: `commands/{plan,build,review,check,eval}.md` each gained a
  "Deterministic Gate" step pointing at the matching `agents/*.md` steps, with an
  explicit `--spec-path` (standalone use doesn't necessarily call `temper state init`,
  so `temper state get spec_path` can be empty — passing it explicitly was required,
  not optional, to stop the scenario-tracing check from silently skipping instead of
  failing loudly). Verified with fresh live runs before and after the fix.
- Collapsed a genuinely duplicated ~13-line "load packs via the cached manifest" block
  — repeated near-verbatim across `plan.md`/`design.md`/`build.md`/`check.md`/
  `review.md` — down to a one-line pointer at `pack.md`'s already-canonical
  documentation of the same mechanism. ~55 lines, zero methodology lost.
- Fixed a dormant shell/Python interpolation bug in `evals/run-fixture.sh` (same class
  already fixed once in `scripts/temper`) and a join-with-comma ambiguity + a subtler
  IFS-first-character-only bug in `temper gate check`'s scenario-tracing detail line.
- Investigated further reference/ line-count reduction beyond the pack-manifest dedup
  and made a deliberate call not to force it: the remaining size in `review.md`/
  `plan.md`/`pack.md`/`check.md` is genuine, load-bearing methodology (confidence
  scoring, diff fingerprinting, Deep Doubt Mode, progressive-loading navigation maps
  that are themselves a token-efficiency mechanism) — not plumbing. Cutting it to hit
  the plan's ~1,500-line target would violate v7's own design rule (delete mechanism,
  keep judgment) for the sake of a number. The gap is real and stays open by design.

**Fourth pass — the eval harness's own "caught" signal was weaker than claimed:**

Asked directly whether the eval suite is actually correct, not just useful — re-read
`evals/run-fixture.sh` cold rather than re-stating the third pass's claims. Found: the
"evidence-ledger" match only checked whether *any* evidence entry's free-text `claim`
matched a keyword regex. It never inspected `severity` (what `temper gate review`
actually checks) or `exit_code`/`scenario` (what `temper gate check` actually checks),
and never ran `temper gate <stage>` or read `.temper/gates.json`. So "confirmed via
evidence-ledger" was true only in the sense that matching text existed — not that the
gate would have mechanically blocked a commit, the actual claim made in this
CHANGELOG's third-pass entry above. That distinction had only been checked by hand
during debugging, never by the automated script CI runs.

- **Fixed:** a three-tier signal, strongest first — `gate-blocking-evidence` (the
  matching entry also carries the specific property that drives the real gate:
  `severity == 'critical'` for review, a `--scenario` row with nonzero `exit_code` for
  check), `evidence-non-blocking` (text matches, wouldn't fail the gate), and
  `transcript-fallback` (only the raw transcript mentions it; no evidence recorded at
  all). Pass bar is now **strict by default** — only tier 1 counts, matching what CI
  should enforce; `TEMPER_EVAL_ACCEPT_ANY_TIER=1` is the explicit override needed only
  for the v6.0.1 comparison (tier 1 is structurally unreachable there — v6.0.1 has no
  CLI at all).
- **Verified live, both directions:** v6.0.1's `orders-api`, run *without* the
  override, correctly reports MISSED — the first real negative-path confirmation this
  harness has ever produced (every prior run had only ever shown CAUGHT). v6.0.1's
  second fixture, run *with* the override, correctly passes. All three v7 fixtures
  re-confirmed at the strict `gate-blocking-evidence` tier. Full writeup:
  `evals/README.md`.
- **Known, disclosed limitations that remain:** only `review`/`check` are exercised by
  a live fixture — `plan`, `build`, `eval`, and `commit` gates are only tested by
  synthetic CLI unit tests, the same class of gap that hid the third-pass bug. Tiers
  2-3 still use fuzzy keyword matching. Both documented in `evals/README.md` under
  "Known limitations", not hidden.

**Fifth pass — closed the tier 2/3 fuzzy-keyword-matching gap:**

The fourth pass's remaining item: tiers 2/3 matched on a single flat `catch_keywords`
list, `OR`ed together — a generic word alone (`"missing"`, `"unused"`) could
false-positive on unrelated text with no connection to the seeded defect.

- **Fixed:** each fixture's `expect.json` now splits `catch_keywords` into
  `anchor_keywords` (specific identifiers — exact scenario names, code symbols,
  component names) and `signal_keywords` (generic descriptive terms). Every tier now
  requires **both** an anchor match and a signal match, not either alone — including
  tier 1's text-matching component, not just tiers 2/3. `evals/run-fixture.sh` passes
  both patterns as `argv` into its `python3 -c` checks (not spliced into source, per
  the same fix already applied once in `scripts/temper` and once earlier in this same
  file), and the transcript-fallback tier now requires both patterns to appear in
  `run.log`, not just one.
- **Also fixed:** `scripts/validate-plugin.sh`'s fixture-schema check, which still
  asserted the old `catch_keywords` key — would have failed CI against every fixture's
  new `expect.json` had it been left as-is.
- **Verified live:** all three `expect.json` files re-validated as well-formed JSON
  carrying both keys; `evals/run-fixture.sh` re-run live against this branch, still
  reporting `CAUGHT` at the strict `gate-blocking-evidence` tier with the new
  anchor+signal logic. Full rationale: `evals/README.md`.
- **Residual, disclosed limitation:** anchor and signal only need to appear *somewhere*
  in the same claim/transcript, not adjacent or about the same clause — narrower than
  before, but still weaker than tier 1's gate-property check. Tiers 2/3 remain
  non-authoritative for CI regardless.

**Sixth pass — closed the `plan`/`build`/`eval` live-coverage gap:**

The remaining disclosed limitation from the fourth pass: only `review`/`check` were
exercised by a live fixture. `plan`, `build`, and `eval` were only tested by
`scripts/tests/test-temper.sh` — real for the CLI's own gate *logic*, but blind to
whether a real model, following the actual prompt, calls `temper evidence add`/
`temper gate` at all. That's not a hypothetical concern — it's exactly the bug class
the third pass found for the standalone commands, just not yet re-checked for these
three specific stages.

- **Added `evals/wiring-smoke/` + `evals/run-wiring-smoke.sh`** — a fourth fixture,
  differently shaped from the other three: no seeded defect, no `expect.json`, no
  catch/miss verdict. It chains three real headless invocations
  (`/temper:plan` → `/temper:build` → `/temper:eval`) against one small, deliberately
  trivial feature, then checks — by reading `.temper/gates.json` and
  `.temper/evidence/*.json` directly, the same files `temper gate commit` itself
  reads — whether each stage actually got called for real, not by matching keywords in
  a transcript.
- **Verified live, first run:** clean pass — `plan: PASS`, `build: PASS`, `eval: PASS`;
  `build` evidence 2 entries, `eval` evidence 1 entry; `temper state get complexity`
  correctly returned `trivial`. No wiring gap found in any of the three previously
  untested stages.
- **Wired into CI:** `.github/workflows/eval-fixtures.yml` runs it alongside
  `evals/run-all.sh` on the nightly + full on-demand paths (not the per-PR smoke
  check, to keep PR cost down); `scripts/validate-plugin.sh` checks the new fixture's
  required files and that `run-wiring-smoke.sh` is executable.
- **Narrowed, not closed at first: `commit` gate aggregation.** `temper gate commit`
  isn't invoked by a model that could forget a prompt instruction — the native
  pre-commit hook and the in-agent PreToolUse hook both call it unconditionally. The
  risk class that justified the rest of this pass doesn't apply the same way there;
  its aggregation logic was already unit-tested, but nothing had ever proven the real
  *mechanism* — the actual git hook the hook writer puts in place — really
  lands, really fires, and really blocks (or allows) a real `git commit`, as
  opposed to just the function it calls.

**Then closed for real, same pass:** asked directly "will it actually work?" instead
of leaving the narrowed gap as a documented tradeoff. Answered it by testing the real
mechanism — put the hook into a scratch repo, set a red gate, ran a real `git
commit`: blocked (exit 1, nothing landed in `git log`). Flipped the gate green, ran it
again: succeeded (exit 0, commit landed). Both directions needed no live model call,
only real git — so both are now permanent assertions in
`scripts/tests/test-temper.sh` (27 → 31 tests), not a one-off manual check. All five
pre-commit gate stages plus the commit gate's own installation mechanism are now
verified for real, live or deterministic as appropriate; no known gap remains.

Full writeup: `evals/README.md`.

## v6.0.1 — Standard Plugin Layout

Restructure to the standard Claude Code plugin layout in preparation for
plugin-directory submission. No behavior changes — every command, skill, pack,
and reference doc is byte-identical, only paths moved.

- **Standard layout:** `.claude/commands/` → `commands/`, `.claude/skills/` → `skills/`,
  `.claude/packs/` → `packs/`, `.claude-plugin/reference/` → `reference/`,
  `.claude-plugin/templates/temper.config.default` → `templates/`. `.claude-plugin/`
  now contains only `plugin.json` and `marketplace.json`, per plugin spec.
- **Plugin folder references updated** across commands, skills, packs, and
  reference docs to the new paths. Bare `.claude/packs/` (project-local) and
  `~/.claude/packs/` (global) resolution paths are unchanged — only the built-in
  tier moved.
- **Session logs untracked:** `.claude/interactions.log` and `.claude/session.log`
  removed from git (already gitignored).
- **README:** new "Security & Trust" section documenting the trust contract
  (no network calls/telemetry, writes confined to the project, autonomy never
  commits/pushes/merges).
- **Cursor export unchanged in role:** `.cursor/` remains a derived, frozen-at-v5.1
  export regenerated by `scripts/generate-cursor.sh`, now reading the new source
  paths. It is outside the plugin's command/skill surface.
- Scripts (`generate-cursor.sh`, `install-cursor.sh`, `version-bump.sh`,
  `validate-*.sh`) updated to the new layout.
- **`validate-phase3.sh` version scenario no longer pinned to `5.9.0`:** it was
  asserting every version stamp equals the Phase 3 release version, so it began
  failing on v6.0.0 and every release after. It now checks lockstep agreement
  against `plugin.json` (the single source of truth) instead, so it keeps
  passing across releases. The CHANGELOG-has-a-v5.9.0-entry check is unchanged.
- **Documented headless invocation:** confirmed via an end-to-end pipeline run
  (real fixture project, all 6 stages, plan gate through commit-gate park) that
  the bare `/temper` alias only resolves in interactive sessions — `claude -p`
  and CI callers must use the fully-qualified `/temper:temper`. Noted in the
  README quick start and in `docs/commands.md`.

## v6.0.0 — New Features

Autonomous Continuation for /temper (#63)

## v5.9.0 — Phase 3: Token Efficiency & Loop Engineering

Three independent, composable levers layered on the v5.6.0 model-routing foundation.
Each is config-flagged under `tokens:` in `.claude/temper.config`, default-on, and
degrades **byte-identically** to v5.8.0 when its flag is off.

### D1 — Cache the static instruction mass
- **`tokens.cache`**: stage agents read the cacheable context (methodology ref,
  orchestrator-patterns, pack-manifest, stack-pack, config) FIRST in a byte-stable order,
  then the volatile delta. Maximizes platform cache hits on re-entry; the orchestrator
  cannot force a cache, only structure reads so the prefix is stable.
- **`tokens.cached_input{value, source}`**: new v3 observability field records what the
  platform reports as cache-served (source `measured`/`estimated`). G-5 source rule extended.
- **Cacheable vs. Volatile Context** + **Cache-Stable Re-Entry** sections in
  `reference/orchestrator-patterns.md`. Cache Routing Resolution block in `temper.md`.

### D2 — Complexity-adaptive pipeline depth
- **`tokens.adaptive-depth`**: the plan stage's existing complexity classification
  (trivial|simple|medium|complex) selects a reduced pipeline per the new **Pipeline Depth**
  table. `floor` clamps the effective tier UP (`floor: medium` kills the trivial fast-path).
- Replaces the 4 blanket enforcement overrides (temper.md:153, temper.md:173, plan.md:518,
  plan.md:983) with a **DEPTH CONTRACT** conditional on `adaptive-depth.enabled`. The
  standalone `/temper:plan` complexity-tiered rules are UNCHANGED.
- Plan gate shows the chosen depth tier with an **"Escalate to full pipeline"** option.

### D3 — Incremental feedback loops
- **`tokens.loops`**: every feedback loop resolves by a cheapest-first decision rule —
  **inline** micro-fix (no subprocess) when all findings auto-fixable AND
  `files_touched <= inline-threshold`; else **fix-mode** minimal-context Build Agent (fix
  list + changed files + fix-mode preamble, NOT full `build.md`); else **full** re-launch.
- New **Loop Cost Tiers** section + per-loop `mode` + `cost` in observability.json `loops[]`.

### Degradation contract
- With `cache.enabled: false` + `adaptive-depth.enabled: false` + `loops.fix-mode: false` +
  `inline-threshold: 0`, a `/temper` run is byte-identical to v5.8.0 (full pipeline, full
  re-launch, no cache prefix, no `cached_input` field). v3 observability is an additive
  superset of v2.

### Other
- `reference/pricing.md`: cache read (~0.1x) / write (~1.25x) multipliers; dropped the
  "excludes caching" note — `cost_usd` MAY now reflect cache savings.
- `reference/tokenomics.md`: canonical 3-lever token-efficiency guidance.
- `.cursor/` frozen at v5.1 (only `.cursor/VERSION` bumped to 5.9.0 via `generate-cursor.sh`).
- New `scripts/validate-phase3.sh` mechanical verifier.

## v5.8.0 — New Features

Explain implementation-approach choices in plans (#59)

## v5.7.0 — Teach Me: comprehension companion across the teaching gates

Adds a sixth capability, **Teach Me** — a Socratic *teaching* companion (the
counterpart to Grill Me's *challenging*) that keeps the human engaged with every
change Temper makes. Where the walkthrough gives a one-shot tour and Grill Me
attacks assumptions, Teach Me confirms the user actually *understands* — phase by
phase — before the pipeline moves on. It maps to the three comprehension pillars:
**Problem** (Plan), **Solution** (Design, Build), **Impact** (Check, Eval).

### New skill
- `.claude/skills/teach-me/SKILL.md`: probe (user restates first) → teach the gaps
  incrementally with real code → quiz via `AskUserQuestion` (correct-answer
  position varied; answer never revealed until submit) → confirm mastery before
  ticking each item. Honors `eli5`/`eli14`/`elii` depth requests. Maintains a
  running `{spec_path}/comprehension.md` checklist organized under three pillars —
  **Problem (why)**, **Solution (what & how)**, **Impact** — that accumulates
  across phases and is never reset.
- Registered in `.claude-plugin/plugin.json` `skills[]`.

### Wired into the teaching stage gates
- `.claude/commands/temper.md`: a shared **"Teach Me (Comprehension Companion)"**
  handler plus a `Teach Me (Quiz me until I get it)` gate option on five gates
  (Plan, Design, Build, Check, Eval). Each phase teaches its own artifacts
  (Plan→intent/plan/tasks, Design→design.md, Build→the diff, Check→validation+coverage,
  Eval→score table) and returns to the same gate. Teach Me NEVER advances or blocks
  the pipeline — it only adds understanding. **Review is intentionally excluded** —
  its substance (the diff and its rationale) is already taught at Build, and its
  findings are usually minor or auto-fixed. The option label is distinct from the
  passive "Walk through … step by step" walkthrough to signal its active, quiz-driven nature.

### Config & docs
- New capability flag `capabilities.teach-me: true` in `.claude/temper.config`
  (default-on; graceful degradation — set `false` to hide the option everywhere).
- `temper-core` capabilities table gains a **Teach Me / Plan, Design, Build, Check, Eval** row.
- Version bump to `5.7.0` (`plugin.json`, `.claude/CLAUDE.md`).

> Cursor parity remains frozen at v5.1 (see v5.2.1 platform strategy) — this
> capability is Claude Code only and is not forward-ported to `.cursor/`.

## v5.6.0 — Phase 2: Harness Economics & Observability

Turns the paper's economic argument (high CapEx / low OpEx, intelligent model routing,
auditable observability) into measured, enforced harness behavior. Routing stops being
advisory; observability stops being self-estimated.

### Deliverable 1 — Intelligent model routing (enforced)
- New `models` block in `.claude/temper.config`: `enabled`, `tiers`
  (`tier-frontier` → opus, `tier-standard` → sonnet, `tier-fast` → haiku), `routing`
  per stage (plan/design→frontier, build→standard, review/check/eval→fast),
  `escalate-on` (`architecture-finding`, `correctness-risk`), `respect-user-override`,
  and `drift-threshold` (std-dev cutoff, default 2).
- `.claude/commands/temper.md`: each of the 6 stage Agent launches carries a `[MODEL:]`
  delta resolved from `models.routing.{stage}`. New "Model Routing Resolution" section:
  first-match-wins — disabled ⇒ no `model` param (v5.5.0 byte-identical), then
  user-override, then routing. Review escalates `escalate-on` findings from fast to
  frontier, reusing `review.md`'s confidence-scoring path.
- **Graceful degradation contract:** `models.enabled: false`/absent ⇒ no `model` param
  emitted, session model inherited — Scenario 1 enforces this.

### Deliverable 2 — Measured telemetry (not estimated)
- `.temper/observability.json` bumps to `version: 2` (schema documented in
  `reference/orchestrator-patterns.md`): per-stage `model_tier`, `model_source`,
  `tokens{input,output,source}`, `latency_ms`, `tool_calls`, `cost_usd`, `retries`,
  `eval_score`, plus `totals`. Extends the G-5 (v5.3.0) source-sibling rule to EVERY
  numeric leaf (`measured` | `estimated` | `user-override` | `pricing`).
- New `.claude-plugin/reference/pricing.md`: advisory, version-dated tier →
  `{input_per_1m, output_per_1m}` table; `cost_usd = (in/1e6)*in_price + (out/1e6)*out_price`.

### Deliverable 3 — Drift detection
- `.temper/metrics.json` extended (additive) with `stage_baseline` (rolling per-stage
  history) and `drift_flags[]`. A run deviating > `drift-threshold` std-dev from its
  baseline is flagged at severity `SUGGEST`. Drift flags NEVER auto-block a stage gate;
  surfaced in `/temper:status`.

### Deliverable 4 — Economics panel in `/temper:status`
- New ECONOMICS panel in `.claude/commands/status.md` + `reference/status.md`:
  per-stage cost/latency/tier (last run), rolling averages, eval-score trend, drift
  flags, and a CapEx vs OpEx summary. Absent/v1 observability ⇒ "No observability
  data yet" (graceful, no error). Source flags surfaced alongside every numeric.

### Cross-cutting
- `.claude-plugin/reference/tokenomics.md`: advisory "prefer Sonnet" replaced with a
  pointer to the enforced `models.routing`, so guidance and behavior agree.
- New `scripts/validate-phase2.sh`: one-shot bash+python mechanical verification for
  all 9 Phase 2 scenarios (config schema, routing conditionals, v2 source provenance,
  pricing parseable, drift flag, status panels, version lockstep, cursor freeze).
- `.cursor/` regenerated via `scripts/generate-cursor.sh`; FROZEN at the v5.1 feature
  set (no v5.6 routing/observability features leaked into frozen cursor commands).
- Version lockstep: `plugin.json` == `.cursor/VERSION` == `CLAUDE.md` == `temper.md` == 5.6.0.

## Unreleased — Eval Score-Table Readability

Improvements to the human-gate readability of the Eval stage score table (extends the v5.5.0
eval feature, same phase). No version bump — ships under v5.5.0.

- **Group dimensions by category:** every rubric dimension now carries a `category`
  (`artifact` = judges the produced code/output → "fix the code"; `process` = judges the run →
  "fix the run"). Score table rows are grouped under `ARTIFACT — fix the code` and
  `PROCESS — fix the run` headers instead of a flat, equally-weighted list. Added to
  `templates/evalset.json`, the rubric dimension table in `reference/eval.md`, and the
  `eval-judge` skill (with name-based defaults when a rubric omits `category`).
- **Recommended action per low row:** each row below `pass_threshold` is annotated with what to
  do — `→ Re-run (code defect)` (artifact-low), `→ Re-run (block-on failed)` (any block-on dim
  low), or `→ accept (process noise)` (process-low, not block-on). Actions computed by the
  `eval-judge` skill and stored in `recommended_actions`. Codified in `reference/eval.md` →
  "Reading the Score Table".
- **Surface partial aggregates loudly:** when any dimension is `"unscored"`, the aggregate is
  computed over the **scored subset only** (weights re-normalized), recorded as
  `aggregate_basis: "scored"` + `scored_weight`, and the table prints a caveat naming the count
  and the unscored dimensions — a 0.80 that's half-unscored no longer reads as a full 0.80.
- **"How to read this" legend:** a one-line legend prints above the table on every eval run
  ("0–1 scale, {pass_threshold} to pass. Low ARTIFACT-scores mean fix the code; low
  PROCESS-scores mean the run was messy.").
- **Schema additions:** `category` per dimension in the rubric + results; `aggregate_basis`,
  `scored_weight`, `recommended_actions` in `results-{ts}.json` and `eval-context.json`.
- **Surfaces kept in sync:** `.claude/commands/temper.md` + `.cursor/commands/temper.md` (Eval
  Summary Format + agent return contract), `.claude/commands/eval.md` +
  `.cursor/commands/temper-eval.md`, `reference/eval.md`, `reference/orchestrator-patterns.md`,
  `eval-judge` SKILL.md.

## v5.5.0 — Phase 1 Verification

Behavioral verification layer + deterministic safety net (PR #49,
`docs/plans/phase-1-verification.md`).

- **D1 — Eval command + skill:** `/temper:eval` command (default output eval, `--create`
  scaffold, `--trajectory` mode), `eval-judge` skill (LM-judge per-dimension scoring on a
  cheaper model tier with deterministic fallback), `reference/eval.md` methodology,
  `templates/evalset.json` schema (5 default rubric dimensions + weights + pass_threshold).
- **D2 — Eval stage in `/temper`:** new "Stage 4.5: Eval" between Check and commit (isolated
  Agent subprocess, score table + `eval-context.json`, gate {Continue, Re-run, View results,
  Save-for-later}, Eval→Build feedback loop). `eval-context.json` schema in
  `orchestrator-patterns.md`. Default-on config with one-line skip when evalset/config absent.
- **D3 — Plan-time evalsets:** Plan stage emits a draft `evalset.json` from intent.md scenarios;
  plan summary box shows an `EVALS: {N}` line.
- **D4, a deterministic guard pack:** guard scripts `block-secrets.sh`,
  `block-forbidden-imports.sh`, `verify-tests-ran.sh` — deterministic, fail-closed on detected
  secrets, fail-open (no-op) on missing scripts/state. Turned on with `/temper:pack enable` (the pack is called guardrails since 9.6.5;
  it merges its settings snippet into settings.json through the `update-config` skill).
- **Cross-cutting:** `eval` + `capabilities.evals` config (default-on, graceful degradation);
  `validate-plugin.sh` assertions for every new file; Cursor parity via `generate-cursor.sh`
  (`temper-eval.md`, `temper-ref-eval.mdc`, `temper-pack-hooks.mdc`); version bump to 5.5.0.

**Graceful degradation contract:** every new capability no-ops cleanly when its config flag,
supporting files, or judge model are absent — never hard-errors.

## v5.4.0 — CI / Tooling

Auto-generate concise CHANGELOG notes from commits (#53); add release-bump.yml — one-button version bump workflow (#51); phase 0 implementation gaps — close G-1..G-6 (v5.3.0) (#50)

## v5.3.0 — Phase 0 Implementation Gaps (Promise vs. Reality)

Closes the six drift findings from `docs/plans/implementation-gaps.md` (PR #49).
The plugin now does what its own docs/config/skills promise, before Phase 1
(verification) extends it.

- **G-1 — Single version source of truth:** `scripts/version-bump.sh` now
  rewrites every stamp (plugin.json, `.cursor/VERSION`, `.claude/CLAUDE.md`,
  `.claude/commands/temper.md` header). `scripts/validate-plugin.sh` gained
  three assertions so stamp drift fails CI. The `temper.md` header (v4.4.1)
  is no longer stale.
- **G-2 — Regenerable Cursor export:** new `scripts/generate-cursor.sh`
  transforms `.claude/` (packs, skills, capabilities, reference docs, commands)
  into `.cursor/` rules + commands as a pure, idempotent, offline function.
  `install-cursor.sh` now delegates to the generator inside a repo checkout.
  Cursor remains **frozen at the v5.1 feature set** — regeneration makes parity
  honest and consistent, not feature-advancing. `.cursor/` was regenerated.
- **G-3 — Phase-scoped pack loading wired in:** `review`, `build`, `check`,
  `plan`, and `design` stage docs now load only packs whose `phases` is `all`
  or contains the current stage, per the `pack.md` contract. The promised
  token/scoping benefit is now realized at the point of use.
- **G-4 — Manifest cache consumed:** the same block consults
  `.temper/pack-manifest.json` (rebuilt if stale) before loading packs,
  closing both G-3 and G-4 in one coherent change. `temper-core/SKILL.md`
  claim updated to match reality.
- **G-5 — Honest observability labels:** every value written to
  `.temper/observability.json` now carries a `source: measured|estimated`
  field; the misleading `track-tokens` config comment is clarified. Real
  measured telemetry is Phase 2 scope.
- **G-6 — Learning flywheel fixture:** redacted
  `.temper/fixtures/learning.sample.json` proves the adaptive-learning loop
  shape. Live dogfooding (enough review cycles to promote a rule) is deferred
  to a follow-up session; G-6 was non-blocking.

**Validation:** `validate-plugin.sh` 16/0, `validate-docs.sh` 6/0,
`validate-readme.sh` 5/0, `generate-cursor.sh` idempotent.

## v5.2.1 — Growth Plan & Benchmark Improvements

- **README rewrite:** 829 → 172 lines (79% reduction). First screen: problem → catch story → quick start.
- **CI quality gates:** 4 offline-safe validation scripts + GitHub Actions workflow (quality.yml).
- **Landing page refresh:** Open Graph tags, JSON-LD, evidence section, OCR card. All parity claims removed per §1 platform strategy.
- **Evidence documents:** Benchmark methodology, dogfooding case study, feature comparison matrix.
- **Benchmark results:** Temper catches 12/12 bug patterns in playground testing vs vanilla Claude Code's 8/12.
- **Race condition detection:** Performance pack now flags non-atomic mutations on shared state in concurrent contexts.
- **Middleware stack completeness:** Review checks for error middleware, CORS, helmet in app entry point.
- **Community infrastructure:** 4 issue templates, CONTRIBUTING.md and getting-started.md updates.
- **Playground repo:** [galando/temper-playground](https://github.com/galando/temper-playground) with 4 intentional flaws for demo.
- **Platform strategy:** Cursor support frozen at v5.1 feature set. New capabilities ship Claude Code-first.

## v5.2.0 — OCR Integration (External Review Engine)

- **open-code-review integration:** `ocr` CLI is now an optional external review
  engine inside `/temper:review`. When present and configured, OCR takes over
  line-level defect detection (NPEs, injections, thread-safety). Temper keeps
  intent validation, security analysis, architecture depth, and review memory.
- **Auto-detection:** `ocr` is probed during Step 1 and enabled automatically
  when available (`tools.ocr.mode: auto`, the default). Missing OCR is silent
  in auto mode; blocks in require mode with setup instructions.
- **Step 2.5:** New pipeline step runs OCR between subagent launch and intent
  validation. JSON output parsed, severity-mapped, labeled `[OCR]`, and
  deduplicated against Temper findings. Cross-validated findings are labeled
  `[OCR+TEMPER]` with boosted confidence (min(0.95, max + 0.15)).
- **Subagent takeover:** When `tools.ocr.replace-defect-subagent: true` (default),
  Temper subagents drop generic defect-hunting sections. OCR owns line-level
  defects; Temper keeps pack rules, security, AI-code detection, architecture.
- **Config block:** `tools.ocr` in `.claude/temper.config` with mode, timeout,
  concurrency, and extra-args settings.
- **Status dashboard:** `/temper:status` shows OCR availability and accept rate
  under renamed "EXTERNAL TOOLS" section (was "MCP TOOLS").
- **Evidence labels:** New `[OCR]` and `[OCR+TEMPER]` labels in review output.
- **Documentation:** Updated recommended-setup.md, README.md, commands.md, and
  schema notes, now in `docs/plans/ocr-notes/`.
- **No breaking changes.** All changes are additive. Zero-config when OCR is not
  installed — review runs identically to v5.1.0.

## v5.1.0 — Nested Subagent Support

- **Nested agents config:** Added `agents` block to `.claude/temper.config` with
  `nested`, `max-depth`, `parallel-width`, and `on-budget-exhausted` settings.
  Defaults to `max-depth: 4`, `parallel-width: 3`, graceful inline fallback.
- **Depth budget governance:** Updated orchestrator-patterns.md to pass
  `depth_remaining` to stage agents. Stages check budget before spawning:
  `depth_remaining > 1` → spawn, `depth_remaining <= 1` → run inline.
- **Depth-2 helpers enabled:** Review parallel subagents, Plan Explore auto-prime,
  Fix Explore RCA, and architecture-depth Explore now work in the composed
  `/temper` pipeline (previously degraded when run through orchestrator).
- **Graceful degradation:** Depth exhaustion falls back to inline work instead
  of hard failure. Deterministic local budgeting; no global tree state needed.
- **ADR-0002:** Documented nested subagent support strategy in
  `docs/decisions/0002-nested-subagent-support.md`.

## v5.0.1 — Token optimization

- **Orchestrator dedup:** `temper.md` and `fix.md` now delegate repeated
  build-state schemas, gate-enforcement prose, context-file schemas, feedback-loop
  schemas, and stage-agent launch scaffolding to a single canonical definition in
  `reference/orchestrator-patterns.md` instead of re-inlining them per stage.
- **Single-load contract:** orchestrators read `orchestrator-patterns.md` once at
  start; all `→ pattern` references point into that already-loaded file (no re-reads).
- **Progressive loading:** `reference/review.md` and `reference/plan.md` gained a
  Progressive Loading Map so stage agents load core sections first and pull optional
  sections only when their trigger fires. Duplicated optional methodology (arch-depth,
  HTML review) trimmed to references.
- **Lean memory:** `.claude/CLAUDE.md` trimmed to the command table + pointers; version
  history moved here, token insights moved to `reference/tokenomics.md`.