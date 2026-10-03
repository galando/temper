// The reserved first words of `/temper:temper` and what each one means. Pure: this file turns
// typed arguments into a machine command, a local answer, or an error; the adapter runs
// the result. Anything that is not a reserved word is left to the prompt based /temper:temper.

import type { Draft, DriftChoice, Phase } from './events'
import { PHASES } from './events'
import { acceptCommand, advanceCommands, backCommand, overrideCommand } from './cli'
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
  'play',
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
      if (!FLOW_PHASES.includes(to.toLowerCase())) return { kind: 'error', text: 'Usage: /temper:temper back <intent|plan|build|review|check> <reason>' }
      return { kind: 'command', command: { type: 'back', to: to.toLowerCase() as Phase, reason } }
    }
    case 'accept': {
      const [id, reason] = split(rest)
      if (!id) return { kind: 'error', text: 'Usage: /temper:temper accept <finding id> <reason>' }
      return { kind: 'command', command: { type: 'acceptFinding', id, reason } }
    }
    case 'drift': {
      const [choiceWord, reason] = split(rest)
      const choices: Record<string, DriftChoice> = { add: 'add', revert: 'revert', allow: 'allow-once', 'allow-once': 'allow-once' }
      const choice = choices[choiceWord.toLowerCase()]
      if (!choice) return { kind: 'error', text: 'Usage: /temper:temper drift <add|revert|allow> <reason>' }
      if (!pendingDrift) return { kind: 'error', text: 'No scope drift waits for a decision.' }
      return { kind: 'command', command: { type: 'drift', path: pendingDrift, choice, reason } }
    }
    default:
      return { kind: 'local', word, rest }
  }
}

// What Claude is asked to do once the person decided with a button (the command path runs the
// prompt based command instead). The decision is already recorded by the mod: the prompt says so,
// names the exact CLI command that mirrors it in the CLI state (the commit gate reads that state),
// and says what to do next. Every command named here is a valid `scripts/temper` invocation.
export function followUp(draft: Draft, complexity: string | null = null): string | null {
  const recorded = 'The user\'s decision is recorded. The command only copies it to the CLI state.'
  switch (draft.type) {
    case 'advance': {
      if (draft.to === 'done') {
        const cmds = advanceCommands(draft.from, draft.to, complexity)
        return `Temper: the user marked the run done. ${recorded} Run ${cmds.map(c => `\`${c}\``).join(' then ')}. Then report the result. Commit only if the user asks.`
      }
      const cmds = advanceCommands(draft.from, draft.to, complexity)
      const run = cmds.length > 0 ? ` Run ${cmds.map(c => `\`${c}\``).join(' then ')}.` : ''
      return `Temper: the user moved the run from ${draft.from} to ${draft.to}. ${recorded}${run} Then continue with the ${draft.to} phase.`
    }
    case 'override':
      return `Temper: the user overrode the ${draft.phase} phase (reason: ${draft.reason}). ${recorded} Run \`${overrideCommand(draft.phase, draft.reason)}\`. Then continue with the next phase.`
    case 'accept':
      return `Temper: the user accepted review finding ${draft.findingId} (reason: ${draft.reason}). ${recorded} Run \`${acceptCommand(draft.findingId, draft.reason)}\`.`
    case 'back':
      return `Temper: the user sent the run back to ${draft.to} (reason: ${draft.reason}). ${recorded} Run \`${backCommand(draft.to)}\`. Then redo ${draft.to} before you move on.`
    case 'drift':
      return draft.choice === 'revert'
        ? `Temper: the user chose to revert the change to ${draft.path}. It is not in the plan. Restore the file to its committed state. Then continue inside the plan.`
        : `Temper: the user decided the scope drift for ${draft.path} (${draft.choice}). Continue.`
    default:
      return null
  }
}

export const HELP = [
  'Temper subcommands (type them after /temper:temper):',
  '  status               show where the run is',
  '  timeline             show the phases of the run',
  '  approve              approve the current phase (Intent or Plan)',
  '  next                 move on when the phase passes its gate',
  '  back <phase> <why>   go back (later phases need a new verdict)',
  '  override <reason>    skip the current phase once (give a reason)',
  '  accept <id> <why>    accept a review finding (give a reason)',
  '  drift <add|revert|allow> <reason>   decide a scope drift',
  '  pause / resume       take the run over, give it back',
  '  report               write .temper/report.md now',
  '  pr                   ask Claude for a pull request description',
  '  play                 play Temper Run while you wait (Esc leaves)',
  '  mode, enforcement, pane   show or change what Temper shows and enforces',
  'Any other text after /temper:temper is a feature description. It starts or resumes a run.',
].join('\n')
