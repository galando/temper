import test from 'node:test';
import assert from 'node:assert';
import { book } from '../src/bookings.ts';
import { available, createEvent } from '../src/events.ts';
import { fresh } from '../src/testkit.ts';

test('booking sells the seats', () => {
  fresh();
  const e = createEvent('Show', ['A1', 'A2', 'A3']);
  const b = book(e.id, 'u1', ['A1', 'A2']);
  assert.deepEqual(b.seatIds, ['A1', 'A2']);
  assert.deepEqual(available(e.id), ['A3']);
});

test('a sold seat cannot be booked again', () => {
  fresh();
  const e = createEvent('Show', ['A1']);
  book(e.id, 'u1', ['A1']);
  assert.throws(() => book(e.id, 'u2', ['A1']), { code: 'SEAT_UNAVAILABLE' });
});
