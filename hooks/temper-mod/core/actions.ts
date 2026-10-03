// Per-phase actions and hotkeys (mods-plan 3.7). Key 1 is the main action and changes
// when the phase is ready to move on. Every action that runs something submits a prompt
// to Claude (`prompt`) or runs a reserved /temper:temper subcommand (`command`); none submits
// on its own. 9 is override everywhere and asks for a reason.

import type { Phase } from './events'

// 1, 2, 3 are the three main actions, 9 is override and 0 opens the full list. The full list
// uses lowercase letters, so no key is ever used twice in one place.
export type ActionKey = '1' | '2' | '3' | '9' | '0' | 'a' | 'b' | 'c' | 'd' | 'e' | 'f' | 'g' | 'h'

export type Action = {
  key: ActionKey
  id: string
  label: string
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

const prompt = (key: ActionKey, id: string, label: string, text: string): Action => ({ key, id, label, prompt: text })
const command = (key: ActionKey, id: string, label: string, cmd: string, asksReason = false): Action => ({
  key,
  id,
  label,
  command: cmd,
  ...(asksReason ? { asksReason } : {}),
})

const OVERRIDE: Action = command('9', 'override', 'Override gate', 'override', true)

export function actionsFor(phase: Phase, ctx: ActionContext): ActionSet {
  switch (phase) {
    case 'intent':
      return {
        primary: [
          ctx.ready
            ? command('1', 'approve', 'Approve intent', 'approve')
            : prompt('1', 'check-intent', 'Check intent', 'Run the intent gate (scripts/temper gate intent). Fix what it reports in intent.md.'),
          prompt('2', 'clarify', 'Ask questions', 'Ask me the questions that make the intent clear. Ask one question at a time.'),
          prompt('3', 'edit-intent', 'Edit intent', 'Show me intent.md. Make the changes I describe next.'),
        ],
        override: OVERRIDE,
        more: [prompt('0', 'capture', 'Capture intent', 'Write my last request as a draft intent.md for a new spec.')],
      }
    case 'plan':
      return {
        primary: [
          ctx.ready
            ? command('1', 'approve', 'Approve plan', 'approve')
            : prompt('1', 'generate-plan', 'Write plan', 'Write plan.md and tasks.md for the approved intent. Include the blast radius and the scenarios.'),
          prompt('2', 'plan-files', 'Show files', 'List each file the plan creates or changes. Give one reason for each file.'),
          prompt('3', 'alternative', 'Other plan', 'Give one other way to do the plan. Compare the two plans.'),
        ],
        override: OVERRIDE,
        more: [
          prompt('0', 'split-tasks', 'Split tasks', 'Split the plan into smaller tasks in tasks.md. Give each task its own Validate command.'),
          command('0', 'back-intent', 'Back to Intent', 'back intent'),
        ],
      }
    case 'build':
      return {
        primary: [
          ctx.tasksDone
            ? command('1', 'to-review', 'Send to Review', 'next')
            : prompt('1', 'next-task', 'Next task', 'Start the next task in tasks.md. Write a failing test first.'),
          prompt('2', 'run-tests', 'Run tests', 'Run the tests for the criterion we work on. Report the result.'),
          prompt('3', 'diff-plan', 'Show diff', 'Show the git diff. Say which changes are outside the plan files.'),
        ],
        override: OVERRIDE,
        more: [],
      }
    case 'review':
      return {
        primary: [
          ctx.hasFindings
            ? prompt('1', 'fix-all', 'Fix all', 'Fix each open review finding, one at a time. Write a regression test for each fix.')
            : prompt('1', 'start-review', 'Start review', 'Run the review on the changed files.'),
          prompt('2', 'review-again', 'Review again', 'Run the review again on the current diff.'),
          prompt('3', 'diff', 'Show diff', 'Show the git diff of the changes in review.'),
        ],
        override: OVERRIDE,
        more: [],
      }
    case 'check':
      return {
        primary: [
          ctx.allChecksPass
            ? command('1', 'mark-done', 'Mark done', 'next')
            : prompt('1', 'run-checks', 'Run checks', 'Run the checks: compile, tests, coverage, lint and security.'),
          prompt('2', 'rerun-failed', 'Rerun failed', 'Run again only the checks that failed.'),
          prompt('3', 'failures', 'Show failures', 'List the failed checks. Group them by acceptance criterion.'),
        ],
        override: OVERRIDE,
        more: [],
      }
    case 'fix':
      if (ctx.loopLimitReached) {
        return {
          primary: [
            command('1', 'plan-again', 'Plan again', 'back plan', true),
            command('2', 'override-limit', 'Override', 'override', true),
            command('3', 'take-over', 'Take over', 'pause'),
          ],
          override: OVERRIDE,
          more: [],
        }
      }
      return {
        primary: [
          prompt('1', 'fix-failures', 'Fix failures', 'Fix the failed checks with the smallest change. Then stop for the check run.'),
          prompt('2', 'fix-findings', 'Fix findings', 'Fix the open review findings, one at a time.'),
          command('3', 'to-check', 'Back to Check', 'next'),
        ],
        override: OVERRIDE,
        more: [],
      }
  }
}

// Per finding actions, shown in the pane.
export function findingActions(id: string): Action[] {
  return [
    prompt('1', `fix-${id}`, 'Fix', `Fix review finding ${id}. Write a regression test.`),
    { ...command('2', `accept-${id}`, 'Accept', `accept ${id}`, true) },
    prompt('3', `explain-${id}`, 'Explain', `Explain review finding ${id}. Say what is wrong, where it is, and why it matters.`),
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
  const out: Action[] = [paused ? command('0', 'resume', 'Resume run', 'resume') : command('0', 'pause', 'Pause run', 'pause')]
  const prev = BACK_ONE[phase]
  if (prev) out.push(command('0', 'back-one', `Go back to ${prev.charAt(0).toUpperCase()}${prev.slice(1)}`, `back ${prev}`, true))
  out.push(prompt('0', 'pr-desc', 'Write PR text', 'Write a pull request description for this change. Use .temper/report.md. Write the report first if it is missing. List the overrides, the accepted findings and the scope drift decisions with their reasons.'))
  return out
}

// One plain sentence: what to do now. It reads the same in the band, the pane, the hint and
// the line under an answer.
export function nowText(phase: Phase | 'done', ctx: ActionContext): string {
  switch (phase) {
    case 'done':
      return 'The run is done. Commit is allowed.'
    case 'intent':
      return ctx.ready ? 'Approve the intent. Then Plan starts.' : 'Check the intent until its gate passes. Then approve it.'
    case 'plan':
      return ctx.ready ? 'Approve the plan. Then Build starts.' : 'Write the plan and the tasks. Then approve them.'
    case 'build':
      return ctx.tasksDone ? 'Build is done. Send it to Review.' : 'Do the tasks one by one. Write a failing test first.'
    case 'review':
      return ctx.hasFindings ? 'Fix the open findings or accept them with a reason.' : 'Run the review.'
    case 'check':
      return ctx.allChecksPass ? 'All checks pass. Mark the run done.' : 'Run the checks.'
    case 'fix':
      return ctx.loopLimitReached ? 'The fix loop limit is reached. Plan again, override, or take over.' : 'Fix the failed checks. Then go back to Check.'
  }
}
