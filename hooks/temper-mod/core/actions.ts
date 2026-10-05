// Per-phase actions and hotkeys (mods-plan 3.7). One flow, two views: the orchestrator
// (commands/temper.md) still runs the stages and the CLI still judges the gates. These actions are
// the same choices the orchestrator asks as questions, with the same words, as buttons.
//
//   1  the main step: "Continue to <next>" once the check passed, "Loop back to <upstream>" when it
//      failed, else "Start <phase>" / "Run <phase>" (the orchestrator runs the stage)
//   2  3  the most useful options of the phase (same words as the original questions)
//   4  Discuss: the original "Other": the person types any message
//   9  Skip with a reason (the original "Override and continue")
//   0  More: the rest of the original options as a numbered menu (1 to 9, 0 goes back)
//
// A label is a short phrase that says the result. Each action has one short line (`desc`, 10 words
// at most) that the pane shows under the label. No internal word ("gate", "override") appears in a
// label or a line.

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
  // After the command is recorded and mirrored, submit `/temper:temper` (no arguments) so the
  // orchestrator launches the stage. Also set alone: the action only launches the stage.
  resume?: boolean
  // Put this draft in the prompt box and let the person type the rest (Discuss, Change).
  fill?: string
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
const BACK_ONE: Partial<Record<Phase, Phase>> = { plan: 'intent', build: 'plan', review: 'build', check: 'review', fix: 'check' }

const READY_DESC: Record<Phase, string> = {
  intent: 'The intent is checked. Plan opens and Claude plans.',
  plan: 'The plan is checked. Build opens and Claude starts building.',
  build: 'All tasks are done. Review opens and Claude reviews.',
  review: 'The review has no open problems. Check opens.',
  check: 'All checks pass. You can then commit.',
  fix: 'Run the checks again.',
}

// Key 1, by what the check said. The orchestrator runs every stage and its check itself, so a person
// arriving at a phase finds the result already there.
function main(phase: Phase, ctx: ActionContext): Action {
  const next = NEXT[phase]
  if (ctx.ready) {
    return command('1', 'continue', `Continue to ${next}`, READY_DESC[phase], phase === 'intent' || phase === 'plan' ? 'approve' : 'next', false, true, `To ${next}`)
  }
  // Build is gated at every checkpoint (one task per launch): a check that fails while tasks are still
  // open is no failure, only a checkpoint. The next step is the next task.
  const left = ctx.tasksLeft
  if (phase === 'build' && ctx.task && (left === undefined ? ctx.gate !== 'fail' : (left ?? 0) > 0)) {
    return launch('1', 'run-stage', `Continue with task ${ctx.task.n}`, 'Claude builds the task and stops for you.')
  }
  const up = UPSTREAM[phase]
  if (ctx.gate === 'fail' && up) {
    return command('1', 'loop-back', `Loop back to ${cap(up)}`, `The check failed. Redo ${cap(up)}. You give a reason.`, `back ${up}`, true, true, `Back to ${cap(up)}`)
  }
  if (phase === 'intent') return launch('1', 'run-stage', 'Start Intent', 'Claude writes the intent and checks it. Then you decide.')
  return launch('1', 'run-stage', ctx.gate === 'fail' ? `Run ${cap(phase)} again` : `Run ${cap(phase)}`, `Claude runs ${cap(phase)} and checks it. Then you decide.`)
}

const noun = (phase: Phase): string => ({ intent: 'intent', plan: 'plan', build: 'work', review: 'review', check: 'checks', fix: 'fix' })[phase]

const grill = (phase: Phase): Action =>
  prompt('1', 'grill-me', 'Grill me', 'Claude asks hard questions about it.', `Use the grill-me skill on the current ${noun(phase)}.`, SHOW)
const teach = (phase: Phase): Action =>
  prompt('1', 'teach-me', 'Teach me', 'Claude explains it so you learn it.', `Use the teach-me skill on the current ${noun(phase)}.`, SHOW)
const timeline = (): Action => command('1', 'timeline', 'Show the timeline', 'See each step of the run.', 'timeline')
const save = (paused: boolean): Action =>
  paused
    ? command('1', 'resume', 'Resume the run', 'Give the run back to Claude.', 'resume', false, true)
    : command('1', 'pause', 'Save for later', 'Pause the run. You come back to it.', 'pause')
const back = (phase: Phase): Action[] => {
  const prev = BACK_ONE[phase]
  return prev ? [command('1', 'back-one', `Go back to ${cap(prev)}`, 'Redo the step before. You give a reason.', `back ${prev}`, true, true)] : []
}
const prText = (): Action =>
  prompt(
    '1',
    'pr-desc',
    'Write the PR text',
    'Claude writes the pull request text from the report.',
    'Write a pull request description for this change. Use .temper/report.md. Write the report first if it is missing. List the skipped steps, the accepted findings and the scope drift decisions with their reasons.',
  )

// The rest of the original options, as a numbered menu (1 to 9). The same words as the questions.
function menu(phase: Phase, ctx: ActionContext): Action[] {
  const paused = ctx.paused ?? false
  switch (phase) {
    case 'intent':
      return [
        grill(phase),
        teach(phase),
        prompt('1', 'capture', 'Save my request', 'Save your last request as a draft intent.', 'Write my last request as a draft intent.md for a new spec.'),
        save(paused),
        timeline(),
      ]
    case 'plan':
      return [
        prompt(
          '1',
          'html-review',
          'Open HTML review',
          'See the plan in a web page. Add comments.',
          'Open the HTML review of the plan: fill templates/plan-review.html from plan.md and tasks.md, open it, wait for me, then apply review-comments.json.',
          SHOW,
        ),
        prompt('1', 'alternative', 'Try another plan', 'Claude compares this plan with another way.', 'Give one other way to do the plan. Compare the two plans.', SHOW),
        prompt('1', 'split-tasks', 'Split the tasks', 'Make the tasks smaller, each with a test command.', 'Split the plan into smaller tasks in tasks.md. Give each task its own Validate command.'),
        grill(phase),
        teach(phase),
        ...back(phase),
        save(paused),
        timeline(),
      ]
    case 'build': {
      const stop: Action = {
        ...command('1', 'stop', 'Stop', 'Run the build check. Then save for later.', 'pause'),
        prompt: `Run the build check (scripts/temper gate build). Then wait. ${SHOW}`,
      }
      return [stop, grill(phase), teach(phase), ...back(phase), save(paused), timeline()]
    }
    case 'review':
      return [
        prompt(
          '1',
          'arch-depth',
          'Architecture depth review',
          'Check the changes for seams, adapters and locality.',
          'Run the Architecture Depth Review on the changed files. Add its ARCH-DEPTH findings to the review summary.',
          SHOW,
          'Depth review',
        ),
        grill(phase),
        teach(phase),
        ...back(phase),
        save(paused),
        timeline(),
        prText(),
      ]
    case 'check':
      return [
        ...(ctx.configSuggestions
          ? [
              prompt(
                '1',
                'config-suggestions',
                'Review config suggestions',
                'Claude shows each suggested setting. You choose.',
                'Show each item in config-suggestions.json. For each one, ask me to accept, reject or defer it.',
                SHOW,
                'Review config',
              ),
            ]
          : []),
        grill(phase),
        teach(phase),
        ...back(phase),
        save(paused),
        timeline(),
        prText(),
      ]
    case 'fix':
      return [grill(phase), teach(phase), ...back(phase), save(paused), timeline()]
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
  const more = moreActions(phase, ctx)
  switch (phase) {
    case 'intent':
      return {
        primary: [
          main(phase, ctx),
          prompt('2', 'clarify', 'Ask me questions', 'Claude asks you short questions to fill gaps.', 'Ask me one short question that makes the intent clear.', SHOW),
          prompt('3', 'edit-intent', 'Edit the intent', 'Change the intent in your own words.', 'Show me intent.md. Make the changes I describe next.', SHOW),
        ],
        discuss: DISCUSS,
        override: OVERRIDE,
        more,
      }
    case 'plan':
      return {
        primary: [
          main(phase, ctx),
          prompt(
            '2',
            'walk-through',
            'Walk through step by step',
            'Claude explains the plan one part at a time.',
            'Walk me through the plan step by step: the scenarios, the files, the tasks. Stop after each part and wait for me.',
            SHOW,
            'Walk through',
          ),
          prompt('3', 'plan-files', 'Show the files', 'See each file the plan changes, and why.', 'List each file the plan creates or changes. Give one reason for each file.', SHOW),
        ],
        discuss: DISCUSS,
        override: OVERRIDE,
        more,
      }
    case 'build':
      return {
        primary: [
          main(phase, ctx),
          draft('2', 'change', 'Change', 'Tell Claude what to change in this task.', 'Change this task: '),
          prompt('3', 'run-tests', 'Run the tests', 'Run the tests and see the result.', 'Run the tests for the criterion we work on. Report the result.'),
        ],
        discuss: DISCUSS,
        override: OVERRIDE,
        more,
      }
    case 'review':
      return {
        primary: [
          main(phase, ctx),
          ...(ctx.hasFindings
            ? [prompt('2', 'fix-all', 'Fix the problems', 'Claude fixes each problem, with a test.', 'Fix each open review finding, one at a time. Write a regression test for each fix.')]
            : []),
          prompt(ctx.hasFindings ? '3' : '2', 'diff', 'Show the changes', 'See the changes under review.', 'Show the git diff of the changes in review.', SHOW),
        ],
        discuss: DISCUSS,
        override: OVERRIDE,
        more,
      }
    case 'check':
      return {
        primary: [
          main(phase, ctx),
          prompt('2', 'rerun-failed', 'Run failed checks again', 'Run only the checks that failed.', 'Run again only the checks that failed.', ACT, 'Run failed again'),
          prompt('3', 'failures', 'Show the failures', 'List the failed checks.', 'List the failed checks. Group them by acceptance criterion.', SHOW),
        ],
        discuss: DISCUSS,
        override: OVERRIDE,
        more,
      }
    case 'fix':
      if (ctx.loopLimitReached) {
        return {
          primary: [
            command('1', 'plan-again', 'Plan again', 'Go back to Plan. You give a reason.', 'back plan', true, true),
            command('2', 'override-limit', 'Skip with a reason', 'Go on without a pass. Temper records it.', 'override', true, true),
            command('3', 'take-over', 'Take over', 'Pause Temper. You work by hand.', 'pause'),
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
          command('3', 'to-check', 'Go back to checks', 'Run the checks again.', 'next', false, true),
        ],
        discuss: DISCUSS,
        override: OVERRIDE,
        more,
      }
  }
}

// The actions of a finished run: the original Commit question, the pull request text and the timeline.
export function doneActions(): ActionSet {
  return {
    primary: [
      prompt(
        '1',
        'commit',
        'Commit',
        'Claude commits the work. It does not push.',
        'Run scripts/temper gate commit. If it passes, commit the work with one conventional commit message. Do not push.',
      ),
      { ...prText(), key: '2' },
      { ...timeline(), key: '3' },
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
        ? 'fix the open findings, or ask the user to accept them with a reason (key 2, /temper:temper accept <id> <reason>)'
        : 'run the review (key 1)'
    case 'check':
      return ctx.allChecksPass ? 'mark the run done (key 1 or /temper:temper next)' : 'run the checks (key 1 in Check or /temper:check)'
    case 'fix':
      return ctx.loopLimitReached
        ? 'the fix loop limit is reached. Ask the user to plan again, override with a reason, or take over'
        : 'fix the failed checks. Then go back to Check (key 3)'
  }
}

// The one line every key 1 sentence ends with is the label's own line. The sentence under the bar
// starts with the key and the label of the main action ("1 Continue to Build."), then its line. It
// reads the same in the band, the pane, the hint and the line under an answer.
export function nowText(phase: Phase | 'done', ctx: ActionContext): string {
  if (phase === 'done') return 'The run is done. 1 Commit when you are ready.'
  if (phase === 'fix' && ctx.loopLimitReached) return 'Fixing did not work after several tries. Choose: 1 plan again, 2 skip with a reason, or 3 take over.'
  const first = actionsFor(phase, ctx).primary[0]
  return first ? `1 ${first.label}. ${first.desc}` : ''
}
