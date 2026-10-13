// The gate, asked as a question. When the Temper bar draws no buttons (minimal and off modes), the
// orchestrator asks the gate in Claude Code's own question dialog, with the header `Temper gate`, and the
// mod reads the person's answer from the dialog's result. The answer records the same decision the
// matching typed `/temper:temper` command records. Pure: no Claude imports.
//
//   "Continue to {next}" (also with " (Recommended)")  approve at Intent and Plan, next after them
//   "Stage by stage" / "Autonomous: ..."               approve at the Plan gate when autonomy is on (the arming choice)
//   "Commit"                                           next at Check: the one question of a passed Check
//   "Save for later"                                   pause
//   "Loop back to {phase}"                             back, only with the person's reason
//   "Override and continue"                            override, only with the person's reason
//   "Accept finding {id}"                              accept that review finding, only with the person's reason
//   "Override and commit"                              at Done, the failed commit gate: override, with a reason
//   "Keep the agent's commits"                         a group parked on a task agent's commits: keep them, with a reason
//
// A reason is the person's own text for that question: the text typed after the choice in "Other"
// ("Loop back to Plan: the API changed"), or the note the person added to the choice. When the choice
// comes without a reason, the orchestrator asks the reason question: the same header, and a question that
// starts with the move and "What is the reason?" ("Loop back to Plan. What is the reason?"). Any answer to
// it but "Cancel" is the person's reason.

import type { Phase } from './events'
import { PHASES } from './events'
import { NEXT } from './actions'
import type { Bare } from './commands'

export const GATE_HEADER = 'Temper gate'
// The question the orchestrator asks when a saved run does not fit (Resume Validation, a run of another feature).
export const RESUME_HEADER = 'Temper resume'
export const START_OVER = 'Start over'
export const REASON_QUESTION = 'What is the reason?'
export const CANCEL = 'Cancel'

type Question = { question?: unknown; header?: unknown }

// Where the run is, beyond its phase: at the Design gate (part of Plan in the mod) a loop back to Plan redoes the plan.
export type GateWhere = { atDesign?: boolean }

// The words after a choice that carry the reason: a separator, or plain space.
const REST = String.raw`(?:\s*\(recommended\))?(?:\s*[:;,.]\s*|\s+-\s+|\s+|$)([\s\S]*)$`
const CONTINUE = /^continue to (\w+)(?:\s*\(recommended\))?$/i
// A bare "Continue": the move on from the gate the run is at (standalone pages name it so).
const CONTINUE_BARE = /^continue(?:\s*\(recommended\))?$/i
const ARMING = /^(?:stage by stage|autonomous\b[^\n]*)$/i
const SAVE = /^save for later(?:\s*\(recommended\))?$/i
const COMMIT = /^commit(?:\s*\(recommended\))?$/i
const LOOP = new RegExp(String.raw`^loop back to (\w+)${REST}`, 'i')
const OVERRIDE = new RegExp(String.raw`^override and continue${REST}`, 'i')
const ACCEPT = new RegExp(String.raw`^accept finding (\w+)${REST}`, 'i')
const OVERRIDE_COMMIT = new RegExp(String.raw`^override and commit${REST}`, 'i')
const KEEP = new RegExp(String.raw`^keep the agent'?s commits${REST}`, 'i')
const ASKS_REASON = new RegExp(String.raw`^\s*(loop back to \w+|override and continue|accept finding \w+|override and commit|keep the agent'?s commits)\s*[.:]\s*${escapeText(REASON_QUESTION)}`, 'i')

function escapeText(text: string): string {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

const FLOW: readonly Phase[] = PHASES.filter(p => p !== 'fix')

// The phases a "Continue to" may name from the phase the run is at. Design is part of Plan in the mod:
// the Plan gate continues to Design when the run has one, and the Design gate continues to Build.
function nextNames(phase: Phase): string[] {
  const next = NEXT[phase].toLowerCase()
  return phase === 'plan' ? [next, 'design'] : [next]
}

// A step back to `to` from the phase the run is at: only to an earlier phase of the flow, or to Plan from the Design gate.
function backTo(word: string, phase: Phase, where: GateWhere): Phase | null {
  const to = FLOW.find(p => p === word.toLowerCase())
  if (to === undefined) return null
  if (where.atDesign && phase === 'plan' && to === 'plan') return to
  return PHASES.indexOf(to) < PHASES.indexOf(phase) ? to : null
}

// The move a choice names, with the reason the person gave for it (empty when none).
function move(choice: string, reason: string, phase: Phase | 'done', where: GateWhere): Bare | null {
  const text = choice.trim()
  if (phase === 'done') {
    const commit = OVERRIDE_COMMIT.exec(text)
    const why = commit ? (commit[1] ?? '').trim() || reason : ''
    return commit && why !== '' ? { type: 'override', reason: why, stage: 'commit' } : null
  }
  const go = CONTINUE.exec(text)
  if (go) {
    if (!nextNames(phase).includes((go[1] ?? '').toLowerCase())) return null
    return phase === 'intent' || phase === 'plan' ? { type: 'approve' } : { type: 'advance' }
  }
  if (CONTINUE_BARE.test(text)) return phase === 'intent' || phase === 'plan' ? { type: 'approve' } : { type: 'advance' }
  // The arming choice replaces Continue at the Plan gate (reference/autonomy.md): either answer approves the plan.
  if (ARMING.test(text.replace(/\s*\(recommended\)$/i, ''))) return phase === 'plan' && !where.atDesign ? { type: 'approve' } : null
  if (SAVE.test(text)) return { type: 'pause' }
  if (COMMIT.test(text)) return phase === 'check' ? { type: 'advance' } : null
  const loop = LOOP.exec(text)
  if (loop) {
    const to = backTo(loop[1] ?? '', phase, where)
    const why = (loop[2] ?? '').trim() || reason
    return to !== null && why !== '' ? { type: 'back', to, reason: why } : null
  }
  const skip = OVERRIDE.exec(text)
  if (skip) {
    const why = (skip[1] ?? '').trim() || reason
    return why !== '' ? { type: 'override', reason: why } : null
  }
  const keep = KEEP.exec(text)
  if (keep) {
    const why = (keep[1] ?? '').trim() || reason
    return why !== '' && phase === 'build' ? { type: 'override', reason: why, stage: 'foreign-commit' } : null
  }
  const accept = ACCEPT.exec(text)
  if (accept) {
    const why = (accept[2] ?? '').trim() || reason
    return why !== '' && (phase === 'review' || phase === 'fix') ? { type: 'acceptFinding', id: accept[1] ?? '', reason: why } : null
  }
  return null
}

// The decision in an AskUserQuestion result for the phase the run is at, or null. Only the result
// counts: it is what the dialog returned after the person chose, not what the caller sent in. A question
// with another header, a choice for another phase, a typed message that names no move, and a step back or
// a skip with no reason are no decision. The first Temper gate question of the result decides.
export function gateAnswer(result: unknown, phase: Phase | 'done' | null, where: GateWhere = {}): Bare | null {
  if (phase === null) return null
  const r = (result && typeof result === 'object' ? (result as { result?: unknown }).result : undefined) as
    | { questions?: unknown; answers?: unknown; annotations?: unknown }
    | undefined
  if (!r || !Array.isArray(r.questions) || !r.answers || typeof r.answers !== 'object') return null
  const answers = r.answers as Record<string, unknown>
  const notes = r.annotations && typeof r.annotations === 'object' ? (r.annotations as Record<string, unknown>) : {}
  for (const q of r.questions as Question[]) {
    if (typeof q?.question !== 'string' || typeof q.header !== 'string') continue
    if (q.header.trim().toLowerCase() !== GATE_HEADER.toLowerCase()) continue
    const answer = answers[q.question]
    if (typeof answer !== 'string' || answer.trim() === '') return null
    const note = notes[q.question]
    const noted = note && typeof note === 'object' ? (note as { notes?: unknown }).notes : undefined
    const typed = typeof noted === 'string' ? noted.trim() : ''
    // The reason question: the move is in the question, the reason is the person's answer.
    const asks = ASKS_REASON.exec(q.question)
    if (asks) {
      if (answer.trim().toLowerCase() === CANCEL.toLowerCase()) return null
      const reason = [answer.trim(), typed].filter(t => t !== '').join(' ')
      return move(asks[1] ?? '', reason, phase, where)
    }
    return move(answer, typed, phase, where)
  }
  return null
}

// The person's "Start over" in the `Temper resume` question: a restart decision, at any phase of an active run.
// Only the result counts, as for the gate. The reason is the person's note, else the question they answered.
export function resumeAnswer(result: unknown): Bare | null {
  const r = (result && typeof result === 'object' ? (result as { result?: unknown }).result : undefined) as
    | { questions?: unknown; answers?: unknown; annotations?: unknown }
    | undefined
  if (!r || !Array.isArray(r.questions) || !r.answers || typeof r.answers !== 'object') return null
  const answers = r.answers as Record<string, unknown>
  const notes = r.annotations && typeof r.annotations === 'object' ? (r.annotations as Record<string, unknown>) : {}
  for (const q of r.questions as Question[]) {
    if (typeof q?.question !== 'string' || typeof q.header !== 'string') continue
    if (q.header.trim().toLowerCase() !== RESUME_HEADER.toLowerCase()) continue
    const answer = answers[q.question]
    if (typeof answer !== 'string' || !new RegExp(String.raw`^${START_OVER}(?:\s*\(recommended\))?$`, 'i').test(answer.trim())) return null
    const note = notes[q.question]
    const noted = note && typeof note === 'object' ? (note as { notes?: unknown }).notes : undefined
    const typed = typeof noted === 'string' ? noted.trim() : ''
    return { type: 'restart', reason: typed !== '' ? typed : `chosen in the question: ${q.question.trim()}` }
  }
  return null
}
