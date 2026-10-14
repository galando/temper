// The guard (ADR 0013): `evaluate(ctx, call)` answers allow or deny for one tool call. Pure. It claims only what it can
// enforce, in three jobs:
//  1. a CLI call that only the person may cause is one the person's answer at the CLI's current step maps to, word for
//     word, or one the CLI's own action lists (an armed run's move, the commit steps);
//  2. Temper's own files (the CLI's files in `.temper`, and during a run the config and the git hooks) are written by
//     neither the editing tools nor a plain Bash write, and each stage allows its own writes by the editing tools;
//  3. a short Bash list: no commit around the native hook (`--no-verify`, a changed `core.hooksPath`).
// Where the run is comes from view.json's guard field (RunFacts); the person's choices come from the question dialogs
// (core/decisions.ts). Whether a stage may be left on its verdict is the CLI's to decide (it refuses the call). Every
// deny text ends with what to do next. core/shell.ts reads a Bash command; it is not a shell parser, and Temper is not a
// sandbox (docs/trust.md).

import { callWords, readShell, sameCall } from './shell'
import type { DriftState } from './decisions'
import { CLI } from './cli'
import { matchesPlan, normalizePath } from './paths'
import type { Stage } from './stages'
import { isStage, stageIndex, stageLabel } from './stages'

export const DRIFT_HEADER = 'Scope drift'
export const DRIFT_PREFIX = 'Outside the plan:'

// What view.json says about the run, for the guard.
export type RunFacts = {
  // The stage the CLI is at. `commit`: every gate is behind the run; it is done.
  stage: Stage
  // The CLI's step count: 0 right after `state init`.
  step: number
  // The spec directory, relative to the root: `.temper/specs/{slug}`.
  specDir: string
  // The files the person approved at the plan gate (before it, the plan's files as they are).
  planFiles: readonly string[]
  // A grouped Build run is active, and the CLI (not an agent) ticks the run's tasks.md.
  groupedActive: boolean
  // The run never left Intent and holds no spec file: a `state clear` loses nothing (the TRIVIAL exit).
  trivialExit: boolean
}

export type RuleContext = {
  // The run, or null when no /temper run is active (the mod then guards only what needs no run).
  run: RunFacts | null
  // The calls the person's answers at this step map to, and the calls and steps of the CLI's own action (an armed
  // run's move, the commit steps): a call only the person may cause passes when it is one of these, word for word.
  allowed: readonly string[]
  // The person chose Start over in this run.
  restart: boolean
  // The person's Scope drift answers in this run.
  drift: DriftState
  // A /temper:fix run is active: the mod judges none of its moves (commands/fix.md asks every gate), but nothing goes
  // around the native commit hook, and the config and the git hooks stay the person's.
  fixRun?: boolean
  // Absolute project root; absolute tool paths inside it are made relative.
  root?: string
  // Where the Temper script is: every deny text names the CLI by it.
  cli?: string
}

export type ToolCall = { tool: string; input: Record<string, unknown> }

// `use`: a decision this call spends (Keep the agent's commits, an Allow once answer); it counts once.
export type RuleResult = { allow: true; use?: string } | { deny: string; drift?: string }

const ALLOW: RuleResult = { allow: true }
const WRITE_TOOLS = new Set(['Write', 'Edit', 'MultiEdit', 'NotebookEdit'])

const TEST_FILE = [/(^|\/)(?:tests?|__tests__|specs?)\//, /\.(?:test|spec)\.[^/]+$/, /(^|\/)test_[^/]*$/, /_test\.[^/]+$/]

export const isTestFile = (path: string): boolean => TEST_FILE.some(re => re.test(path))

const ASK = 'ask the user with AskUserQuestion, header `Temper gate`'

export const ONLY_USER = `Only the user decides this. Next: ask the question \`temper next --json\` gives, exactly as given (header \`Temper gate\`), then wait.`

const AUTONOMY_REPORT = '.temper/autonomy-report.md'

function targetPath(call: ToolCall): string | null {
  const raw = call.tool === 'NotebookEdit' ? call.input.notebook_path : call.input.file_path
  return typeof raw === 'string' && raw.length > 0 ? raw : null
}

const inDir = (path: string, dir: string): boolean => path === dir || path.startsWith(dir + '/')

// The files the editing tools never write. `config` and `hooks` only while a run is active (the person writes the config
// with /temper:init, and installs the hooks, when no run is on). `hooks` is the native commit gate: the git hooks, the
// git config (core.hooksPath) and the Temper commit hook (the temper-gate folder in the git folder, the older
// temper-pre-commit file there, and the older folders hooks-temper and temper-git-hooks).
export type ProtectedKind = 'events' | 'gates' | 'status' | 'overrides' | 'state' | 'folder' | 'evidence' | 'loops' | 'config' | 'hooks'

// Every name is compared without regard to case: macOS (APFS) and Windows folders are case insensitive.
const PROTECTED: ReadonlyArray<readonly [ProtectedKind, RegExp]> = [
  ['events', /(^|\/)\.temper\/specs\/[^/\s]+\/events(\/|$)/i],
  ['gates', /(^|\/)\.temper\/gates\.json$/i],
  ['status', /(^|\/)\.temper\/status\.json$/i],
  ['overrides', /(^|\/)\.temper\/overrides\.json$/i],
  // The run state, the grouped Build record, the token usage record and the view the mod draws: the CLI writes them.
  ['state', /(^|\/)\.temper\/(?:build-state|groups|usage|view)\.json$/i],
  ['evidence', /(^|\/)\.temper\/evidence\/[^/]+\.json$/i],
  ['loops', /(^|\/)\.temper\/feedback-loops\.json$/i],
  ['config', /(^|\/)\.claude\/temper\.config$/i],
  ['hooks', /(^|\/)\.git\/(?:hooks(\/|$)|hooks-temper(\/|$)|temper-git-hooks(\/|$)|config$|config\.worktree$|worktrees\/[^/]+\/config\.worktree$|temper-gate(\/|$)|temper-pre-commit(\/|$))/i],
  // Folders that hold guarded files: removing or replacing one removes them too.
  ['folder', /(^|\/)\.temper(\/specs(\/[^/\s]+)?|\/evidence)?\/?$/i],
]

// A guarded path of each kind, to test a glob a Bash command writes against (`rm .temper/*.json`).
const GUARDED_SAMPLES = [
  '.temper', '.temper/specs', '.temper/evidence', '.temper/gates.json', '.temper/status.json', '.temper/overrides.json',
  '.temper/build-state.json', '.temper/groups.json', '.temper/usage.json', '.temper/view.json', '.temper/feedback-loops.json',
  '.temper/evidence/review.json', '.claude/temper.config', '.git/config', '.git/hooks', '.git/hooks/pre-commit', '.git/temper-gate',
]
// A glob as bash reads it, one segment at a time: `*` and `?` stay inside a segment, and a segment that starts with one
// does not match a name that starts with a dot (bash's default: `rm -rf *` leaves `.temper` alone).
const globRe = (glob: string): RegExp =>
  new RegExp(
    '^' +
      glob
        .split('/')
        .map(seg => (/^[*?[]/.test(seg) ? '(?!\\.)' : '') + seg.split('').map(c => (c === '*' ? '[^/]*' : c === '?' ? '[^/]' : c === '[' || c === ']' ? c : c.replace(/[.+^${}()|\\]/g, '\\$&'))).join(''))
        .join('/') +
      '$',
    'i',
  )

// Which guarded kind a glob a command writes can reach, or null (the glob against a guarded path of each kind).
function globKind(path: string): ProtectedKind | null {
  if (!/[*?[]/.test(path)) return null
  let re: RegExp
  try {
    re = globRe(path)
  } catch {
    return null
  }
  const hit = GUARDED_SAMPLES.find(g => re.test(g))
  return hit === undefined ? null : protectedKind(hit)
}

// Which guarded Temper path a path names, or null. `..` and `.` segments are collapsed first.
export function protectedKind(path: string): ProtectedKind | null {
  const p = normalizePath(path)
  for (const [kind, re] of PROTECTED) if (re.test(p)) return kind
  return null
}

// A /temper run is on, at any stage up to and with Commit: the commit gate can still fail at the commit stage (a missing
// verdict, an autonomous park), so nothing may go around it there either. Writes are free at Commit (stageWriteRule).
const isActive = (ctx: RuleContext): ctx is RuleContext & { run: RunFacts } => ctx.run !== null

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
  `Next: ${ASK} at the plan gate, exactly as \`temper next --json\` gives it. ` +
  'It needs autonomy.enabled: true in .claude/temper.config, which only the user sets.'

// The keys of build-state.json that only the CLI's own moves write. next_stage is a step (see the back calls).
const GUARD_KEYS = new Set(['stage', 'branch', 'spec_path', 'command', 'run_id', 'step', 'approved_files'])

const DONE_OVERRIDE_DENY =
  "Temper: the run is done, and an override now is the user's choice. " +
  `Next: show the failed commit gate and ${ASK}: "Override and commit" (with a reason) or "Save for later". ` +
  'Then run every override that commit needs.'

const STATE_RESTART =
  'Temper: state init and state loop restart or move the run. Only the user decides that. ' +
  'Next: ask the user with AskUserQuestion, header `Temper resume`, whether to start over (or, for a step back, the Loop back choice of the `Temper gate` question).'

const STATE_END = (cli: string): string =>
  'Temper: do not clear or archive the run state during a run. Next: finish the run, ' +
  `commit, then run ${cli} state archive. To throw the run away, ask the user with AskUserQuestion, header \`Temper resume\`, whether to start over.`

const HOOKS_DENY =
  'Temper: --no-verify, -n and core.hooksPath switch the native pre-commit hook off. The hook is the commit gate for every commit. ' +
  'Next: commit without them. If the hook blocks the commit, finish the stages it names.'

const TOO_MANY_DENY =
  'Temper: a word of this command expands to more words (a brace list) than the guard reads, so what it writes is not known. ' +
  'Next: write the paths out, or split the command.'

// The plugin data folder of Claude Code (`~/.claude/plugins/data/`) holds the mod's store, and in it the person's
// decisions. The editing tools do not write it while a run is active.
const PLUGIN_DATA = /\.claude\/plugins\/data(?:\/|\b)/

const PLUGIN_DATA_DENY =
  'Temper: the plugin data folder under ~/.claude holds the decisions the user made. Do not change it while a run is active. ' +
  `Next: ${ASK} for a decision.`

const KEY_DENY = (key: string): string =>
  `Temper: state set ${key} is allowed only in the form and the stage the orchestrator uses ` +
  '(complexity while the plan is open, base_sha as the current commit in Plan or Build; run_id, step and command never). ' +
  'Next: ask the user if the run needs another value.'

function evaluateBash(ctx: RuleContext, command: string): RuleResult {
  const c = readShell(command)
  const cli = ctx.cli ?? CLI
  const active = isActive(ctx)
  // Nothing goes around the native commit hook while a /temper run or a /temper:fix run is active.
  const guardsCommit = active || ctx.fixRun === true

  if (guardsCommit && c.noVerify) return { deny: HOOKS_DENY }
  if (guardsCommit && c.hooksPath) return protectedDeny('hooks', cli)
  if (c.tooMany) return { deny: TOO_MANY_DENY }
  // A plain write onto a protected file: the same list, and the same texts, as the editing tools.
  const kinds = c.writes.map(p => protectedKind(normalizePath(p, ctx.root)) ?? globKind(normalizePath(p, ctx.root))).filter((k): k is ProtectedKind => k !== null && (guardsCommit || (k !== 'config' && k !== 'hooks')))
  if (kinds.length > 0) return protectedDeny(kinds.find(k => k === 'events' || k === 'overrides') ?? (kinds[0] as ProtectedKind), cli)

  if (!active) return ALLOW
  const r = ctx.run
  for (const call of c.calls) {
    const w = callWords(call)
    const [a, b, key, value] = w
    if (a === 'state' && b === 'set' && key !== undefined) {
      if (GUARD_KEYS.has(key)) return { deny: KEY_DENY(key) }
      // The keys the orchestrator sets itself, only in the form and the stage it sets them: the complexity while the
      // plan is open (a later change would drop Design), base_sha as the current commit in Plan or Build.
      if (key === 'complexity' && !((r.stage === 'intent' || r.stage === 'plan') && /^(?:trivial|simple|medium|complex)$/.test(value ?? ''))) return { deny: KEY_DENY(key) }
      if (key === 'base_sha') {
        const v = value ?? ''
        const form = /^[0-9a-f]{7,40}$/i.test(v) || v === '$(git rev-parse HEAD)' || v === '`git rev-parse HEAD`'
        if (!((r.stage === 'plan' || r.stage === 'build') && form)) return { deny: KEY_DENY(key) }
      }
    }
    if (!personOnly(w, r)) continue
    // The person's answer at this step, or the CLI's own action, maps to this very call.
    if (ctx.allowed.some(written => sameCall(written, w))) continue
    const resets = a === 'state' && (b === 'clear' || b === 'archive' || b === 'init')
    // The TRIVIAL exit of the orchestrator: a clear of a run that never left Intent loses nothing.
    if (a === 'state' && b === 'clear' && r.trivialExit && r.stage === 'intent' && r.step <= 0) continue
    // Start over: the saved run state goes, and a run of the same command begins (never a fix run, which the mod stands
    // aside for).
    if (resets && ctx.restart && !w.some((x, i) => (x === '--command' && w[i + 1] === 'fix') || x === '--command=fix')) continue
    return { deny: personDeny(w, r, cli) }
  }
  return ALLOW
}

// The temper calls only the person may cause (ADR 0013), by their words after the script: leaving Intent or Plan, a
// skip, a step back, accepting a finding, arming autonomy, keeping a task agent's commits, and starting over or ending
// the run before it is done.
function personOnly(w: readonly string[], r: RunFacts): boolean {
  const [a, b, c, d] = w
  if (a === 'override') return true
  if (a === 'group' && b === 'reopen') return w.some(x => x === '--accept-foreign' || x.startsWith('--accept-foreign='))
  // Accepting a finding, or clearing a ledger (which erases what a stage found), is the person's.
  if (a === 'evidence') return b === 'accept' || b === 'clear'
  if (a !== 'state') return false
  if (b === 'advance') return c === 'intent_complete' || c === 'plan_complete'
  if (b === 'loop' || b === 'init' || b === 'clear' || b === 'archive') return true
  if (b === 'set' && c === 'run_mode') return d !== 'interactive'
  // A step back (a set to the stage the run is at changes nothing; a step forward is the CLI's to check).
  if (b === 'set' && c === 'next_stage') return !(d !== undefined && isStage(d) && stageIndex(d) >= stageIndex(r.stage))
  return false
}

function personDeny(w: readonly string[], r: RunFacts, cli: string): string {
  const [a, b, c] = w
  if (a === 'state' && (b === 'clear' || b === 'archive')) return STATE_END(cli)
  if (a === 'state' && (b === 'init' || b === 'loop')) return STATE_RESTART
  if (a === 'state' && b === 'set' && c === 'run_mode') return AUTONOMY_DENY
  if (a === 'override' && r.stage === 'commit') return DONE_OVERRIDE_DENY
  return ONLY_USER
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
