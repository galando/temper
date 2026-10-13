// Per-phase actions and hotkeys (mods-plan 3.7). One flow, two views: the orchestrator
// (commands/temper.md) still runs the stages and the CLI still judges the gates. These actions are
// the options the original orchestrator asks as questions, with the same words, as buttons. Nothing
// else is a button: the person can still ask for anything else by typing (key 4, Discuss).
//
//   1  the main step: "Continue to <next>" once the check passed, "Loop back to <upstream>" when it
//      failed, else "Start <phase>" / "Run <phase>" (the orchestrator runs the stage)
//   2  3  two more original options of the phase (Grill me, Teach me, Walk through step by step ...)
//   4  Discuss: the original "Other": the person types any message
//   9  Skip with a reason (the original "Override and continue")
//   0  More: the other original options as a numbered menu (1 to 9, 0 goes back)
//
// A label is a short phrase that says the result. Each action has one short line (`desc`, 10 words
// at most) that the pane shows under the label. No internal word ("gate", "override") appears in a
// label or a line. scripts/check-original-options.sh and tests/mod/actions.test.ts refuse a label that
// is not an original option or one of the explicit extras.

import type { Phase } from './events'
import { CLI, IN_PLUGIN, pluginRootOf } from './cli'

// 1 to 9 and 0 are digits because only a digit works from an empty prompt (a letter would type into
// the composer). The More menu reuses the digits 1 to 9; 0 leaves the menu.
export type ActionKey = '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' | '0'

export type Action = {
  key: ActionKey
  id: string
  label: string
  // A shorter label for a narrow band (under 100 columns).
  short?: string
  // What the action does, in 10 words at most. The pane shows it under the label.
  desc: string
  // Text submitted to Claude as a prompt.
  prompt?: string
  // A reserved subcommand typed as `/temper:temper <command>`.
  command?: string
  asksReason?: boolean
  // After the command is recorded and mirrored, run `/temper:temper` (no arguments) so the
  // orchestrator launches the stage. Also set alone: the action only launches the stage.
  resume?: boolean
  // Put this draft in the prompt box and let the person type the rest (Discuss, Change).
  fill?: string
  // Record the person's last choice in the CLI again: the mirror prompt for the pending decision is
  // submitted once more. No new decision is made.
  record?: boolean
}

export type ActionContext = {
  // The current phase's check passed (fresh PASS verdict).
  ready?: boolean
  // The state of the current phase's check: fresh, fail, stale (a step back made it old) or none.
  gate?: 'fresh' | 'stale' | 'fail' | 'none'
  tasksDone?: boolean
  hasFindings?: boolean
  allChecksPass?: boolean
  loopLimitReached?: boolean
  // The run is paused (saved for later).
  paused?: boolean
  // The task the Build phase works on, from tasks.md, and how many tasks are not done (null: unknown).
  task?: { n: number; of: number } | null
  tasksLeft?: number | null
  // Build runs in groups (groups.json exists): a checkpoint continues the group loop, not one task.
  grouped?: boolean
  // Check wrote config-suggestions.json in the spec folder.
  configSuggestions?: boolean
  // The person's last move is not recorded in the CLI yet (Snapshot.sync.pending), and what that move is.
  pending?: boolean
  pendingMove?: PendingChoice
  // Where the Temper script is: its full path in the plugin folder, or the plain `scripts/temper` when that is not
  // known (see pluginCliFrom). A prompt names the CLI and the plugin's files by it.
  cli?: string
  // The bar draws the action buttons (full mode). False: the person chooses in the `Temper gate` question, so a text
  // for Claude names that question and never a key. Absent means buttons.
  buttons?: boolean
  // Design follows this Plan (a medium or complex run with phases.design on): the Plan gate continues to Design.
  designNext?: boolean
  // The run is at its Design gate (part of Plan in the mod): a failed design check loops back to Plan.
  atDesign?: boolean
  // Loops of the CLI whose budget is spent (`{from}>{to}` in CLI stages, from .temper/feedback-loops.json): the bar no
  // longer offers them.
  spentLoops?: readonly string[]
}

// The person's move that waits to be recorded: a Continue out of a phase, a step back, or a skip.
export type PendingChoice = { type: 'advance'; from: Phase } | { type: 'back'; to: Phase } | { type: 'override' }

export type ActionSet = { primary: Action[]; discuss: Action; override: Action | null; more: Action[] }

// Every prompt ends with one of these two, so Claude acts and does not narrate.
export const ACT = 'Do this now. Reply with one short line.'
export const SHOW = 'Do this now. Keep the answer short.'

const prompt = (key: ActionKey, id: string, label: string, desc: string, text: string, tail: string = ACT, short?: string): Action => ({
  key,
  id,
  label,
  desc,
  prompt: `${text} ${tail}`,
  ...(short ? { short } : {}),
})
const command = (key: ActionKey, id: string, label: string, desc: string, cmd: string, asksReason = false, resume = false, short?: string): Action => ({
  key,
  id,
  label,
  desc,
  command: cmd,
  ...(asksReason ? { asksReason } : {}),
  ...(resume ? { resume } : {}),
  ...(short ? { short } : {}),
})
const launch = (key: ActionKey, id: string, label: string, desc: string): Action => ({ key, id, label, desc, resume: true })
const draft = (key: ActionKey, id: string, label: string, desc: string, fill: string, short?: string): Action => ({ key, id, label, desc, fill, ...(short ? { short } : {}) })

const OVERRIDE: Action = command('9', 'override', 'Skip with a reason', 'Skip this step. Temper writes your reason in the report.', 'override', true, true)

// The original "Other": a free message about this step. It changes nothing by itself.
export const DISCUSS: Action = draft('4', 'discuss', 'Discuss', 'Type your own message about this step.', 'Discuss this step: ')

const cap = (p: string): string => `${p.charAt(0).toUpperCase()}${p.slice(1)}`

// What follows each phase, and what the orchestrator loops back to when a check fails.
export const NEXT: Record<Phase, string> = { intent: 'Plan', plan: 'Build', build: 'Review', review: 'Check', check: 'Commit', fix: 'Check' }
// Where a failed check of the step loops back to: Plan from the Design gate, else the phase upstream.
const upstreamOf = (phase: Phase, ctx: ActionContext): Phase | undefined => (phase === 'plan' && ctx.atDesign ? 'plan' : UPSTREAM[phase])

// The CLI keeps a budget per loop (loops.max-per-type): a loop whose budget is spent is not offered again.
function spent(phase: Phase, to: Phase, ctx: ActionContext): boolean {
  const from = phase === 'plan' && ctx.atDesign ? 'design' : phase === 'fix' ? 'check' : phase
  return (ctx.spentLoops ?? []).includes(`${from}>${to}`)
}

// The step after a phase for this run: Design after a Plan that has one.
const nextName = (phase: Phase, ctx: ActionContext): string => (phase === 'plan' && ctx.designNext ? 'Design' : NEXT[phase])
const UPSTREAM: Partial<Record<Phase, Phase>> = { plan: 'intent', build: 'plan', review: 'build' }

const READY_DESC: Record<Phase, string> = {
  intent: 'The intent is checked. Plan opens and Claude plans.',
  plan: 'The plan is checked. Build opens and Claude starts building.',
  build: 'All tasks are done. Review opens and Claude reviews.',
  review: 'The review has no open problems. Check opens.',
  check: 'All checks pass. You can then commit.',
  fix: 'Run the checks again.',
}

// Build is gated at every checkpoint (one task per launch, or one group in grouped Build): a check that fails
// while tasks are still open is no failure, only a checkpoint. The next step is the next task or group.
// In grouped Build the last group's gate comes after its tasks are all ticked: until the build check has run and failed (the
// completion gate), that is still a checkpoint of the group loop.
const isCheckpoint = (phase: Phase, ctx: ActionContext): boolean => {
  const left = ctx.tasksLeft
  const lastGroup = ctx.grouped === true && left === 0 && ctx.gate !== 'fail'
  return phase === 'build' && !ctx.ready && Boolean(ctx.task) && (left === undefined ? ctx.gate !== 'fail' : (left ?? 0) > 0 || lastGroup)
}

// Key 1, by what the check said. The orchestrator runs every stage and its check itself, so a person
// arriving at a phase finds the result already there.
function main(phase: Phase, ctx: ActionContext): Action {
  // The person chose a move that the CLI has not recorded: key 1 records it again. It is not a new choice, so it
  // carries the words of that move.
  if (ctx.pending) return record(ctx.pendingMove)
  const next = nextName(phase, ctx)
  if (ctx.ready) {
    const desc = phase === 'plan' && ctx.designNext ? 'The plan is checked. Design opens and Claude designs.' : READY_DESC[phase]
    return command('1', 'continue', `Continue to ${next}`, desc, phase === 'intent' || phase === 'plan' ? 'approve' : 'next', false, true, `To ${next}`)
  }
  if (isCheckpoint(phase, ctx) && ctx.task) {
    if (ctx.grouped) return launch('1', 'run-stage', 'Continue with the groups', 'Claude runs the ready tasks and stops at the next group gate.')
    return launch('1', 'run-stage', `Continue with task ${ctx.task.n}`, 'Claude builds the task and stops for you.')
  }
  // A failed check sends the work back upstream on key 1. Not for Build: its completion gate fails on a task, a group or
  // the integration, which Build itself mends; going back to Plan is for a plan that cannot be built (the menu has it).
  // At the Design gate a failed design goes back to Plan. Once that loop's budget is spent, key 1 is the skip.
  const up = upstreamOf(phase, ctx)
  if (ctx.gate === 'fail' && up && phase !== 'build') {
    if (spent(phase, up, ctx)) return command('1', 'override-spent', 'Skip with a reason', 'Loop back is used up. Go on without a pass.', 'override', true, true)
    return loopBack(up, '1')
  }
  // A failed Build check: Claude mends what it names (the Build completion gate of the Build loop), then checks again.
  if (phase === 'build' && ctx.gate === 'fail') {
    return prompt(
      '1',
      'run-stage',
      'Run Build again',
      'Claude mends what the build check found. Then checks again.',
      'The user chose Run Build again. Mend what the failed build check names, as the Build completion gate of the Build loop says ' +
        '(the tasks of a group with group reopen, an integrate failure with the fix pass), then run the build check again and stop for the user.',
      SHOW,
      'Build again',
    )
  }
  if (phase === 'intent' && ctx.gate !== 'fail') return launch('1', 'run-stage', 'Start Intent', 'Claude writes the intent and checks it. Then you decide.')
  // At the Design gate (part of Plan in the mod) the stage that runs is Design.
  const step = phase === 'plan' && ctx.atDesign ? 'Design' : cap(phase)
  return launch('1', 'run-stage', ctx.gate === 'fail' ? `Run ${step} again` : `Run ${step}`, `Claude runs ${step} and checks it. Then you decide.`)
}

// The line under the bar while the person's move waits: `idle` once Claude has stopped (key 1 finishes the move), `working`
// while Claude is still carrying it out (nothing to press).
// With no buttons (minimal and off modes) there is no key 1: the line is for Claude, which runs the steps of the move again.
export function pendingLines(move: PendingChoice | undefined, buttons = true): { idle: string; working: string } {
  const what = move?.type === 'advance' ? `Your move to ${NEXT[move.from]}` : move?.type === 'back' ? `Your step back to ${cap(move.to)}` : move?.type === 'override' ? 'Your skip of this step' : 'Your last choice'
  const working = `Claude is finishing ${what.charAt(0).toLowerCase()}${what.slice(1)}.`
  if (!buttons) {
    const theirs = `The user's ${what.slice('Your '.length)}`
    return { idle: `${theirs} is recorded but did not go through yet. Run its steps once more. If they fail again, say so in one line and ask the gate question again.`, working }
  }
  return { idle: `${what} did not go through yet. Press 1 to finish it.`, working }
}

// The question of a button that needs the person's reason, with choices that fit the move. The answer is the reason;
// the person can also type their own.
export function reasonAsk(id: string, label: string): { question: string; options: string[] } {
  if (id === 'loop-back') return { question: `${label}. What is the reason?`, options: ['The check found a real problem', 'The earlier step needs a change'] }
  if (id === 'restart') return { question: 'Start over. What is the reason?', options: ['This is the wrong feature', 'I want to start the work fresh'] }
  if (id.startsWith('accept')) return { question: `${label}. What is the reason?`, options: ['It is not a real issue', 'I accept the risk'] }
  return { question: 'Skip this step. What is the reason?', options: ['I accept the risk', 'It is not a real issue'] }
}

// Key 1 while the person's move waits to be recorded, named by that move.
function record(move: PendingChoice | undefined): Action {
  const base = { key: '1' as const, id: 'record', record: true }
  if (move?.type === 'advance') return { ...base, label: `Continue to ${NEXT[move.from]}`, short: `To ${NEXT[move.from]}`, desc: 'Not recorded yet. Temper records it and goes on.' }
  if (move?.type === 'back') return { ...base, label: `Loop back to ${cap(move.to)}`, short: `Back to ${cap(move.to)}`, desc: 'Not recorded yet. Temper records it and goes back.' }
  if (move?.type === 'override') return { ...base, label: 'Skip and go on', desc: 'Not recorded yet. Temper records the skip and goes on.' }
  return { ...base, label: 'Record my choice', desc: 'Temper records your last choice again.' }
}

// The original "Loop back to {upstream}": it asks for a reason, records the step back, and the orchestrator
// launches the earlier stage again. The loop budget (loops.max-per-type) is kept by the CLI.
const loopBack = (to: Phase, key: ActionKey): Action =>
  command(key, 'loop-back', `Loop back to ${cap(to)}`, `Redo ${cap(to)}. You give a reason.`, `back ${to}`, true, true, `Back to ${cap(to)}`)

const noun = (phase: Phase): string => ({ intent: 'intent', plan: 'plan', build: 'work', review: 'review', check: 'checks', fix: 'fix' })[phase]

const grill = (phase: Phase, key: ActionKey = '1'): Action =>
  prompt(key, 'grill-me', 'Grill me', 'Claude asks hard questions about it.', `Use the grill-me skill on the current ${noun(phase)}.`, SHOW)
const teach = (phase: Phase, key: ActionKey = '1'): Action =>
  prompt(key, 'teach-me', 'Teach me', 'Claude explains it so you learn it.', `Use the teach-me skill on the current ${noun(phase)}.`, SHOW)
// "Save for later" is the original pause. A paused run offers Resume in its place.
const save = (paused: boolean, key: ActionKey = '1'): Action =>
  paused ? command(key, 'resume', 'Resume', 'Give the run back to Claude.', 'resume', false, true) : command(key, 'pause', 'Save for later', 'Pause the run. You come back to it.', 'pause', false, false)

const walk = (key: ActionKey): Action =>
  prompt(
    key,
    'walk-through',
    'Walk through step by step',
    'Claude explains the plan one part at a time.',
    'Walk me through the plan step by step: the scenarios, the files, the tasks. Stop after each part and wait for me.',
    SHOW,
    'Walk through',
  )
// The plan review files are in the plugin folder, not in the project: a prompt names them by full path. When the
// plugin folder is not known, it names the plain paths and says where they are.
const htmlReview = (key: ActionKey, cli: string): Action => {
  const root = pluginRootOf(cli)
  return prompt(
    key,
    'html-review',
    'Open HTML review',
    'See the plan in a web page. Add comments.',
    root === null
      ? 'Open the HTML review of the plan as written in reference/plan-review.md: render it with scripts/plan_review.py, open it, wait for me, then apply review-comments.json. Both files are in the Temper plugin folder, not in the project.'
      : `Open the HTML review of the plan as written in ${root}/reference/plan-review.md: render it with ${root}/scripts/plan_review.py, open it, wait for me, then apply review-comments.json.`,
    SHOW,
  )
}
const shareReview = (key: ActionKey, cli: string): Action => {
  const root = pluginRootOf(cli)
  return prompt(
    key,
    'share-review',
    'Share HTML review',
    'Publish the plan page so others can comment.',
    root === null
      ? 'Share the HTML review of the plan as written in reference/plan-review.md in the Temper plugin folder. Ask me before anything leaves this machine.'
      : `Share the HTML review of the plan as written in ${root}/reference/plan-review.md. Ask me before anything leaves this machine.`,
    SHOW,
    'Share review',
  )
}
const archDepth = (key: ActionKey): Action =>
  prompt(
    key,
    'arch-depth',
    'Architecture depth review',
    'Check the changes for seams, adapters and locality.',
    'Run the Architecture Depth Review on the changed files. Add its ARCH-DEPTH findings to the review summary.',
    SHOW,
    'Depth review',
  )
const configSuggestions = (key: ActionKey): Action =>
  prompt(
    key,
    'config-suggestions',
    'Review config suggestions',
    'Claude shows each suggested setting. You choose.',
    'Show each item in config-suggestions.json. For each one, ask me to accept, reject or defer it.',
    SHOW,
    'Review config',
  )
// The Temper script by its full path; the plain path and where it is when the plugin folder is not known.
const where = (cli: string): string => (pluginRootOf(cli) === null ? ` ${IN_PLUGIN}` : '')

const stop = (key: ActionKey, cli: string): Action => ({
  ...command(key, 'stop', 'Stop', 'Run the build check. Then save for later.', 'pause'),
  prompt: `Run the build check (${cli} gate build).${where(cli)} Then wait. ${SHOW}`,
})

// The two buttons after Continue, by phase, and the rest of the original options for the menu.
function pair(phase: Phase, ctx: ActionContext): [Action, Action] {
  switch (phase) {
    case 'intent':
      return [grill(phase, '2'), teach(phase, '3')]
    case 'plan':
      return [walk('2'), htmlReview('3', ctx.cli ?? CLI)]
    case 'build':
      return isCheckpoint(phase, ctx)
        ? [
            ctx.grouped
              ? draft('2', 'change', 'Change', 'Tell Claude what to change in this group.', 'Change in this group: ')
              : draft('2', 'change', 'Change', 'Tell Claude what to change in this task.', 'Change this task: '),
            stop('3', ctx.cli ?? CLI),
          ]
        : [teach(phase, '2'), grill(phase, '3')]
    case 'review':
      // Open findings: the step back to Build is on the main row (unless key 1 already is it), depth review in the menu.
      return ctx.hasFindings && main(phase, ctx).id !== 'loop-back' && !spent(phase, 'build', ctx) ? [loopBack('build', '2'), grill(phase, '3')] : [archDepth('2'), grill(phase, '3')]
    case 'check':
      return ctx.configSuggestions ? [configSuggestions('2'), teach(phase, '3')] : [grill(phase, '2'), teach(phase, '3')]
    case 'fix':
      return [grill(phase, '2'), teach(phase, '3')]
  }
}

// The original "Accept a finding" of a failed Review: the mod asks which open finding and the reason, in its own dialog,
// so it works with no pane open.
const acceptOne: Action = { key: '1', id: 'accept-finding', label: 'Accept a finding', desc: 'Keep one finding as it is. You give a reason.' }

// The original "Start over" of the orchestrator's Resume Validation: the saved run state goes, the spec files stay.
// It asks for a reason, which also confirms it. The mod records it; the follow up asks Claude to start the run again.
const restart = (key: ActionKey = '1'): Action =>
  command(key, 'restart', 'Start over', 'Throw the saved run away. The spec files stay.', 'restart', true, false)

// The other original options, as a numbered menu (1 to 9). An option already on a main button is not repeated.
function menu(phase: Phase, ctx: ActionContext): Action[] {
  return [...phaseMenu(phase, ctx), restart()]
}

function phaseMenu(phase: Phase, ctx: ActionContext): Action[] {
  const paused = ctx.paused ?? false
  const loopMain = main(phase, ctx).id === 'loop-back'
  const shown = new Set([...pair(phase, ctx).map(a => a.id)])
  const extra = (a: Action[]): Action[] => a.filter(x => !shown.has(x.id))
  switch (phase) {
    case 'intent':
      return [save(paused)]
    case 'plan':
      return [...extra([grill(phase), teach(phase), shareReview('1', ctx.cli ?? CLI)]), save(paused)]
    case 'build':
      return isCheckpoint(phase, ctx) ? [grill(phase), teach(phase), save(paused)] : [...(loopMain || spent(phase, 'plan', ctx) ? [] : [loopBack('plan', '1')]), save(paused)]
    case 'review':
      return [...extra([teach(phase), archDepth('1')]), ...(loopMain || spent(phase, 'build', ctx) ? [] : extra([loopBack('build', '1')])), ...(ctx.hasFindings ? [acceptOne] : []), save(paused)]
    case 'check':
      return [...(ctx.configSuggestions ? extra([grill(phase)]) : []), save(paused)]
    case 'fix':
      // At the loop limit Save for later is already key 3, and only a loop back to Plan is left. Before it, a failed Check
      // can go back to Build, as the original Check gate offers.
      return ctx.loopLimitReached
        ? [grill(phase), teach(phase), ...(ctx.hasFindings ? [acceptOne] : [])]
        : [...(spent(phase, 'build', ctx) ? [] : [loopBack('build', '1')]), grill(phase), teach(phase), ...(ctx.hasFindings ? [acceptOne] : []), save(paused)]
  }
}

// The menu keys: 1 to 9, in order. A tenth entry would have no key, so a phase never has one.
export function numbered(list: readonly Action[]): Action[] {
  const keys: ActionKey[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9']
  return list.slice(0, keys.length).map((a, i) => ({ ...a, key: keys[i] ?? '9' }))
}

// The phase's menu, with its keys.
export function moreActions(phase: Phase, ctx: ActionContext): Action[] {
  return numbered(menu(phase, ctx))
}

export function actionsFor(phase: Phase, ctx: ActionContext): ActionSet {
  const set = baseActions(phase, ctx)
  // A move of the person that the CLI has not recorded: key 1 records it again, in every phase. The menu does not
  // offer the same move a second time.
  if (!ctx.pending) return set
  const first = main(phase, ctx)
  return { ...set, primary: [first, ...set.primary.slice(1)], more: numbered(set.more.filter(a => a.label !== first.label)) }
}

function baseActions(phase: Phase, ctx: ActionContext): ActionSet {
  const more = moreActions(phase, ctx)
  if (phase === 'fix') {
    if (ctx.loopLimitReached) {
      return {
        primary: [loopBack('plan', '1'), command('2', 'override-limit', 'Skip with a reason', 'Go on without a pass. Temper records it.', 'override', true, true), { ...save(ctx.paused ?? false, '3') }],
        discuss: DISCUSS,
        override: OVERRIDE,
        more,
      }
    }
    // The check passes again (the orchestrator re-ran it): going back to Check is the next step, and key 1.
    if (ctx.allChecksPass) {
      return {
        primary: [
          command('1', 'continue', 'Continue to Check', 'The checks pass again. Run the check step.', 'next', false, true, 'To Check'),
          prompt('2', 'fix-failures', 'Fix the failures', 'Claude makes the smallest change that fixes them.', 'Fix the failed checks with the smallest change. Then stop for the check run.'),
          prompt('3', 'fix-findings', 'Fix the findings', 'Claude fixes the open review problems.', 'Fix the open review findings, one at a time.'),
        ],
        discuss: DISCUSS,
        override: OVERRIDE,
        more,
      }
    }
    return {
      primary: [
        prompt('1', 'fix-failures', 'Fix the failures', 'Claude makes the smallest change that fixes them.', 'Fix the failed checks with the smallest change. Then stop for the check run.'),
        prompt('2', 'fix-findings', 'Fix the findings', 'Claude fixes the open review problems.', 'Fix the open review findings, one at a time.'),
        command('3', 'to-check', 'Continue to Check', 'Run the checks again.', 'next', false, true, 'To Check'),
      ],
      discuss: DISCUSS,
      override: OVERRIDE,
      more,
    }
  }
  const [two, three] = pair(phase, ctx)
  return { primary: [main(phase, ctx), two, three], discuss: DISCUSS, override: OVERRIDE, more }
}

// The actions of a finished run: the original Commit question ("Commit" / "Save for later" / "Other").
// The Commit steps are named by the slash command, and the CLI by `cli` (see ActionContext.cli).
export function doneActions(cli: string = CLI, suggestions = false): ActionSet {
  return {
    primary: [
      prompt(
        '1',
        'commit',
        'Commit',
        'Claude commits the work. It does not push.',
        'The user pressed Commit. Do the Commit steps of /temper:temper now. ' +
          `In short: run ${cli} gate commit. If it passes, set intent.md to Status completed, run ${cli} state archive, ` +
          `stage the diff and the .temper/specs artifacts, make one conventional commit, then run ${cli} state clear.${where(cli)} ` +
          'If it fails, do the FAIL step of the Commit section (the Temper gate question, Override and commit or Save for later). ' +
          'Do not ask the Commit question again. Do not push.',
      ),
      { key: '2', id: 'save-done', label: 'Save for later', desc: 'Leave the work as it is. Commit later.', command: 'saved' },
      // Check wrote config suggestions: the original offers them at the passed Check, before the commit.
      ...(suggestions ? [configSuggestions('3')] : []),
    ],
    discuss: DISCUSS,
    override: null,
    more: [],
  }
}

// Per finding actions, shown in the pane.
export function findingActions(id: string): Action[] {
  return [
    // Fix is a loop back to Build for this finding (the guard lets Build change code; Review then runs again).
    { key: '1', id: `fix-${id}`, label: 'Fix', desc: 'Claude fixes it in Build. Review runs again.', command: `back build fix finding ${id}`, resume: true },
    { ...command('2', `accept-${id}`, 'Accept', 'Keep it as it is. You give a reason.', `accept ${id}`, true) },
    prompt('3', `explain-${id}`, 'Explain', 'Claude says what is wrong and why it matters.', `Explain review finding ${id}. Say what is wrong, where it is, and why it matters.`, SHOW),
  ]
}

// The sentence that goes after "Next:" in the system prompt section. Claude reads it. It names the key the person
// presses when the bar draws buttons, and the `Temper gate` question when it does not; never a typed command.
export function nextStep(phase: Phase | 'done', ctx: ActionContext): string {
  const bar = ctx.buttons !== false
  const ask = (choice: string, key = '1'): string =>
    bar ? `ask the user to ${choice} (key ${key} on the Temper bar)` : `ask the user with AskUserQuestion, header \`Temper gate\`: ${choice}`
  switch (phase) {
    case 'done':
      return 'the run is done. Commit is allowed'
    case 'intent':
      return ctx.ready ? ask('continue to Plan') : `finish intent.md until the intent check passes. Then ${ask('continue to Plan')}`
    case 'plan': {
      const next = nextName(phase, ctx)
      return ctx.ready ? ask(`continue to ${next}`) : `finish plan.md and tasks.md. Then ${ask(`continue to ${next}`)}`
    }
    case 'build':
      return ctx.tasksDone ? ask('continue to Review') : 'do the next task in tasks.md. Write a failing test first. Stay inside the plan files'
    case 'review':
      if (!ctx.hasFindings) return 'run the review stage and its check'
      return bar
        ? 'the review has open findings. Ask the user to choose on the Temper bar: loop back to Build to fix them, accept one with a reason (Accept a finding, under More), or skip with a reason'
        : 'the review has open findings. Ask the user with AskUserQuestion, header `Temper gate`: loop back to Build, accept a finding, or override and continue'
    case 'check':
      return ctx.allChecksPass ? ask(bar ? 'continue to Commit' : 'commit') : 'run the check stage and its check'
    case 'fix':
      if (ctx.loopLimitReached) return 'the fix loop limit is reached. Ask the user to loop back to Plan, skip with a reason, or save the run for later'
      if (ctx.allChecksPass) return ask('continue to Check')
      return bar
        ? 'the checks failed. Ask the user to choose on the Temper bar: fix the failures, loop back to Build, or skip with a reason'
        : 'the checks failed. Ask the user with AskUserQuestion, header `Temper gate`: loop back to Build, override and continue, or save for later'
  }
}

// The sentence under the bar starts with the key and the label of the main action ("1 Continue to
// Build."), then its line. It reads the same in the band, the pane, the hint and the line under an answer.
export function nowText(phase: Phase | 'done', ctx: ActionContext): string {
  if (phase === 'done') return 'The run is done. 1 Commit when you are ready.'
  // A saved run: any move takes it up again (the mod records the resume first).
  const saved = ctx.paused ? 'The run is saved for later; a choice takes it up again. ' : ''
  if (phase === 'fix' && ctx.loopLimitReached) return `${saved}Fixing did not work after several tries. Choose: 1 loop back to Plan, 2 skip with a reason, or 3 save for later.`
  const first = actionsFor(phase, ctx).primary[0]
  return first ? `${saved}1 ${first.label}. ${first.desc}` : ''
}
