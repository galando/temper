import { audit } from './audit.ts';
import { BookingError } from './errors.ts';
import { store, type Event } from './store.ts';

export function createEvent(name: string, seats: string[]): Event {
  const event: Event = { id: store.id(), name, seats: [...seats] };
  store.events.set(event.id, event);
  store.sold.set(event.id, new Set());
  audit.record('event.created', { eventId: event.id });
  return structuredClone(event);
}

export function getEvent(eventId: number): Event {
  const event = store.events.get(eventId);
  if (!event) throw new BookingError('UNKNOWN_EVENT');
  return structuredClone(event);
}

/** The seats of an event that can still be bought, in the event's seat order. */
export function available(eventId: number): string[] {
  const event = getEvent(eventId);
  const sold = store.sold.get(eventId) ?? new Set();
  return event.seats.filter(s => !sold.has(s));
}
