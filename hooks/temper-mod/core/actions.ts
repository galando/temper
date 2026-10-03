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
            : prompt('1', 'lint-intent', 'Lint intent', 'Run the intent gate for the current spec (temper gate intent) and fix what it reports in intent.md.'),
          prompt('2', 'clarify', 'Ask clarifying questions', 'Ask me the clarifying questions that would make the intent unambiguous, one at a time.'),
          prompt('3', 'edit-intent', 'Edit intent', 'Show me intent.md and apply the edits I describe next.'),
        ],
        override: OVERRIDE,
        more: [prompt('0', 'capture', 'Capture intent from my prompt', 'Capture my last request as a draft intent.md for a new spec.')],
      }
    case 'plan':
      return {
        primary: [
          ctx.ready
            ? command('1', 'approve', 'Approve plan', 'approve')
            : prompt('1', 'generate-plan', 'Generate plan', 'Write plan.md and tasks.md for the approved intent, with blast radius and scenarios.'),
          prompt('2', 'plan-files', 'Show files the plan touches', 'List every file the plan creates or modifies, one line each with the reason.'),
          prompt('3', 'alternative', 'Propose an alternative', 'Propose one alternative approach to the current plan and compare the two.'),
        ],
        override: OVERRIDE,
        more: [
          prompt('0', 'split-tasks', 'Split into tasks', 'Split the plan into smaller tasks in tasks.md, each with its own Validate command.'),
          command('0', 'back-intent', 'Back to Intent', 'back intent'),
        ],
      }
    case 'build':
      return {
        primary: [
          ctx.tasksDone
            ? command('1', 'to-review', 'Send to Review', 'next')
            : prompt('1', 'next-task', 'Start next task', 'Start the next unfinished task in tasks.md with a failing test first.'),
          prompt('2', 'run-tests', 'Run tests for current criterion', 'Run the tests for the criterion we are on and report the result.'),
          prompt('3', 'diff-plan', 'Show diff against plan', 'Show the git diff and say which hunks fall outside the plan files.'),
        ],
        override: OVERRIDE,
        more: [command('0', 'pause', 'Pause', 'pause')],
      }
    case 'review':
      return {
        primary: [
          ctx.hasFindings
            ? prompt('1', 'fix-all', 'Fix all', 'Fix every open review finding, one at a time, with a regression test for each.')
            : prompt('1', 'start-review', 'Start review', 'Run the review stage on the changed files.'),
          prompt('2', 're-review', 'Re-review', 'Run the review stage again on the current diff.'),
          prompt('3', 'diff', 'Show diff', 'Show the git diff of the changes under review.'),
        ],
        override: OVERRIDE,
        more: [],
      }
    case 'check':
      return {
        primary: [
          ctx.allChecksPass
            ? command('1', 'mark-done', 'Mark done', 'next')
            : prompt('1', 'run-checks', 'Run all checks', 'Run the check stage: compile, tests, coverage, lint and security.'),
          prompt('2', 'rerun-failed', 'Rerun failed only', 'Rerun only the checks that failed last time.'),
          prompt('3', 'failures', 'Failures by criterion', 'List the failing checks grouped by acceptance criterion.'),
        ],
        override: OVERRIDE,
        more: [],
      }
    case 'fix':
      if (ctx.loopLimitReached) {
        return {
          primary: [
            command('1', 're-plan', 'Re-plan', 'back plan', true),
            command('2', 'override-limit', 'Override', 'override', true),
            command('3', 'take-over', 'I take over', 'pause'),
          ],
          override: OVERRIDE,
          more: [],
        }
      }
      return {
        primary: [
          prompt('1', 'fix-failures', 'Fix failures', 'Fix the failing checks with the smallest change, then stop for the check run.'),
          prompt('2', 'fix-findings', 'Fix open findings', 'Fix the open review findings, one at a time.'),
          command('3', 'to-check', 'Return to Check', 'next'),
        ],
        override: OVERRIDE,
        more: [],
      }
  }
}

// Per finding actions, shown in the pane.
export function findingActions(id: string): Action[] {
  return [
    prompt('1', `fix-${id}`, 'Fix', `Fix review finding ${id} with a regression test.`),
    { ...command('2', `accept-${id}`, 'Accept with reason', `accept ${id}`, true) },
    prompt('3', `explain-${id}`, 'Explain', `Explain review finding ${id}: what is wrong, where, and why it matters.`),
  ]
}

// The sentence that goes after "Next:" in the system prompt section and in denials.
export function nextStep(phase: Phase | 'done', ctx: ActionContext): string {
  switch (phase) {
    case 'done':
      return 'the run is complete; commit is allowed'
    case 'intent':
      return ctx.ready
        ? 'ask the user to approve the intent (key 1 or /temper:temper approve)'
        : 'finish intent.md until the intent gate passes, then ask the user to approve (key 1 or /temper:temper approve)'
    case 'plan':
      return ctx.ready
        ? 'ask the user to approve the plan (key 1 or /temper:temper approve)'
        : 'finish plan.md and tasks.md, then ask the user to approve (key 1 or /temper:temper approve)'
    case 'build':
      return ctx.tasksDone
        ? 'send the work to Review (key 1 or /temper:temper next)'
        : 'work the next task in tasks.md with a failing test first; stay inside the plan files'
    case 'review':
      return ctx.hasFindings
        ? 'fix the open findings or ask the user to accept them with a reason (key 1, /temper:temper accept <id> <reason>)'
        : 'run the review (key 1)'
    case 'check':
      return ctx.allChecksPass ? 'mark the run done (key 1 or /temper:temper next)' : 'run the checks (key 1 in Check or /temper:check)'
    case 'fix':
      return ctx.loopLimitReached
        ? 'the fix loop limit is reached; ask the user to re-plan, override with a reason, or take over'
        : 'fix the failing checks, then return to Check (key 3)'
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
  const out: Action[] = [paused ? command('0', 'resume', 'Resume the run', 'resume') : command('0', 'pause', 'Pause the run', 'pause')]
  const prev = BACK_ONE[phase]
  if (prev) out.push(command('0', 'back-one', `Go back to ${prev.charAt(0).toUpperCase()}${prev.slice(1)}`, `back ${prev}`, true))
  out.push(prompt('0', 'pr-desc', 'Draft the pull request description', 'Write a pull request description for this change from .temper/report.md (write the report first if it is missing). List overrides, accepted findings and scope drift decisions with their reasons.'))
  return out
}

// One plain sentence: what to do now. It reads the same in the band, the pane, the hint and
// the line under an answer.
export function nowText(phase: Phase | 'done', ctx: ActionContext): string {
  switch (phase) {
    case 'done':
      return 'The run is complete: commit is allowed.'
    case 'intent':
      return ctx.ready ? 'Approve the intent, then Plan starts.' : 'Finish the intent until its gate passes, then approve it.'
    case 'plan':
      return ctx.ready ? 'Approve the plan, then Build starts.' : 'Write the plan and the tasks, then approve them.'
    case 'build':
      return ctx.tasksDone ? 'Build is done: send it to Review.' : 'Work through the tasks, one failing test at a time.'
    case 'review':
      return ctx.hasFindings ? 'Fix the open findings, or accept them with a reason.' : 'Run the review.'
    case 'check':
      return ctx.allChecksPass ? 'Every check passed: mark the run done.' : 'Run the checks.'
    case 'fix':
      return ctx.loopLimitReached ? 'Fix loop limit reached: re-plan, override, or take over.' : 'Fix the failing checks, then go back to Check.'
  }
}
