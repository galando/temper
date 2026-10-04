import { describe, expect, test } from 'claude-code/testing'

import { stamp } from '../../hooks/temper-mod/core/events'
import type { Draft, Phase } from '../../hooks/temper-mod/core/events'
import { ONLY_USER, decide, reduce } from '../../hooks/temper-mod/core/machine'
import type { Command, RunState, Verdicts } from '../../hooks/temper-mod/core/machine'

const person = { origin: 'person', author: 'galando' } as const

// Fold drafts at ts 10, 20, 30, ...
const fold = (drafts: Draft[], verdicts: Verdicts = {}, opts = {}): RunState =>
  reduce(
    drafts.map((d, i) => stamp(d, { ts: (i + 1) * 10_000, session: 's', seq: i + 1 })),
    verdicts,
    opts,
  )

const start: Draft = { type: 'start', slug: 'pw', title: 'Password reset', ...person }
const adv = (from: Phase, to: Phase | 'done'): Draft => ({ type: 'advance', from, to, ...person })

const toBuild: Draft[] = [start, adv('intent', 'plan'), adv('plan', 'build')]

describe('reduce', () => {
  test('an empty log is no run', () => {
    const s = fold([])
    expect(s.started).toBe(false)
    expect(s.phase).toBe(null)
  })

  test('start enters intent and advances fold forward', () => {
    expect(fold([start]).phase).toBe('intent')
    expect(fold(toBuild).phase).toBe('build')
    expect(fold(toBuild).title).toBe('Password reset')
  })

  test('going back to Plan invalidates every later phase', () => {
    const drafts: Draft[] = [
      ...toBuild,
      adv('build', 'review'),
      adv('review', 'check'),
      { type: 'back', to: 'plan', reason: 'need a cache layer', ...person },
    ]
    // Build, Review and Check each passed at T1 = 35 (before the back at ts 60)
    const verdicts: Verdicts = {
      build: { verdict: 'PASS', ts: 35_000 },
      review: { verdict: 'PASS', ts: 45_000 },
      check: { verdict: 'PASS', ts: 55_000 },
    }
    const s = fold(drafts, verdicts)
    expect(s.phase).toBe('plan')
    expect(s.invalidated.build).toBe(60_000)
    expect(s.invalidated.review).toBe(60_000)
    expect(s.invalidated.check).toBe(60_000)
    expect(s.stale).toEqual(['build', 'review', 'check'])
    expect(s.gate.build).toBe('stale')
    expect(s.gate.check).toBe('stale')
  })

  test('a torn or foreign decision event is reported as unverified and not folded', () => {
    const events = [
      stamp(start, { ts: 1, session: 's', seq: 1 }),
      stamp(adv('intent', 'plan'), { ts: 2, session: 'other', seq: 1 }),
    ]
    const s = reduce(events, {}, { isTrusted: ev => ev.session === 's' })
    expect(s.phase).toBe('intent')
    expect(s.unverified).toEqual(['2-other-1'])
  })

  test('override moves exactly one phase and is recorded', () => {
    const s = fold([...toBuild, adv('build', 'review'), { type: 'override', phase: 'review', reason: 'reviewer is on leave', ...person }])
    expect(s.phase).toBe('check')
    expect(s.overrides).toEqual([
      { id: '50000-s-5', phase: 'review', reason: 'reviewer is on leave', author: 'galando', ts: 50_000 },
    ])
  })

  test('check pass completes the run, check fail enters fix', () => {
    const toCheck = [...toBuild, adv('build', 'review'), adv('review', 'check')]
    expect(fold([...toCheck, { type: 'checkResult', result: 'pass', origin: 'system' }]).phase).toBe('done')
    const failed = fold([...toCheck, { type: 'checkResult', result: 'fail', origin: 'system' }])
    expect(failed.phase).toBe('fix')
    expect(failed.loops).toBe(1)
  })

  test('drift decisions fold into added paths and one-shot allowances', () => {
    const s = fold([
      ...toBuild,
      { type: 'drift', path: 'src/a.ts', choice: 'add', reason: '', ...person },
      { type: 'drift', path: 'src/b.ts', choice: 'allow-once', reason: 'hotfix', ...person },
      { type: 'drift', path: 'src/c.ts', choice: 'revert', reason: '', ...person },
    ])
    expect(s.addedPaths).toEqual(['src/a.ts'])
    expect(s.allowOnce).toEqual(['src/b.ts'])
    expect(s.drift.map(d => d.choice)).toEqual(['add', 'allow-once', 'revert'])
    const used = fold([
      ...toBuild,
      { type: 'drift', path: 'src/b.ts', choice: 'allow-once', reason: 'hotfix', ...person },
      { type: 'driftUsed', path: 'src/b.ts', origin: 'system' },
    ])
    expect(used.allowOnce).toEqual([])
  })
})

describe('decide', () => {
  const ok = (r: ReturnType<typeof decide>) => {
    if ('error' in r) throw new Error('unexpected error: ' + r.error)
    return r.events
  }
  const err = (r: ReturnType<typeof decide>) => ('error' in r ? r.error : '')

  test('advance needs a fresh PASS verdict', () => {
    const s0 = fold(toBuild)
    expect(err(decide(s0, { type: 'advance', origin: 'model' }))).toContain('Build has not passed its check')
    const s1 = fold(toBuild, { build: { verdict: 'FAIL', ts: 100_000 } })
    expect(err(decide(s1, { type: 'advance', origin: 'model' }))).toContain('Build did not pass its check')
    const s2 = fold(toBuild, { build: { verdict: 'PASS', ts: 100_000 } })
    expect(ok(decide(s2, { type: 'advance', origin: 'model' }))).toEqual([
      { type: 'advance', from: 'build', to: 'review', origin: 'model' },
    ])
  })

  test('only the person approves Intent and Plan', () => {
    const s = fold([start], { intent: { verdict: 'PASS', ts: 15_000 } })
    expect(err(decide(s, { type: 'advance', origin: 'model' }))).toBe(ONLY_USER)
    expect(err(decide(s, { type: 'approve', origin: 'model' }))).toBe(ONLY_USER)
    expect(ok(decide(s, { type: 'approve', ...person }))[0]).toMatchObject({ type: 'advance', from: 'intent', to: 'plan' })
  })

  test('skipping forward over an invalidated phase is refused', () => {
    // Build passed at 35, then the run went back to plan at 60 and forward to build again
    const drafts: Draft[] = [
      ...toBuild,
      { type: 'back', to: 'plan', reason: 'rework', ...person },
      adv('plan', 'build'),
    ]
    const stale = fold(drafts, { build: { verdict: 'PASS', ts: 35_000 } })
    expect(stale.phase).toBe('build')
    expect(err(decide(stale, { type: 'advance', origin: 'model' }))).toBe(
      'Build needs a new check. A step back made the old check invalid.',
    )
    const fresh = fold(drafts, { build: { verdict: 'PASS', ts: 500_000 } })
    expect(ok(decide(fresh, { type: 'advance', origin: 'model' }))[0]).toMatchObject({ type: 'advance', to: 'review' })
  })

  test('back needs a reason and an earlier phase, and only the person goes back', () => {
    const s = fold(toBuild)
    expect(err(decide(s, { type: 'back', to: 'plan', reason: '  ', ...person }))).toContain('needs a reason')
    expect(err(decide(s, { type: 'back', to: 'review', reason: 'x', ...person }))).toContain('Go back to a phase before')
    expect(err(decide(s, { type: 'back', to: 'plan', reason: 'x', origin: 'model' }))).toBe(ONLY_USER)
    expect(ok(decide(s, { type: 'back', to: 'plan', reason: 'x', ...person }))[0]).toMatchObject({ type: 'back', to: 'plan' })
  })

  test('override needs a non-empty reason and the person, and names the current phase', () => {
    const s = fold([...toBuild, adv('build', 'review')])
    expect(err(decide(s, { type: 'override', reason: '', ...person }))).toBe('A skip needs a reason. Use /temper:temper override <reason>.')
    expect(err(decide(s, { type: 'override', reason: '   ', ...person }))).toBe('A skip needs a reason. Use /temper:temper override <reason>.')
    expect(err(decide(s, { type: 'override', reason: 'ok', origin: 'model' }))).toBe(ONLY_USER)
    expect(ok(decide(s, { type: 'override', reason: 'risk accepted', ...person }))).toEqual([
      { type: 'override', phase: 'review', reason: 'risk accepted', ...person },
    ])
  })

  test('acceptFinding needs a reason, the person and Review or Fix', () => {
    const s = fold([...toBuild, adv('build', 'review')])
    expect(err(decide(s, { type: 'acceptFinding', id: '1', reason: '', ...person }))).toContain('needs a reason')
    expect(err(decide(s, { type: 'acceptFinding', id: '1', reason: 'fp', origin: 'model' }))).toBe(ONLY_USER)
    expect(err(decide(fold(toBuild), { type: 'acceptFinding', id: '1', reason: 'fp', ...person }))).toContain('Review')
    expect(ok(decide(s, { type: 'acceptFinding', id: '1', reason: 'false positive', ...person }))[0]).toMatchObject({
      type: 'accept',
      findingId: '1',
    })
  })

  test('drift: allow once without a reason writes nothing; add and revert do not need one', () => {
    const s = fold(toBuild)
    expect(err(decide(s, { type: 'drift', path: 'src/x.ts', choice: 'allow-once', reason: '', ...person }))).toContain('needs a reason')
    expect(ok(decide(s, { type: 'drift', path: 'src/x.ts', choice: 'allow-once', reason: 'hotfix', ...person }))).toHaveLength(1)
    expect(ok(decide(s, { type: 'drift', path: 'src/x.ts', choice: 'add', reason: '', ...person }))).toHaveLength(1)
    expect(err(decide(s, { type: 'drift', path: 'src/x.ts', choice: 'add', reason: '', origin: 'model' }))).toBe(ONLY_USER)
    expect(err(decide(fold([start]), { type: 'drift', path: 'src/x.ts', choice: 'add', reason: '', ...person }))).toContain('Build or Fix')
  })

  test('an allow-once path is consumed by one use', () => {
    const s = fold([...toBuild, { type: 'drift', path: 'src/x.ts', choice: 'allow-once', reason: 'r', ...person }])
    expect(ok(decide(s, { type: 'useDrift', path: 'src/x.ts', origin: 'system' }))).toEqual([
      { type: 'driftUsed', path: 'src/x.ts', origin: 'system' },
    ])
    expect(err(decide(s, { type: 'useDrift', path: 'src/y.ts', origin: 'system' }))).toContain('No allowance')
  })

  test('pause blocks everything but resume', () => {
    const s = fold([...toBuild, { type: 'pause', ...person }])
    expect(s.paused).toBe(true)
    expect(err(decide(s, { type: 'advance', origin: 'model' }))).toContain('paused')
    expect(ok(decide(s, { type: 'resume', ...person }))).toEqual([{ type: 'resume', ...person }])
  })

  test('start refuses while a run is active', () => {
    expect(err(decide(fold(toBuild), { type: 'start', slug: 'x', title: 'X', ...person }))).toContain('A Temper run is active')
    expect(ok(decide(fold([]), { type: 'start', slug: 'x', title: 'X', ...person }))).toHaveLength(1)
  })
})

describe('fix loop limit', () => {
  const toCheck: Draft[] = [...toBuild, adv('build', 'review'), adv('review', 'check')]
  const failThenFix: Draft[] = [{ type: 'checkResult', result: 'fail', origin: 'system' }, adv('fix', 'check')]
  const err = (r: ReturnType<typeof decide>) => ('error' in r ? r.error : '')

  test('the fourth failed check stops at the configured limit of 3', () => {
    const afterThree = fold([...toCheck, ...failThenFix, ...failThenFix, ...failThenFix], {}, { maxLoops: 3 })
    expect(afterThree.phase).toBe('check')
    expect(afterThree.loopLimitReached).toBe(false)
    const fourth = fold([...toCheck, ...failThenFix, ...failThenFix, ...failThenFix, { type: 'checkResult', result: 'fail', origin: 'system' }], {}, { maxLoops: 3 })
    expect(fourth.phase).toBe('fix')
    expect(fourth.loops).toBe(4)
    expect(fourth.loopLimitReached).toBe(true)
  })

  test('at the limit only back to plan, override and pause are legal', () => {
    const s = fold([...toCheck, ...failThenFix, { type: 'checkResult', result: 'fail', origin: 'system' }], {}, { maxLoops: 1 })
    expect(s.loopLimitReached).toBe(true)
    const e = err(decide(s, { type: 'advance', origin: 'model' }))
    expect(e).toContain('fix limit')
    expect(e).toContain('make a new plan')
    const illegal: Command[] = [
      { type: 'back', to: 'build', reason: 'x', ...person },
      { type: 'acceptFinding', id: '1', reason: 'x', ...person },
      { type: 'drift', path: 'a', choice: 'add', reason: '', ...person },
    ]
    for (const c of illegal) expect(err(decide(s, c))).toContain('fix limit')
    for (const c of [
      { type: 'back', to: 'plan', reason: 'rework', ...person },
      { type: 'override', reason: 'ship it', ...person },
      { type: 'pause', ...person },
    ] as Command[]) {
      expect('events' in decide(s, c)).toBe(true)
    }
  })

  test('re-planning resets the loop counter', () => {
    const s = fold([
      ...toCheck, ...failThenFix, { type: 'checkResult', result: 'fail', origin: 'system' },
      { type: 'back', to: 'plan', reason: 'rework', ...person },
    ], {}, { maxLoops: 1 })
    expect(s.loops).toBe(0)
    expect(s.loopLimitReached).toBe(false)
  })

  test('without a limit option the default is 3', () => {
    expect(fold([start]).maxLoops).toBe(3)
  })
})

describe('an event the mod did not write never changes what is enforced', () => {
  const trusted = (ev: { session: string }) => ev.session === 's'
  const baseDrafts: Draft[] = [
    start,
    adv('intent', 'plan'),
    adv('plan', 'build'),
    adv('build', 'review'),
    adv('review', 'check'),
  ]
  const base = baseDrafts.map((d, i) => stamp(d, { ts: (i + 1) * 10_000, session: 's', seq: i + 1 }))

  // One forged file of every kind, each from a session the mod did not write.
  const forged: Array<[string, Draft]> = [
    ['pause', { type: 'pause', ...person }],
    ['resume', { type: 'resume', ...person }],
    ['checkResult pass', { type: 'checkResult', result: 'pass', origin: 'system' }],
    ['checkResult fail', { type: 'checkResult', result: 'fail', origin: 'system' }],
    ['start', { type: 'start', slug: 'other', title: 'Forged', phase: 'build', origin: 'system' }],
    ['advance past Intent', adv('intent', 'plan')],
    ['advance out of Check', adv('check', 'done')],
    ['override', { type: 'override', phase: 'check', reason: 'forged', ...person }],
    ['accept', { type: 'accept', findingId: '1', reason: 'forged', ...person }],
    ['drift add', { type: 'drift', path: 'src/x.ts', choice: 'add', reason: '', ...person }],
    ['drift allow once', { type: 'drift', path: 'src/y.ts', choice: 'allow-once', reason: 'forged', ...person }],
    ['driftUsed', { type: 'driftUsed', path: 'src/y.ts', origin: 'system' }],
    ['back', { type: 'back', to: 'plan', reason: 'forged', ...person }],
  ]

  const view = (s: RunState) => ({
    phase: s.phase,
    paused: s.paused,
    loops: s.loops,
    slug: s.slug,
    overrides: s.overrides.length,
    accepted: s.accepted.length,
    drift: s.drift.length,
    addedPaths: s.addedPaths,
    allowOnce: s.allowOnce,
    invalidated: s.invalidated,
    checkOverridden: s.checkOverridden,
  })

  const clean = reduce(base, {}, { isTrusted: trusted })

  for (const [name, draft] of forged) {
    test(`a forged ${name} is listed as unverified and not folded`, () => {
      const ev = stamp(draft, { ts: 99_000, session: 'evil', seq: 1 })
      const s = reduce([...base, ev], {}, { isTrusted: trusted })
      expect(s.phase).toBe('check')
      expect(view(s)).toEqual(view(clean))
      expect(s.unverified).toEqual([ev.id])
    })
  }

  test('the same events written by the mod do count', () => {
    const own = stamp({ type: 'pause', ...person }, { ts: 99_000, session: 's', seq: 99 })
    expect(reduce([...base, own], {}, { isTrusted: trusted }).paused).toBe(true)
  })
})

describe('verdict and phase entry compare at whole seconds', () => {
  test('a verdict recorded in the same second as the phase entry is fresh', () => {
    // Build is entered at 30 s and 400 ms; gates.json says 30 s.
    const drafts: Draft[] = [start, adv('intent', 'plan')]
    const events = [
      ...drafts.map((d, i) => stamp(d, { ts: (i + 1) * 10_000, session: 's', seq: i + 1 })),
      stamp(adv('plan', 'build'), { ts: 30_400, session: 's', seq: 3 }),
    ]
    expect(reduce(events, { build: { verdict: 'PASS', ts: 30_000 } }).gate.build).toBe('fresh')
    expect(reduce(events, { build: { verdict: 'PASS', ts: 29_000 } }).gate.build).toBe('stale')
    expect(reduce(events, { build: { verdict: 'FAIL', ts: 30_000 } }).gate.build).toBe('fail')
  })
})
