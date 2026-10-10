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


# ---------------------------------------------------------------- METAL
A1, F1, C2, G1 = 33, 29, 36, 31
progression = [A1, F1, C2, G1] * 2 + [F1, G1, C2, A1] + [F1, G1, A1, G1]
NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

# chug rhythms: (step, kind, len_steps) kind: o=open ring, c=palm-muted chug
PAT_A = [(0, "o", 4), (4, "c", 1), (5, "c", 1), (6, "c", 1), (8, "c", 1), (10, "c", 1),
         (11, "c", 1), (12, "c", 1), (14, "c", 1)]
PAT_B = [(0, "o", 3), (3, "c", 1), (4, "c", 1), (6, "c", 1), (7, "c", 1), (8, "c", 1),
         (10, "c", 1), (11, "c", 1), (12, "c", 1), (13, "c", 1), (14, "c", 1), (15, "c", 1)]
PAT_GALLOP = [(0, "o", 2)] + [(s, "c", 1) for s in (2, 3, 4, 6, 7, 8, 10, 11, 12, 14, 15)]
PAT_FILL = [(0, "o", 4), (4, "c", 1), (6, "c", 1), (8, "c", 1), (10, "c", 1), (12, "c", 1)]
PAT_LAST = [(0, "o", 4), (4, "c", 1), (6, "c", 1), (8, "c", 1), (10, "c", 1), (12, "c", 1), (13, "c", 1)]

# melodic riff lines (bars 5-8, 13-16): (step, len, midi). A natural minor only.
MEL = {
    4: [(0, 2, 33), (2, 1, 36), (3, 1, 38), (4, 2, 40), (6, 2, 38), (8, 2, 36), (10, 1, 33),
        (11, 1, 36), (12, 2, 40), (14, 2, 38)],
    5: [(0, 2, 29), (2, 1, 33), (3, 1, 36), (4, 2, 33), (6, 2, 31), (8, 2, 29), (10, 1, 33),
        (11, 1, 36), (12, 2, 41), (14, 2, 36)],
    6: [(0, 2, 36), (2, 1, 40), (3, 1, 43), (4, 2, 40), (6, 2, 38), (8, 2, 36), (10, 1, 31),
        (11, 1, 36), (12, 2, 43), (14, 2, 40)],
    7: [(0, 2, 31), (2, 1, 35), (3, 1, 38), (4, 2, 35), (6, 2, 33), (8, 2, 31), (10, 1, 35),
        (11, 1, 38)],
    12: [(0, 2, 29), (2, 2, 36), (4, 2, 33), (6, 1, 36), (7, 1, 38), (8, 2, 41), (10, 2, 36),
         (12, 2, 33), (14, 2, 29)],
    13: [(0, 2, 31), (2, 2, 38), (4, 2, 35), (6, 1, 38), (7, 1, 40), (8, 2, 43), (10, 2, 38),
         (12, 2, 35), (14, 2, 31)],
    14: [(0, 2, 33), (2, 2, 40), (4, 2, 36), (6, 1, 40), (7, 1, 43), (8, 2, 45), (10, 2, 43),
         (12, 2, 40), (14, 2, 36)],
    15: [(0, 2, 31), (2, 1, 35), (3, 1, 38), (4, 2, 43), (6, 2, 38), (8, 2, 35), (10, 2, 38),
         (12, 2, 31)],
}


def render_metal():
    rnd = random.Random(99)
    buf = [0.0] * N

    def guitar(i0, dur, midis, vol, kind):
        """Distorted two-saw (+pulse) voice; midis = list of (midi, gain)."""
        n = int(dur * SR)
        decay = 22.0 if kind == "c" else (2.2 if kind == "o" else 4.0)
        ph = []
        for m, gn in midis:
            f = hz(m)
            ph.append([f, gn, rnd.random(), rnd.random(), rnd.random()])
        rel = int(0.004 * SR)
        for k in range(n):
            t = k / SR
            env = min(1.0, k / 25) * math.exp(-decay * t)
            if kind == "c":
                env *= 1.0 if k < n - rel else (n - k) / rel
            else:
                tl = n - k
                if tl < rel * 2:
                    env *= tl / (rel * 2)
            x = 0.0
            for p in ph:
                f = p[0]
                p[2] += f * 1.0025 / SR
                p[3] += f * 0.9972 / SR
                p[4] += f / SR
                saw1 = 2 * (p[2] % 1.0) - 1
                saw2 = 2 * (p[3] % 1.0) - 1
                pul = 1.0 if (p[4] % 1.0) < 0.3 else -1.0
                x += p[1] * (0.45 * saw1 + 0.45 * saw2 + 0.25 * pul)
            drive = 6.0 if kind == "c" else 5.0
            y = math.tanh(drive * x * (0.35 + 0.65 * env))
            y = max(-0.9, min(0.9, y * 1.15))
            buf[(i0 + k) % N] += vol * y * (env ** 0.35)

    def squeal(i0, dur, m_from, m_to, vol):
        n = int(dur * SR)
        ph = 0.0
        for k in range(n):
            t = k / SR
            u = min(1.0, t / (dur * 0.25))
            m = m_from + (m_to - m_from) * (u * u * (3 - 2 * u))
            f = hz(m) * (1 + 0.004 * math.sin(TWO_PI * 6 * t) * min(1, t * 3))
            ph += f / SR
            env = min(1.0, k / 200) * math.exp(-1.3 * t) * (1 if n - k > 300 else (n - k) / 300)
            s = math.sin(TWO_PI * ph) + 0.55 * math.sin(TWO_PI * 2 * ph) + 0.25 * math.sin(TWO_PI * 3 * ph)
            buf[(i0 + k) % N] += vol * math.tanh(2.2 * s * env) * env ** 0.3

    for bar in range(BARS):
        r = progression[bar]
        if bar in MEL:
            # melodic riff: single notes (+octave) -- plus power chord stab on beat 1
            for st, ln, m in MEL[bar]:
                dur = ln * STEP * 0.92
                kind = "c" if ln == 1 else "m"
                voices = [(m, 1.0), (m + 12, 0.45)]
                if st == 0:
                    voices = [(m, 1.0), (m + 7 if m % 12 in (9, 5, 0, 7) else m + 12, 0.7), (m + 12, 0.45)]
                guitar(pos(bar, st), dur, voices, 0.9, kind if ln > 1 else "c")
        else:
            if bar % 4 == 3:
                pat = PAT_LAST if bar == 11 else PAT_FILL
            elif bar >= 8:
                pat = PAT_GALLOP if bar % 2 == 0 else PAT_B
            else:
                pat = PAT_A if bar % 2 == 0 else PAT_B
            for st, kind, ln in pat:
                i0 = pos(bar, st)
                if kind == "o":
                    voices = [(r, 1.0), (r + 7, 0.8), (r + 12, 0.6)]
                    guitar(i0, ln * STEP * 0.97 + 0.1, voices, 1.0, "o")
                else:
                    voices = [(r, 1.0), (r + 7, 0.65)]
                    guitar(i0, STEP * 0.80, voices, 0.9 * (1 + rnd.uniform(-0.06, 0.06)), "c")
        # open accent on the downbeat for the melodic bars is in the stab above

    # pinch-harmonic / bend squeals (over chord tones)
    squeal(pos(7, 12), 0.5, 59, 62, 0.28)     # G chord: slide up to D
    squeal(pos(11, 12), 0.5, 62, 64, 0.26)    # Am chord: bend up to E

    # cabinet: high-pass ~70 Hz (x2), low-pass ~4.2 kHz (x3), low-mid body
    x = circ_filter(buf, onepole_hp(70))
    x = circ_filter(x, onepole_hp(70))
    low = circ_filter(x, onepole_lp(900))
    y = [a + 0.55 * b for a, b in zip(x, low)]
    for _ in range(3):
        y = circ_filter(y, onepole_lp(4200))
    return finish(y, 0.45)


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


def main():
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


if __name__ == "__main__":
    main()
