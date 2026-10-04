// The pictures of Temper Run, as data. Every picture is a table of rows of palette letters. A letter
// is one pixel. A dot is no pixel. The Client draws two pixels in one terminal cell with a half
// block, so the pictures are sharp and square. Pure data: no Claude imports.

// The palette. Fill colours of the dragon (o O y f F) are warm; the obstacles are gray and blue; the
// world is dark. `e`, `k` and `w` are small details drawn on the body (eye, dead eye, tooth).
export const PALETTE: Readonly<Record<string, string>> = {
  // Ember, the dragon.
  o: '#ff7800', // body
  O: '#d75f00', // shade: back, wing, tail
  y: '#ffd700', // belly and the tip of the flame
  F: '#ff3c00', // flame
  e: '#990000', // red eye
  k: '#000000', // dead eye (an X) and ash
  w: '#fff7d7', // tooth and horn
  a: '#9e9e9e', // ash: the flame after the dragon fell
  v: '#ffa500', // the wing
  // Obstacles.
  g: '#8c8c8c', // iron
  G: '#e4e4e4', // iron, the light top edge
  b: '#0087ff', // the water bucket
  B: '#5fd7ff', // the water
  i: '#d7ffff', // ice
  h: '#bcbcbc', // handle of the hammer
}

export type Rect = { x: number; y: number; w: number; h: number }
export type Frame = {
  // Rows of palette letters. All rows have the same width.
  rows: readonly string[]
  // The part that can hit or be hit, in pixels from the top left of the picture. It is smaller than
  // the picture: one pixel in from the drawn pixels on each side, so a near miss is a miss.
  hit: Rect
}

// ---- Ember, the dragon ------------------------------------------------------------------
// 12 pixels wide and 12 tall (12 columns by 6 rows). It faces right. The tail on the left ends in a
// small flame.

// The head with two horns, an eye and a tooth; the neck and the belly in yellow; a wing in amber on
// the back; the tail in a darker orange with a little flame at the end; two sturdy legs.
const RUN_A: Frame = {
  rows: [
    '.......w.w..',
    '......ooooo.',
    '.v....oeooow',
    '.vv...oooooo',
    '.vvv..ooyyy.',
    '..vvvvooyyy.',
    '..OvvOooyy..',
    '...OOooooyy.',
    'FOOooooyyy..',
    'yFooooyy....',
    '...oo..oo...',
    '..ooo.ooo...',
  ],
  hit: { x: 3, y: 2, w: 7, h: 8 },
}

// Mid stride: the legs together under the body.
const RUN_B: Frame = {
  rows: [
    '.......w.w..',
    '......ooooo.',
    '.v....oeooow',
    '.vv...oooooo',
    '.vvv..ooyyy.',
    '..vvvvooyyy.',
    '..OvvOooyy..',
    '...OOooooyy.',
    'FOOooooyyy..',
    'yFooooyy....',
    '....oooo....',
    '....ooo.oo..',
  ],
  hit: { x: 3, y: 2, w: 7, h: 8 },
}

// In the air the legs are tucked.
const JUMP: Frame = {
  rows: [
    '.......w.w..',
    '......ooooo.',
    '.v....oeooow',
    '.vv...oooooo',
    '.vvv..ooyyy.',
    '..vvvvooyyy.',
    '..OvvOooyy..',
    '...OOooooyy.',
    'FOOooooyyy..',
    'yFooooyy....',
    '....oooo....',
    '.....o.o....',
  ],
  hit: { x: 3, y: 2, w: 7, h: 8 },
}

const DUCK: Frame = {
  rows: [
    '.....wow.ooo.',
    '..O.ooooooeoo',
    'FOOOoooooooow',
    'yFOooooyyyyy.',
    '..oooooyyoo..',
    '...o.o...o.o.',
  ],
  hit: { x: 3, y: 1, w: 9, h: 4 },
}

// Fallen: an X for an eye, and the flame at the tail is only gray ash.
const DEAD: Frame = {
  rows: [
    '.......w.w..',
    '......kokoo.',
    '.v....okooow',
    '.vv...kokooo',
    '.vvv..ooyyy.',
    '..vvvvooyyy.',
    '..OvvOooyy..',
    '...OOooooyy.',
    'aOOooooyyy..',
    '.aooooyy....',
    '...oo..oo...',
    '..ooo.ooo...',
  ],
  hit: { x: 3, y: 2, w: 7, h: 8 },
}

export const DRAGON = {
  run: [RUN_A, RUN_B] as const,
  jump: JUMP,
  duck: DUCK,
  dead: DEAD,
}

// ---- Obstacles -------------------------------------------------------------------------

export type Kind = 'anvil_s' | 'anvil_l' | 'bucket' | 'hammer'

// An anvil: a light top face, a narrow waist, a wide base.
export const ANVIL_S: Frame = {
  rows: ['.GGGGGG.', 'gggggggg', '..gggg..', '..gggg..', 'gggggggg'],
  hit: { x: 1, y: 1, w: 6, h: 3 },
}

export const ANVIL_L: Frame = {
  rows: ['GGGGGGGGGG', 'gggggggggg', '.gggggggg.', '...gggg...', '...gggg...', '..gggggg..', 'gggggggggg'],
  hit: { x: 1, y: 1, w: 8, h: 5 },
}

// A bucket of cold water with a handle, a few ice crystals on the water.
export const BUCKET: Frame = {
  rows: ['..hhhh..', '.h....h.', 'iBiBiBiB', 'bbbbbbbb', '.bbbbbb.', '.bbbbbb.', '..bbbb..'],
  hit: { x: 1, y: 2, w: 6, h: 4 },
}

// The hammer spins as it flies: the head up, then the head to the side.
export const HAMMER: readonly Frame[] = [
  {
    rows: ['GGGGGGGG', 'gggggggg', '...hh...', '...hh...', '...hh...', '...hh...'],
    hit: { x: 1, y: 1, w: 6, h: 2 },
  },
  {
    rows: ['GGg.....', 'GGgh....', 'GGghhhhh', 'GGghhhhh', 'GGgh....', 'GGg.....'],
    hit: { x: 1, y: 1, w: 6, h: 2 },
  },
]

// A hammer flies low (the dragon ducks) or high (it flies over the dragon). The number is how many
// pixels above the floor the bottom of the picture is.
export const HAMMER_LOW = 5
export const HAMMER_HIGH = 15

export const OBSTACLES = {
  anvil_s: [ANVIL_S] as readonly Frame[],
  anvil_l: [ANVIL_L] as readonly Frame[],
  bucket: [BUCKET] as readonly Frame[],
  hammer: HAMMER,
}

export const widthOf = (f: Frame): number => (f.rows[0] ?? '').length
export const heightOf = (f: Frame): number => f.rows.length

// ---- The world --------------------------------------------------------------------------

// The far wall warms from dark gray to deep red as the heat grows (heat 1 to 5).
// A terminal with 256 colours (not true colour) draws every step after the first as the same deep
// red, which is still dark enough for every picture.
export const WALL: readonly string[] = ['#1c1c1c', '#241010', '#2e0e0e', '#3a0c0c', '#4a0808']
// The glow of the furnace windows in the far wall, one for each heat.
export const GLOW: readonly string[] = ['#2c2c2c', '#3a1414', '#4a1010', '#5a0c0c', '#680808']
export const FLOOR = {
  edge: '#333333',
  brick: '#3b1010',
  mortar: '#262626',
  ember: '#5f0000',
  emberHot: '#7a0000',
}
export const SPARK = '#ffaf5f'
// The dragon turns this colour for half a second at every hundred points.
export const FLASH = '#ffd700'
