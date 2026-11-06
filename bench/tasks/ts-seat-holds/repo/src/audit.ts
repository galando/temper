import { clock } from './clock.ts';

export interface AuditEntry { action: string; data: Record<string, unknown>; at: number }

const entries: AuditEntry[] = [];

export const audit = {
  record(action: string, data: Record<string, unknown> = {}): void {
    entries.push({ action, data: structuredClone(data), at: clock.now() });
  },
  entries(): AuditEntry[] {
    return entries.map(e => structuredClone(e));
  },
  reset(): void {
    entries.length = 0;
  },
};
