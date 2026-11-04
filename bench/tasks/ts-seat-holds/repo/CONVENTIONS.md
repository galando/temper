# House rules

1. **Time** comes from `clock.now()` (milliseconds). Never call `Date.now()` elsewhere: tests set the clock.
2. **Errors** are `BookingError` with a code from `ErrorCode` in `src/errors.ts`. Add a new code there; never throw a
   plain `Error` for a rule the caller can break.
3. **Every change is audited**: exactly one `audit.record(action, data)` per change, the action `<thing>.<past tense>`
   (`booking.created`). A refused call records nothing.
4. **Seat ids** are strings like `"A1"`. A list of seats is checked as a whole: one bad seat refuses the whole call and
   changes nothing.
5. **Returned objects are copies**: a caller changing what it got back never changes the store.
6. Tests use `node:test` and `node:assert` only, and live in `test/`.
7. **Node runs the TypeScript by stripping the types** (no build step), so use only erasable syntax: no `enum`, no
   `namespace`, no parameter properties (`constructor(public x)`); import local files with their `.ts` extension.
