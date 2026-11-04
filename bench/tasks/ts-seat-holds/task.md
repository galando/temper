Add seat holds, so a customer can keep seats while paying.

- `holdSeats(eventId, userId, seatIds)` in `src/holds.ts` returns a hold `{ id, eventId, userId, seatIds, expiresAt }`. A hold lasts 10 minutes from `clock.now()`.
- Held seats are not available: `available(eventId)` leaves them out, and `book` and another user's `holdSeats` refuse them with `SEAT_UNAVAILABLE`.
- A hold has 1 to 6 seats (`NO_SEATS`, `TOO_MANY_SEATS`); an unknown seat is `UNKNOWN_SEAT`.
- A user has at most one hold per event: holding again replaces the earlier hold and releases its seats. The new hold may include seats of the hold it replaces.
- `confirmHold(holdId)` in `src/holds.ts` turns the hold into a booking (the same shape `book` returns) and the seats are sold. An expired hold is `HOLD_EXPIRED`; an unknown or already confirmed one is `HOLD_NOT_FOUND`.
- An expired hold frees its seats at once: no job has to run first.
