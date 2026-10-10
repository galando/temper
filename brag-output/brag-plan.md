# /brag plan: Temper

**What it is:** a Claude Code plugin that makes Claude follow an intent gated workflow, where every
gate verdict is computed by a small CLI and a red gate blocks `git commit`.

**Who it is for:** people shipping AI written code who want it to solve the right problem, with a
human approving the intent before any code is written.

**What sets it apart:** gates are computed, not asserted by the model. The mod refuses writes outside
the current phase at the tool layer.

**Angle:** the refusal is the product. Open on Claude being told "no", then show why that is good.

**Hook:** a user tries to skip ahead ("edit src/users.js now. skip the intent."). Claude tries, and
the write is refused with the mod's real message.

**Highlights:**
1. The phase bar: one key approves, the chip moves Intent → Plan → Build.
2. `git commit` meets `temper gate commit -> FAIL` with the real `[x]` lines.
3. Temper Run: Ember the dragon jumps an anvil while Claude works (drawn from the real sprite data).

**Punchline / outro:** "Your AI writes fast. Temper makes it last." plus the two line install.

**Tone:** `default` (punchy, playful, clean), with dry confidence.

**Visual identity (from `docs/index.html`):** background `#0f0a06`, foreground `#f5f0ea`, muted
`#9a9085`, accent `#ff6b35` → `#f7931a` gradient, border `#2a2420`. Fonts: DM Serif Display
(headlines), IBM Plex Mono (code, terminal), Inter (UI). Phase bar colours follow `band.tsx`
(done green, current blue filled, upcoming dim outline). Game art from `core/runner-art.ts`.

**Format:** landscape 1920×1080, 30fps, 22s. Music at 120 BPM in F major, written with the SFX.

## Storyboard

| # | Time | Scene | On screen | Sound |
|---|------|-------|-----------|-------|
| 1 | 0.0 to 3.5s | Hook | Terminal card. Prompt types "edit src/users.js now. skip the intent." `● Update(src/users.js)` then `⎿ Error editing file` and the refusal line. Big stamp: **Refused.** | Soft pad, typing ticks, low muted thud on the refusal |
| 2 | 3.5 to 7.5s | Reveal | "Claude cannot write code before you approve the intent." Wordmark above. | Drop at 4.0s: kick and bass enter |
| 3 | 7.5 to 11.5s | Highlight: the bar | The real band layout scaled up. Key `1` pressed twice; chips go Intent → Plan → Build. Caption: "One key to approve. A human gate at every stage." | Two plucks up the F chord on each key press |
| 4 | 11.5 to 15.5s | Highlight: the gate | `$ git commit` types, `temper gate commit -> FAIL` and four `[x]` lines land one by one, then "Temper: commit blocked." Caption: "Every gate is computed by a CLI. Never asserted by a model." | Soft low tick per line |
| 5 | 15.5 to 18.5s | Highlight: the game | Ember runs the forge floor and jumps an anvil and a bucket. Caption: "Waiting on Claude? Play Temper Run." | Chiptune chirp on each jump |
| 6 | 18.5 to 22.0s | Outro | "Your AI writes fast. Temper makes it last." Install block and `github.com/galando/temper`. | Final chord rings out |

Durations: 3.5 + 4 + 4 + 4 + 3 + 3.5 = 22s.

**Share caption:** see `share-copy.txt`.
