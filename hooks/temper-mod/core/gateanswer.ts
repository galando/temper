// The gate, asked as a question (ADR 0012). At every gate, in every setup, Claude asks the person in Claude Code's own
// question dialog with the header `Temper gate`, and the mod reads the person's answer from the dialog's result. Only
// the result counts: it is what the dialog returned after the person chose. Pure: no Claude imports.
//
//   "Continue to {next}" / "Continue" (also with " (Recommended)")  approve at Intent and Plan, advance after them
//   "Stage by stage" / "Autonomous: ..."                         at the Plan gate when autonomy is on: approve, or arm
//   "Commit"                                                     advance at Check: the one question of a passed Check
//   "Save for later"                                             pause
//   "Loop back to {stage}"                                       back, only with the person's reason
//   "Override and continue"                                      override, only with the person's reason
//   "Accept finding {id}"                                        accept that review finding, only with the person's reason
//   "Override and commit"                                        at the commit stage, the failed commit gate: with a reason
//   "Keep the agent's commits"                                   a group parked on a task agent's commits, with a reason
//
// A reason is the person's own text for that question: the text typed after the choice in "Other" ("Loop back to Plan:
// the API changed"), or the note the person added to the choice. When the choice comes without a reason, Claude asks
// the reason question: the same header, and a question that starts with the move and "What is the reason?" ("Loop back
// to Plan. What is the reason?"). Any answer to it but "Cancel" is the person's reason.

import type { MoveKind } from './decisions'
import type { Stage } from './stages'
import { earlierStages, isStage, nextStage } from './stages'

export const GATE_HEADER = 'Temper gate'
// The question Claude asks when a saved run does not fit (Resume Validation, a run of another feature).
export const RESUME_HEADER = 'Temper resume'
export const START_OVER = 'Start over'
export const REASON_QUESTION = 'What is the reason?'
export const CANCEL = 'Cancel'

export type Answer = { kind: MoveKind; reason: string; to?: Stage } | { kind: 'accept'; findingId: string; reason: string }

type Question = { question?: unknown; header?: unknown; multiSelect?: unknown }

// The words after a choice that carry the reason: a separator, or plain space.
const REST = String.raw`(?:\s*\(recommended\))?(?:\s*[:;,.]\s*|\s+-\s+|\s+|$)([\s\S]*)$`
const CONTINUE = /^continue to (\w+)(?:\s*\(recommended\))?$/i
const CONTINUE_BARE = /^continue(?:\s*\(recommended\))?$/i
const STAGE_BY_STAGE = /^stage by stage(?:\s*\(recommended\))?$/i
const AUTONOMOUS = /^autonomous\b[^\n]*$/i
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

// Where the run is, beyond its stage: whether it has a Design stage (Plan then continues to Design).
export type GateWhere = { design?: boolean }

// The move a gate leaves with when the person goes on: an approval at Intent and Plan (only the person may leave them),
// else an advance (the stage follows its own verdict).
const goOn = (stage: Stage): MoveKind => (stage === 'intent' || stage === 'plan' ? 'approve' : 'advance')

// The move a choice names, with the reason the person gave for it (empty when none).
function move(choice: string, reason: string, stage: Stage, where: GateWhere): Answer | null {
  const text = choice.trim()
  const design = where.design === true
  if (stage === 'commit') {
    const m = OVERRIDE_COMMIT.exec(text)
    const why = m ? (m[1] ?? '').trim() || reason : ''
    if (m && why !== '') return { kind: 'commitOverride', reason: why }
    return SAVE.test(text) ? { kind: 'pause', reason: '' } : null
  }
  const go = CONTINUE.exec(text)
  if (go) {
    // "Continue to Build" at the Plan gate of a run with Design still means going on: the orchestrator does Design next.
    const named = (go[1] ?? '').toLowerCase()
    const next = nextStage(stage, design)
    const ok = named === next || (stage === 'plan' && (named === 'design' || named === 'build'))
    return ok ? { kind: goOn(stage), reason: '' } : null
  }
  if (CONTINUE_BARE.test(text)) return { kind: goOn(stage), reason: '' }
  // The arming choice replaces Continue at the Plan gate (reference/autonomy.md).
  if (STAGE_BY_STAGE.test(text)) return stage === 'plan' ? { kind: 'approve', reason: '' } : null
  if (AUTONOMOUS.test(text.replace(/\s*\(recommended\)$/i, ''))) return stage === 'plan' ? { kind: 'arm', reason: '' } : null
  if (SAVE.test(text)) return { kind: 'pause', reason: '' }
  if (COMMIT.test(text)) return stage === 'check' ? { kind: 'advance', reason: '' } : null
  const loop = LOOP.exec(text)
  if (loop) {
    const word = (loop[1] ?? '').toLowerCase()
    const why = (loop[2] ?? '').trim() || reason
    if (!isStage(word) || !earlierStages(stage, design).includes(word) || why === '') return null
    return { kind: 'back', to: word, reason: why }
  }
  const skip = OVERRIDE.exec(text)
  if (skip) {
    const why = (skip[1] ?? '').trim() || reason
    return why !== '' ? { kind: 'override', reason: why } : null
  }
  const keep = KEEP.exec(text)
  if (keep) {
    const why = (keep[1] ?? '').trim() || reason
    return why !== '' && stage === 'build' ? { kind: 'keep', reason: why } : null
  }
  const accept = ACCEPT.exec(text)
  if (accept) {
    const why = (accept[2] ?? '').trim() || reason
    return why !== '' && stage === 'review' && /^\d+$/.test(accept[1] ?? '') ? { kind: 'accept', findingId: accept[1] ?? '', reason: why } : null
  }
  return null
}

type Result = { questions?: unknown; answers?: unknown; annotations?: unknown; afkTimeoutMs?: unknown; followUp?: unknown }

// The result of a dialog the person answered. A dialog that resolved by itself while the person was away
// (`afkTimeoutMs`), or one the person answered by asking for another round (`followUp`), holds no decision.
export function answeredResult(result: unknown): Result | null {
  const r = (result && typeof result === 'object' ? (result as { result?: unknown }).result : undefined) as Result | undefined
  if (!r || !Array.isArray(r.questions) || !r.answers || typeof r.answers !== 'object') return null
  if (r.afkTimeoutMs !== undefined || r.followUp === true) return null
  return r
}

// The decision in an AskUserQuestion result for the stage the run is at, or null. A question with another header, a
// multi-select question, a choice for another stage, a typed message that names no move, and a step back or a skip
// with no reason are no decision. The first Temper gate question whose answer is a move decides (a first question
// answered "More options" leaves the move to the next one).
export function gateAnswer(result: unknown, stage: Stage | null, where: GateWhere = {}): Answer | null {
  if (stage === null) return null
  const r = answeredResult(result)
  if (r === null) return null
  const answers = r.answers as Record<string, unknown>
  const notes = r.annotations && typeof r.annotations === 'object' ? (r.annotations as Record<string, unknown>) : {}
  for (const q of r.questions as Question[]) {
    if (typeof q?.question !== 'string' || typeof q.header !== 'string') continue
    if (q.header.trim().toLowerCase() !== GATE_HEADER.toLowerCase() || q.multiSelect === true) continue
    const answer = answers[q.question]
    if (typeof answer !== 'string' || answer.trim() === '') continue
    const note = notes[q.question]
    const noted = note && typeof note === 'object' ? (note as { notes?: unknown }).notes : undefined
    const typed = typeof noted === 'string' ? noted.trim() : ''
    // The reason question: the move is in the question, the reason is the person's answer.
    const asks = ASKS_REASON.exec(q.question)
    if (asks) {
      if (answer.trim().toLowerCase() === CANCEL.toLowerCase()) return null
      const reason = [answer.trim(), typed].filter(t => t !== '').join(' ')
      const decided = move(asks[1] ?? '', reason, stage, where)
      if (decided !== null) return decided
      continue
    }
    const decided = move(answer, typed, stage, where)
    if (decided !== null) return decided
  }
  return null
}

// The person's "Start over" in the `Temper resume` question: a restart, at any stage of an active run. Only the result
// counts, as for the gate. The reason is the person's note, else the question they answered.
export function resumeAnswer(result: unknown): { reason: string } | null {
  const r = answeredResult(result)
  if (r === null) return null
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
    return { reason: typed !== '' ? typed : `chosen in the question: ${q.question.trim()}` }
  }
  return null
}
