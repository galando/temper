import { audit } from './audit.ts';
import { clock } from './clock.ts';
import { store } from './store.ts';

/** A clean world and a fixed clock for tests; returns the clock's setter. */
export function fresh(start = 1_700_000_000_000): { at: (ms: number) => void; advance: (ms: number) => void } {
  store.reset();
  audit.reset();
  let t = start;
  clock.now = () => t;
  return { at: ms => { t = ms; }, advance: ms => { t += ms; } };
}
