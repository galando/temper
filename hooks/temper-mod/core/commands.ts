// The reserved first words of `/temper` and what each one means. Pure: this file turns
// typed arguments into a machine command, a local answer, or an error; the adapter runs
// the result. Anything that is not a reserved word is left to the prompt based /temper.

import type { Draft, DriftChoice, Phase } from './events'
import { PHASES } from './events'
import type { Command } from './machine'

export const RESERVED = [
  'status',
  'timeline',
  'back',
  'override',
  'approve',
  'accept',
  'drift',
  'pause',
  'resume',
  'help',
  'report',
  'pr',
  'mode',
  'enforcement',
  'next',
  'pane',
] as const

export type Reserved = (typeof RESERVED)[number]

export const isReserved = (w: string): w is Reserved => (RESERVED as readonly string[]).includes(w)

export type Parsed = { word: Reserved; rest: string }

// null when the first word is not reserved (a feature description, or nothing).
export function parseArgs(args: string): Parsed | null {
  const text = args.trim()
  const m = /^(\S+)\s*([\s\S]*)$/.exec(text)
  const word = (m?.[1] ?? '').toLowerCase()
  return m && isReserved(word) ? { word, rest: (m[2] ?? '').trim() } : null
}

// What the machine is asked to do, before the origin is stamped on.
export type Bare = Command extends infer C ? (C extends unknown ? Omit<C, 'origin' | 'author'> : never) : never

export type Plan =
  | { kind: 'command'; command: Bare }
  | { kind: 'local'; word: Reserved; rest: string }
  | { kind: 'error'; text: string }

const FLOW_PHASES: readonly string[] = PHASES.filter(p => p !== 'fix')

const split = (rest: string): [string, string] => {
  const m = /^(\S+)\s*([\s\S]*)$/.exec(rest.trim())
  return [m?.[1] ?? '', (m?.[2] ?? '').trim()]
}

export function planCommand(parsed: Parsed, pendingDrift: string | null): Plan {
  const { word, rest } = parsed
  switch (word) {
    case 'approve':
      return { kind: 'command', command: { type: 'approve' } }
    case 'next':
      return { kind: 'command', command: { type: 'advance' } }
    case 'pause':
      return { kind: 'command', command: { type: 'pause' } }
    case 'resume':
      return { kind: 'command', command: { type: 'resume' } }
    case 'override':
      return { kind: 'command', command: { type: 'override', reason: rest } }
    case 'back': {
      const [to, reason] = split(rest)
      if (!FLOW_PHASES.includes(to.toLowerCase())) return { kind: 'error', text: 'Usage: /temper back <intent|plan|build|review|check> <reason>' }
      return { kind: 'command', command: { type: 'back', to: to.toLowerCase() as Phase, reason } }
    }
    case 'accept': {
      const [id, reason] = split(rest)
      if (!id) return { kind: 'error', text: 'Usage: /temper accept <finding id> <reason>' }
      return { kind: 'command', command: { type: 'acceptFinding', id, reason } }
    }
    case 'drift': {
      const [choiceWord, reason] = split(rest)
      const choices: Record<string, DriftChoice> = { add: 'add', revert: 'revert', allow: 'allow-once', 'allow-once': 'allow-once' }
      const choice = choices[choiceWord.toLowerCase()]
      if (!choice) return { kind: 'error', text: 'Usage: /temper drift <add|revert|allow> <reason>' }
      if (!pendingDrift) return { kind: 'error', text: 'No scope drift is pending. Nothing to decide.' }
      return { kind: 'command', command: { type: 'drift', path: pendingDrift, choice, reason } }
    }
    default:
      return { kind: 'local', word, rest }
  }
}

// What Claude is asked to do once the person decided with a button (the command path
// runs the prompt based /temper instead): mirror the decision in the CLI, or act on it.
export function followUp(draft: Draft): string | null {
  switch (draft.type) {
    case 'advance':
      return draft.to === 'done'
        ? 'Temper: the run is complete. Report the result and, if the user asks, commit.'
        : `Temper: the user moved the run from ${draft.from} to ${draft.to}. Record it with scripts/temper state advance ${draft.from} ${draft.to}, then continue with the ${draft.to} phase.`
    case 'override':
      return `Temper: the user overrode the ${draft.phase} phase (reason: ${draft.reason}). Record it with scripts/temper override ${draft.phase} --reason "${draft.reason}" and continue with the next phase.`
    case 'accept':
      return `Temper: the user accepted review finding ${draft.findingId} (reason: ${draft.reason}). Record it with scripts/temper evidence accept --stage review --id ${draft.findingId} --reason "${draft.reason}".`
    case 'back':
      return `Temper: the user sent the run back to ${draft.to} (reason: ${draft.reason}). Rework ${draft.to} before moving forward again.`
    case 'drift':
      return draft.choice === 'revert'
        ? `Temper: the user chose to revert the out of plan change to ${draft.path}. Restore that file to its committed state and continue inside the plan.`
        : `Temper: the user decided scope drift for ${draft.path} (${draft.choice}). Continue.`
    default:
      return null
  }
}

export const HELP = [
  'Temper subcommands (typed after /temper):',
  '  status               where the run stands',
  '  timeline             the phases the run went through',
  '  approve              approve the current phase (Intent or Plan)',
  '  next                 move on when the phase passed its gate',
  '  back <phase> <why>   go back; every later phase needs a fresh verdict',
  '  override <reason>    skip the current phase, once, with a reason',
  '  accept <id> <why>    accept a review finding with a reason',
  '  drift <add|revert|allow> <reason>   decide a pending scope drift',
  '  pause / resume       hand the run over, take it back',
  '  report               write .temper/report.md now',
  '  pr                   ask Claude for a pull request description',
  '  mode, enforcement, pane   show or change how Temper draws and enforces',
  'Anything else after /temper is a feature description and starts or resumes a run.',
].join('\n')
