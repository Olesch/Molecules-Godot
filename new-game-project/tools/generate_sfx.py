import wave, struct, math, random, os

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")
os.makedirs(OUT, exist_ok=True)


def buf(dur):
    return [0.0] * int(SR * dur)


def tri(p):
    return 2.0 * abs(2.0 * (p - math.floor(p + 0.5))) - 1.0


def add_tone(b, start, dur, freq, amp, decay, wave_fn="sine", vib=0.0, vib_hz=5.5, f_end=None):
    n0 = int(start * SR)
    n = int(dur * SR)
    phase = 0.0
    for i in range(n):
        if n0 + i >= len(b):
            break
        t = i / SR
        f = freq if f_end is None else freq * (f_end / freq) ** (min(1.0, t / dur))
        if vib:
            f *= 1.0 + vib * math.sin(2 * math.pi * vib_hz * t)
        phase += f / SR
        if wave_fn == "sine":
            s = math.sin(2 * math.pi * phase)
        elif wave_fn == "tri":
            s = tri(phase)
        else:
            s = 1.0 if (phase % 1.0) < 0.5 else -1.0
        b[n0 + i] += s * amp * math.exp(-decay * t)


def finish(name, b, fade_out=0.02):
    fi = int(0.003 * SR)
    fo = int(fade_out * SR)
    for i in range(min(fi, len(b))):
        b[i] *= i / fi
    for i in range(min(fo, len(b))):
        b[-1 - i] *= i / fo
    b[-1] = 0.0
    pk = max(abs(x) for x in b) or 1.0
    b = [x * 0.8 / pk for x in b]
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", max(-32767, min(32767, int(round(x * 32767))))) for x in b))


def place():
    random.seed(1)
    b = buf(0.12)
    add_tone(b, 0, 0.12, 220, 1.0, 28, "sine", f_end=110)
    for i in range(int(0.006 * SR)):
        b[i] += (random.random() * 2 - 1) * 0.35 * math.exp(-i / SR * 700)
    finish("place.wav", b, 0.03)


def rotate():
    b = buf(0.07)
    add_tone(b, 0, 0.07, 900, 1.0, 60, "sine")
    add_tone(b, 0, 0.07, 1800, 0.2, 80, "sine")
    finish("rotate.wav", b, 0.02)


def clear():
    random.seed(2)
    b = buf(0.6)
    for k, f in enumerate([523.25, 659.25, 783.99, 1046.5]):
        st = k * 0.08
        add_tone(b, st, 0.6 - st, f, 0.6, 7, "tri")
        add_tone(b, st, 0.6 - st, f * 2, 0.12, 9, "sine")
        add_tone(b, st + 0.012, 0.6 - st - 0.012, f * 1.004, 0.25, 6, "sine")
    # reverb-like echoes
    for d, g in [(0.045, 0.35), (0.09, 0.22), (0.14, 0.14)]:
        o = int(d * SR)
        src = b[:]
        for i in range(len(b) - o):
            b[i + o] += src[i] * g
    finish("clear.wav", b, 0.15)


def lose():
    b = buf(1.0)
    for k, f in enumerate([392.0, 311.13, 261.63, 130.81]):
        st = k * 0.2
        add_tone(b, st, 1.0 - st, f, 0.8, 3.5, "tri", vib=0.012)
        add_tone(b, st, 1.0 - st, f / 2, 0.25, 4, "sine", vib=0.012)
    finish("lose.wav", b, 0.25)


def invalid():
    b = buf(0.1)
    add_tone(b, 0, 0.1, 120, 0.5, 20, "square")
    add_tone(b, 0, 0.1, 60, 0.3, 20, "sine")
    # soften the square edges with a one-pole low-pass
    y = 0.0
    for i in range(len(b)):
        y += 0.15 * (b[i] - y)
        b[i] = y
    finish("invalid.wav", b, 0.03)


def explode():
    rng = random.Random(3)  # separate instance: leaves other sounds untouched
    b = buf(0.8)
    # low sub thump: sine sweeping 90 -> 35 Hz, fast attack, ~0.5s decay
    add_tone(b, 0, 0.8, 90, 1.0, 6, "sine", f_end=35)
    # noise burst through a one-pole low-pass with falling cutoff
    y = 0.0
    n = len(b)
    for i in range(n):
        t = i / SR
        fc = 150.0 + 7000.0 * math.exp(-t * 14)
        a = 1.0 - math.exp(-2 * math.pi * fc / SR)
        y += a * ((rng.random() * 2 - 1) - y)
        b[i] += y * 1.6 * math.exp(-t * 5)
    # saturation for punch
    b = [math.tanh(1.8 * x) for x in b]
    finish("explode.wav", b, 0.2)


for f in (place, rotate, clear, lose, invalid, explode):
    f()

for n in ("place", "rotate", "clear", "lose", "invalid", "explode"):
    with wave.open(os.path.join(OUT, n + ".wav")) as w:
        fr = w.readframes(w.getnframes())
        s = struct.unpack("<%dh" % w.getnframes(), fr)
        pk = max(abs(x) for x in s)
        print(n, w.getframerate(), w.getnchannels(), w.getsampwidth() * 8, "dur=%.3f" % (w.getnframes() / w.getframerate()),
              "peak=%.3f" % (pk / 32768), "clip=" + str(pk >= 32767))
