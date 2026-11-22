// The upgrade from 9.8.4, with every gate computed (the audit's R7-4). Case file 46 (row D60 of
// docs/plans/one-go/done.md) restores saved states and writes each later verdict by hand, on a short config; nothing
// there computes a gate on a project whose config is the template 9.8.4 shipped. Here the project of default-run keeps
// that template (scripts/selftest/saved-old.json, the entry of 7c7a1c1, with the check commands of the scripted project
// in its check block), and the real CLI runs the whole run on it:
//
//   upgrade-tidy  the person answers the one time config question with Remove them: the config becomes the new template
//                 with the person's lines, the copy .claude/temper.config.before-9.8.5 holds the old file
//   upgrade-keep  the person answers Keep my file: the file keeps every old line and gains upgrade.asked
//
// Both: config.tidy is the first question and is asked once; the run then asks the approval and the commit question and
// no other (no commit.fail: the copy and the changed config are Temper's own files, never a change outside the plan);
// the verdicts of Intent, Plan, Build, Review, Check and of the commit gate are computed by the CLI, each PASS with its
// rows; the commit is made. Plain and mod.
import fs from 'node:fs'
import path from 'node:path'

import { orchestrate } from './loop'
import { idOf, pickId } from './persons'
import { recommended, script, startProject } from './scenarios'
import { ROOT } from './world'
import type { Json, Person, World } from './world'

const OLD = '7c7a1c1'   // 9.8.4, what users have
const CONFIG = '.claude/temper.config'
const COPY = `${CONFIG}.before-9.8.5`
const expect = (cond: unknown, message: string): void => {
  if (!cond) throw new Error(message)
}
export const oldTemplate = (): string =>
  String(JSON.parse(fs.readFileSync(path.join(ROOT, 'scripts/selftest/saved-old.json'), 'utf8'))[OLD].template)

const upgraded = (answer: 'tidy-config' | 'keep-config') => (w: World): void => {
  startProject(w, '', undefined, oldTemplate())
  const before = w.read(CONFIG)
  expect(before.includes('coverage-threshold: 80') && before.includes('packs: [quality, tdd, security, git, performance]'),
    'R7-4 the project starts from the config template of 9.8.4 (its coverage floor and its five packs)')
  const asked: string[] = []
  let gates: Json = {}   // the verdicts as they stand at the commit question (the run's end clears the file)
  const person: Person = (ask, wd) => {
    asked.push(idOf(ask))
    if (idOf(ask) === 'commit.confirm') gates = wd.json('.temper/gates.json')
    return idOf(ask) === 'config.tidy' ? pickId(wd, ask, answer) : recommended(ask, wd)
  }
  orchestrate(w, script({ person }))
  expect(asked[0] === 'config.tidy' && asked.filter(x => x === 'config.tidy').length === 1,
    `R7-4 the one time config question is the first question and is asked once (asked ${asked.join(', ')})`)
  expect(!asked.includes('commit.fail'), `R7-4 the upgraded run meets no commit.fail (asked ${asked.join(', ')})`)
  expect(asked.join(', ') === 'config.tidy, plan.approve, commit.confirm',
    `R7-4 the upgraded run asks the config question, the approval and the commit, and nothing else (asked ${asked.join(', ')})`)
  for (const g of ['intent', 'plan', 'build', 'review', 'check', 'commit']) {
    const e = (gates[g] ?? {}) as Json
    const rows = (e.requirements ?? []) as Json[]
    expect(e.verdict === 'PASS' && rows.length > 0 && rows.every(r => r.pass !== false),
      `R7-4 the gate ${g} is computed by the CLI and passes with its rows (${e.verdict}: ${rows.filter(r => r.pass === false).map(r => `${r.name}: ${r.detail}`).join('; ').slice(0, 200)})`)
  }
  const blast = ((gates.commit?.requirements ?? []) as Json[]).find(r => String(r.name).startsWith('blast radius'))
  expect(blast?.pass === true, `R7-4 the commit gate's blast radius row passes after the answer (${JSON.stringify(blast ?? null).slice(0, 200)})`)
  const after = w.read(CONFIG)
  if (answer === 'tidy-config') {
    const head = fs.readFileSync(path.join(ROOT, 'templates/temper.config.default'), 'utf8').split('\n')[0]!
    expect(after.split('\n')[0] === head && !after.includes('coverage-threshold: 80'), 'R7-4 Remove them wrote the new template, without the old coverage floor')
    expect(/^\s+test: /m.test(after), 'R7-4 Remove them kept the check commands, which the person wrote')
    expect(w.exists(COPY) && w.read(COPY) === before, 'R7-4 the copy holds the old file, byte for byte')
  } else {
    expect(after.startsWith(before) && /^upgrade:\n  asked: "9\.8\.5"$/m.test(after), 'R7-4 Keep my file kept every old line and added upgrade.asked')
    expect(!w.exists(COPY), 'R7-4 Keep my file writes no copy')
  }
  expect(/^[0-9a-f]{7,}/.test(w.sh('git log -1 --format=%h -- src').trim()) && w.sh('git status --porcelain -- src unit').trim() === '',
    'R7-4 the run ends with its commit made')
}

export const UPGRADE_SCENARIOS: Record<string, { run: (w: World) => void; modes: string[] }> = {
  'upgrade-tidy': { run: upgraded('tidy-config'), modes: ['plain', 'mod'] },
  'upgrade-keep': { run: upgraded('keep-config'), modes: ['plain', 'mod'] },
}
