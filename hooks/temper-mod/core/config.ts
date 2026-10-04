// The few keys the mod reads: `.claude/temper.config` (a small YAML subset) and the
// plain-string userConfig fields. userConfig declares no `options` (that would stop the
// whole plugin loading before Claude Code 2.1.271), so every value is validated here.

export type UiMode = 'full' | 'minimal' | 'off'

// Value of a dotted key such as `fix.max-loops`, read by indentation. Comments, inline
// comments and surrounding quotes are dropped. Null when the key is absent.
export function readConfigValue(text: string, dotted: string): string | null {
  const want = dotted.split('.')
  const stack: Array<{ indent: number; key: string }> = []
  for (const raw of text.split('\n')) {
    if (raw.trim() === '' || raw.trimStart().startsWith('#')) continue
    const m = /^(\s*)([A-Za-z0-9_-]+):\s*(.*)$/.exec(raw)
    if (!m) continue
    const indent = (m[1] ?? '').length
    const key = m[2] ?? ''
    for (let top = stack[stack.length - 1]; top !== undefined && top.indent >= indent; top = stack[stack.length - 1]) stack.pop()
    const path = [...stack.map(s => s.key), key]
    const value = (m[3] ?? '').replace(/\s+#.*$/, '').trim()
    if (value === '') {
      stack.push({ indent, key })
      continue
    }
    if (path.length === want.length && path.every((k, i) => k === want[i])) {
      return value.replace(/^(['"])(.*)\1$/, '$2')
    }
  }
  return null
}

const norm = (v: string | undefined): string => (v ?? '').trim().toLowerCase()

export function parseUiMode(v: string | undefined): UiMode {
  const n = norm(v)
  return n === 'minimal' || n === 'off' || n === 'full' ? n : 'full'
}

export function parseOnOff(v: string | undefined, fallback: 'on' | 'off'): 'on' | 'off' {
  const n = norm(v)
  return n === 'on' || n === 'off' ? n : fallback
}

// The game setting: `on` offers the game while Claude works and answers the command, `command`
// answers the command only, `off` hides it all. Checked here, never as a picker.
export type GameMode = 'on' | 'command' | 'off'

export function parseGameMode(v: string | undefined): GameMode {
  const n = norm(v)
  return n === 'command' || n === 'off' ? n : 'on'
}

export const parseEnforcement =(v: string | undefined): 'on' | 'off' => parseOnOff(v, 'on')

const positiveInt = (v: string | null | undefined): number | null => {
  if (v === null || v === undefined || !/^\s*\d+\s*$/.test(v)) return null
  const n = Number(v)
  return n >= 1 ? n : null
}

// fix.max-loops in temper.config wins, then the userConfig field, then 3.
export function parseMaxLoops(configText: string, userValue: string | undefined): number {
  return positiveInt(readConfigValue(configText, 'fix.max-loops')) ?? positiveInt(userValue) ?? 3
}

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
