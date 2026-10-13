// The guard (ADR 0012): `evaluate(ctx, call)` answers allow or deny for one tool call. Pure. It has three jobs:
//  1. a CLI call that only the person may cause needs the person's move at the CLI's current step;
//  2. Claude never writes Temper's own files, and no commit gets past the native hook (it is the commit gate);
//  3. each stage allows its own writes.
// Where the run is, every verdict and every skip come from the CLI's files (RunFacts); the person's choices come from the
// question dialogs (core/decisions.ts). Every deny text ends with what to do next, and names the `Temper gate` question,
// the one place the person decides. core/bash.ts reads the shell commands; it is frozen (no new parsing).

import { DRIFT_HEADER, DRIFT_PREFIX } from './drift'
import { classifyBash, protectedKind } from './bash'
import type { ProtectedKind } from './bash'
import type { DriftState, Move } from './decisions'
import { CLI } from './cli'
import { matchesPlan, normalizePath } from './paths'
import type { Stage } from './stages'
import { hasDesign, isStage, nextStage, stageIndex, stageLabel } from './stages'

// What the CLI's files say about the run, for the guard.
export type RunFacts = {
  // The stage the CLI is at (`next_stage`). `commit`: every gate is behind the run; it is done.
  stage: Stage
  // The CLI's step count (ADR 0012): 0 right after `state init`, -1 for a run state written before it.
  step: number
  runMode: string | null
  complexity: string | null
  // `phases.design: true` in .claude/temper.config.
  designRequired: boolean
  // The run has a design verdict or is at Design: it has a Design stage whatever the config says now.
  designSeen: boolean
  // `autonomy.enabled: true` in .claude/temper.config: the person has opted in to autonomous runs.
  autonomyEnabled: boolean
  // .temper/groups.json exists: a grouped Build run is active, and the CLI (not an agent) ticks the run's tasks.md.
  groupedActive: boolean
  verdicts: Partial<Record<Stage, 'PASS' | 'FAIL'>>
  skipped: ReadonlySet<Stage>
  // The spec directory, relative to the root: `.temper/specs/{slug}`.
  specDir: string
  // File entries from plan.md and tasks.md (exact paths, `dir/` prefixes or globs).
  planFiles: readonly string[]
}

export type RuleContext = {
  // The run, or null when no /temper run is active (the mod then guards only what needs no run).
  run: RunFacts | null
  // The person's move at the CLI's current step (the latest one), or null.
  move: Move | null
  // The findings the person accepted at this step.
  accepts: readonly string[]
  // The person chose Start over in this run.
  restart: boolean
  // The person's Scope drift answers in this run.
  drift: DriftState
  // A /temper:fix run is active: the mod judges none of its moves (commands/fix.md asks every gate), but nothing goes
  // around the native commit hook, and the config and the git hooks stay the person's.
  fixRun?: boolean
  // Absolute project root; absolute tool paths inside it are made relative.
  root?: string
  // The folder the shell is in (relative to the project root, or absolute), carried from the earlier Bash calls.
  cwd?: string | null
  // Where the Temper script is: every deny text names the CLI by it.
  cli?: string
  // The CLI's files and the spec folder show a run that never left Intent (see nothingToLose in the adapter): a
  // `state clear` then loses nothing (the TRIVIAL exit of the orchestrator). Left out: not known, and the clear is refused.
  nothingToLose?: boolean
}

export type ToolCall = { tool: string; input: Record<string, unknown> }

// `use`: a decision this call spends (Keep the agent's commits, an Allow once answer); it counts once.
export type RuleResult = { allow: true; use?: string } | { deny: string; drift?: string }

const ALLOW: RuleResult = { allow: true }
const WRITE_TOOLS = new Set(['Write', 'Edit', 'MultiEdit', 'NotebookEdit'])

const TEST_FILE = [/(^|\/)(?:tests?|__tests__|specs?)\//, /\.(?:test|spec)\.[^/]+$/, /(^|\/)test_[^/]*$/, /_test\.[^/]+$/]

export const isTestFile = (path: string): boolean => TEST_FILE.some(re => re.test(path))

const ASK = 'ask the user with AskUserQuestion, header `Temper gate`'

export const ONLY_USER = `Only the user decides this. Next: ${ASK}, then wait.`

const AUTONOMY_REPORT = '.temper/autonomy-report.md'

function targetPath(call: ToolCall): string | null {
  const raw = call.tool === 'NotebookEdit' ? call.input.notebook_path : call.input.file_path
  return typeof raw === 'string' && raw.length > 0 ? raw : null
}

const inDir = (path: string, dir: string): boolean => path === dir || path.startsWith(dir + '/')

// A /temper run is on, at any stage up to and with Commit: the commit gate can still fail at the commit stage (a missing
// verdict, an autonomous park), so nothing may go around it there either. Writes are free at Commit (stageWriteRule).
const isActive = (ctx: RuleContext): ctx is RuleContext & { run: RunFacts } => ctx.run !== null

const design = (r: RunFacts): boolean => hasDesign(r.complexity, r.designRequired, r.designSeen)

// The stages a `state advance` from `s` may name next. A medium or complex plan goes to Design; when the project never
// switched design on, it may go straight to Build.
function allowedNext(r: RunFacts, s: Stage): Stage[] {
  // A design.md in the spec folder makes Design the next stage (the commit gate wants its verdict then).
  if (s === 'plan' && (r.complexity === 'medium' || r.complexity === 'complex') && !r.designRequired && !r.designSeen) return ['build', 'design']
  const n = nextStage(s, design(r))
  return n === null ? [] : [n]
}

// The stage's check passed, or the person skipped it, in this pass of the stage (the CLI clears both on a step back).
const settled = (r: RunFacts, s: Stage): boolean => r.verdicts[s] === 'PASS' || r.skipped.has(s)

// An armed autonomous run loops back to Build by itself after a failed Review or Check (never to Plan or Intent), within
// the CLI's loop budget (reference/autonomy.md). It was armed at the plan gate, by the person.
const armed = (r: RunFacts): boolean => r.runMode === 'autonomous' && r.autonomyEnabled

function protectedDeny(kind: ProtectedKind, cli: string): RuleResult {
  if (kind === 'events' || kind === 'overrides') return { deny: ONLY_USER }
  if (kind === 'folder') {
    return {
      deny:
        'Temper: the .temper folders hold the run, its verdicts and its decisions. Do not remove or replace them by hand. ' +
        `Next: use ${cli} state archive after the run, or name one file.`,
    }
  }
  if (kind === 'config') {
    return {
      deny:
        'Temper: .claude/temper.config sets how this run is checked (autonomy, thresholds, what blocks a review). Only the user changes it while a run is active. ' +
        'Next: ask the user to edit it themselves, or to end the run first.',
    }
  }
  if (kind === 'evidence' || kind === 'loops') {
    return {
      deny:
        'Temper: the evidence ledger and the loop counter belong to the temper CLI. Do not write them by hand. ' +
        `Next: use ${cli} evidence add, run or resolve, and ${cli} state loop.`,
    }
  }
  if (kind === 'hooks') {
    return {
      deny:
        'Temper: the git hooks, the Temper commit hook and core.hooksPath are the native commit gate. Do not change them while a run is active. ' +
        'Next: ask the user, or finish the run first.',
    }
  }
  if (kind === 'state') {
    return {
      deny: 'Temper: use the temper CLI to change run state. Do not write it by hand. ' + `Next: use ${cli} state set or ${cli} state advance.`,
    }
  }
  return {
    deny: 'Temper: the temper CLI makes the gate verdicts. Do not write them by hand. ' + `Next: run ${cli} gate <stage> and read the verdict.`,
  }
}

// The path inside a group or task worktree of THIS run (`.claude/worktrees/temper-{slug}-G{n}/...` or `-T{n}/...`),
// relative to that worktree; null for any other path. The path is normalized already, so a `..` after the prefix has
// been collapsed and cannot leave the worktree this way.
function worktreeRelative(path: string, specDir: string): string | null {
  const slug = normalizePath(specDir).split('/').pop() ?? ''
  if (slug === '') return null
  const prefix = `.claude/worktrees/temper-${slug}-`
  if (!path.startsWith(prefix)) return null
  const m = /^[GT](\d+)\/(.+)$/.exec(path.slice(prefix.length))
  return m?.[2] ?? null
}

const TASKS_OWNED =
  'Next: the temper CLI ticks task boxes and records task verdicts. Run the task through the CLI (task test, task gate), or ask the user to end the grouped Build run first.'

function stageWriteRule(ctx: RuleContext & { run: RunFacts }, rawPath: string): RuleResult {
  const r = ctx.run
  // A write in a group or task worktree of this run is judged by its worktree-relative path, with the same rule.
  const rel = worktreeRelative(rawPath, r.specDir)
  const path = rel ?? rawPath
  const spec = normalizePath(r.specDir)
  // In grouped Build the CLI ticks the run's tasks.md: from Build on, no agent writes it.
  if (r.groupedActive && stageIndex(r.stage) >= stageIndex('build') && path === `${spec}/tasks.md`) {
    return { deny: `Temper: grouped Build is active. Writing ${rawPath} is not allowed: the run's tasks.md belongs to the temper CLI. ${TASKS_OWNED}` }
  }
  const inSpec = inDir(path, spec)
  const specFile = (name: string) => path === `${spec}/${name}`
  const label = stageLabel(r.stage)

  switch (r.stage) {
    case 'intent':
      if (specFile('intent.md') || specFile('intent-context.json')) return ALLOW
      return {
        deny:
          `Temper: ${label} stage. Writing ${path} is not allowed until the user approves the intent. ` +
          'Do not look for another way. Do not offer to turn Temper off. ' +
          `Next: finish intent.md. Then ${ASK} (Continue to Plan).`,
      }
    case 'plan':
    case 'design': {
      const ok =
        ['intent.md', 'plan.md', 'tasks.md', 'design.md', 'config-suggestions.json'].some(specFile) ||
        (inSpec && /-context\.json$/.test(path)) ||
        (path.startsWith('docs/decisions/') && path.endsWith('.md'))
      if (ok) return ALLOW
      return {
        deny:
          `Temper: ${label} stage. Writing ${path} is not allowed until the user approves the plan and Build starts. ` +
          'Do not look for another way. Do not offer to turn Temper off. ' +
          `Next: finish the ${r.stage === 'plan' ? 'plan' : 'design'}. Then ${ASK}.`,
      }
    }
    case 'review':
      if (inSpec) return ALLOW
      return {
        deny:
          `Temper: ${label} stage. Writing ${path} is not allowed. Review changes the spec folder only. ` +
          `Next: write the finding in the spec folder. To fix it, ${ASK} whether to loop back to Build.`,
      }
    case 'check':
      if (inSpec) return ALLOW
      return {
        deny:
          `Temper: ${label} stage. Writing ${path} is not allowed. Check only runs checks. ` +
          `Next: finish the check stage. To change code, ${ASK} whether to loop back to Build.`,
      }
    case 'build': {
      if (inSpec || isTestFile(path) || matchesPlan(path, r.planFiles) || ctx.drift.added.some(p => normalizePath(p) === path)) return ALLOW
      const once = ctx.drift.allowOnce.find(a => normalizePath(a.path) === path)
      if (once) return { allow: true, use: once.id }
      return {
        deny:
          `Temper: scope drift. ${path} is not in the plan, so the user decides first: add to plan, revert, or allow once. ` +
          'Do not write it another way. Next: in the Build stage, stop this task and list the file in the DRIFT section of your ' +
          'panel, with why it is needed and what you would change. In the main conversation, ask with AskUserQuestion: ' +
          `header "${DRIFT_HEADER}", a question whose first line is "${DRIFT_PREFIX} ${path}", then a "Why:" line and a ` +
          '"Change:" line, and the options Add to plan, Revert, Allow once.',
        drift: path,
      }
    }
    case 'commit':
      return ALLOW
  }
}

const AUTONOMY_DENY =
  'Temper: only the user can turn on autonomous mode, at the plan gate. ' +
  `Next: ${ASK} at the plan gate: "Stage by stage" or "Autonomous: run the rest unattended". ` +
  'It needs autonomy.enabled: true in .claude/temper.config, which only the user sets.'

// The keys of build-state.json that only the CLI's own moves write. next_stage is a step (see the back calls).
const GUARD_KEYS = new Set(['stage', 'branch', 'spec_path', 'command', 'run_id', 'step'])

const UNCHECKABLE = (cli: string): string =>
  'Temper: this command writes to a path that Temper cannot check, and it names Temper state. ' +
  'Next: write the exact file path with no variables, globs, braces or substitutions. Or use ' +
  `${cli} gate <stage>, ${cli} evidence or ${cli} state.`

const DONE_OVERRIDE_DENY =
  "Temper: the run is done, and an override now is the user's choice. " +
  `Next: show the failed commit gate and ${ASK}: "Override and commit" (with a reason) or "Save for later". ` +
  'Then run every override that commit needs.'

const REPEATED_FLAG =
  'Temper: this decision call repeats a flag (--id, --stage or --reason). ' +
  'Temper cannot match it to the decision of the user. Next: run the call again. Give each flag one time.'

const STATE_RESTART =
  'Temper: state init and state loop restart or move the run. Only the user decides that. ' +
  'Next: ask the user with AskUserQuestion, header `Temper resume`, whether to start over (or, for a step back, the Loop back choice of the `Temper gate` question).'

const STATE_END = (cli: string): string =>
  'Temper: do not clear or archive the run state during a run. Next: finish the run, ' +
  `commit, then run ${cli} state archive. To throw the run away, ask the user with AskUserQuestion, header \`Temper resume\`, whether to start over.`

const OPAQUE_DENY = (cli: string): string =>
  'Temper: this command runs the Temper script in a way Temper cannot read, and it holds a decision word. ' +
  'Only the user decides, in the `Temper gate` question. ' +
  `Next: run each ${cli} call with its words written out, one per Bash call.`

const DYNAMIC_DENY = (cli: string): string =>
  'Temper: this command writes what a Temper call does (its subcommand) in a form Temper cannot read: a variable, a substitution or an escaped string. ' +
  'It could be a decision, and only the user decides, in the `Temper gate` question. ' +
  `Next: run each ${cli} call with its words written out, one per Bash call.`

const OPAQUE_HIDDEN_DENY = (cli: string): string =>
  'Temper: this command may run the Temper script (it names the script, or starts a program that can run it) and hides part of what it runs behind a substitution, an expansion or a here-string, so Temper cannot read it. ' +
  `Next: run ${cli} with its words written out, in a Bash call of its own.`

const ALIAS_DENY = (cli: string): string =>
  'Temper: do not link, copy or source the Temper script. A second name for it hides the decision calls. ' +
  `Next: run ${cli} by its own path. The user decides in the \`Temper gate\` question.`

const HIDDEN_DENY =
  'Temper: a shell, or a builtin that runs text as commands (source and the like), is given a program that this command does not show (a pipe from another command, a file on stdin, a substitution, or a word split by quotes, backslashes, braces or globs). ' +
  'While a run is active only a program that is written out plainly passes. Next: run each command in its own Bash call, with the words written out.'

const GUARDED_USE_DENY = (word: string, cli: string): string =>
  `Temper: this command names ${word}, a file of the run, and it is not a plain read. The CLI writes those files; nothing else does. ` +
  `Next: read it with cat, grep, jq, head or git diff, or use ${cli} gate, evidence or state.`

const ENV_DENY = (cli: string): string =>
  "Temper: TEMPER_DIR and TEMPER_CONFIG point the CLI at other files than the run's, so its verdicts would be written for a run that is not this one. " +
  `Next: run ${cli} with no TEMPER_DIR or TEMPER_CONFIG.`

const HOOKS_DENY =
  'Temper: --no-verify, -n and core.hooksPath switch the native pre-commit hook off. The hook is the commit gate for every commit. ' +
  'Next: commit without them. If the hook blocks the commit, finish the stages it names.'

const GIT_SHELL_ALIAS = /\balias\.[A-Za-z0-9_.-]+(?:\s*=\s*|\s+)['"]?\s*!/i

const GIT_ALIAS_DENY =
  'Temper: a git alias that runs a shell command (alias.<name>=!...) hides what it runs. ' +
  'Next: run each command itself, in its own Bash call, with the words written out.'

// git runs a command of its own: rebase --exec, bisect run, submodule foreach, filter-branch, difftool --extcmd, a
// transport program, or an editor, pager, diff, filter or credential program set for the call. Temper cannot read that
// command, so it could hide a decision of the person.
const GIT_RUNS_COMMAND: readonly RegExp[] = [
  /\bgit\b[^\n;&|]*\brebase\b[^\n;&|]*\s(?:--exec\b|-[A-Za-z]*x(?=[\s=]|$))/,
  /\bgit\b[^\n;&|]*\bbisect\s+run\b/,
  /\bgit\b[^\n;&|]*\bsubmodule\b[^\n;&|]*\bforeach\b/,
  /\bgit\b[^\n;&|]*\bfilter-(?:branch|repo)\b/,
  /\bgit\b[^\n;&|]*\bdifftool\b[^\n;&|]*\s(?:--extcmd\b|-[A-Za-z]*x(?=[\s=]|$))/,
  /\bgit\b[^\n;&|]*\s--(?:upload-pack|receive-pack)\b/,
  /\bgit\b[^\n;&|]*?(?:core\.(?:editor|pager|sshcommand|fsmonitor|askpass)|sequence\.editor|diff\.external|pager\.[\w.-]+|gpg\.(?:[\w-]+\.)?program|credential\.helper|interactive\.difffilter|(?:merge|filter|diff)\.[\w.-]+\.(?:driver|clean|smudge|process|textconv|command))\b/i,
  /\b(?:GIT_EDITOR|GIT_SEQUENCE_EDITOR|GIT_PAGER|GIT_EXTERNAL_DIFF|GIT_SSH_COMMAND|GIT_SSH|GIT_ASKPASS|EDITOR|VISUAL|PAGER)\s*=[^\n;&|]*\bgit\b/,
]

// The plugin data folder of Claude Code (`~/.claude/plugins/data/`) holds the mod's store, and in it the person's
// decisions. Nothing but the mod touches it while a run is active.
const PLUGIN_DATA = /\.claude\/plugins\/data(?:\/|\b)/

const PLUGIN_DATA_DENY =
  'Temper: the plugin data folder under ~/.claude holds the decisions the user made. Do not read or change it while a run is active. ' +
  `Next: ${ASK} for a decision.`

const GIT_EXEC_DENY =
  'Temper: this git command runs a command of its own (rebase --exec, bisect run, submodule foreach, filter-branch, an editor, pager or diff program). ' +
  'Temper cannot read what it runs while a run is active. Next: run that command itself, in its own Bash call, with the words written out.'

// git plumbing that makes or moves a commit without git commit, so the native hook never sees it. Everyday commands that
// move a branch (reset, checkout, rebase) are not judged here: the docs list them among the limits of the Bash reader.
const GIT_PLUMBING = /\bgit\b[^\n;&|]*\s(?:update-ref|replace|stash\s+(?:create|store))\b/

const GIT_PLUMBING_DENY =
  'Temper: this git command makes or moves a commit without git commit (update-ref, stash create or store, replace), so the native commit hook never sees it. ' +
  'Next: git add the files, then git commit -m "...".'

const UNPLAIN_COMMIT_DENY =
  'Temper: this command makes a commit that the native pre-commit hook does not check (a merge, cherry-pick, revert, am, pull, commit-tree, or a commit of named paths). ' +
  'While a run is active, every commit is a plain git commit of the index, which the commit gate checks. Next: git add the files, then git commit -m "...".'

const MOVE_AND_BACK =
  'Temper: this command steps the run back and moves it on in one go. The stage the run goes back to needs its own work and its own check. ' +
  'Next: run the step back alone, then the stage it goes back to.'

const BACK_DENY = `Temper: state advance cannot move the run to an earlier stage. Only the user steps back. Next: ${ASK} whether to loop back.`

const NOT_HERE = (stage: string, here: Stage): string =>
  `Temper: the run is at ${stageLabel(here)}, not at ${stage}. A move is for the stage the run is at. Next: ${ASK} at the ${stageLabel(here)} gate.`

const WRONG_NEXT = (stage: Stage, next: readonly Stage[], cli: string): string =>
  `Temper: after ${stage} the next stage of this run is ${next.join(' or ') || 'none'}. Next: run ${cli} state advance ${stage}_complete ${next[0] ?? ''}.`

const KEY_DENY = (key: string): string =>
  `Temper: state set ${key} is allowed only in the form and the stage the orchestrator uses ` +
  '(complexity while the plan is open, base_sha as the current commit in Plan or Build; run_id, step and command never). ' +
  'Next: ask the user if the run needs another value.'

function evaluateBash(ctx: RuleContext, command: string): RuleResult {
  const c = classifyBash(command, ctx.cwd === undefined ? '' : ctx.cwd)
  const cli = ctx.cli ?? CLI
  const active = isActive(ctx)
  // Nothing goes around the native commit hook while a /temper run or a /temper:fix run is active.
  const guardsCommit = active || ctx.fixRun === true

  if (c.alias) return { deny: ALIAS_DENY(cli) }
  if (c.opaque && active) return { deny: c.opaqueWhy === 'dynamic' ? DYNAMIC_DENY(cli) : c.opaqueWhy === 'hidden' ? OPAQUE_HIDDEN_DENY(cli) : OPAQUE_DENY(cli) }
  if (active && c.hidden) return { deny: HIDDEN_DENY }
  if (active && PLUGIN_DATA.test(command)) return { deny: PLUGIN_DATA_DENY }
  // A command git runs itself could hide a decision (a fix run's root cause stage may use `git bisect run`).
  if (active && GIT_RUNS_COMMAND.some(rx => rx.test(command))) return { deny: GIT_EXEC_DENY }
  if (guardsCommit) {
    if (c.envTamper) return { deny: ENV_DENY(cli) }
    if (c.hookTamper || c.noVerify) return { deny: HOOKS_DENY }
    // A git alias that runs a shell (`-c alias.x='!...'`, `git config alias.x '!...'`) hides the command it runs.
    if (GIT_SHELL_ALIAS.test(command)) return { deny: GIT_ALIAS_DENY }
    // The commit gate is the native pre-commit hook, which runs on a plain `git commit` only. A commit it does not see
    // (a merge, cherry-pick, revert, am, pull, commit-tree, or a pathspec commit) waits until the run is cleared.
    if (c.commits && c.unplainCommit) return { deny: UNPLAIN_COMMIT_DENY }
    if (GIT_PLUMBING.test(command)) return { deny: GIT_PLUMBING_DENY }
  }

  if (c.protectedWrites.length > 0) {
    const known = c.protectedWrites.filter(p => !c.uncheckable.includes(p))
    if (known.length === 0) return { deny: UNCHECKABLE(cli) }
    // The config, the git hooks and the Temper commit hook are the run's only while a run is active (/temper:init writes
    // the config and installs the hook before). A path of no known kind (a link made inside .temper) gets the text of the
    // .temper folders.
    const kinds = known.map(p => protectedKind(p) ?? 'folder').filter(k => guardsCommit || (k !== 'config' && k !== 'hooks'))
    if (kinds.length > 0) {
      const forged = kinds.find(k => k === 'events' || k === 'overrides')
      return protectedDeny(forged ?? kinds[0] ?? 'folder', cli)
    }
    if (c.uncheckable.length > 0) return { deny: UNCHECKABLE(cli) }
  }
  if (active && c.guardedUse.length > 0) return { deny: GUARDED_USE_DENY(c.guardedUse[0] ?? 'a guarded file', cli) }

  // Removing or archiving the run's state is for after the run, or for the person's Start over. One exception, the
  // TRIVIAL exit of the orchestrator: a clear of a run that never left Intent (no step taken) loses nothing.
  const resets = c.stateOps.length > 0 && c.stateOps.every(o => o.op === 'archive' || o.op === 'clear' || o.op === 'init')
  // Start over begins a run of the same command: a /temper run never restarts as a fix run, which the mod stands aside for.
  if (active && ctx.restart && resets && c.calls.length === 0 && !c.commits && !/--command[=\s]+['"]?fix\b/.test(command)) return ALLOW
  if (active) {
    const r = ctx.run
    const trivialExit = r.stage === 'intent' && r.step <= 0 && ctx.nothingToLose === true
    // At the commit stage the Commit steps archive the run and clear it: the run is done.
    if (r.stage !== 'commit' && c.stateOps.some(o => o.op === 'archive' || (o.op === 'clear' && !trivialExit))) return { deny: STATE_END(cli) }
    if (c.stateOps.some(o => o.op === 'init')) return { deny: STATE_RESTART }
  }

  // After the run is done the commit gate may still FAIL: an override then is the person's "Override and commit".
  if (ctx.run !== null && ctx.run.stage === 'commit' && c.calls.some(call => call.kind === 'override')) {
    if (c.calls.some(call => call.invalid)) return { deny: REPEATED_FLAG }
    return ctx.move?.kind === 'commitOverride' ? ALLOW : { deny: DONE_OVERRIDE_DENY }
  }
  if (!active) return ALLOW
  const r = ctx.run
  if (c.calls.some(call => call.invalid)) return { deny: REPEATED_FLAG }
  const move = ctx.move
  const backTo = (to: string): boolean => move?.kind === 'back' && move.to === to
  // The armed run's own loop back to Build, after a failed Review or Check.
  const autoLoop = (from: Stage, to: string): boolean => armed(r) && to === 'build' && (from === 'review' || from === 'check')

  // `state loop <from> <to>`: the person's step back from the stage the run is at.
  for (const op of c.stateOps) {
    if (op.op !== 'loop') continue
    if (op.from !== r.stage || op.to === undefined || !isStage(op.to) || stageIndex(op.to) >= stageIndex(r.stage)) return { deny: STATE_RESTART }
    if (!backTo(op.to) && !autoLoop(r.stage, op.to)) return { deny: STATE_RESTART }
  }

  for (const op of c.stateOps) {
    if (op.op !== 'set') continue
    if (op.key === 'run_mode') {
      if (op.value === 'interactive') continue
      // Armed only by the person's "Autonomous" answer at the plan gate, and only where autonomy is switched on.
      if (op.value === 'autonomous' && move?.kind === 'arm' && r.autonomyEnabled) continue
      return { deny: AUTONOMY_DENY }
    }
    if (GUARD_KEYS.has(op.key)) return { deny: KEY_DENY(op.key) }
    // The keys the orchestrator sets itself, only in the form and the stage it sets them: the complexity while the plan
    // is open (a later change would drop Design), base_sha as the current commit in Plan or Build.
    if (op.key === 'complexity' && !((r.stage === 'intent' || r.stage === 'plan') && /^(?:trivial|simple|medium|complex)$/.test(op.value ?? ''))) return { deny: KEY_DENY(op.key) }
    if (op.key === 'base_sha') {
      const v = op.value ?? ''
      const form = /^[0-9a-f]{7,40}$/i.test(v) || v === '$(git rev-parse HEAD)' || v === '`git rev-parse HEAD`'
      if (!((r.stage === 'plan' || r.stage === 'build') && form)) return { deny: KEY_DENY(op.key) }
    }
  }

  // A step back and another move in one command: the move would be judged on the verdicts the step back clears. Once a
  // command steps back, every other move in it goes to that same stage (a `state set next_stage` that repeats the loop).
  const backTargets = new Set<string>([
    ...c.stateOps.flatMap(o => (o.op === 'loop' && o.to !== undefined ? [o.to] : [])),
    ...c.calls.flatMap(call => (call.kind === 'back' && isStage(call.stage ?? '') && stageIndex(call.stage as Stage) < stageIndex(r.stage) ? [call.stage as string] : [])),
  ])
  if (backTargets.size > 1 || (backTargets.size === 1 && c.calls.some(call => call.kind === 'advance' || (call.kind === 'back' && !backTargets.has(call.stage ?? ''))))) {
    return { deny: MOVE_AND_BACK }
  }

  // The calls, in order: an advance moves the stage the next call of the same command is read at.
  let here: Stage = r.stage
  let use: string | undefined
  for (const call of c.calls) {
    const first = here === r.stage
    if (call.kind === 'advance') {
      const stage = (call.stage ?? '').replace(/_complete$/, '')
      const next = call.next ?? ''
      if (!/_complete$/.test(call.stage ?? '') || !isStage(stage)) return { deny: ONLY_USER }
      // A next that is no stage (`done`, a typo) gets the stage that comes next named.
      if (!isStage(next)) return { deny: WRONG_NEXT(stage, allowedNext(r, stage), cli) }
      // No advance lowers the stage the run is at: only the person's step back does.
      if (stageIndex(next) < stageIndex(here)) return { deny: BACK_DENY }
      if (stage !== here) return { deny: NOT_HERE(stage, here) }
      const ok = allowedNext(r, stage)
      if (!ok.includes(next)) return { deny: WRONG_NEXT(stage, ok, cli) }
      // Intent and Plan are left only by the person (Continue, an arming answer, or a skip). Every later stage follows
      // its own verdict, or the person's skip.
      const byPerson = first && (move?.kind === 'override' || ((stage === 'intent' || stage === 'plan') && (move?.kind === 'approve' || move?.kind === 'arm')))
      const byVerdict = stage !== 'intent' && stage !== 'plan' && settled(r, stage)
      const bySkip = (stage === 'intent' || stage === 'plan') && r.skipped.has(stage)
      if (!byPerson && !byVerdict && !bySkip) return { deny: ONLY_USER }
      here = next
      continue
    }
    if (call.kind === 'override') {
      const stage = call.stage ?? ''
      if (stage.startsWith('foreign-commit:')) {
        // Keeping a task agent's commits (`group reopen G --accept-foreign`): the person's choice, once.
        if (!(first && r.stage === 'build' && move?.kind === 'keep')) return { deny: ONLY_USER }
        use = move.id
        continue
      }
      if (stage !== here) return { deny: NOT_HERE(stage, here) }
      if (!(first && move?.kind === 'override')) return { deny: ONLY_USER }
      continue
    }
    if (call.kind === 'back') {
      // `state set next_stage X`: X is where the run is (it changes nothing), the person's step back, or the stage after
      // one whose check passed.
      const to = call.stage ?? ''
      if (to === here) continue
      if (!isStage(to)) return { deny: ONLY_USER }
      if (stageIndex(to) < stageIndex(here)) {
        if (first && (backTo(to) || autoLoop(here, to))) continue
        return { deny: ONLY_USER }
      }
      if (allowedNext(r, here).includes(to) && here !== 'intent' && here !== 'plan' && settled(r, here)) {
        here = to
        continue
      }
      return { deny: ONLY_USER }
    }
    if (call.kind === 'accept') {
      // An accept is for the Review ledger, for the finding the person accepted at this step.
      if (call.stage !== 'review' || here !== 'review' || call.id === undefined || !ctx.accepts.includes(call.id)) return { deny: ONLY_USER }
      continue
    }
  }
  return use !== undefined ? { allow: true, use } : ALLOW
}

export function evaluate(ctx: RuleContext, call: ToolCall): RuleResult {
  if (call.tool === 'Bash') {
    const command = typeof call.input.command === 'string' ? call.input.command : ''
    return evaluateBash(ctx, command)
  }
  if (!WRITE_TOOLS.has(call.tool)) return ALLOW

  const raw = targetPath(call)
  if (raw === null) return ALLOW
  const path = normalizePath(raw, ctx.root)
  const active = isActive(ctx)
  if (active && PLUGIN_DATA.test(raw)) return { deny: PLUGIN_DATA_DENY }

  const kind = protectedKind(path)
  // The config, the git hooks and the Temper commit hook are guarded while a run is active, a fix run too (the person
  // writes them with no run on).
  if (kind !== null && (active || ctx.fixRun === true || (kind !== 'config' && kind !== 'hooks'))) return protectedDeny(kind, ctx.cli ?? CLI)
  // The report a parked autonomous run leaves (reference/autonomy.md): a note of the run, at any stage.
  if (path === AUTONOMY_REPORT) return ALLOW

  // Save for later stops the run; it lifts no rule (enforcement off is the person's way to lift them).
  if (!active) return ALLOW
  return stageWriteRule(ctx, path)
}
