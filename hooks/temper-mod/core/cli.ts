// The exact `scripts/temper` invocations the mod asks Claude to run to mirror a person's
// decision in the CLI state. Pure. The stage names are those of STAGE_SEQ_TEMPER in
// scripts/temper (a test there keeps the two in step).

import type { Phase } from './events'

export const CLI = 'scripts/temper'

// The Temper script in the plugin folder as a full path, from the module URL of register.tsx
// (<plugin>/hooks/temper-mod/register.tsx). The path is decoded FIRST and then checked, so an
// encoded space or quote (%20, %27) cannot reach a command. Any odd location gives `scripts/temper`.
export function pluginCliFrom(url: string | undefined): string {
  try {
    const here = decodeURIComponent(new URL(url ?? '').pathname)
    const tail = '/hooks/temper-mod/register.tsx'
    if (here.endsWith(tail) && !/[\s'"`$;&|<>()\\]/.test(here)) return `${here.slice(0, -tail.length)}/scripts/temper`
  } catch {
    // no module URL here
  }
  return CLI
}

// STAGE_SEQ_TEMPER, in order. `state advance` takes `<stage>_complete <next stage>`.
export const CLI_STAGES = 'intent plan design build review check'

const STAGES = CLI_STAGES.split(' ')

export const isCliStage = (s: string): boolean => STAGES.includes(s)

// `state advance` for a move the person made, one command per CLI stage the move covers. Plan
// is followed by design when the run's complexity is medium or complex (design belongs to the
// Plan phase here), and Check is followed by commit. A move out of Fix has no CLI stage.
export function advanceCommands(from: Phase, to: Phase | 'done', complexity: string | null): string[] {
  const state = (stage: string, next: string) => `${CLI} state advance ${stage}_complete ${next}`
  switch (from) {
    case 'intent':
      return [state('intent', 'plan')]
    case 'plan':
      return complexity === 'medium' || complexity === 'complex'
        ? [state('plan', 'design'), state('design', 'build')]
        : [state('plan', 'build')]
    case 'build':
      return [state('build', 'review')]
    case 'review':
      return [state('review', 'check')]
    case 'check':
      return to === 'done' ? [state('check', 'commit')] : []
    default:
      return []
  }
}

// The gate stage an override or an advance names, for a phase of the mod.
export const stageOf = (phase: Phase): string => (phase === 'fix' ? 'check' : phase)

// A reason is person typed text inside a shell command: single quoted, quotes escaped, newlines
// flattened, so nothing in it (quotes, $(...), backticks) is read as shell.
export const shellQuote = (text: string): string => `'${text.replace(/\r?\n/g, ' ').replace(/'/g, "'\\''")}'`

export const overrideCommand = (phase: Phase, reason: string): string => `${CLI} override ${stageOf(phase)} --reason ${shellQuote(reason)}`

export const acceptCommand = (findingId: string, reason: string): string => `${CLI} evidence accept --stage review --id ${findingId} --reason ${shellQuote(reason)}`

// Sending a run back: the CLI resumes from the stage it is pointed at.
export const backCommand = (to: Phase): string => `${CLI} state set next_stage ${stageOf(to)}`

// The loop the CLI keeps for a step back: it counts against loops.max-per-type and clears the evidence of
// the stage that is redone and every later one.
export const loopCommand = (from: Phase, to: Phase, reason: string): string => `${CLI} state loop ${stageOf(from)} ${stageOf(to)} --reason ${shellQuote(reason)}`

// The stage of a `state advance <stage>_complete <next>` call, as a phase of the mod, only for
// the two approvals that need a person: leaving Intent and leaving Plan. Design belongs to
// Plan but its own advance needs no second approval, so it is not mapped.
export function guardedPhase(stageArg: string | undefined): Phase | null {
  const stage = (stageArg ?? '').replace(/_complete$/, '')
  return stage === 'intent' || stage === 'plan' ? stage : null
}
