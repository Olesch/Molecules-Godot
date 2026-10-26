"""Generate a seamless 16-bar chiptune loop -> assets/music/theme.wav (16-bit mono 22050 Hz)."""
import math, os, random, struct, wave

SR = 22050
BPM = 120
BEAT = 60.0 / BPM
STEP = BEAT / 4            # 16th note
BARS = 16
N = int(round(BARS * 4 * BEAT * SR))
random.seed(7)
buf = [0.0] * N


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def pulse(ph, duty):
    return 1.0 if (ph % 1.0) < duty else -1.0


def tri(ph):
    p = ph % 1.0
    return 4 * p - 1 if p < 0.5 else 3 - 4 * p


def add(i, v):
    buf[i % N] += v  # wrap tails around for seamless loop


def note_pulse(start, dur, midi, vol, duty, vib=False, rel=0.02, decay=0.0):
    s0 = int(start * SR)
    n = int(dur * SR)
    f = hz(midi)
    ph = 0.0
    for k in range(n):
        t = k / SR
        ff = f
        if vib and t > 0.18:
            ff = f * (1 + 0.006 * math.sin(2 * math.pi * 5.5 * (t - 0.18)))
        ph += ff / SR
        env = min(1.0, t / 0.005) * math.exp(-decay * t)
        tl = dur - t
        if tl < rel:
            env *= tl / rel
        add(s0 + k, vol * env * pulse(ph, duty))


def note_tri(start, dur, midi, vol):
    s0 = int(start * SR)
    n = int(dur * SR)
    f = hz(midi)
    for k in range(n):
        t = k / SR
        env = min(1.0, t / 0.004)
        tl = dur - t
        if tl < 0.015:
            env *= tl / 0.015
        add(s0 + k, vol * env * tri(f * t))


def hat(start, vol, length=0.04):
    s0 = int(start * SR)
    for k in range(int(length * SR)):
        env = (1 - k / (length * SR)) ** 2
        add(s0 + k, vol * env * random.uniform(-1, 1))


def snare(start, vol):
    s0 = int(start * SR)
    L = int(0.12 * SR)
    for k in range(L):
        t = k / SR
        env = math.exp(-t * 30)
        # LFSR-ish: coarse noise, held samples for a crunchier tone
        if k % 2 == 0:
            snare.v = random.uniform(-1, 1)
        add(s0 + k, vol * env * snare.v + 0.3 * vol * env * tri(190 * t))
snare.v = 0.0


def kick(start, vol):
    s0 = int(start * SR)
    L = int(0.14 * SR)
    ph = 0.0
    for k in range(L):
        t = k / SR
        f = 45 + 110 * math.exp(-t * 35)
        ph += f / SR
        env = math.exp(-t * 18) * min(1.0, k / 40)
        add(s0 + k, vol * env * math.sin(2 * math.pi * ph))


# progression: (root midi for bass, chord tones)
Am = (45, [57, 60, 64]); F = (41, [53, 57, 60]); C = (48, [60, 64, 67]); G = (43, [55, 59, 62])
Dm = (50, [62, 65, 69]); Em = (52, [64, 67, 71])
prog_a = [Am, F, C, G]
prog_b = [Am, F, C, G]
prog_b2 = [F, G, Am, Em]
progression = prog_a + prog_a + [F, G, C, Am] + [F, G, Am, G]

# Lead motif (bars of 16 steps): list of (step, length_in_steps, midi); midi None = rest
A4, B4, C5, D5, E5, F5, G5, A5 = 69, 71, 72, 74, 76, 77, 79, 81
motif1 = [  # over Am F C G
    [(0, 3, E5), (3, 1, D5), (4, 2, C5), (6, 2, D5), (8, 6, E5), (14, 2, None)],
    [(0, 3, F5), (3, 1, E5), (4, 2, C5), (6, 2, A4), (8, 6, C5), (14, 2, None)],
    [(0, 2, G5), (2, 2, E5), (4, 2, C5), (6, 2, E5), (8, 4, G5), (12, 4, E5)],
    [(0, 3, D5), (3, 1, E5), (4, 2, D5), (6, 2, B4), (8, 8, G5 - 5 + 5)],
]
motif2 = [  # variation (higher, busier)
    [(0, 2, E5), (2, 2, A5), (4, 2, G5), (6, 2, E5), (8, 4, C5), (12, 2, D5), (14, 2, E5)],
    [(0, 2, F5), (2, 2, A5), (4, 2, G5), (6, 2, F5), (8, 6, E5), (14, 2, None)],
    [(0, 2, G5), (2, 2, E5), (4, 2, C5), (6, 2, D5), (8, 2, E5), (10, 2, G5), (12, 4, A5)],
    [(0, 2, G5), (2, 2, F5), (4, 2, E5), (6, 2, D5), (8, 4, B4), (12, 4, D5)],
]
motif3 = [  # bars 9-12 over F G C Am : answer phrase
    [(0, 3, C5), (3, 1, D5), (4, 4, F5), (8, 6, E5), (14, 2, None)],
    [(0, 3, D5), (3, 1, E5), (4, 4, G5), (8, 6, F5), (14, 2, None)],
    [(0, 2, E5), (2, 2, G5), (4, 4, C5 + 12), (8, 4, G5), (12, 4, E5)],
    [(0, 3, E5), (3, 1, D5), (4, 2, C5), (6, 2, A4), (8, 8, E5)],
]
motif4 = [  # bars 13-16 over F G Am G : build then resolve to loop start
    [(0, 2, A5), (2, 2, F5), (4, 2, C5), (6, 2, F5), (8, 6, A5), (14, 2, None)],
    [(0, 2, G5), (2, 2, D5), (4, 2, B4), (6, 2, D5), (8, 6, G5), (14, 2, None)],
    [(0, 2, E5), (2, 2, A5), (4, 2, G5), (6, 2, E5), (8, 4, C5), (12, 4, E5)],
    [(0, 2, D5), (2, 2, E5), (4, 2, D5), (6, 2, B4), (8, 6, G5 - 12 + 12), (14, 2, None)],
]
lead_bars = motif1 + motif2 + motif3 + motif4

for bar in range(BARS):
    t0 = bar * 4 * BEAT
    root, tones = progression[bar]
    # lead
    for st, ln, m in lead_bars[bar]:
        if m is None:
            continue
        d = ln * STEP
        note_pulse(t0 + st * STEP, d * 0.95, m, 0.20, 0.25 if bar < 8 else 0.125,
                   vib=ln >= 4, decay=1.2)
    # arpeggio (16ths) on second pulse
    pattern = [0, 1, 2, 1, 0, 1, 2, 1, 0, 1, 2, 1, 0, 1, 2, 1]
    for s in range(16):
        m = tones[pattern[s]] + (12 if s % 8 >= 4 and bar >= 8 else 0)
        note_pulse(t0 + s * STEP, STEP * 0.9, m, 0.075, 0.5, rel=0.004, decay=6.0)
    # bass: 8th notes root/fifth/octave
    bpat = [0, 0, 7, 0, 12, 0, 7, 0]
    for s in range(8):
        note_tri(t0 + s * BEAT / 2, BEAT / 2 * 0.9, root + bpat[s], 0.30)
    # drums
    for b in range(4):
        tb = t0 + b * BEAT
        if b in (0, 2):
            kick(tb, 0.35)
        if b in (1, 3):
            snare(tb, 0.16)
        hat(tb, 0.05)
        hat(tb + BEAT / 2, 0.075 if bar >= 4 else 0.055)
    if bar % 4 == 3:  # little fill
        for s in (12, 13, 14, 15):
            hat(t0 + s * STEP, 0.06, 0.03)

# normalize to 0.55 peak
peak = max(abs(x) for x in buf)
g = 0.55 / peak
# short fades at the seam
fade = int(0.004 * SR)
out = [x * g for x in buf]
for i in range(fade):
    w = i / fade
    out[i] *= w
    out[N - 1 - i] *= w
out[0] = 0.0
out[-1] = 0.0

here = os.path.dirname(os.path.abspath(__file__))
path = os.path.normpath(os.path.join(here, "..", "assets", "music", "theme.wav"))
os.makedirs(os.path.dirname(path), exist_ok=True)
with wave.open(path, "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in out))
print("wrote", path)
