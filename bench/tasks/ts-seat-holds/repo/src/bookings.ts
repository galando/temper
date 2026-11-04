import { audit } from './audit.ts';
import { clock } from './clock.ts';
import { BookingError } from './errors.ts';
import { available, getEvent } from './events.ts';
import { store, type Booking } from './store.ts';

export const MAX_SEATS = 6;

/** Checks a list of seats for an event as a whole; throws for the first problem. */
export function checkSeats(eventId: number, seatIds: string[]): void {
  const event = getEvent(eventId);
  if (seatIds.length === 0) throw new BookingError('NO_SEATS');
  if (seatIds.length > MAX_SEATS) throw new BookingError('TOO_MANY_SEATS');
  for (const s of seatIds) if (!event.seats.includes(s)) throw new BookingError('UNKNOWN_SEAT', s);
  const free = new Set(available(eventId));
  for (const s of seatIds) if (!free.has(s)) throw new BookingError('SEAT_UNAVAILABLE', s);
}

/** Buy seats now. */
export function book(eventId: number, userId: string, seatIds: string[]): Booking {
  checkSeats(eventId, seatIds);
  return sell(eventId, userId, seatIds);
}

/** Records a sale of seats already checked. */
export function sell(eventId: number, userId: string, seatIds: string[]): Booking {
  const booking: Booking = { id: store.id(), eventId, userId, seatIds: [...seatIds], createdAt: clock.now() };
  store.bookings.set(booking.id, booking);
  const sold = store.sold.get(eventId)!;
  for (const s of seatIds) sold.add(s);
  audit.record('booking.created', { bookingId: booking.id, eventId, seatIds });
  return structuredClone(booking);
}
