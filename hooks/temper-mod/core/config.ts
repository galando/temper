// The plain text userConfig fields the mod reads. userConfig declares no `options` (that
// would stop the whole plugin loading before Claude Code 2.1.271), so every value is
// validated here. The mod reads no `.claude/temper.config`: the CLI puts what it needs in view.json.

export type UiMode = 'full' | 'minimal' | 'off'

const norm = (v: string | undefined): string => (v ?? '').trim().toLowerCase()

export function parseUiMode(v: string | undefined): UiMode {
  const n = norm(v)
  return n === 'minimal' || n === 'off' || n === 'full' ? n : 'full'
}

export function parseOnOff(v: string | undefined, fallback: 'on' | 'off'): 'on' | 'off' {
  const n = norm(v)
  return n === 'on' || n === 'off' ? n : fallback
}

export const parseEnforcement =(v: string | undefined): 'on' | 'off' => parseOnOff(v, 'on')

// "build=sonnet, plan=opus" -> { build: 'sonnet', plan: 'opus' }; malformed pairs skipped.
export function parsePhaseModels(v: string | undefined): Record<string, string> {
  const out: Record<string, string> = {}
  for (const pair of (v ?? '').split(',')) {
    const m = /^\s*([A-Za-z-]+)\s*=\s*(\S+)\s*$/.exec(pair)
    if (m?.[1] && m[2]) out[m[1].toLowerCase()] = m[2]
  }
  return out
}

export const MIN_VERSION = '2.1.287'

// "2.1.288" or "2.1.280-dev.2026..." -> [2, 1, 288 or 280]; null when not a release.
export function parseVersion(v: string): [number, number, number] | null {
  const m = /^(\d+)\.(\d+)\.(\d+)/.exec(v.trim())
  return m ? [Number(m[1]), Number(m[2]), Number(m[3])] : null
}

// True when `v` is at least `min`. An unparseable version is not supported: the mod
// stays inert rather than guess.
export function versionAtLeast(v: string | undefined, min: string = MIN_VERSION): boolean {
  const have = parseVersion(v ?? '')
  const want = parseVersion(min)
  if (!have || !want) return false
  for (let i = 0; i < 3; i++) {
    const a = have[i] ?? 0
    const b = want[i] ?? 0
    if (a !== b) return a > b
  }
  return true
}

export type Effort = 'low' | 'medium' | 'high' | 'xhigh' | 'max'
const EFFORTS: readonly string[] = ['low', 'medium', 'high', 'xhigh', 'max']

// "sonnet", "sonnet:high" or ":high" -> a model, an effort, or both; empty parts stay out.
export function parsePhaseModel(value: string | undefined): { model?: string; effort?: Effort } {
  const [model = '', effort = ''] = (value ?? '').split(':').map(s => s.trim())
  const out: { model?: string; effort?: Effort } = {}
  if (model) out.model = model
  if (EFFORTS.includes(effort)) out.effort = effort as Effort
  return out
}
