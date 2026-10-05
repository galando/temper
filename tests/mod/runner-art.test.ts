import { describe, expect, test } from 'claude-code/testing'

import { DRAGON, FLASH, FLOOR, GLOW, HAMMER_HIGH, HAMMER_LOW, OBSTACLES, PALETTE, SPARK, WALL, heightOf, widthOf } from '../../hooks/temper-mod/core/runner-art'
import type { Frame } from '../../hooks/temper-mod/core/runner-art'
import { contrast } from '../../hooks/temper-mod/ui/palette'

const dragonFrames: Array<[string, Frame]> = [
  ['run A', DRAGON.run[0]],
  ['run B', DRAGON.run[1]],
  ['jump', DRAGON.jump],
  ['duck', DRAGON.duck],
  ['dead', DRAGON.dead],
]
const obstacleFrames: Array<[string, Frame]> = [
  ['anvil small', OBSTACLES.anvil_s[0] as Frame],
  ['anvil large', OBSTACLES.anvil_l[0] as Frame],
  ['bucket', OBSTACLES.bucket[0] as Frame],
  ['hammer 1', OBSTACLES.hammer[0] as Frame],
  ['hammer 2', OBSTACLES.hammer[1] as Frame],
]
const all = [...dragonFrames, ...obstacleFrames]

// The box around the pixels that are drawn, in pixels from the top left.
const bbox = (f: Frame) => {
  let x0 = Infinity
  let y0 = Infinity
  let x1 = -1
  let y1 = -1
  f.rows.forEach((row, y) => {
    for (let x = 0; x < row.length; x++) {
      if (row[x] !== '.') {
        x0 = Math.min(x0, x)
        y0 = Math.min(y0, y)
        x1 = Math.max(x1, x)
        y1 = Math.max(y1, y)
      }
    }
  })
  return { x0, y0, x1, y1 }
}

describe('the pictures are tables', () => {
  test('every row of every picture has the same width, so nothing shifts', () => {
    for (const [name, f] of all) {
      expect(f.rows.length, name).toBeGreaterThan(0)
      for (const row of f.rows) expect(row.length, `${name}: ${row}`).toBe(widthOf(f))
    }
  })

  test('every letter is in the palette (or is a dot) and every colour is #rrggbb', () => {
    for (const [name, f] of all) for (const row of f.rows) for (const ch of row) if (ch !== '.') expect(PALETTE[ch], `${name}: letter ${ch}`).toBeDefined()
    for (const c of Object.values(PALETTE)) expect(/^#[0-9a-f]{6}$/i.test(c)).toBe(true)
  })

  test('the dragon is 8 pixels wide and 8 tall (8 columns by 4 rows); the duck is 8 by 4 (2 rows)', () => {
    for (const f of [DRAGON.run[0], DRAGON.run[1], DRAGON.jump, DRAGON.dead]) {
      expect(widthOf(f)).toBe(8)
      expect(heightOf(f)).toBe(8)
    }
    expect(heightOf(DRAGON.duck)).toBe(4)
    expect(widthOf(DRAGON.duck)).toBe(8)
    // A cell holds two pixels, so every height is even.
    for (const [name, f] of dragonFrames) expect(heightOf(f) % 2, name).toBe(0)
  })

  test('the two run frames differ (the legs move) and the dead frame has an X for an eye and no flame', () => {
    expect(DRAGON.run[0].rows.join('')).not.toEqual(DRAGON.run[1].rows.join(''))
    expect(DRAGON.dead.rows.join('')).toContain('k')
    expect(DRAGON.run[0].rows.join('')).toContain('e')
    expect(DRAGON.run[0].rows.join('')).toContain('F')
    expect(DRAGON.dead.rows.join('')).not.toContain('F')
  })

  test('the hammer has two frames of the same size, and a low and a high height', () => {
    expect(widthOf(OBSTACLES.hammer[0] as Frame)).toBe(widthOf(OBSTACLES.hammer[1] as Frame))
    expect(heightOf(OBSTACLES.hammer[0] as Frame)).toBe(heightOf(OBSTACLES.hammer[1] as Frame))
    expect(OBSTACLES.hammer[0]?.rows.join('')).not.toEqual(OBSTACLES.hammer[1]?.rows.join(''))
    expect(HAMMER_LOW).toBeLessThan(HAMMER_HIGH)
  })

  test('the anvil, the bucket and the hammer have the sizes the game needs', () => {
    expect(heightOf(OBSTACLES.anvil_l[0] as Frame)).toBeGreaterThan(heightOf(OBSTACLES.anvil_s[0] as Frame))
    expect(widthOf(OBSTACLES.anvil_l[0] as Frame)).toBeGreaterThan(widthOf(OBSTACLES.anvil_s[0] as Frame))
    // The big anvil is well under the height of a jump.
    expect(heightOf(OBSTACLES.anvil_l[0] as Frame)).toBe(6)
    expect(widthOf(OBSTACLES.anvil_l[0] as Frame)).toBe(8)
    expect(widthOf(OBSTACLES.anvil_s[0] as Frame)).toBe(6)
    expect(heightOf(OBSTACLES.anvil_s[0] as Frame)).toBe(4)
    expect(widthOf(OBSTACLES.bucket[0] as Frame)).toBe(5)
    expect(heightOf(OBSTACLES.bucket[0] as Frame)).toBe(5)
    expect(widthOf(OBSTACLES.hammer[0] as Frame)).toBe(6)
    expect(heightOf(OBSTACLES.hammer[0] as Frame)).toBe(4)
  })
})

describe('the hit boxes are inside the pictures and smaller than what is drawn', () => {
  test('every hit box lies inside the picture, one pixel in from the drawn pixels on each side', () => {
    for (const [name, f] of all) {
      const b = bbox(f)
      const { x, y, w, h } = f.hit
      expect(w, name).toBeGreaterThan(0)
      expect(h, name).toBeGreaterThan(0)
      expect(x, `${name}: left`).toBeGreaterThanOrEqual(b.x0 + 1)
      expect(y, `${name}: top`).toBeGreaterThanOrEqual(b.y0 + 1)
      expect(x + w - 1, `${name}: right`).toBeLessThanOrEqual(b.x1 - 1)
      expect(y + h - 1, `${name}: bottom`).toBeLessThanOrEqual(b.y1 - 1)
    }
  })

  test('the hit box of the dragon covers drawn pixels in every frame', () => {
    for (const [name, f] of dragonFrames) {
      let drawn = 0
      for (let yy = f.hit.y; yy < f.hit.y + f.hit.h; yy++) for (let xx = f.hit.x; xx < f.hit.x + f.hit.w; xx++) if (f.rows[yy]?.[xx] !== '.') drawn++
      expect(drawn, name).toBeGreaterThan((f.hit.w * f.hit.h) / 2)
    }
  })
})

describe('the colours can be told apart', () => {
  const fills = (frames: Frame[]): string[] => [...new Set(frames.flatMap(f => f.rows.flatMap(r => [...r]).filter(ch => ch !== '.')))].map(ch => PALETTE[ch] as string)
  const dragonFills = fills(dragonFrames.map(([, f]) => f)).filter(c => ![PALETTE.e, PALETTE.k, PALETTE.w, PALETTE.a].includes(c))
  const iron = fills(obstacleFrames.map(([, f]) => f))
  const world = [...WALL, ...GLOW, FLOOR.edge, FLOOR.brick, FLOOR.mortar, FLOOR.ember, FLOOR.emberHot]

  test('every dragon fill colour stands out from every wall, window and floor colour (3 to 1 or more)', () => {
    for (const d of dragonFills) for (const w of world) expect(contrast(d, w), `${d} on ${w}`).toBeGreaterThanOrEqual(3)
  })

  test('every obstacle colour stands out from every wall, window and floor colour (3 to 1 or more)', () => {
    for (const o of iron) for (const w of world) expect(contrast(o, w), `${o} on ${w}`).toBeGreaterThanOrEqual(3)
  })

  // A terminal with 256 colours gets every colour changed to the nearest of 256 (the way many tools
  // do it: each channel scaled to 0 to 5, then the cube level, and the gray ramp for grays).
  const quantize = (hex: string): string => {
    const n = [1, 3, 5].map(i => parseInt(hex.slice(i, i + 2), 16)) as [number, number, number]
    const levels = [0, 95, 135, 175, 215, 255]
    const [r, g, b] = n
    if (r === g && g === b) {
      if (r < 8) return '#000000'
      if (r > 248) return '#ffffff'
      const v = 8 + 10 * Math.round(((r - 8) / 247) * 24)
      return `#${v.toString(16).padStart(2, '0').repeat(3)}`
    }
    return `#${n.map(v => levels[Math.round(v / 51)]?.toString(16).padStart(2, '0')).join('')}`
  }

  test('in a terminal with 256 colours the dragon and the obstacles still stand out (2.9 to 1 or more)', () => {
    const q = (cs: string[]) => cs.map(quantize)
    const wq = q(world)
    for (const c of [...q(dragonFills), ...q(iron)]) for (const w of wq) expect(contrast(c, w), `${c} on ${w}`).toBeGreaterThanOrEqual(2.9)
  })

  test('in a terminal with 256 colours the body, the wing and the shade of the dragon stay three different colours', () => {
    const body = quantize(PALETTE.o as string)
    const wing = quantize(PALETTE.v as string)
    const shade = quantize(PALETTE.O as string)
    const belly = quantize(PALETTE.y as string)
    expect(new Set([body, wing, shade, belly]).size).toBe(4)
  })

  test('the spark and the flash colour stand out from the wall', () => {
    for (const w of WALL) {
      expect(contrast(SPARK, w)).toBeGreaterThanOrEqual(3)
      expect(contrast(FLASH, w)).toBeGreaterThanOrEqual(3)
    }
  })

  test('two bright fills cannot reach 3 to 1, so the dragon and the obstacles differ in hue instead', () => {
    const dist = (a: string, b: string) => {
      const n = (h: string, i: number) => parseInt(h.slice(1 + i * 2, 3 + i * 2), 16)
      return Math.hypot(n(a, 0) - n(b, 0), n(a, 1) - n(b, 1), n(a, 2) - n(b, 2))
    }
    for (const d of dragonFills) for (const o of iron) expect(dist(d, o), `${d} and ${o}`).toBeGreaterThanOrEqual(90)
  })

  test('the world warms from dark gray to deep red, one step for each heat level', () => {
    expect(WALL).toHaveLength(5)
    expect(GLOW).toHaveLength(5)
    const red = (h: string) => parseInt(h.slice(1, 3), 16) - parseInt(h.slice(3, 5), 16)
    for (let i = 1; i < 5; i++) expect(red(WALL[i] as string)).toBeGreaterThanOrEqual(red(WALL[i - 1] as string))
    expect(red(WALL[0] as string)).toBe(0)
    expect(red(WALL[4] as string)).toBeGreaterThan(40)
  })
})
