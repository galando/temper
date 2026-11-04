// Hidden tests, written from task.md and CONVENTIONS.md only.
import test from 'node:test';
import assert from 'node:assert';
import { audit } from '../src/audit.ts';
import { book } from '../src/bookings.ts';
import { available, createEvent } from '../src/events.ts';
import { fresh } from '../src/testkit.ts';
import { confirmHold, holdSeats } from '../src/holds.ts';

const MIN = 60_000;
const SEATS = ['A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8'];
const world = () => { const c = fresh(); const e = createEvent('Show', SEATS); return { c, e }; };

test('a hold has the shape and lasts ten minutes', () => {
  const { e } = world();
  const h = holdSeats(e.id, 'u1', ['A1', 'A2']);
  assert.equal(h.eventId, e.id);
  assert.equal(h.userId, 'u1');
  assert.deepEqual(h.seatIds, ['A1', 'A2']);
  assert.equal(h.expiresAt, 1_700_000_000_000 + 10 * MIN);
  assert.equal(typeof h.id, 'number');
});

test('held seats are not available', () => {
  const { e } = world();
  holdSeats(e.id, 'u1', ['A1', 'A2']);
  assert.deepEqual(available(e.id), ['A3', 'A4', 'A5', 'A6', 'A7', 'A8']);
});

test('book and another user refuse held seats', () => {
  const { e } = world();
  holdSeats(e.id, 'u1', ['A1']);
  assert.throws(() => book(e.id, 'u2', ['A1']), { code: 'SEAT_UNAVAILABLE' });
  assert.throws(() => holdSeats(e.id, 'u2', ['A1', 'A2']), { code: 'SEAT_UNAVAILABLE' });
  assert.deepEqual(available(e.id).includes('A2'), true, 'a refused hold holds nothing');
});

test('seat count and unknown seats', () => {
  const { e } = world();
  assert.throws(() => holdSeats(e.id, 'u1', []), { code: 'NO_SEATS' });
  assert.throws(() => holdSeats(e.id, 'u1', SEATS.slice(0, 7)), { code: 'TOO_MANY_SEATS' });
  assert.throws(() => holdSeats(e.id, 'u1', ['A1', 'Z9']), { code: 'UNKNOWN_SEAT' });
  assert.equal(available(e.id).length, 8);
  assert.equal(holdSeats(e.id, 'u1', SEATS.slice(0, 6)).seatIds.length, 6);
});

test('holding again replaces the earlier hold and releases its seats', () => {
  const { e } = world();
  const first = holdSeats(e.id, 'u1', ['A1', 'A2']);
  holdSeats(e.id, 'u1', ['A2', 'A3']);
  assert.deepEqual(available(e.id), ['A1', 'A4', 'A5', 'A6', 'A7', 'A8']);
  assert.throws(() => confirmHold(first.id), { code: 'HOLD_NOT_FOUND' });
});

test('one hold per user per event, not per user', () => {
  const { e } = world();
  const other = createEvent('Other', ['B1', 'B2']);
  const h1 = holdSeats(e.id, 'u1', ['A1']);
  holdSeats(other.id, 'u1', ['B1']);
  assert.deepEqual(confirmHold(h1.id).seatIds, ['A1']);
});

test('confirm sells the seats with the booking shape', () => {
  const { e } = world();
  const h = holdSeats(e.id, 'u1', ['A1', 'A2']);
  const b = confirmHold(h.id);
  assert.deepEqual(Object.keys(b).sort(), ['createdAt', 'eventId', 'id', 'seatIds', 'userId']);
  assert.deepEqual([b.eventId, b.userId, b.seatIds], [e.id, 'u1', ['A1', 'A2']]);
  assert.throws(() => book(e.id, 'u2', ['A1']), { code: 'SEAT_UNAVAILABLE' });
  assert.throws(() => confirmHold(h.id), { code: 'HOLD_NOT_FOUND' });
});

test('an expired hold cannot be confirmed and frees its seats at once', () => {
  const { c, e } = world();
  const h = holdSeats(e.id, 'u1', ['A1']);
  c.advance(10 * MIN - 1);
  assert.equal(available(e.id).includes('A1'), false);
  c.advance(1);
  assert.equal(available(e.id).includes('A1'), true);
  assert.throws(() => confirmHold(h.id), { code: 'HOLD_EXPIRED' });
  assert.equal(book(e.id, 'u2', ['A1']).seatIds[0], 'A1');
});

test('an unknown hold', () => {
  world();
  assert.throws(() => confirmHold(999), { code: 'HOLD_NOT_FOUND' });
});

test('one audit entry per change, none for a refused call', () => {
  const { e } = world();
  const n = audit.entries().length;
  const h = holdSeats(e.id, 'u1', ['A1']);
  assert.equal(audit.entries().length, n + 1);
  assert.match(audit.entries()[n].action, /^[a-z]+\.[a-z_]+ed$/);
  assert.throws(() => holdSeats(e.id, 'u2', ['A1']));
  assert.equal(audit.entries().length, n + 1);
  confirmHold(h.id);
  assert.ok(audit.entries().length >= n + 2);
});

test('a returned hold is a copy', () => {
  const { e } = world();
  const h = holdSeats(e.id, 'u1', ['A1']);
  h.seatIds.push('A2');
  assert.equal(available(e.id).includes('A2'), true);
});
