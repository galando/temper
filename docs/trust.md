# Trust

With the mod off, every stage works the same; the mod adds the bar, the pane and its write guards. Nothing falls back
silently.

Markdown, a mod written in TypeScript, about 5,900 lines of auditable bash (the CLI `scripts/temper` and the eleven
guard scripts), and 86 Python files under `scripts` outside its test folders `selftest` and `e2e` (about 25,200 lines,
standard library only), which compute the gate requirements and what comes next; seven of them are checks of this
repository. Counted with `wc -l` for 9.8.5. Temper itself makes no network calls, sends no telemetry and adds no
packages. The committed artifacts (intent, plan, design, gate ledger and diff) are the audit trail, in the same commits
as the code.

## What Temper runs and changes

Temper's scripts run locally with `bash`, `git` and `python3`, and write only inside your project and its git
folder. Apart from the mod's plugin store, Temper reads no place in your home folder that git does not name (since
9.8.5 not even a pack folder there). Through git it reads the hooks folder your git
config names, which may be in your home folder; it reads no name or email from git (an accepted intent or an
override records that the person decided it at the gate). It reads no key, login, transcript, settings or other
Claude Code file. A pack's link targets come from the skills and commands your session lists.

- **Plugin hooks.** The plugin's hooks file registers four classic hooks and the mod module. `UserPromptSubmit` runs
  `scripts/guards/stage-marker.sh`, which notes that a `/temper:temper draft` session owes an intent gate (a run of
  `/temper:temper` owes none). `Stop` runs `scripts/guards/verify-stage-gate.sh`, which can ask Claude to keep working
  (at most twice per stage) until that gate has a verdict. `PreToolUse` on Bash runs
  `scripts/guards/block_stdin_wait.py` (9.8.0; a Python file since 9.8.1, answering deny as JSON), which refuses, in a
  folder with a `.temper` folder at or above it, a command whose `cat` has no input while the command holds a heredoc:
  Claude Code leaves that command's input open, so the `cat` would wait until the Bash timeout. It reads only the
  command and looks for that folder. `PreToolUse` on the tools that write a file (Write, Edit, MultiEdit, NotebookEdit)
  runs `scripts/guards/hold_before_approval.py` (9.8.5), which holds rule 1 with the mod off: at Intent, Plan and Design
  of a `/temper:temper` run, before you approve the plan, it refuses a write of a project file (a path of the project
  outside `.temper/`, where the spec folder is), as the mod's own rule does. A `/temper:fix` run and a shell command
  that writes a file are outside it; for those the commit hook still refuses a commit of a project file before the
  approval. It reads the run state and the path, and only ever answers deny. All four fail open.
- **The approval is bound to what was shown (9.8.5).** The approving call carries the digests of `intent.md` and
  `tasks.md` as the question showed them, and the CLI refuses it when a file changed since. With the mod the click is
  checked against those digests (the call is matched word for word); with the mod off nothing checks the click, but
  the Build, Check and commit gates still fail on a later change to either file (the row `intent unchanged since the
  approval`) until you approve again. Before the approval a run makes no branch and no commit; the commit hook gates
  the branch the run stands on then too.
- **The run driver (9.8.0).** With the mod loaded, the mod carries a `/temper:temper` run itself: it runs the temper
  CLI's calls (`temper go` and the calls it gives: the plugin's own `scripts/temper` by its path with plain arguments,
  in the project, never through a shell since 9.8.1), launches the agents the CLI names and asks its questions. It runs
  no command the CLI did not give, and a call of an answer only after you picked that answer in the question dialog.
  What needs a model or your words goes back to the conversation ([The mod](mod.md), The run driver).
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
  Build runs each task's declared test command in its worktree, the way your shell would, but without the
  environment variables whose names say they hold a credential (a key, a token, a secret, a password,
  credentials, an auth socket): no command the CLI runs is handed your keys.
- **What Check measures (9.8.5).** A gate row is passed, failed, or `not measured`: a measurement that was not taken,
  such as coverage with no coverage tool for the stack, a coverage program that could not start, or no base value to
  judge it against. A row not measured fails nothing and passes nothing; the gate output marks it `[?]`, the mod
  draws it `?`, and the commit card names it, so a number nobody measured is never shown as passed. Coverage is
  judged against the project's own base value, not a fixed number, unless your config sets `check.coverage-threshold`.
  The planted bug score (`temper check ahead`, beside Review, into `.temper/evidence/mutation.json`) is information
  only: it gates nothing and moves the run nowhere.
- **The baseline (9.8.5).** Before any agent and before any approval, a run checks the tools and services your
  project's files and config name, then runs your project's own test command once on the current code, in a detached
  worktree under `.claude/worktrees/` (no branch, no commit, no project file changes). The command is the one your
  config names, or the one Temper detects; it runs with the credential variables left out, as every command the CLI
  runs. "Go on anyway" at a red base is a recorded skip of the base's failures; only the mod ties it to your click
  (with the mod off nothing checks who ran `temper baseline accept-red`, and the skip row says it was the person). A
  green base that Temper reuses from its store is as old as the date the store shows for it.
- **A reused result (9.8.5).** The same command on the same tree runs once: a pass or a failure is kept in
  `temper-results.json` in your git folder and given again, with its date, on the same key (the tree as it is, the
  command, the setup block, the folder, the first version line of each program it starts). A reused pass proves what
  one run proved: one run per tree is the guarantee one CI run gives, weaker than the repeated runs of 9.8.4, so a test
  that fails one time in ten can pass once and be kept. What the key cannot see is not in it: ignored folders such as
  `node_modules` or `target/`, environment variables outside the setup block, a service's state, the clock, a file
  outside the repository. A pass in a group worktree
  is reused for the project folder with the same content, so a test that depends on its absolute path is not run again
  where the code will live. A failure kept on the same tree is not run again until the code, the command or the
  setup block changes; "Run it anyway" (`--fresh`) runs it whatever the store holds, and counts as one repeat. It is
  your option only: a run that goes on by itself never takes it (the CLI refuses it there), and only the mod ties it
  to your click. With the mod off the budget alone holds it: nothing checks who ran `--fresh`, and each call spends
  one repeat.
- **Its own commits.** In a grouped Build the CLI commits each task's declared files in its worktree and merges
  them, as plain `git commit` and `git merge` calls that use git's own identity and settings (signing too, when
  you turned it on). Before one, it asks git only whether an identity is set (an exit status; git guesses none
  from your system account), and uses the fixed `Temper <temper@localhost>` when none is.
- **No diff leaves the machine through Temper.** Review runs inside Claude Code, and 9.8.5 removed the external
  review engine. Temper adds no tool; the guardrails pack and autonomy run only when you ask.
- **Guardrails pack (opt in).** `/temper:temper pack enable guardrails` prints the guard hooks, with the plugin folder's
  absolute path written in, for you to add to the project's `.claude/settings.local.json` or `.claude/settings.json`;
  `/temper:temper pack disable guardrails` says which to remove. Temper never opens a Claude Code settings file, the
  project's or your home folder's.
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

**What resolves a finding, and what the completion row proves (9.8.5).** A finding is resolved only by the CLI, in
`temper repair close` (WP24, ADR 0021), for the repair commit it made after the reviewed HEAD on the run's branch: the
checks ran again on that tree and passed, a reader that did not write the fix wrote `recheck #<id>: fixed` after the
commit and after the recheck's launch mark, and a finding marked `proof: test` had a RED before the fix and a GREEN
after it, both run by the CLI on unchanged test files. A note or a commit made by hand resolves nothing. Otherwise a
finding ends by your accept, or by a loop back and a second Review. The CLI cannot tell the fixer and the reader apart:
the order of the rows stands in for it. The recheck reads the diff, not the code around it, so a defect outside the
changed lines is caught only by the CLI's own runs: a project with a thin suite gets less than a second full Review
gave, and a diff over 300 lines, or one that touches a file no finding names, gets a full Review again. Review's
completion row names the files the reviewer says it read, and the CLI compares those names with the changed files. No
more: the CLI cannot see the reading. The row turns skipping a file from silence into a false statement in the ledger.

**What a repair may commit (9.8.5).** A repair commits by rule only the plan's files, the tests, and a file you added
to the plan or allowed once by answering a question the CLI asked: a Scope drift question about a file a drift ask
named, the stop of a repair on that file, or the commit gate's failed scope row. The CLI marks such an answer as it
writes it, and refuses an answer to no question while a repair is open. That you gave the answer, and not the fixer,
only the mod holds: it refuses an agent's call that records an answer you did not give. With the mod off, nothing
checks who ran the answer's call.

**A criterion you confirm (9.8.5).** A criterion validated by hand, or by `code` or `metric` with no command in
backticks, passes Check only from the row your Confirmed answer at the Check question writes: `temper evidence add
--person`, a row marked `executed_by: person`. A row an agent records, or a CLI run of a command an agent chose, does
not count for it. That the answer was yours only the mod holds: it lets a `--person` call through only as the call of
the option you picked, word for word, as it does Run it anyway. With the mod off, nothing checks who ran it: the Check
brief tells the agent never to record one, the CLI takes the flag only with a criterion and exit 0 and never in a run
that goes on by itself with no stop open, and the row stays in the ledger as the person's, where `temper evidence list
--stage check` marks it. A field list passed through `--read` is refused, so no other call marks a row as yours.


**What only the mod holds.** The rules of a run hold in the CLI or in the commit hook with the mod off, within the
limits this page names, but one: that a person, not the model, picked an option. With the mod off, nothing but the
page's rule holds it: `commands/temper.md` tells Claude to ask each question exactly as the CLI wrote it and never to
choose for you, and the CLI runs the calls of whatever option is carried out. With the mod on, an answer counts only
when the header, the question and the label match what the CLI wrote, at the run and the step the CLI is at.

## Pull requests and the Pipeline stage (9.7.5)

- **Reads.** The Pipeline stage reads the pull request's checks with `gh pr checks` and `gh run view <id> --log-failed`
  (over REST, `gh api repos/{owner}/{repo}/commits/{head sha}/check-runs`, where GraphQL is not available); `gh` takes
  the repository from `origin`. A log is untrusted text: the agent runs nothing from it and copies no token from it.
  Temper reads, stores, prints and sets no token.
- **Writes.** Only `reference/pr.md` pushes or calls `gh pr create`, after the person chose a pull request option at the
  Check question. Every pull request is a draft; Temper never runs `gh pr ready`. A run that goes on by itself never
  pushes. Temper pushes only after the person chose a pull request option at the commit question; the run stops there.
- **The commit hook** gates the run's branch only. A commit on another branch passes with one line. That is a known
  limit.
- **Turning Temper off.** After you disable the plugin, run `temper guards uninstall`. The hook also passes on its own,
  with one line that names the command, once the plugin's files are gone. Temper reads no settings file to find out that
  a plugin is disabled.
