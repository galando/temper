// The person's answers, read from the result of a question dialog (ADR 0013). Claude asks each question exactly as
// `temper next --json` gives it; the CLI writes the same question into view.json. An answer counts only when its
// header, its question and the chosen label match exactly what the view holds for the run and step the CLI is at, so a
// reworded question is no answer. A typed answer ("Other") is never a move: it is a change request or a question, except
// as the answer to a reason question, where any answer but Cancel is the person's reason. Pure.

import type { Ask, Option, Question, RunView } from './runview'

export const CANCEL = 'Cancel'

export type DriftChoice = 'add' | 'revert' | 'allow-once'

export type Answer =
  // A gate question's option (and the reason, when the option needs one).
  // `ask` is the CLI's question of this step that the answer belongs to (More options and the reason question included).
  | { kind: 'gate'; stage: string; question: string; ask: string; option: Option; reason: string }
  // The `Temper resume` question's Start over.
  | { kind: 'restart'; option: Option }
  // A Scope drift question's answer for one file.
  | { kind: 'drift'; path: string; choice: DriftChoice; reason: string }

type Result = { questions?: unknown; answers?: unknown; annotations?: unknown; afkTimeoutMs?: unknown; followUp?: unknown }

// The result of a dialog the person answered. A dialog that resolved by itself while the person was away
// (`afkTimeoutMs`), or one the person answered by asking for another round (`followUp`), holds no answer.
export function answeredResult(result: unknown): Result | null {
  const r = (result && typeof result === 'object' ? (result as { result?: unknown }).result : undefined) as Result | undefined
  if (!r || !Array.isArray(r.questions) || !r.answers || typeof r.answers !== 'object') return null
  if (r.afkTimeoutMs !== undefined || r.followUp === true) return null
  return r
}

const same = (a: { header: string; question: string }, header: unknown, text: unknown): boolean => a.header === header && a.question === text

// Every question the view asks at this step: the gate question, its More options and Accept a finding questions, and the
// Context check of Plan while the view still asks it (a question of the CLI's own; the plan gate may hold other failed rows).
function asks(a: Ask | null, check: Ask | null = null): Ask[] {
  const own = a === null ? [] : [a, ...asks(a.more), ...asks(a.accept)]
  return check !== null && !own.some(x => x.question.question === check.question.question) ? [...own, check] : own
}

// A word for a shell, in single quotes: a typed answer is data, so no character of it is code.
const quote = (text: string): string => `'${text.replace(/'/g, `'\\''`)}'`

const DRIFT_CHOICE: Record<string, DriftChoice> = { 'Add to plan': 'add', Revert: 'revert', 'Allow once': 'allow-once' }

// The value of a `Label: value` line of a question.
const line = (text: string, label: string): string => {
  for (const l of text.split('\n')) if (l.trim().startsWith(label)) return l.trim().slice(label.length).trim()
  return ''
}

export function answersIn(result: unknown, view: RunView): Answer[] {
  const r = answeredResult(result)
  if (r === null) return []
  const answers = r.answers as Record<string, unknown>
  const notes = r.annotations && typeof r.annotations === 'object' ? (r.annotations as Record<string, unknown>) : {}
  const out: Answer[] = []
  for (const raw of r.questions as unknown[]) {
    const q = (raw && typeof raw === 'object' ? raw : {}) as { header?: unknown; question?: unknown; multiSelect?: unknown }
    if (typeof q.question !== 'string' || typeof q.header !== 'string' || q.multiSelect === true) continue
    const answer = answers[q.question]
    if (typeof answer !== 'string' || answer === '') continue
    const noteRow = notes[q.question]
    const noted = noteRow && typeof noteRow === 'object' ? (noteRow as { notes?: unknown }).notes : undefined
    const note = typeof noted === 'string' ? noted.trim() : ''

    // The gate question, More options, Accept a finding: the chosen option, exactly. One that needs a reason counts with
    // the person's note; without one, it counts once the reason question is answered.
    for (const a of asks(view.ask, view.contextCheck?.ask ?? null)) {
      if (!same(a.question, q.header, q.question)) continue
      const option = a.options.find(o => o.label === answer)
      if (option === undefined || option.move === null) continue
      if ((option.reasonQuestion !== null || option.answerQuestion !== null) && note === '') continue
      out.push({ kind: 'gate', stage: a.stage, question: q.question, ask: view.ask?.question.question ?? q.question, option, reason: note })
    }
    // The Context check, answered by typing: the call the CLI wrote for a typed answer, filled with the text, quoted.
    const check = view.contextCheck
    if (check !== null && same(check.ask.question, q.header, q.question) && !check.ask.options.some(o => o.label === answer)) {
      const text = answer.replace(/\s+/g, ' ').trim()
      if (text !== '' && text.length <= 100 && answer !== CANCEL && check.answer !== '') {
        const option: Option = {
          label: text, description: '', move: 'answer', steps: [], reasonQuestion: null, answerQuestion: null, skill: null,
          calls: [check.answer.replace("'{text}'", quote(text)), ...(check.ask.options[0]?.calls.slice(1) ?? [])],
        }
        out.push({ kind: 'gate', stage: 'plan', question: q.question, ask: view.ask?.question.question ?? q.question, option, reason: '' })
      }
    }
    // A name question (the person who confirms a manual task): the typed name is the answer, any but Cancel.
    for (const a of asks(view.ask)) {
      for (const option of a.options) {
        const nq: Question | null = option.answerQuestion
        // Any typed text but Cancel; an option of the name question itself ("Type it below") only says to type, and is no name.
        if (nq === null || !same(nq, q.header, q.question) || answer === CANCEL || nq.options.some(o => o.label === answer)) continue
        out.push({ kind: 'gate', stage: a.stage, question: a.question.question, ask: view.ask?.question.question ?? a.question.question, option, reason: answer })
      }
    }
    // A reason question: any answer but Cancel is the reason, a typed one too.
    for (const a of asks(view.ask)) {
      for (const option of a.options) {
        const rq: Question | null = option.reasonQuestion
        if (rq === null || !same(rq, q.header, q.question) || answer === CANCEL) continue
        out.push({ kind: 'gate', stage: a.stage, question: a.question.question, ask: view.ask?.question.question ?? a.question.question, option, reason: [answer, note].filter(t => t !== '').join(' ') })
      }
    }
    // Start over.
    if (view.restart !== null && same(view.restart, q.header, q.question)) {
      const option = view.restart.options.find(o => o.label === answer)
      if (option !== undefined && option.move === 'restart') out.push({ kind: 'restart', option })
    }
    // Scope drift: the header, a first line `Outside the plan: <path>`, and one of the three choices.
    if (q.header === view.drift.header && q.question.split('\n')[0]?.startsWith(view.drift.prefix) && view.drift.options.includes(answer)) {
      const path = ((q.question.split('\n')[0] ?? '').slice(view.drift.prefix.length).trim().split(/\s+/)[0] ?? '').replace(/[.,;:]+$/, '')
      const choice = DRIFT_CHOICE[answer]
      if (path !== '' && choice !== undefined) {
        // Allow once keeps Claude's why, marked as Claude's, which the person accepted.
        const why = line(q.question, 'Why:')
        out.push({ kind: 'drift', path, choice, reason: choice === 'allow-once' ? `why (Claude): ${why || 'not given'}` : note })
      }
    }
  }
  return out
}
