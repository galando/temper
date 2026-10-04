// One look for everything Temper draws inside a card with its own background (the pane and the
// game). The engine frames a pane with its own colour, which follows Claude Code's theme and not the
// terminal's. Text with no colour of its own takes the terminal's foreground, so on a light terminal
// it is dark on a dark pane. So the card sets an explicit background, and every text node inside it
// sets an explicit colour with a contrast of at least 4.5 to 1 against that background. It then looks
// the same on every theme. The band and the hint have no background: they keep the theme's colours.

// Every colour is one of the 256 colour palette (xterm 234, 254, 248, 114, 111, 222, 216, 218), so a
// terminal without true colour draws exactly these and not a nearby guess.
export const CARD_BG = '#1c1c1c'
export const FG = '#e4e4e4'
export const MUTED = '#a8a8a8'
export const GREEN = '#87d787'
export const BLUE = '#87afff'
export const YELLOW = '#ffd787'
export const ORANGE = '#ffaf87'
export const PINK = '#ffafd7'

// WCAG relative luminance and contrast ratio of two #rrggbb colours.
const channel = (v: number): number => {
  const s = v / 255
  return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4
}

export function luminance(hex: string): number {
  const m = /^#([0-9a-f]{6})$/i.exec(hex)
  if (!m) return NaN
  const n = parseInt(m[1] as string, 16)
  return 0.2126 * channel((n >> 16) & 255) + 0.7152 * channel((n >> 8) & 255) + 0.0722 * channel(n & 255)
}

export function contrast(a: string, b: string): number {
  const la = luminance(a)
  const lb = luminance(b)
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}
