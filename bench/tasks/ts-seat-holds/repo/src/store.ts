// The in-memory store.
export interface Event { id: number; name: string; seats: string[] }
export interface Booking { id: number; eventId: number; userId: string; seatIds: string[]; createdAt: number }

export const store = {
  events: new Map<number, Event>(),
  sold: new Map<number, Set<string>>(),   // eventId -> seat ids sold
  bookings: new Map<number, Booking>(),
  nextId: 1,
  reset(): void {
    this.events.clear();
    this.sold.clear();
    this.bookings.clear();
    this.nextId = 1;
  },
  id(): number {
    return this.nextId++;
  },
};
