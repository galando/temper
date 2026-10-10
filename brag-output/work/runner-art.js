// Transpiled verbatim from hooks/temper-mod/core/runner-art.ts
(function(){// The pictures of Temper Run, as data. Every picture is a table of rows of palette letters. A letter
// is one pixel. A dot is no pixel. The Client draws two pixels in one terminal cell with a half
// block, so the pictures are sharp and square. Pure data: no Claude imports.
// The palette. Fill colours of the dragon (o O y f F) are warm; the obstacles are gray and blue; the
// world is dark. `e`, `k` and `w` are small details drawn on the body (eye, dead eye, tooth).
const PALETTE = {
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
};
// ---- Ember, the dragon ------------------------------------------------------------------
// 8 pixels wide and 8 tall (8 columns by 4 rows). It faces right. Two horns, an eye, a tooth, a wing
// in amber, a tail that ends in a small flame, and two legs.
const RUN_A = {
    rows: [
        '....w.w.',
        '...ooooo',
        'v..oeoow',
        'vv.ooooo',
        'OvvoyyyO',
        'FOOooyy.',
        'yFoooy..',
        '..oo.oo.',
    ],
    hit: { x: 2, y: 1, w: 5, h: 6 },
};
// Mid stride: the legs together under the body.
const RUN_B = {
    rows: [
        '....w.w.',
        '...ooooo',
        'v..oeoow',
        'vv.ooooo',
        'OvvoyyyO',
        'FOOooyy.',
        'yFoooy..',
        '...ooo..',
    ],
    hit: { x: 2, y: 1, w: 5, h: 6 },
};
// In the air the legs are tucked.
const JUMP = {
    rows: [
        '....w.w.',
        '...ooooo',
        'v..oeoow',
        'vv.ooooo',
        'OvvoyyyO',
        'FOOooyy.',
        'yFoooy..',
        '..o..o..',
    ],
    hit: { x: 2, y: 1, w: 5, h: 6 },
};
// Low and long: 8 pixels wide and 4 tall (2 rows).
const DUCK = {
    rows: [
        '.vv.w.oo',
        'vvooeooo',
        'FOooyyoo',
        'yFo.o.o.',
    ],
    hit: { x: 2, y: 1, w: 4, h: 2 },
};
// Fallen: an X for an eye, and the flame at the tail is only gray ash.
const DEAD = {
    rows: [
        '....w.w.',
        '...kokoo',
        'v..okoow',
        'vv.kokoo',
        'OvvoyyyO',
        'aOOooyy.',
        '.aoooy..',
        '..oo.oo.',
    ],
    hit: { x: 2, y: 1, w: 5, h: 6 },
};
const DRAGON = {
    run: [RUN_A, RUN_B],
    jump: JUMP,
    duck: DUCK,
    dead: DEAD,
};
// An anvil: a light top face, a narrow waist, a wide base.
const ANVIL_S = {
    rows: ['.GGGG.', 'gggggg', '..gg..', 'gggggg'],
    hit: { x: 1, y: 1, w: 4, h: 2 },
};
const ANVIL_L = {
    rows: ['GGGGGGGG', 'gggggggg', '.gggggg.', '..gggg..', '..gggg..', 'gggggggg'],
    hit: { x: 1, y: 1, w: 6, h: 4 },
};
// A bucket of cold water with a handle, a few ice crystals on the water.
const BUCKET = {
    rows: ['.hhh.', 'iBiBi', 'bbbbb', '.bbb.', '.bbb.'],
    hit: { x: 1, y: 1, w: 3, h: 3 },
};
// The hammer spins as it flies: the head up, then the head to the side.
const HAMMER = [
    {
        rows: ['GGGGGG', 'gggggg', '..hh..', '..hh..'],
        hit: { x: 1, y: 1, w: 4, h: 2 },
    },
    {
        rows: ['GG....', 'GGhhhh', 'GGhhhh', 'GG....'],
        hit: { x: 1, y: 1, w: 4, h: 2 },
    },
];
// A hammer flies low (the dragon ducks) or high (it flies over the dragon). The number is how many
// pixels above the floor the bottom of the picture is.
const HAMMER_LOW = 4;
const HAMMER_HIGH = 7;
const OBSTACLES = {
    anvil_s: [ANVIL_S],
    anvil_l: [ANVIL_L],
    bucket: [BUCKET],
    hammer: HAMMER,
};
const widthOf = (f) => (f.rows[0] ?? '').length;
const heightOf = (f) => f.rows.length;
// ---- The world --------------------------------------------------------------------------
// The far wall warms from dark gray to deep red as the heat grows (heat 1 to 5).
// A terminal with 256 colours (not true colour) draws every step after the first as the same deep
// red, which is still dark enough for every picture.
const WALL = ['#1c1c1c', '#241010', '#2e0e0e', '#3a0c0c', '#4a0808'];
// The glow of the furnace windows in the far wall, one for each heat.
const GLOW = ['#2c2c2c', '#3a1414', '#4a1010', '#5a0c0c', '#680808'];
const FLOOR = {
    edge: '#333333',
    brick: '#3b1010',
    mortar: '#262626',
    ember: '#5f0000',
    emberHot: '#7a0000',
};
const SPARK = '#ffaf5f';
// The dragon turns this colour for half a second at every hundred points.
const FLASH = '#ffd700';

window.ART={PALETTE,DRAGON,OBSTACLES,WALL,GLOW,FLOOR,SPARK,widthOf,heightOf};})();