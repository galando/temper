import type { Register } from 'claude-code'

// Pass-through stub. The enforcement adapter lands in a later task; until then every
// hook is absent, so Claude Code behaves exactly as it does without the mod.
export const register: Register = () => {}
