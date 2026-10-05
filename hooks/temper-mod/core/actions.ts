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
  // Check wrote config-suggestions.json in the spec folder.
  configSuggestions?: boolean
  // The person's last move is not recorded in the CLI yet (Snapshot.sync.pending).
  pending?: boolean
}

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
const NEXT: Record<Phase, string> = { intent: 'Plan', plan: 'Build', build: 'Review', review: 'Check', check: 'Commit', fix: 'Check' }
const UPSTREAM: Partial<Record<Phase, Phase>> = { plan: 'intent', build: 'plan', review: 'build' }

const READY_DESC: Record<Phase, string> = {
  intent: 'The intent is checked. Plan opens and Claude plans.',
  plan: 'The plan is checked. Build opens and Claude starts building.',
  build: 'All tasks are done. Review opens and Claude reviews.',
  review: 'The review has no open problems. Check opens.',
  check: 'All checks pass. You can then commit.',
  fix: 'Run the checks again.',
}

// Build is gated at every checkpoint (one task per launch): a check that fails while tasks are still
// open is no failure, only a checkpoint. The next step is the next task.
const isCheckpoint = (phase: Phase, ctx: ActionContext): boolean => {
  const left = ctx.tasksLeft
  return phase === 'build' && !ctx.ready && Boolean(ctx.task) && (left === undefined ? ctx.gate !== 'fail' : (left ?? 0) > 0)
}

// Key 1, by what the check said. The orchestrator runs every stage and its check itself, so a person
// arriving at a phase finds the result already there.
function main(phase: Phase, ctx: ActionContext): Action {
  // The person chose a move that the CLI has not recorded: key 1 records it again. It is not a new choice.
  if (ctx.pending) return { key: '1', id: 'record', label: 'Record my choice', desc: 'Temper records your last choice again.', record: true }
  const next = NEXT[phase]
  if (ctx.ready) {
    return command('1', 'continue', `Continue to ${next}`, READY_DESC[phase], phase === 'intent' || phase === 'plan' ? 'approve' : 'next', false, true, `To ${next}`)
  }
  if (isCheckpoint(phase, ctx) && ctx.task) {
    return launch('1', 'run-stage', `Continue with task ${ctx.task.n}`, 'Claude builds the task and stops for you.')
  }
  const up = UPSTREAM[phase]
  if (ctx.gate === 'fail' && up) return loopBack(up, '1')
  if (phase === 'intent') return launch('1', 'run-stage', 'Start Intent', 'Claude writes the intent and checks it. Then you decide.')
  return launch('1', 'run-stage', ctx.gate === 'fail' ? `Run ${cap(phase)} again` : `Run ${cap(phase)}`, `Claude runs ${cap(phase)} and checks it. Then you decide.`)
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
const htmlReview = (key: ActionKey): Action =>
  prompt(
    key,
    'html-review',
    'Open HTML review',
    'See the plan in a web page. Add comments.',
    'Open the HTML review of the plan as written in reference/plan-review.md: render it with scripts/plan_review.py, open it, wait for me, then apply review-comments.json.',
    SHOW,
  )
const shareReview = (key: ActionKey): Action =>
  prompt(
    key,
    'share-review',
    'Share HTML review',
    'Publish the plan page so others can comment.',
    'Share the HTML review of the plan as written in reference/plan-review.md. Ask me before anything leaves this machine.',
    SHOW,
    'Share review',
  )
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
const stop = (key: ActionKey): Action => ({
  ...command(key, 'stop', 'Stop', 'Run the build check. Then save for later.', 'pause'),
  prompt: `Run the build check (scripts/temper gate build). Then wait. ${SHOW}`,
})

// The two buttons after Continue, by phase, and the rest of the original options for the menu.
function pair(phase: Phase, ctx: ActionContext): [Action, Action] {
  switch (phase) {
    case 'intent':
      return [grill(phase, '2'), teach(phase, '3')]
    case 'plan':
      return [walk('2'), htmlReview('3')]
    case 'build':
      return isCheckpoint(phase, ctx)
        ? [draft('2', 'change', 'Change', 'Tell Claude what to change in this task.', 'Change this task: '), stop('3')]
        : [teach(phase, '2'), grill(phase, '3')]
    case 'review':
      return [archDepth('2'), grill(phase, '3')]
    case 'check':
      return ctx.configSuggestions ? [configSuggestions('2'), teach(phase, '3')] : [grill(phase, '2'), teach(phase, '3')]
    case 'fix':
      return [grill(phase, '2'), teach(phase, '3')]
  }
}

// The other original options, as a numbered menu (1 to 9). An option already on a main button is not repeated.
function menu(phase: Phase, ctx: ActionContext): Action[] {
  const paused = ctx.paused ?? false
  const loopMain = main(phase, ctx).id === 'loop-back'
  const shown = new Set([...pair(phase, ctx).map(a => a.id)])
  const extra = (a: Action[]): Action[] => a.filter(x => !shown.has(x.id))
  switch (phase) {
    case 'intent':
      return [save(paused)]
    case 'plan':
      return [...extra([grill(phase), teach(phase), shareReview('1')]), save(paused)]
    case 'build':
      return isCheckpoint(phase, ctx) ? [grill(phase), teach(phase), save(paused)] : [...(loopMain ? [] : [loopBack('plan', '1')]), save(paused)]
    case 'review':
      return [...extra([teach(phase)]), ...(loopMain ? [] : [loopBack('build', '1')]), save(paused)]
    case 'check':
      return [...(ctx.configSuggestions ? extra([grill(phase)]) : []), save(paused)]
    case 'fix':
      // At the loop limit Save for later is already key 3.
      return ctx.loopLimitReached ? [grill(phase), teach(phase)] : [grill(phase), teach(phase), save(paused)]
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
  // A move of the person that the CLI has not recorded: key 1 records it again, in every phase.
  return ctx.pending ? { ...set, primary: [main(phase, ctx), ...set.primary.slice(1)] } : set
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
export function doneActions(): ActionSet {
  return {
    primary: [
      prompt(
        '1',
        'commit',
        'Commit',
        'Claude commits the work. It does not push.',
        'The user pressed Commit. Do the Commit steps of /temper now, as written in the Commit section of commands/temper.md in the Temper plugin. ' +
          'In short: run scripts/temper gate commit. If it passes, set intent.md to Status completed, run scripts/temper state archive, ' +
          'stage the diff and the .temper/specs artifacts, make one conventional commit, then run scripts/temper state clear. ' +
          'Do not ask the Commit question again. Do not push.',
      ),
      { key: '2', id: 'save-done', label: 'Save for later', desc: 'Leave the work as it is. Commit later.', command: 'saved' },
    ],
    discuss: DISCUSS,
    override: null,
    more: [],
  }
}

// Per finding actions, shown in the pane.
export function findingActions(id: string): Action[] {
  return [
    prompt('1', `fix-${id}`, 'Fix', 'Claude fixes this problem, with a test.', `Fix review finding ${id}. Write a regression test.`),
    { ...command('2', `accept-${id}`, 'Accept', 'Keep it as it is. You give a reason.', `accept ${id}`, true) },
    prompt('3', `explain-${id}`, 'Explain', 'Claude says what is wrong and why it matters.', `Explain review finding ${id}. Say what is wrong, where it is, and why it matters.`, SHOW),
  ]
}

// The sentence that goes after "Next:" in the system prompt section and in denials.
export function nextStep(phase: Phase | 'done', ctx: ActionContext): string {
  switch (phase) {
    case 'done':
      return 'the run is done. Commit is allowed'
    case 'intent':
      return ctx.ready
        ? 'ask the user to continue to Plan (key 1 or /temper:temper approve)'
        : 'finish intent.md until the intent check passes. Then ask the user to continue to Plan (key 1 or /temper:temper approve)'
    case 'plan':
      return ctx.ready
        ? 'ask the user to continue to Build (key 1 or /temper:temper approve)'
        : 'finish plan.md and tasks.md. Then ask the user to continue to Build (key 1 or /temper:temper approve)'
    case 'build':
      return ctx.tasksDone
        ? 'send the work to Review (key 1 or /temper:temper next)'
        : 'do the next task in tasks.md. Write a failing test first. Stay inside the plan files'
    case 'review':
      return ctx.hasFindings
        ? 'fix the open findings, or ask the user to accept them with a reason (/temper:temper accept <id> <reason>)'
        : 'run the review (key 1)'
    case 'check':
      return ctx.allChecksPass ? 'mark the run done (key 1 or /temper:temper next)' : 'run the checks (key 1 in Check or /temper:check)'
    case 'fix':
      return ctx.loopLimitReached
        ? 'the fix loop limit is reached. Ask the user to loop back to Plan, skip with a reason, or save the run for later'
        : 'fix the failed checks. Then continue to Check (key 3)'
  }
}

// The sentence under the bar starts with the key and the label of the main action ("1 Continue to
// Build."), then its line. It reads the same in the band, the pane, the hint and the line under an answer.
export function nowText(phase: Phase | 'done', ctx: ActionContext): string {
  if (phase === 'done') return 'The run is done. 1 Commit when you are ready.'
  if (phase === 'fix' && ctx.loopLimitReached) return 'Fixing did not work after several tries. Choose: 1 loop back to Plan, 2 skip with a reason, or 3 save for later.'
  const first = actionsFor(phase, ctx).primary[0]
  return first ? `1 ${first.label}. ${first.desc}` : ''
}
