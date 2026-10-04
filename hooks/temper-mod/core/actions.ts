// Per-phase actions and hotkeys (mods-plan 3.7). Key 1 is the main action and changes
// when the phase is ready to move on. Every action that runs something submits a prompt
// to Claude (`prompt`) or runs a reserved /temper:temper subcommand (`command`); none submits
// on its own. 9 skips the step and asks for a reason.
//
// A label is a short verb phrase that says the result ("Make the plan"). Each action has one
// short line (`desc`, 10 words at most) that the pane shows under the label. No internal word
// ("gate", "override") appears in a label or a line.

import type { Phase } from './events'

// 1, 2, 3 are the three main actions, 9 skips the step and 0 opens the full list. The full list
// uses lowercase letters, so no key is ever used twice in one place.
export type ActionKey = '1' | '2' | '3' | '9' | '0' | 'a' | 'b' | 'c' | 'd' | 'e' | 'f' | 'g' | 'h'

export type Action = {
  key: ActionKey
  id: string
  label: string
  // What the action does, in 10 words at most. The pane shows it under the label.
  desc: string
  // Text submitted to Claude as a prompt.
  prompt?: string
  // A reserved subcommand typed as `/temper:temper <command>`.
  command?: string
  asksReason?: boolean
}

export type ActionContext = {
  // The current phase's gate passes (fresh PASS verdict).
  ready?: boolean
  tasksDone?: boolean
  hasFindings?: boolean
  allChecksPass?: boolean
  loopLimitReached?: boolean
}

export type ActionSet = { primary: Action[]; override: Action; more: Action[] }

// Every prompt ends with one of these two, so Claude acts and does not narrate.
export const ACT = 'Do this now. Reply with one short line.'
export const SHOW = 'Do this now. Keep the answer short.'

const prompt = (key: ActionKey, id: string, label: string, desc: string, text: string, tail: string = ACT): Action => ({
  key,
  id,
  label,
  desc,
  prompt: `${text} ${tail}`,
})
const command = (key: ActionKey, id: string, label: string, desc: string, cmd: string, asksReason = false): Action => ({
  key,
  id,
  label,
  desc,
  command: cmd,
  ...(asksReason ? { asksReason } : {}),
})

const OVERRIDE: Action = command('9', 'override', 'Skip with a reason', 'Skip this step. Temper writes your reason in the report.', 'override', true)

export function actionsFor(phase: Phase, ctx: ActionContext): ActionSet {
  switch (phase) {
    case 'intent':
      return {
        primary: [
          ctx.ready
            ? command('1', 'approve', 'Approve the intent', 'Accept the intent. Planning can start.', 'approve')
            : prompt(
                '1',
                'check-intent',
                'Check the intent',
                'Claude checks the intent for gaps and fixes them.',
                'Run the intent gate (scripts/temper gate intent). Fix what it reports in intent.md.',
              ),
          prompt('2', 'clarify', 'Ask me questions', 'Claude asks you short questions to fill gaps.', 'Ask me one short question that makes the intent clear.', SHOW),
          prompt('3', 'edit-intent', 'Edit the intent', 'Change the intent in your own words.', 'Show me intent.md. Make the changes I describe next.', SHOW),
        ],
        override: OVERRIDE,
        more: [prompt('0', 'capture', 'Save my request', 'Save your last request as a draft intent.', 'Write my last request as a draft intent.md for a new spec.')],
      }
    case 'plan':
      return {
        primary: [
          ctx.ready
            ? command('1', 'approve', 'Approve the plan', 'Claude may then change the files in the plan.', 'approve')
            : prompt(
                '1',
                'generate-plan',
                'Make the plan',
                'Claude lists the files to change and the steps.',
                'Write plan.md and tasks.md for the approved intent. Include the blast radius and the scenarios.',
              ),
          prompt('2', 'plan-files', 'Show the files', 'See each file the plan changes, and why.', 'List each file the plan creates or changes. Give one reason for each file.', SHOW),
          prompt('3', 'alternative', 'Try another plan', 'Claude compares this plan with another way.', 'Give one other way to do the plan. Compare the two plans.', SHOW),
        ],
        override: OVERRIDE,
        more: [
          prompt('0', 'split-tasks', 'Split the tasks', 'Make the tasks smaller, each with a test command.', 'Split the plan into smaller tasks in tasks.md. Give each task its own Validate command.'),
          command('0', 'back-intent', 'Go back to Intent', 'Return to the intent step.', 'back intent'),
        ],
      }
    case 'build':
      return {
        primary: [
          ctx.tasksDone
            ? command('1', 'to-review', 'Send to review', 'All tasks are done. Claude then reviews the changes.', 'next')
            : prompt('1', 'next-task', 'Start the next task', 'Claude writes a failing test, then the code.', 'Start the next task in tasks.md. Write a failing test first.'),
          prompt('2', 'run-tests', 'Run the tests', 'Run the tests and see the result.', 'Run the tests for the criterion we work on. Report the result.'),
          prompt('3', 'diff-plan', 'Show the changes', 'See the changes. Files outside the plan are flagged.', 'Show the git diff. Say which changes are outside the plan files.', SHOW),
        ],
        override: OVERRIDE,
        more: [],
      }
    case 'review':
      return {
        primary: [
          ctx.hasFindings
            ? prompt('1', 'fix-all', 'Fix the problems', 'Claude fixes each problem, with a test.', 'Fix each open review finding, one at a time. Write a regression test for each fix.')
            : prompt('1', 'start-review', 'Start the review', 'Claude looks for problems in the changes.', 'Run the review on the changed files.'),
          prompt('2', 'review-again', 'Review again', 'Review the current changes once more.', 'Run the review again on the current diff.'),
          prompt('3', 'diff', 'Show the changes', 'See the changes under review.', 'Show the git diff of the changes in review.', SHOW),
        ],
        override: OVERRIDE,
        more: [],
      }
    case 'check':
      return {
        primary: [
          ctx.allChecksPass
            ? command('1', 'mark-done', 'Finish the run', 'All checks pass. Commit is allowed.', 'next')
            : prompt('1', 'run-checks', 'Run the checks', 'Claude runs build, tests, coverage, lint and security.', 'Run the checks: compile, tests, coverage, lint and security.'),
          prompt('2', 'rerun-failed', 'Run failed checks again', 'Run only the checks that failed.', 'Run again only the checks that failed.'),
          prompt('3', 'failures', 'Show the failures', 'List the failed checks.', 'List the failed checks. Group them by acceptance criterion.', SHOW),
        ],
        override: OVERRIDE,
        more: [],
      }
    case 'fix':
      if (ctx.loopLimitReached) {
        return {
          primary: [
            command('1', 'plan-again', 'Make a new plan', 'Go back to Plan. You give a reason.', 'back plan', true),
            command('2', 'override-limit', 'Skip with a reason', 'Go on without a pass. Temper records it.', 'override', true),
            command('3', 'take-over', 'Take over', 'Pause Temper. You work by hand.', 'pause'),
          ],
          override: OVERRIDE,
          more: [],
        }
      }
      return {
        primary: [
          prompt('1', 'fix-failures', 'Fix the failures', 'Claude makes the smallest change that fixes them.', 'Fix the failed checks with the smallest change. Then stop for the check run.'),
          prompt('2', 'fix-findings', 'Fix the findings', 'Claude fixes the open review problems.', 'Fix the open review findings, one at a time.'),
          command('3', 'to-check', 'Go back to checks', 'Run the checks again.', 'next'),
        ],
        override: OVERRIDE,
        more: [],
      }
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
        ? 'ask the user to approve the intent (key 1 or /temper:temper approve)'
        : 'finish intent.md until the intent gate passes. Then ask the user to approve it (key 1 or /temper:temper approve)'
    case 'plan':
      return ctx.ready
        ? 'ask the user to approve the plan (key 1 or /temper:temper approve)'
        : 'finish plan.md and tasks.md. Then ask the user to approve them (key 1 or /temper:temper approve)'
    case 'build':
      return ctx.tasksDone
        ? 'send the work to Review (key 1 or /temper:temper next)'
        : 'do the next task in tasks.md. Write a failing test first. Stay inside the plan files'
    case 'review':
      return ctx.hasFindings
        ? 'fix the open findings, or ask the user to accept them with a reason (key 1, /temper:temper accept <id> <reason>)'
        : 'run the review (key 1)'
    case 'check':
      return ctx.allChecksPass ? 'mark the run done (key 1 or /temper:temper next)' : 'run the checks (key 1 in Check or /temper:check)'
    case 'fix':
      return ctx.loopLimitReached
        ? 'the fix loop limit is reached. Ask the user to plan again, override with a reason, or take over'
        : 'fix the failed checks. Then go back to Check (key 3)'
  }
}

const LETTERS = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'] as const

// Gives each action in a list its own letter hotkey (a, b, c ...). Anything past the eighth
// keeps no hotkey rather than repeating one.
export function lettered(list: readonly Action[]): Action[] {
  return list.slice(0, LETTERS.length).map((a, i) => ({ ...a, key: LETTERS[i] ?? 'h' }))
}

const BACK_ONE: Partial<Record<Phase, Phase>> = { plan: 'intent', build: 'plan', review: 'build', check: 'review', fix: 'check' }

// Actions that belong to every phase, shown after the phase's own extras in the full list.
export function globalActions(phase: Phase, paused: boolean): Action[] {
  const out: Action[] = [
    paused
      ? command('0', 'resume', 'Resume the run', 'Give the run back to Claude.', 'resume')
      : command('0', 'pause', 'Pause the run', 'Stop Claude at the next step. You take over.', 'pause'),
  ]
  const prev = BACK_ONE[phase]
  if (prev) out.push(command('0', 'back-one', `Go back to ${prev.charAt(0).toUpperCase()}${prev.slice(1)}`, 'Redo the step before. You give a reason.', `back ${prev}`, true))
  out.push(
    prompt(
      '0',
      'pr-desc',
      'Write the PR text',
      'Claude writes the pull request text from the report.',
      'Write a pull request description for this change. Use .temper/report.md. Write the report first if it is missing. List the skipped steps, the accepted findings and the scope drift decisions with their reasons.',
    ),
  )
  return out
}

// One plain sentence: what the main action does, and what happens next. It reads the same in the
// band, the pane, the hint and the line under an answer. It starts with the key and the label of
// the main action ("1 Make the plan.").
export function nowText(phase: Phase | 'done', ctx: ActionContext): string {
  switch (phase) {
    case 'done':
      return 'The run is done. You can commit.'
    case 'intent':
      return ctx.ready
        ? '1 Approve the intent. Claude can then make the plan. Plan opens.'
        : '1 Check the intent. Claude checks it for gaps. Then press 1 again to approve.'
    case 'plan':
      return ctx.ready
        ? '1 Approve the plan. Claude can then change the files in the plan. Build opens.'
        : '1 Make the plan. Claude writes the plan: which files change and the steps. Then you approve it.'
    case 'build':
      return ctx.tasksDone
        ? '1 Send to review. All tasks are done. Review opens.'
        : '1 Start the next task. Claude writes a failing test, then the code. Then run the tests.'
    case 'review':
      return ctx.hasFindings
        ? '1 Fix the problems. Claude fixes each one, with a test. Then review again.'
        : '1 Start the review. Claude looks for problems in the changes. Then you fix or accept them.'
    case 'check':
      return ctx.allChecksPass
        ? '1 Finish the run. All checks pass. Then you can commit.'
        : '1 Run the checks. Claude runs build, tests and lint. Then you finish the run.'
    case 'fix':
      return ctx.loopLimitReached
        ? 'Fixing did not work after several tries. Choose: 1 make a new plan, 2 skip with a reason, or 3 take over.'
        : '1 Fix the failures. Claude makes the smallest fix. Then press 3 to run the checks again.'
  }
}
