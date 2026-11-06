export type ErrorCode = 'UNKNOWN_EVENT' | 'UNKNOWN_SEAT' | 'SEAT_UNAVAILABLE' | 'TOO_MANY_SEATS' | 'NO_SEATS';

export class BookingError extends Error {
  readonly code: ErrorCode;

  constructor(code: ErrorCode, message?: string) {
    super(message ?? code);
    this.name = 'BookingError';
    this.code = code;
  }
}
