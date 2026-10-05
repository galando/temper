// Event codec: the shape of one Temper event and how it is written and read back.
// Pure. Nothing here touches a file; the adapter hands over file names and text and
// writes the text this module returns.

export type Phase = 'intent' | 'plan' | 'build' | 'review' | 'check' | 'fix'

export const PHASES: readonly Phase[] = ['intent', 'plan', 'build', 'review', 'check', 'fix']

export type Origin = 'person' | 'model' | 'system'

export type DriftChoice = 'add' | 'revert' | 'allow-once'

export type EventBody =
  | { type: 'start'; slug: string; title: string; phase?: Phase }
  | { type: 'advance'; from: Phase; to: Phase | 'done' }
  | { type: 'back'; to: Phase; reason: string }
  | { type: 'override'; phase: Phase; reason: string }
  | { type: 'accept'; findingId: string; reason: string }
  | { type: 'drift'; path: string; choice: DriftChoice; reason: string }
  | { type: 'driftUsed'; path: string }
  | { type: 'checkResult'; result: 'pass' | 'fail' }
  | { type: 'pause' }
  | { type: 'resume' }

export type Draft = EventBody & { origin: Origin; author?: string }

export type StampMeta = { ts: number; session: string; seq: number }

export type TemperEvent = Draft & StampMeta & { id: string }

export type DecodeResult = { ok: true; event: TemperEvent } | { ok: false; reason: string }

export type EventFile = { name: string; text: string }

export type Unreadable = { name: string; reason: string }

export function stamp(draft: Draft, meta: StampMeta): TemperEvent {
  return { ...draft, ...meta, id: `${meta.ts}-${meta.session}-${meta.seq}` }
}

export function eventFileName(ev: { id: string }): string {
  return `${ev.id}.json`
}

export function encodeEvent(ev: TemperEvent): string {
  return JSON.stringify(ev)
}

const ORIGINS: readonly string[] = ['person', 'model', 'system']
const CHOICES: readonly string[] = ['add', 'revert', 'allow-once']

const isString = (v: unknown): v is string => typeof v === 'string'
const isPhase = (v: unknown): v is Phase => isString(v) && (PHASES as readonly string[]).includes(v)

// Required string/phase fields per event type, checked on decode.
function bodyProblem(o: Record<string, unknown>): string | null {
  switch (o.type) {
    case 'start':
      return isString(o.slug) && isString(o.title) && (o.phase === undefined || isPhase(o.phase))
        ? null
        : 'start needs slug and title'
    case 'advance':
      return isPhase(o.from) && (o.to === 'done' || isPhase(o.to)) ? null : 'advance needs from and to'
    case 'back':
      return isPhase(o.to) && isString(o.reason) ? null : 'back needs to and reason'
    case 'override':
      return isPhase(o.phase) && isString(o.reason) ? null : 'override needs phase and reason'
    case 'accept':
      return isString(o.findingId) && isString(o.reason) ? null : 'accept needs findingId and reason'
    case 'drift':
      return isString(o.path) && isString(o.reason) && CHOICES.includes(o.choice as string)
        ? null
        : 'drift needs path, choice and reason'
    case 'driftUsed':
      return isString(o.path) ? null : 'driftUsed needs path'
    case 'checkResult':
      return o.result === 'pass' || o.result === 'fail' ? null : 'checkResult needs result'
    case 'pause':
    case 'resume':
      return null
    default:
      return 'unknown event type'
  }
}

export function decodeEvent(text: string): DecodeResult {
  let raw: unknown
  try {
    raw = JSON.parse(text)
  } catch {
    return { ok: false, reason: 'not valid JSON (torn write?)' }
  }
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return { ok: false, reason: 'not an event object' }
  }
  const o = raw as Record<string, unknown>
  if (!isString(o.id) || typeof o.ts !== 'number' || !isString(o.session) || typeof o.seq !== 'number') {
    return { ok: false, reason: 'missing id, ts, session or seq' }
  }
  if (!isString(o.origin) || !ORIGINS.includes(o.origin)) {
    return { ok: false, reason: 'missing or unknown origin' }
  }
  const problem = bodyProblem(o)
  if (problem !== null) return { ok: false, reason: problem }
  return { ok: true, event: o as unknown as TemperEvent }
}

export function compareEvents(a: TemperEvent, b: TemperEvent): number {
  if (a.ts !== b.ts) return a.ts - b.ts
  if (a.session !== b.session) return a.session < b.session ? -1 : 1
  return a.seq - b.seq
}

// Only `*.json` files are considered events; other names are ignored, not reported.
export function readEvents(files: readonly EventFile[]): { events: TemperEvent[]; unreadable: Unreadable[] } {
  const events: TemperEvent[] = []
  const unreadable: Unreadable[] = []
  for (const f of files) {
    if (!f.name.endsWith('.json')) continue
    const out = decodeEvent(f.text)
    if (!out.ok) {
      unreadable.push({ name: f.name, reason: out.reason })
    } else if (eventFileName(out.event) !== f.name) {
      unreadable.push({ name: f.name, reason: 'file name does not match the event id' })
    } else {
      events.push(out.event)
    }
  }
  events.sort(compareEvents)
  return { events, unreadable }
}
