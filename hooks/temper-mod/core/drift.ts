// Scope drift, asked as one question. Claude asks it (the orchestrator, after the Build stage lists a
// file outside the plan in its DRIFT section), the person answers it in Claude Code's own question
// dialog, and the mod reads the answer from the dialog's result. The question carries the why and the
// what in fixed lines, so the same question works with the mod and without it. Pure: no Claude imports.

import type { DriftChoice } from './events'

export const DRIFT_HEADER = 'Scope drift'
export const DRIFT_PREFIX = 'Outside the plan:'

const LABELS: Record<string, DriftChoice> = { 'add to plan': 'add', revert: 'revert', 'allow once': 'allow-once' }

export type DriftAnswer = { path: string; choice: DriftChoice; reason: string }

type Question = { question?: unknown; header?: unknown }

const line = (text: string, label: string): string => {
  const m = new RegExp(`^\\s*${label}\\s*(.*)$`, 'mi').exec(text)
  return (m?.[1] ?? '').trim()
}

// The Scope drift answers in an AskUserQuestion result. Only the result counts: it is what the dialog
// returned after the person chose, not what the caller sent in. A question that is not a Scope drift
// question, or an answer that is not one of the three choices (a typed "Other"), is no decision.
export function driftAnswers(result: unknown): DriftAnswer[] {
  const r = (result && typeof result === 'object' ? (result as { result?: unknown }).result : undefined) as
    | { questions?: unknown; answers?: unknown }
    | undefined
  if (!r || !Array.isArray(r.questions) || !r.answers || typeof r.answers !== 'object') return []
  const answers = r.answers as Record<string, unknown>
  const out: DriftAnswer[] = []
  for (const q of r.questions as Question[]) {
    if (typeof q?.question !== 'string' || typeof q.header !== 'string') continue
    if (q.header.trim().toLowerCase() !== DRIFT_HEADER.toLowerCase()) continue
    const path = line(q.question, DRIFT_PREFIX).split(/\s+/)[0]?.replace(/[.,;:]+$/, '') ?? ''
    const answer = answers[q.question]
    const choice = typeof answer === 'string' ? LABELS[answer.trim().toLowerCase()] : undefined
    if (!path || !choice) continue
    // Allow once needs a reason in the record: Claude's why, marked as Claude's, which the person accepted.
    const why = line(q.question, 'Why:')
    out.push({ path, choice, reason: choice === 'allow-once' ? `why (Claude): ${why || 'not given'}` : '' })
  }
  return out
}
