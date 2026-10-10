"""Soundtrack for the Temper brag video: music and SFX written as one piece.

120 BPM, F major, 22 seconds. Every SFX is pitched to the chord under it and shares one reverb.
Usage: python3 audio.py out.wav
"""
import sys, wave
import numpy as np

SR = 44100
DUR = 22.0
N = int(SR * DUR)
BEAT = 0.5
BAR = 2.0
rng = np.random.default_rng(7)

def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)

# Note numbers
F2, C3, D3, Bb2 = 41, 48, 50, 46
CHORDS = {  # root (bass), chord tones for pad and plucks
    'F':  (41, [65, 69, 72]),        # F A C
    'C':  (48, [64, 67, 72]),        # C E G (voiced E G C)
    'Dm': (50, [62, 65, 69]),        # D F A
    'Bb': (46, [62, 65, 70]),        # Bb D F (voiced D F Bb)
}
PROG = ['F', 'C', 'Dm', 'Bb', 'F', 'C', 'Dm', 'Bb', 'F', 'Bb', 'F']

def buf():
    return np.zeros(N)

def place(dst, sig, t, gain=1.0):
    i = int(t * SR)
    if i >= N:
        return
    j = min(N, i + len(sig))
    dst[i:j] += sig[: j - i] * gain

def env_exp(n, decay):
    return np.exp(-np.arange(n) / (decay * SR))

def adsr(n, a=0.005, r=0.05):
    e = np.ones(n)
    na, nr = max(1, int(a * SR)), max(1, int(r * SR))
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] *= np.linspace(1, 0, nr)
    return e

def fft_filter(x, lo=None, hi=None, order=2):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if hi:
        g *= 1 / np.sqrt(1 + (f / hi) ** (2 * order))
    if lo:
        g *= 1 / np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** (2 * order))
    return np.fft.irfft(X * g, len(x))

def saw(freq, n, detune=0.0):
    t = np.arange(n) / SR
    ph = (freq * (1 + detune)) * t + rng.random()
    return 2 * (ph - np.floor(ph + 0.5))

def sine(freq, n, phase=0.0):
    return np.sin(2 * np.pi * freq * np.arange(n) / SR + phase)

# ---------------- instruments ----------------
def kick():
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 45 + 85 * np.exp(-t / 0.035)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t / 0.16)
    click = fft_filter(rng.standard_normal(n), lo=1500, hi=6000) * np.exp(-t / 0.004) * 0.15
    return (body + click) * 0.9

def hat(open_=False):
    n = int((0.18 if open_ else 0.05) * SR)
    x = fft_filter(rng.standard_normal(n), lo=7000, order=3)
    return x * env_exp(n, 0.05 if open_ else 0.012) * 0.25

def clap():
    n = int(0.25 * SR)
    x = fft_filter(rng.standard_normal(n), lo=900, hi=4500)
    e = np.zeros(n)
    for k, d in enumerate([0, 0.011, 0.022]):
        i = int(d * SR)
        e[i:] += env_exp(n - i, 0.006 if k < 2 else 0.07)
    return x * e * 0.35

def bass(midi, length):
    n = int(length * SR)
    f = hz(midi)
    x = 0.6 * sine(f, n) + 0.35 * fft_filter(saw(f, n), hi=500)
    return x * adsr(n, 0.004, 0.06) * env_exp(n, 0.35)

def pluck(midi, length=0.6, bright=3000, decay=0.22):
    n = int(length * SR)
    f = hz(midi)
    t = np.arange(n) / SR
    x = sum((1 / k) * np.sin(2 * np.pi * f * k * t) * np.exp(-t * k * 1.2 / decay) for k in range(1, 7))
    x = fft_filter(x, hi=bright)
    return x * adsr(n, 0.002, 0.05) * env_exp(n, decay)

def pad_chord(notes, length):
    n = int(length * SR)
    x = np.zeros(n)
    for m in notes:
        for d in (-0.004, 0.0, 0.005):
            x += saw(hz(m - 12), n, d)
    x = fft_filter(x, hi=900, order=2) / (3 * len(notes))
    return x * adsr(n, 0.35, 0.4)

def square(freq_from, freq_to, length, duty=0.25):
    n = int(length * SR)
    f = np.linspace(freq_from, freq_to, n)
    ph = np.cumsum(f) / SR
    x = np.where((ph % 1) < duty, 1.0, -1.0)
    return fft_filter(x, hi=5000) * env_exp(n, length / 2.5) * adsr(n, 0.002, 0.02)

def tick():
    n = int(0.03 * SR)
    x = fft_filter(rng.standard_normal(n), lo=2500, hi=9000)
    return x * env_exp(n, 0.004)

def thud(midi):
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    f = hz(midi) * (1 + 0.6 * np.exp(-t / 0.03))
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.28)
    knock = fft_filter(rng.standard_normal(n), lo=150, hi=1200) * np.exp(-t / 0.03) * 0.5
    return body + knock

def riser(length):
    n = int(length * SR)
    x = fft_filter(rng.standard_normal(n), lo=1500, hi=7000)
    return x * np.linspace(0, 1, n) ** 2.5 * 0.22

def whoosh(length=0.5):
    n = int(length * SR)
    x = fft_filter(rng.standard_normal(n), lo=600, hi=3500)
    e = np.sin(np.linspace(0, np.pi, n)) ** 2
    return x * e * 0.12

# ---------------- music ----------------
kick_b, hat_b, clap_b, bass_b, pad_b, pluck_b, lead_b = (buf() for _ in range(7))
DROP = 4.0
OUT_STOP = 20.0  # drums stop, final chord rings

for bar, name in enumerate(PROG):
    t0 = bar * BAR
    root, tones = CHORDS[name]
    last = bar == len(PROG) - 1
    place(pad_b, pad_chord(tones, BAR + (1.9 if last else 0.25)), t0, 0.55 if t0 < DROP else 0.45)
    if DROP <= t0 < OUT_STOP:
        for b in range(4):
            place(kick_b, kick(), t0 + b * BEAT)
        for b in (1, 3):
            place(clap_b, clap(), t0 + b * BEAT, 0.8)
        for e in range(8):
            place(bass_b, bass(root - 12 if e % 2 == 0 else root, BEAT / 2 * 0.95), t0 + e * BEAT / 2, 0.55)
        # offbeat plucks walk the chord
        seq = [tones[0], tones[1], tones[2], tones[1] + 12 if False else tones[1]]
        for e in range(8):
            if e % 2 == 1:
                place(pluck_b, pluck(tones[(e // 2) % 3] + 12, 0.5, bright=2600), t0 + e * BEAT / 2, 0.22)
    # hats: soft 8ths from 1s in the intro, full 8ths after the drop, open hat on the off of 4
    if t0 + BAR > 1.0 and t0 < OUT_STOP:
        for e in range(8):
            tt = t0 + e * BEAT / 2
            if tt < 1.0:
                continue
            g = 0.35 if tt < DROP else (0.6 if e % 2 else 0.3)
            place(hat_b, hat(open_=(e == 7 and tt >= DROP)), tt, g)

# game section: a little square-wave line over bar 8 (16 to 18s), in F
for k, (m, tt) in enumerate([(72, 16.0), (77, 16.25), (81, 16.5), (77, 16.75), (72, 17.0), (77, 17.25), (81, 17.5), (84, 17.75)]):
    place(lead_b, square(hz(m), hz(m), 0.2, 0.25), tt, 0.07)

# final strum on the last F
for k, m in enumerate([65, 69, 72, 77]):
    place(pluck_b, pluck(m + 12, 2.0, bright=3500, decay=0.6), 20.0 + k * 0.03, 0.22)
place(kick_b, kick(), 20.0, 0.9)

place(hat_b, riser(1.0), 3.0, 1.0)

# ---------------- SFX (in key, same room) ----------------
sfx = buf()
# typing: prompt in the hook, then the git commit
for i in range(40):
    place(sfx, tick(), 0.15 + i / 36 + rng.uniform(-0.004, 0.004), 0.10 + 0.04 * rng.random())
for i in range(42):
    place(sfx, tick(), 11.95 + i / 52 + rng.uniform(-0.003, 0.003), 0.08 + 0.03 * rng.random())
# tool call and error lines: soft C and A blips over F
place(sfx, pluck(72, 0.4, bright=1800, decay=0.12), 1.45, 0.16)
place(sfx, pluck(69, 0.4, bright=1500, decay=0.12), 1.62, 0.14)
# the refusal: a low F thud as the stamp lands
place(sfx, thud(29), 2.0, 0.42)
place(sfx, whoosh(0.35), 1.82, 0.9)
# reveal and outro whooshes
place(sfx, whoosh(0.5), 3.45, 0.8)
place(sfx, whoosh(0.5), 18.35, 0.7)
place(sfx, whoosh(0.4), 7.4, 0.5)
place(sfx, whoosh(0.4), 11.4, 0.5)
place(sfx, whoosh(0.4), 15.4, 0.5)
# key 1, twice: a click then a pluck up the F chord (A then C)
for tt, m in [(8.5, 81), (9.5, 84)]:
    place(sfx, tick(), tt, 0.25)
    place(sfx, pluck(m, 0.8, bright=4000, decay=0.3), tt + 0.01, 0.22)
# gate lines over Dm: muted D and A, then the BLOCK on a low D
for tt, m in zip([12.85, 13.1, 13.3, 13.5, 13.7], [62, 62, 62, 62, 57]):
    place(sfx, pluck(m, 0.3, bright=1400, decay=0.08), tt, 0.16)
place(sfx, thud(38), 14.0, 0.30)
# jumps in the game: square chirp C5 to F5
for tt in (16.23, 17.23):
    place(sfx, square(hz(72), hz(77), 0.18, 0.5), tt, 0.06)

# ---------------- mix ----------------
def reverb_ir(length=1.4, decay=0.45):
    n = int(length * SR)
    t = np.arange(n) / SR
    l = rng.standard_normal(n) * np.exp(-t / decay)
    r = rng.standard_normal(n) * np.exp(-t / decay)
    l = fft_filter(l, lo=200, hi=6000)
    r = fft_filter(r, lo=200, hi=6000)
    return l / np.sqrt(np.sum(l ** 2)), r / np.sqrt(np.sum(r ** 2))

def convolve(x, ir):
    m = len(x) + len(ir) - 1
    L = 1 << (m - 1).bit_length()
    y = np.fft.irfft(np.fft.rfft(x, L) * np.fft.rfft(ir, L), L)[: len(x)]
    return y

# sidechain pump from the kick, gentle
pump = np.ones(N)
for bar in range(len(PROG)):
    for b in range(4):
        tt = bar * BAR + b * BEAT
        if DROP <= tt < OUT_STOP:
            i = int(tt * SR); n = int(0.3 * SR)
            seg = 1 - 0.35 * np.exp(-np.arange(n) / (0.08 * SR))
            j = min(N, i + n)
            pump[i:j] = np.minimum(pump[i:j], seg[: j - i])

pad_b *= pump
bass_b *= pump
pluck_b *= 0.6 + 0.4 * pump

dry = kick_b * 0.75 + clap_b * 0.5 + hat_b * 0.38 + bass_b * 0.8 + pad_b * 0.6 + pluck_b * 0.9 + lead_b + sfx * 0.85
send = pad_b * 0.3 + pluck_b * 0.5 + clap_b * 0.25 + lead_b * 0.4 + sfx * 0.45
irl, irr = reverb_ir()
wet_l, wet_r = convolve(send, irl) * 0.35, convolve(send, irr) * 0.35

# light stereo: hats and plucks a little wide
L = dry + wet_l + hat_b * 0.06 - pluck_b * 0.05
R = dry + wet_r - hat_b * 0.06 + pluck_b * 0.05

# gentle high shelf trim, then a soft limiter and a fade at the very end
L, R = fft_filter(L, hi=14000, order=1), fft_filter(R, hi=14000, order=1)
fade = np.ones(N)
nf = int(1.2 * SR)
fade[-nf:] = np.linspace(1, 0, nf) ** 1.5
fade[: int(0.02 * SR)] = np.linspace(0, 1, int(0.02 * SR))
L, R = L * fade, R * fade
peak = max(np.abs(L).max(), np.abs(R).max())
L, R = L / peak * 1.2, R / peak * 1.2
L, R = np.tanh(L) * 0.89, np.tanh(R) * 0.89

out = np.stack([L, R], axis=1)
pcm = (np.clip(out, -1, 1) * 32767).astype('<i2')
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print('wrote', sys.argv[1], f'{len(L)/SR:.2f}s')
