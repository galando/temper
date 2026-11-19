// The end to end world: a scratch project, the real temper CLI, and (in mod mode) the mod's own rule engine. A scripted
// orchestrator plays commands/temper.md (the loop over `temper next --json`), scripted agents write the files a stage agent
// would, and a scripted person answers each question. Run: bun scripts/e2e/run.ts [mod|plain] [scenario...]
import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

import { answersIn } from '../../hooks/temper-mod/core/answers'
import { evaluate } from '../../hooks/temper-mod/core/rules'
import { evaluateSession, factsOf } from '../../hooks/temper-mod/core/session'
import type { RuleContext, RunFacts } from '../../hooks/temper-mod/core/rules'
import { parseRunView } from '../../hooks/temper-mod/core/runview'
import { cliStage } from '../../hooks/temper-mod/core/stages'

// TEMPER_E2E_ROOT: another plugin folder to drive (the A/B replay runs the same script against the version before a change)
export const ROOT = process.env.TEMPER_E2E_ROOT ? path.resolve(process.env.TEMPER_E2E_ROOT) : path.resolve(import.meta.dir, '../..')
export const TEMPER = path.join(ROOT, 'scripts/temper')

export type Json = Record<string, any>
export type Mode = 'mod' | 'plain' | 'driver'   // driver: the mod loaded, and its run driver carries the run
export type Agent = (w: World, agent: Json) => void
export type Person = (ask: Json, w: World) => string | { label: string; note?: string } | null

export class Denied extends Error {}

// 9.8.5 (WP05): what a run did, for the floor (scripts/e2e/floor.json): the dialogs the person saw, by stage and by kind;
// the agents launched, by type; the steps the CLI took by itself (`auto`); the steps back the person chose; the hand backs
// of the run driver to the model loop; and the runs of the whole suite (`suite_runs`, the lines the fixture's suite
// script appends to the file named by TEMPER_E2E_COUNT).
export type Counts = {
  dialogs: number
  by_stage: Record<string, number>
  by_kind: Record<string, number>
  launches: Record<string, number>
  auto: number
  back: number
  handbacks: number
  suite_runs: number
}

// 9.8.5 (WP18): Review's completion row, as a scripted reviewer records it: one --read for each file `temper review files`
// prints (a CLI before 9.8.5 has no such word, and its row names no file)
export function reviewDone(w: World, cmd = 'review panel'): void {
  const t = (args: string): { code: number; out: string } => { w.guardBash(`${TEMPER} ${args}`); return w.run(`${TEMPER} ${args}`) }
  const r = t('review files')
  const files = r.code === 0 ? r.out.split('\n').map(x => x.trim()).filter(x => x !== '') : []
  t(`evidence add --stage review --claim 'review completed' --exit 0 --cmd '${cmd}'${files.map(f => ` --read '${f.replace(/'/g, "'\\''")}'`).join('')}`)
}

export class World {
  dir: string
  trace: string[] = []
  denials: string[] = []
  allowed: string[] = []
  counts: Counts = { dialogs: 0, by_stage: {}, by_kind: {}, launches: {}, auto: 0, back: 0, handbacks: 0, suite_runs: 0 }
  countFile: string
  env: Record<string, string>
  started = Date.now()
  // TEMPER_E2E_LIMIT_S: the seconds a scenario may run before next() stops it (default 300); a step count alone let a
  // looping scenario run for 21 minutes a mode before it failed
  limitS = Number(process.env.TEMPER_E2E_LIMIT_S ?? '') > 0 ? Number(process.env.TEMPER_E2E_LIMIT_S) : 300
  constructor(public mode: Mode, public name: string) {
    this.dir = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), `temper-e2e-${name}-`)))
    this.env = { ...process.env, GIT_AUTHOR_NAME: 'e2e', GIT_AUTHOR_EMAIL: 'e2e@example.com', GIT_COMMITTER_NAME: 'e2e', GIT_COMMITTER_EMAIL: 'e2e@example.com' } as Record<string, string>
    for (const k of Object.keys(this.env)) if (!k.startsWith('GIT_CONFIG') && /(^|_)(KEY|TOKEN|SECRET|PASSWORD)(_|$)/i.test(k)) delete this.env[k]
    // WP20: the baseline runs the suite in the foreground in a scripted run, so no step races its process (a scenario
    // that needs its own process deletes this)
    this.env.TEMPER_BASELINE_FOREGROUND = '1'
    this.countFile = `${this.dir}.suite-runs`
    fs.writeFileSync(this.countFile, '')
    this.env.TEMPER_E2E_COUNT = this.countFile
    this.sh('git init -q . && git checkout -q -B main')
  }
  // WP19: the planted bugs of `temper check ahead` go on in the background after Check adopted its run (Check never
  // waits for them). Their runs of the suite are counted once that process of this world has ended (at most two
  // minutes), so the count is the same on every run. Where /proc cannot be read, nothing is waited for.
  waitAhead(limitMs = 120000): void {
    const mine = (): boolean => {
      let ids: string[] = []
      try {
        ids = fs.readdirSync('/proc').filter(x => /^\d+$/.test(x))
      } catch {
        return false
      }
      return ids.some(id => {
        try {
          const c = fs.readFileSync(`/proc/${id}/cmdline`, 'utf8')
          return c.includes('check_run.py') && c.includes('\0ahead\0') && c.includes(this.dir)
        } catch {
          return false
        }
      })
    }
    const t0 = Date.now()
    while (mine() && Date.now() - t0 < limitMs) Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 200)
  }
  // The counts of the run so far, with the suite runs read from the count file and `launch_total`, the sum of the launches.
  finalCounts(): Counts & { launch_total: number } {
    this.waitAhead()
    let suite = 0
    try {
      suite = fs.readFileSync(this.countFile, 'utf8').split('\n').filter(Boolean).length
    } catch {
      suite = 0
    }
    const c = { ...this.counts, suite_runs: suite }
    const sorted = (r: Record<string, number>): Record<string, number> => Object.fromEntries(Object.keys(r).sort().map(k => [k, r[k]!]))
    return { ...c, by_stage: sorted(c.by_stage), by_kind: sorted(c.by_kind), launches: sorted(c.launches), launch_total: Object.values(c.launches).reduce((a, b) => a + b, 0) }
  }
  countLaunch(type: string): void {
    this.counts.launches[type] = (this.counts.launches[type] ?? 0) + 1
  }
  // ---- the project ----
  write(rel: string, text: string): void {
    this.guardWrite(rel)
    fs.mkdirSync(path.dirname(path.join(this.dir, rel)), { recursive: true })
    fs.writeFileSync(path.join(this.dir, rel), text)
  }
  read(rel: string): string {
    return fs.readFileSync(path.join(this.dir, rel), 'utf8')
  }
  exists(rel: string): boolean {
    return fs.existsSync(path.join(this.dir, rel))
  }
  json(rel: string): Json {
    return JSON.parse(this.read(rel))
  }
  // ---- processes ----
  run(command: string, cwd = this.dir): { code: number; out: string } {
    const r = spawnSync('bash', ['-c', command], { cwd, env: this.env, encoding: 'utf8', timeout: 240000 })
    return { code: r.status ?? 1, out: (r.stdout ?? '') + (r.stderr ?? '') }
  }
  sh(command: string): string {
    const r = this.run(command)
    if (r.code !== 0) throw new Error(`command failed (${r.code}): ${command}\n${r.out}`)
    return r.out
  }
  cli(args: string): { code: number; out: string } {
    return this.run(`${TEMPER} ${args}`)
  }
  // ---- the mod ----
  facts(): { ctx: RuleContext | null } {
    if (this.mode === 'plain' || !this.exists('.temper/view.json')) return { ctx: null }
    const rv = parseRunView(this.read('.temper/view.json'))
    if (rv === null || rv.run === null || rv.run.command === 'fix') return { ctx: null }
    const stage = cliStage(rv.run.stage)
    const g = rv.guard
    const run: RunFacts | null = stage === null || g === null ? null : { stage, step: g.step, specDir: g.spec, planFiles: g.planFiles, groupedActive: g.grouped, trivialExit: g.trivialExit, prefix: g.prefix, adhocStage: g.adhocStage }
    return { ctx: { run, allowed: [...this.allowed, ...rv.next.calls, ...rv.next.steps], root: this.dir, drift: { added: [], allowOnce: [] }, restart: false, cli: TEMPER, fixRun: false } as unknown as RuleContext }
  }
  guard(call: { tool: string; input: Json }): void {
    const { ctx } = this.facts()
    if (ctx === null) return
    const r = evaluate(ctx, call as never) as { deny?: string }
    if (r.deny !== undefined) {
      this.denials.push(r.deny)
      throw new Denied(r.deny)
    }
  }
  guardWrite(rel: string): void {
    this.guard({ tool: 'Write', input: { file_path: path.join(this.dir, rel) } })
  }
  // 9.8.0: a call of the orchestrator (the main session) is also held to core/session.ts: it runs the CLI and reads, launches
  // the CLI's agent as named and asks the CLI's question.
  // No memory between calls, as in the engine (it loads the mod again between turns): the view alone says what may run.
  session(call: { tool: string; input: Json }): void {
    const { ctx } = this.facts()
    if (ctx === null) return
    const r = evaluateSession(ctx, factsOf(parseRunView(this.read('.temper/view.json')), false), call as never) as { deny?: string }
    if (r.deny !== undefined) {
      this.denials.push(r.deny)
      throw new Denied(`${r.deny} [${call.tool}: ${JSON.stringify(call.input).slice(0, 200)}]`)
    }
  }
  guardBash(command: string): void {
    this.guard({ tool: 'Bash', input: { command } })
    this.session({ tool: 'Bash', input: { command } })
  }
  guardAgent(a: Json): void {
    this.countLaunch(String(a.type))
    this.session({ tool: 'Agent', input: { subagent_type: a.type, model: a.model, prompt: a.prompt, description: 'stage' } })
  }
  // One dialog: the questions shown at once (a Blocking set holds up to four), with the stage and the kind it counts under.
  guardAsk(q: Json | Json[], stage = '', kind = ''): void {
    this.counts.dialogs++
    const st = stage || 'none'
    const kd = kind || 'none'
    this.counts.by_stage[st] = (this.counts.by_stage[st] ?? 0) + 1
    this.counts.by_kind[kd] = (this.counts.by_kind[kd] ?? 0) + 1
    this.session({ tool: 'AskUserQuestion', input: { questions: Array.isArray(q) ? q : [q] } })
  }
  // The mod's check of a call, without raising: the denial text, or null when it passes.
  denies(call: { tool: string; input: Json }): string | null {
    try {
      this.guard(call)
      return null
    } catch (e) {
      if (e instanceof Denied) return e.message
      throw e
    }
  }
  // ---- the view and the person ----
  next(extra = ''): Json {
    if (Date.now() - this.started > this.limitS * 1000) throw new Error(`the scenario ran over its time limit of ${this.limitS} s`)
    const r = this.cli(`next --json ${extra}`)
    if (r.code !== 0) throw new Error(`next failed: ${r.out}`)
    return JSON.parse(r.out)
  }
  // The person answers a question: the mod reads the answer from the dialog result against the view, and what it maps to is
  // allowed. Without the mod the answer is simply the option's calls and steps.
  answer(ask: Json, label: string, note = ''): Json {
    const option = (ask.options as Json[]).find(o => o.label === label)
    if (option === undefined) throw new Error(`no option ${label} in ${ask.question.question} (${(ask.options as Json[]).map(o => o.label).join(' | ')})`)
    if (this.mode !== 'plain') {
      const rv = parseRunView(this.read('.temper/view.json'))
      const q = ask.question
      const result = { result: { questions: [{ header: q.header, question: q.question, multiSelect: false }], answers: { [q.question]: label }, annotations: note ? { [q.question]: { notes: note } } : {} } }
      const found = rv === null ? [] : answersIn(result, rv)
      this.allowed = found.flatMap(a => (a.kind === 'gate' ? [...a.option.calls, ...a.option.steps] : []))
    }
    return option
  }
  fill(text: string, fills: Record<string, string>): string {
    return text.replace(/\{(\w+)\}/g, (m, k: string) => (k in fills ? fills[k]!.replace(/'/g, "'\\''") : m))
  }
}
