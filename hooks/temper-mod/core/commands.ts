// The reserved first words of `/temper:temper` and what each one means. Pure: this file turns
// typed arguments into a machine command, a local answer, or an error; the adapter runs
// the result. Anything that is not a reserved word is left to the prompt based /temper:temper.

import type { Draft, DriftChoice, Phase } from './events'
import { PHASES } from './events'
import { ACT } from './actions'
import { CLI, acceptCommand, advanceCommands, backCommand, overrideCommand } from './cli'
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
  'discuss',
  'continue',
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

// The command a button runs after the mirror prompt (`$.command.run`, as `/temper:temper` with no
// arguments), so the orchestrator (commands/temper.md, its Resume path) launches the next stage with
// its own brief. No arguments: the decision is already recorded and mirrored.
export const RESUME = 'temper:temper'

// What Claude is asked to do once the person decided with a button (the command path runs the
// prompt based command instead). The decision is already recorded by the mod: the prompt says so
// and names the exact CLI command that mirrors it in the CLI state (the commit gate reads that
// state). It never says what to run next: RESUME does that, through the orchestrator.
// Every command named here is a valid `scripts/temper` invocation.
// `cli` is where the Temper script really is (the plugin folder, not the project). Without it the
// prompt names `scripts/temper` and says the script lives in the plugin folder, so Claude does not
// waste the one allowed run on a path that does not exist in the project.
export function followUp(draft: Draft, complexity: string | null = null, cli: string = CLI): string | null {
  const text = followUpText(draft, complexity)
  if (text === null) return null
  if (cli !== CLI) return text.split(`\`${CLI} `).join(`\`${cli} `)
  return text.includes(`\`${CLI} `) ? text.replace(` ${ACT}`, ` The script is in the Temper plugin folder, not in the project. ${ACT}`) : text
}

function followUpText(draft: Draft, complexity: string | null): string | null {
  // Short on purpose: one or two lines, and no narration.
  const recorded = 'The decision is already recorded.'
  switch (draft.type) {
    case 'advance': {
      const cmds = advanceCommands(draft.from, draft.to, complexity)
      if (cmds.length === 0) return null
      const run = ` Run ${cmds.map(c => `\`${c}\``).join(' then ')}.`
      if (draft.to === 'done') return `Temper: the user finished the run. ${recorded}${run} Do not commit. ${ACT}`
      return `Temper: the user moved the run from ${draft.from} to ${draft.to}. ${recorded}${run} Do not start the next stage yourself. ${ACT}`
    }
    case 'override':
      return `Temper: the user skipped ${draft.phase} (reason: ${draft.reason}). ${recorded} Run \`${overrideCommand(draft.phase, draft.reason)}\`. Do not start the next stage yourself. ${ACT}`
    case 'accept':
      return `Temper: the user accepted finding ${draft.findingId} (reason: ${draft.reason}). ${recorded} Run \`${acceptCommand(draft.findingId, draft.reason)}\`. ${ACT}`
    case 'back':
      return `Temper: the user went back to ${draft.to} (reason: ${draft.reason}). ${recorded} Run \`${backCommand(draft.to)}\`. Do not start the stage yourself. ${ACT}`
    case 'drift':
      return draft.choice === 'revert'
        ? `Temper: the user chose to revert ${draft.path}. Restore it to its committed state. Then stay inside the plan. ${ACT}`
        : `Temper: the user decided the scope drift for ${draft.path} (${draft.choice}). Go on. ${ACT}`
    default:
      return null
  }
}

export const HELP = [
  'Temper subcommands (type them after /temper:temper):',
  '  status               show where the run is',
  '  timeline             show the phases of the run',
  '  approve              approve the current phase (Intent or Plan)',
  '  next                 move on when the step has passed its check',
  '  back <phase> <why>   go back (later steps need a new check)',
  '  override <reason>    skip the current step once (give a reason)',
  '  accept <id> <why>    accept a review finding (give a reason)',
  '  drift <add|revert|allow> <reason>   decide a scope drift',
  '  pause / resume       take the run over, give it back',
  '  report               write .temper/report.md now',
  '  pr                   ask Claude for a pull request description',
  '  play                 play Temper Run while you wait (key 8 too; r runs, w jumps, s ducks, q leaves)',
  '  discuss <text>       send a message about the step you are at (the same as key 4)',
  '  continue <stage>     the Temper bar sends this after you chose Continue: Claude does the On Continue steps of that stage',
  '  mode, enforcement, pane   show or change what Temper shows and enforces',
  'Any other text after /temper:temper is a feature description. It starts or resumes a run.',
].join('\n')
