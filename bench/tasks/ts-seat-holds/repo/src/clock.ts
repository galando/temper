// The clock. Tests replace clock.now.
export const clock = {
  now: (): number => Date.now(),
};
