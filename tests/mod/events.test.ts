import { describe, expect, test } from 'claude-code/testing'

import {
  decodeEvent,
  encodeEvent,
  eventFileName,
  readEvents,
  stamp,
} from '../../hooks/temper-mod/core/events'

const draft = { type: 'override', phase: 'review', reason: 'reviewer is on leave', origin: 'person', author: 'galando' } as const

describe('event codec', () => {
  test('stamp builds an id that matches the file name', () => {
    const ev = stamp(draft, { ts: 1700000000000, session: 's1', seq: 4 })
    expect(ev.id).toBe('1700000000000-s1-4')
    expect(eventFileName(ev)).toBe('1700000000000-s1-4.json')
  })

  test('encode then decode round trips', () => {
    const ev = stamp(draft, { ts: 5, session: 'abc-def', seq: 1 })
    const out = decodeEvent(encodeEvent(ev))
    expect(out.ok).toBe(true)
    if (out.ok) expect(out.event).toEqual(ev)
  })

  test('half a JSON object is unreadable, not a throw', () => {
    const out = decodeEvent('{"id":"1-a-1","ts":1,"sess')
    expect(out.ok).toBe(false)
  })

  test('an unknown type or a missing field is unreadable', () => {
    expect(decodeEvent('{"id":"1-a-1","ts":1,"session":"a","seq":1,"origin":"person","type":"bogus"}').ok).toBe(false)
    expect(decodeEvent('{"id":"1-a-1","ts":1,"session":"a","seq":1,"origin":"person","type":"override","phase":"review"}').ok).toBe(false)
    expect(decodeEvent('[]').ok).toBe(false)
  })

  test('a torn file is skipped and reported while valid events are kept', () => {
    const a = stamp({ type: 'start', slug: 'pw', title: 'Password reset', origin: 'person' }, { ts: 1, session: 's', seq: 1 })
    const b = stamp({ type: 'checkResult', result: 'fail', origin: 'system' }, { ts: 2, session: 's', seq: 2 })
    const c = stamp({ type: 'pause', origin: 'person' }, { ts: 3, session: 's', seq: 3 })
    const files = [
      { name: eventFileName(a), text: encodeEvent(a) },
      { name: eventFileName(b), text: encodeEvent(b) },
      { name: '4-s-4.json', text: '{"id":"4-s-4","ts":4,"ses' },
      { name: eventFileName(c), text: encodeEvent(c) },
      { name: 'notes.txt', text: 'not an event' },
    ]
    const out = readEvents(files)
    expect(out.events.map(e => e.id)).toEqual(['1-s-1', '2-s-2', '3-s-3'])
    expect(out.unreadable.map(u => u.name)).toEqual(['4-s-4.json'])
  })

  test('a file whose name disagrees with its id is unreadable', () => {
    const a = stamp({ type: 'pause', origin: 'person' }, { ts: 1, session: 's', seq: 1 })
    const out = readEvents([{ name: '9-x-9.json', text: encodeEvent(a) }])
    expect(out.events).toEqual([])
    expect(out.unreadable.length).toBe(1)
  })

  test('events come back ordered by ts, then session, then seq', () => {
    const e1 = stamp({ type: 'pause', origin: 'person' }, { ts: 5, session: 'b', seq: 1 })
    const e2 = stamp({ type: 'resume', origin: 'person' }, { ts: 5, session: 'a', seq: 2 })
    const e3 = stamp({ type: 'pause', origin: 'person' }, { ts: 1, session: 'z', seq: 9 })
    const out = readEvents([e1, e2, e3].map(e => ({ name: eventFileName(e), text: encodeEvent(e) })))
    expect(out.events.map(e => e.id)).toEqual(['1-z-9', '5-a-2', '5-b-1'])
  })
})
