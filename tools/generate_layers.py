"""Generate layer stems matching theme.wav: assets/music/drums.wav and metal.wav.

Same grid as generate_music.py: 120 BPM, 16 bars, 22050 Hz mono 16-bit,
N = 705600 samples (32 s). Pure standard library. Deterministic.
Run: python tools/generate_layers.py
"""
import math, os, random, struct, wave

SR = 22050
BPM = 120
BEAT = 60.0 / BPM
STEP = BEAT / 4
BARS = 16
N = int(round(BARS * 4 * BEAT * SR))
TWO_PI = 2 * math.pi

here = os.path.dirname(os.path.abspath(__file__))
MUSIC = os.path.normpath(os.path.join(here, "..", "assets", "music"))


def pos(bar, step):
    """Sample index of a 16th step; identical rounding to generate_music.py."""
    return int((bar * 4 * BEAT + step * STEP) * SR)


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def finish(buf, peak):
    """Normalize to peak, tiny seam fades, return float list."""
    p = max(abs(x) for x in buf)
    g = peak / p
    out = [x * g for x in buf]
    fade = int(0.0005 * SR)
    for i in range(fade):
        w = i / fade
        out[i] *= w
        out[N - 1 - i] *= w
    out[0] = 0.0
    out[-1] = 0.0
    return out


def write_wav(name, data):
    path = os.path.join(MUSIC, name)
    os.makedirs(MUSIC, exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in data))
    print("wrote", path)


def circ_filter(buf, fn):
    """Run a stateful filter over buf twice (circular) and return the 2nd pass."""
    state = fn(None)
    out = [0.0] * N
    for rep in range(2):
        for i in range(N):
            y = state(buf[i])
            if rep:
                out[i] = y
    return out


def onepole_lp(fc):
    a = 1 - math.exp(-TWO_PI * fc / SR)

    def make(_):
        s = [0.0]

        def f(x):
            s[0] += a * (x - s[0])
            return s[0]
        return f
    return make


def onepole_hp(fc):
    a = 1 - math.exp(-TWO_PI * fc / SR)

    def make(_):
        s = [0.0]

        def f(x):
            s[0] += a * (x - s[0])
            return x - s[0]
        return f
    return make


# ---------------------------------------------------------------- DRUMS
def render_drums():
    rnd = random.Random(1234)
    buf = [0.0] * N

    def add(i, v):
        buf[i % N] += v

    def vel(v):
        return v * (1 + rnd.uniform(-0.09, 0.09))

    def kick(i0, v):
        L = int(0.30 * SR)
        ph = 0.0
        for k in range(L):
            t = k / SR
            f = 45 + 78 * math.exp(-t * 45)
            ph += f / SR
            env = math.exp(-t * 11) * min(1.0, k / 20)
            s = math.sin(TWO_PI * ph) * env
            if k < 80:  # beater click
                s += 0.35 * rnd.uniform(-1, 1) * (1 - k / 80) ** 2
            add(i0 + k, v * s)

    def snare(i0, v):
        L = int(0.25 * SR)
        prev = 0.0
        ph = 0.0
        for k in range(L):
            t = k / SR
            n = rnd.uniform(-1, 1)
            hp = n - 0.55 * prev  # slight high tilt
            prev = n
            body = math.sin(TWO_PI * 190 * t) * math.exp(-t * 38)
            noise = hp * math.exp(-t * 20)
            snap = (rnd.uniform(-1, 1) * (1 - k / 60) if k < 60 else 0.0)
            add(i0 + k, v * (0.75 * noise + 0.7 * body + 0.3 * snap))

    def hat(i0, v, length, decay):
        L = int(length * SR)
        p1 = p2 = 0.0
        for k in range(L):
            t = k / SR
            n = rnd.uniform(-1, 1)
            h1 = n - p1
            p1 = n
            h2 = h1 - p2
            p2 = h1
            add(i0 + k, v * 0.45 * h2 * math.exp(-t * decay))

    def tom(i0, v, f0):
        L = int(0.32 * SR)
        ph = 0.0
        for k in range(L):
            t = k / SR
            f = f0 * (0.78 + 0.22 * math.exp(-t * 18))
            ph += f / SR
            env = math.exp(-t * 11) * min(1.0, k / 15)
            s = math.sin(TWO_PI * ph) + 0.25 * math.sin(TWO_PI * 2.1 * ph) * math.exp(-t * 40)
            if k < 60:
                s += 0.3 * rnd.uniform(-1, 1) * (1 - k / 60)
            add(i0 + k, v * 0.9 * env * s)

    def crash(i0, v):
        L = int(2.0 * SR)
        p1 = p2 = 0.0
        for k in range(L):
            t = k / SR
            n = rnd.uniform(-1, 1)
            h1 = n - p1
            p1 = n
            h2 = h1 - 0.5 * p2
            p2 = h1
            # shimmer: bright noise with some metallic ring
            ring = 0.25 * math.sin(TWO_PI * 3300 * t) * math.sin(TWO_PI * 4710 * t)
            env = (0.65 * math.exp(-t * 2.6) + 0.35 * math.exp(-t * 9))
            add(i0 + k, v * 0.3 * (h2 + ring) * env * min(1.0, k / 30))

    TOMS = [190, 150, 110]

    for bar in range(BARS):
        late = bar >= 8
        fill_bar = bar % 4 == 3
        last = bar == 15
        # crash on first beat of each 4-bar phrase
        if bar % 4 == 0:
            crash(pos(bar, 0), vel(0.55))

        # kicks (steps)
        kicks = {0: 1.0, 10: 0.9}
        if bar % 2 == 1:
            kicks[6] = 0.8          # 'and of 2'
        if late:
            kicks[3] = 0.7
            if bar % 2 == 0:
                kicks[7] = 0.7
            kicks[14 if not fill_bar else 8] = 0.75
        if fill_bar:
            kicks.pop(10, None)
            kicks.pop(6, None)
        if last:
            kicks = {0: 1.0, 3: 0.7, 6: 0.85, 8: 0.9, 10: 0.8, 14: 1.0, 15: 0.95}
        for s, v in kicks.items():
            kick(pos(bar, s), vel(0.9 * v))

        # snares: 2 and 4, locked to theme's backbeat (steps 4 and 12)
        if last:
            snare(pos(bar, 4), vel(0.95))
            # roll from step 8 to 15 (16ths, crescendo)
            for j, s in enumerate(range(9, 16)):
                if s in (14, 15):
                    continue
                snare(pos(bar, s), vel(0.45 + 0.07 * j))
            snare(pos(bar, 13), vel(0.85))
            snare(pos(bar, 12), vel(0.9))
        else:
            snare(pos(bar, 4), vel(0.95))
            if not fill_bar:
                snare(pos(bar, 12), vel(0.95))
            if late and bar % 2 == 1 and not fill_bar:
                snare(pos(bar, 15), vel(0.28))   # ghost note
            if bar >= 4 and bar % 2 == 0 and not fill_bar:
                snare(pos(bar, 7), vel(0.22))    # ghost

        # tom fill: 3 descending toms (high, mid, low) + snare accents
        if fill_bar:
            tom(pos(bar, 12), vel(0.95), TOMS[0])
            tom(pos(bar, 13), vel(0.85), TOMS[0])
            tom(pos(bar, 14), vel(0.95), TOMS[1])
            tom(pos(bar, 15), vel(1.0), TOMS[2])
            if bar in (7, 11):
                tom(pos(bar, 11), vel(0.8), TOMS[0])

        # hats
        for s in range(16):
            if fill_bar and s >= 12:
                continue
            if last and s >= 8:
                continue
            accent = 1.0 if s % 4 == 0 else (0.75 if s % 2 == 0 else 0.5)
            if not late:
                if s % 2:
                    continue          # straight 8ths in the first half
                accent = 1.0 if s % 4 == 0 else 0.75
            else:
                # open hats on the 'and' of beats 2 and 4 (steps 6/14) / step 10
                if s in (2, 10) and bar % 2 == 0 and s == 10:
                    hat(pos(bar, s), vel(0.55), 0.28, 11)
                    continue
                if s == 14:
                    hat(pos(bar, s), vel(0.55), 0.30, 10)
                    continue
                if s == 6 and bar % 2 == 1:
                    hat(pos(bar, s), vel(0.5), 0.22, 13)
                    continue
            hat(pos(bar, s), vel(0.5 * accent), 0.05, 75)
    return finish(buf, 0.55)


# ---------------------------------------------------------------- METAL (v2)
# Plucked-string (Karplus-Strong) power chords, double-tracked, through a
# tight-screamer -> 3 asymmetric clipping stages -> 4x12-style cab -> compressor.
A1, F1, C2, G1 = 33, 29, 36, 31
progression = [A1, F1, C2, G1] * 2 + [F1, G1, C2, A1] + [F1, G1, A1, G1]
NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

# 16-step rhythm strings. A=open power chord (ring, '-' extends), C=accented chug,
# c=palm-muted chug, b=b2 dyad (A-Bb-A flavour), t=tritone dyad, d=leading tone below,
# '.'=gate closed (silence).
PATS = {
    0: "A-.ccb.cC.cc.cc.",
    1: "A-.ccc.cC.ccc.c.",
    2: "A-.ccc.cC.cc.cc.",
    3: "A-.ccc.cC.c.C...",
    8: "A-ccCcccC-ccCccc",
    9: "A-ccCccbC-ccCcc.",
    10: "A-ccCcccC-ccCcc.",
    11: "A-ccCcctC-ccC...",
}
# melodic riff lines (A natural minor; short chromatic passing notes on weak 16ths):
# (step, len, midi)
MEL = {
    4: [(2, 1, 36), (3, 1, 38), (4, 2, 40), (6, 2, 38), (8, 1, 36), (9, 1, 34), (10, 1, 33),
        (11, 1, 36), (12, 2, 40), (14, 2, 38)],
    5: [(2, 1, 33), (3, 1, 36), (4, 2, 33), (6, 2, 31), (8, 2, 29), (10, 1, 33), (11, 1, 36),
        (12, 2, 41), (14, 2, 36)],
    6: [(2, 1, 40), (3, 1, 43), (4, 2, 40), (6, 2, 38), (8, 2, 36), (10, 1, 31), (11, 1, 36),
        (12, 2, 43), (14, 2, 40)],
    7: [(8, 1, 38), (9, 1, 37), (10, 1, 36), (11, 1, 35)],
    12: [(4, 2, 33), (6, 1, 36), (7, 1, 38), (8, 2, 41), (10, 2, 36), (12, 2, 33), (14, 2, 29)],
    13: [(4, 2, 35), (6, 1, 38), (7, 1, 40), (8, 2, 43), (10, 2, 38), (12, 2, 35), (14, 2, 31)],
    14: [(4, 2, 36), (6, 1, 40), (7, 1, 43), (8, 2, 45), (10, 2, 43), (12, 1, 40), (13, 1, 39),
         (14, 1, 38), (15, 1, 35)],
    15: [(8, 2, 35), (10, 2, 38)],
}
TREMOLO_BARS = (7, 15)     # siren-like tremolo-picked D4 on beats 2 (steps 4-7)
DISS_BARS = (12, 13, 14, 15)  # held chord: b2 minor-second clash resolving to the fifth


def bq(kind, f0, q=0.707, gdb=0.0):
    w = TWO_PI * f0 / SR
    cw, sw = math.cos(w), math.sin(w)
    al = sw / (2 * q)
    A = 10 ** (gdb / 40)
    if kind == "lp":
        b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = b0
        a0 = 1 + al; a1 = -2 * cw; a2 = 1 - al
    elif kind == "hp":
        b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = b0
        a0 = 1 + al; a1 = -2 * cw; a2 = 1 - al
    else:  # peaking
        b0 = 1 + al * A; b1 = -2 * cw; b2 = 1 - al * A
        a0 = 1 + al / A; a1 = -2 * cw; a2 = 1 - al / A
    return (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)


def run_bq(x, c, warm=int(0.6 * SR)):
    """Biquad over a circular buffer (state warmed up on the buffer's tail)."""
    b0, b1, b2, a1, a2 = c
    x1 = x2 = y1 = y2 = 0.0
    for v in x[-warm:]:
        y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = v; y2 = y1; y1 = y
    out = [0.0] * len(x)
    for i, v in enumerate(x):
        y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = v; y2 = y1; y1 = y
        out[i] = y
    return out


def clip_stage(x, gain, bias):
    """Asymmetric tanh clipper, 2x oversampled (midpoint + averaging)."""
    th = math.tanh
    tb = th(bias)
    out = [0.0] * len(x)
    prev = x[-1]
    for i, v in enumerate(x):
        out[i] = 0.5 * (th(gain * 0.5 * (prev + v) + bias) + th(gain * v + bias)) - tb
        prev = v
    return out


def compress(x, thr, ratio, att=0.0015, rel=0.08):
    aa = 1 - math.exp(-1 / (att * SR))
    ar = 1 - math.exp(-1 / (rel * SR))
    e = 0.0
    out = [0.0] * len(x)
    for rep in range(2):
        seq = x[-int(0.5 * SR):] if rep == 0 else x
        for i, v in enumerate(seq):
            a = abs(v)
            e += (aa if a > e else ar) * (a - e)
            g = 1.0 if e <= thr else (thr + (e - thr) / ratio) / e
            if rep:
                out[i] = v * g
    return out


def render_metal():
    takes = [random.Random(11), random.Random(12)]   # two separate double-tracked takes
    noise = random.Random(5)
    dry = [0.0] * N
    sub = [0.0] * N

    def ks(rng, i0, midi, dur, t60, vel, rel):
        f = hz(midi) * 2 ** (rng.uniform(-4, 4) / 1200)
        P = SR / f
        L = int(P - 1.0)
        d = P - 0.5 - L
        C = (1 - d) / (1 + d)
        g = 10 ** (-3.0 * (P / SR) / t60)
        e = [rng.uniform(-1, 1) for _ in range(L)]
        for i in range(1, L):                      # soften the pick excitation
            e[i] = 0.6 * e[i] + 0.4 * e[i - 1]
        p = max(1, int(L * rng.uniform(0.12, 0.22)))   # pick position comb
        e = [e[i] - (0.9 * e[i - p] if i >= p else 0.0) for i in range(L)]
        mean = sum(e) / L
        e = [v - mean for v in e]
        pk = max(abs(v) for v in e) or 1.0
        sc = vel / pk
        e = [v * sc for v in e]
        n = int((dur + rel) * SR)
        nd = int(dur * SR)
        nr = max(1, int(rel * SR))
        idx = 0
        x1 = y1 = 0.0
        for k in range(n):
            s = e[idx]
            nx = e[idx + 1] if idx + 1 < L else e[0]
            a = 0.5 * (s + nx)
            ap = C * a + x1 - C * y1
            x1 = a
            y1 = ap
            e[idx] = g * ap
            idx += 1
            if idx == L:
                idx = 0
            env = 1.0 if k < nd else 1.0 - (k - nd) / nr
            dry[(i0 + k) % N] += s * env
        for k in range(50):                          # pick click
            dry[(i0 + k) % N] += vel * 0.3 * rng.uniform(-1, 1) * (1 - k / 50) ** 2
        return n

    def sub_note(i0, midi, dur, vel):
        f = hz(midi)
        rel = 0.012
        n = int((dur + rel) * SR)
        for k in range(n):
            t = k / SR
            env = min(1.0, k / 50) * (1.0 if t < dur else max(0.0, 1 - (t - dur) / rel))
            s = math.sin(TWO_PI * f * t) + 0.35 * math.sin(TWO_PI * 2 * f * t)
            sub[(i0 + k) % N] += vel * env * s

    def play(bar, step, dur_steps, midis, gains, t60, rel, vel, strum, sub_v=1.0, fixed_dur=None):
        base = pos(bar, step)
        dur = fixed_dur if fixed_dur else dur_steps * STEP
        for rng in takes:
            jit = int(rng.uniform(-1.2, 1.2) * SR / 1000)
            for j, (m, gn) in enumerate(zip(midis, gains)):
                o = int(j * rng.uniform(*strum) * SR / 1000) + (jit if j == 0 else jit)
                ks(rng, base + o, m, dur, t60, vel * gn * rng.uniform(0.92, 1.08) * 0.5, rel)
        sub_note(base, midis[0], dur, 0.5 * vel * sub_v)
        if t60 < 0.5 and rel < 0.02 and noise.random() < 0.35:   # palm-mute release squeak
            e0 = base + int(dur * SR)
            for k in range(70):
                dry[(e0 + k) % N] += 0.05 * vel * noise.uniform(-1, 1) * (1 - k / 70)

    def squeal(i0, dur, m1, m2, vol, bend_t=0.25):
        n = int(dur * SR)
        ph = 0.0
        for k in range(n):
            t = k / SR
            u = min(1.0, t / (dur * bend_t))
            m = m1 + (m2 - m1) * u * u * (3 - 2 * u)
            f = hz(m) * (1 + 0.006 * math.sin(TWO_PI * 5.7 * t) * min(1.0, t * 3))
            ph += f / SR
            env = min(1.0, k / 300) * math.exp(-1.0 * t) * (1 if n - k > 400 else (n - k) / 400)
            s = math.sin(TWO_PI * ph) + 0.6 * math.sin(TWO_PI * 2 * ph) + 0.3 * math.sin(TWO_PI * 3 * ph)
            dry[(i0 + k) % N] += vol * s * env

    def dive(i0, n, m1, m2, vol):
        ph = 0.0
        for k in range(n):
            u = k / n
            m = m1 + (m2 - m1) * u ** 0.8
            ph += hz(m) / SR
            env = (u ** 1.6) * (1.0 if n - k > 180 else (n - k) / 180)
            s = math.sin(TWO_PI * ph) + 0.5 * math.sin(TWO_PI * 2 * ph) + 0.25 * math.sin(TWO_PI * 3 * ph)
            dry[(i0 + k) % N] += vol * s * env

    for bar in range(BARS):
        r = progression[bar]
        if bar in PATS:
            pat = PATS[bar]
            assert len(pat) == 16, (bar, len(pat))
            i = 0
            while i < 16:
                ch = pat[i]
                if ch in ".-":
                    i += 1
                    continue
                j = i + 1
                while j < 16 and pat[j] == "-":
                    j += 1
                ln = j - i
                if ch == "A":
                    play(bar, i, ln, [r, r + 7, r + 12], [1.0, 0.85, 0.6], 1.6, 0.09, 1.0,
                         (3, 7), 1.2, fixed_dur=ln * STEP * 0.97)
                elif ch == "C":
                    play(bar, i, ln, [r, r + 7, r + 12], [1.0, 0.8, 0.4], 0.35, 0.012, 0.95,
                         (0.5, 1.5), 1.1, fixed_dur=ln * STEP * 0.85)
                elif ch == "c":
                    play(bar, i, 1, [r, r + 7], [1.0, 0.7], 0.22, 0.010, 0.72, (0.5, 1.5),
                         1.0, fixed_dur=STEP * 0.72)
                elif ch == "t":
                    play(bar, i, 1, [r + 6, r + 12], [1.0, 0.7], 0.22, 0.010, 0.62, (0.5, 1.5),
                         0.9, fixed_dur=STEP * 0.62)
                elif ch in "bd":
                    o = 1 if ch == "b" else -1
                    play(bar, i, 1, [r + o, r + o + 7], [1.0, 0.7], 0.22, 0.010, 0.62,
                         (0.5, 1.5), 0.9, fixed_dur=STEP * 0.62)
                i = j
        else:
            # melodic bar: downbeat chord stab
            if bar in DISS_BARS:
                play(bar, 0, 2, [r, r + 1, r + 12], [1.0, 0.7, 0.6], 1.8, 0.03, 1.0, (3, 7),
                     1.2, fixed_dur=2 * STEP * 0.97)          # minor-second clash ...
                play(bar, 2, 2, [r, r + 7, r + 12], [1.0, 0.9, 0.6], 1.8, 0.09, 0.95, (3, 7),
                     1.2, fixed_dur=2 * STEP * 0.97)          # ... resolving to the fifth
            elif bar == 7:
                play(bar, 0, 4, [r, r + 7, r + 12], [1.0, 0.85, 0.6], 1.6, 0.09, 1.0, (3, 7),
                     1.2, fixed_dur=4 * STEP * 0.97)
            else:
                play(bar, 0, 2, [r, r + 7, r + 12], [1.0, 0.85, 0.6], 1.6, 0.09, 1.0, (3, 7),
                     1.2, fixed_dur=2 * STEP * 0.97)
            for st, ln, m in MEL.get(bar, []):
                if ln == 1:
                    play(bar, st, 1, [m, m + 12], [1.0, 0.5], 0.3, 0.012, 0.85, (0.5, 1.0),
                         1.0, fixed_dur=STEP * 0.78)
                else:
                    play(bar, st, ln, [m, m + 12], [1.0, 0.5], 0.9, 0.03, 0.9, (0.5, 1.0),
                         1.0, fixed_dur=ln * STEP * 0.92)
        if bar in TREMOLO_BARS:
            h = int(STEP * SR / 2)
            for j in range(8):                      # 32nd-note tremolo picking, D4
                i0 = pos(bar, 4) + j * h
                for rng in takes:
                    ks(rng, i0 + int(rng.uniform(-8, 8)), 62, 0.040, 0.25,
                       0.40 * rng.uniform(0.9, 1.1), 0.006)

    squeal(pos(7, 12), 0.55, 59, 62, 0.45)       # G chord: pinch/bend squeal up to D
    squeal(pos(11, 12), 0.55, 62, 64, 0.40)      # Am chord: bend up to E
    dive(pos(15, 12), pos(16, 0) - pos(15, 12) - 1, 74, 38, 0.5)   # feedback swell + dive-bomb

    pk = max(abs(v) for v in dry) or 1.0
    x = [v / pk for v in dry]

    # --- amp: tight screamer pre-boost, then 3 clipping stages with filtering between
    x = run_bq(x, bq("hp", 170, 0.7))
    x = run_bq(x, bq("pk", 800, 0.9, 5.0))
    x = run_bq(x, bq("lp", 6000, 0.7))
    x = clip_stage(x, 14.0, 0.15)
    x = run_bq(x, bq("hp", 110, 0.7))
    x = run_bq(x, bq("lp", 5500, 0.7))
    x = clip_stage(x, 5.0, 0.10)
    x = run_bq(x, bq("lp", 5000, 0.7))
    x = clip_stage(x, 2.0, 0.0)
    # --- 4x12 cab: low cut, 120 Hz bump, 500 Hz scoop, presence, steep top roll-off, short IR
    x = run_bq(x, bq("hp", 80, 0.8))
    x = run_bq(x, bq("pk", 120, 1.2, 5.0))
    x = run_bq(x, bq("pk", 500, 0.8, -7.0))
    x = run_bq(x, bq("pk", 3000, 1.2, 5.0))
    x = run_bq(x, bq("lp", 5500, 0.707))
    x = run_bq(x, bq("lp", 5500, 0.707))
    x = [x[i] + 0.22 * x[i - 29] - 0.12 * x[i - 41] for i in range(N)]
    pk = max(abs(v) for v in x) or 1.0
    # --- sub reinforcement (quiet sine+2nd harmonic on the chord roots), then glue compressor
    spk = max(abs(v) for v in sub) or 1.0
    y = [a / pk + 0.30 * b / spk for a, b in zip(x, sub)]
    y = compress(y, 0.18, 6.0)
    srt = sorted(abs(v) for v in y[::7])
    ref = srt[int(len(srt) * 0.995)] or 1.0
    y = [math.tanh(1.1 * v * 0.5 / ref) for v in y]
    return finish(y, 0.50)


# ---------------------------------------------------------------- CHECKS
def read_wav(path):
    with wave.open(path, "rb") as w:
        assert w.getnchannels() == 1 and w.getsampwidth() == 2 and w.getframerate() == SR
        raw = w.readframes(w.getnframes())
    return [v / 32768.0 for v in struct.unpack("<%dh" % (len(raw) // 2), raw)]


def goertzel(seg, f):
    w = TWO_PI * f / SR
    c = 2 * math.cos(w)
    s1 = s2 = 0.0
    for v in seg:
        s0 = v + c * s1 - s2
        s2 = s1
        s1 = s0
    return math.sqrt(max(0.0, s1 * s1 + s2 * s2 - c * s1 * s2))


def pitch(seg):
    """Harmonic-product style root estimate over midi 28..44; returns (midi, f)."""
    n = len(seg)
    seg = [v * (0.5 - 0.5 * math.cos(TWO_PI * i / (n - 1))) for i, v in enumerate(seg)]
    best = None
    for midi in range(28, 45):
        f = hz(midi)
        sc = 1.0
        for h in (1, 2, 3, 4):
            sc *= goertzel(seg, f * h) + 1e-9
        if best is None or sc > best[0]:
            best = (sc, midi)
    return best[1], hz(best[1])


def fft(a):
    n = len(a)
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j ^= bit
        if i < j:
            a[i], a[j] = a[j], a[i]
    ln = 2
    while ln <= n:
        wl = complex(math.cos(TWO_PI / ln), -math.sin(TWO_PI / ln))
        for i in range(0, n, ln):
            w = 1 + 0j
            for k in range(ln // 2):
                u = a[i + k]
                v = a[i + k + ln // 2] * w
                a[i + k] = u + v
                a[i + k + ln // 2] = u - v
                w *= wl
        ln <<= 1
    return a


def band_report(sig):
    W = 8192
    ps = [0.0] * (W // 2)
    cnt = 0
    for st in range(0, N - W, (N - W) // 12):
        seg = [sig[st + i] * (0.5 - 0.5 * math.cos(TWO_PI * i / (W - 1))) for i in range(W)]
        sp = fft([complex(v) for v in seg])
        for k in range(W // 2):
            ps[k] += abs(sp[k]) ** 2
        cnt += 1
    tot = sum(ps)
    df = SR / W
    bands = [(0, 80), (80, 5000), (5000, 7000), (7000, SR / 2)]
    res = []
    for lo, hi in bands:
        res.append(sum(ps[k] for k in range(W // 2) if lo <= k * df < hi) / tot)
    print("spectrum share  <80Hz %.1f%%  80-5k %.1f%%  5-7k %.1f%%  >7k %.1f%%" % tuple(100 * r for r in res))


def main():
    try:
        old = read_wav(os.path.join(MUSIC, "metal.wav"))
        print("previous metal.wav rms %.4f peak %.3f" % (
            math.sqrt(sum(v * v for v in old) / len(old)), max(abs(v) for v in old)))
    except Exception:
        pass
    drums = render_drums()
    metal = render_metal()
    write_wav("drums.wav", drums)
    write_wav("metal.wav", metal)

    theme = read_wav(os.path.join(MUSIC, "theme.wav"))
    d = read_wav(os.path.join(MUSIC, "drums.wav"))
    m = read_wav(os.path.join(MUSIC, "metal.wav"))
    print("samples theme/drums/metal:", len(theme), len(d), len(m), "equal:", len(theme) == len(d) == len(m))
    for nm, s in (("theme", theme), ("drums", d), ("metal", m)):
        print("%s peak %.3f rms %.3f first %.4f last %.4f" % (
            nm, max(abs(v) for v in s), math.sqrt(sum(v * v for v in s) / len(s)), s[0], s[-1]))
    mix = [a + b + c for a, b, c in zip(theme, d, m)]
    pk = max(abs(v) for v in mix)
    over = sum(1 for v in mix if abs(v) > 0.95)
    print("MIX peak %.3f, rms %.3f, mean|x| %.3f, samples>0.95: %d" % (
        pk, math.sqrt(sum(v * v for v in mix) / len(mix)), sum(abs(v) for v in mix) / len(mix), over))

    # riff vs progression: pitch at first note of each bar (0.2 s window after attack)
    ok = 0
    for bar in range(BARS):
        i0 = pos(bar, 0) + int(0.03 * SR)
        midi, f = pitch(m[i0:i0 + int(0.2 * SR)])
        want = progression[bar]
        # accept root or octave
        good = (midi - want) % 12 == 0
        ok += good
        print("bar %2d want %-2s (%5.1f Hz) got %-2s (%5.1f Hz) %s" % (
            bar + 1, NAMES[want % 12], hz(want), NAMES[midi % 12], f, "OK" if good else "??"))
    print("root match: %d/16" % ok)
    band_report(m)


if __name__ == "__main__":
    main()
