"""Synthesise the placeholder sound set for Trickshot Range.

These are deliberately simple: a noise burst plus a body tone for the gun, short
tonal blips for feedback. They exist so movement and shooting can be TUNED with
audio in the loop, because feel is impossible to judge silently. Replace them
with recorded audio before shipping; nothing in the game depends on how they
were made.

Run from the project root:  python3 tools/make_sounds.py
"""
import math
import random
import struct
import wave

RATE = 44100


def write(name, samples):
    data = bytearray()
    for s in samples:
        v = int(max(-1.0, min(1.0, s)) * 32000)
        data += struct.pack("<h", v)
    with wave.open("audio/%s.wav" % name, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(bytes(data))
    print("audio/%s.wav  %d samples" % (name, len(samples)))


def env(i, n, attack=0.002, curve=3.0):
    """Fast attack, exponential decay."""
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * math.exp(-curve * (i / n) * 5.0)


def lowpass(samples, alpha):
    out, prev = [], 0.0
    for s in samples:
        prev += alpha * (s - prev)
        out.append(prev)
    return out


def gunshot():
    n = int(RATE * 0.30)
    noise = [random.uniform(-1.0, 1.0) for _ in range(n)]
    # Two filter passes give the crack a body instead of a hiss.
    body = lowpass(lowpass(noise, 0.35), 0.35)
    out = []
    for i in range(n):
        e = env(i, n, 0.0006, 4.2)
        t = i / RATE
        # Low thump that pitches down: the "weight" of the shot.
        thump = math.sin(2 * math.pi * (120.0 * math.exp(-t * 22.0) + 45.0) * t)
        out.append((body[i] * 0.85 + noise[i] * 0.25 + thump * 0.55) * e * 0.9)
    return out


def blip(freq_start, freq_end, seconds, curve=3.5, harmonic=0.0):
    n = int(RATE * seconds)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / n
        f = freq_start + (freq_end - freq_start) * t
        phase += 2 * math.pi * f / RATE
        v = math.sin(phase) + harmonic * math.sin(phase * 2.0)
        out.append(v * env(i, n, 0.001, curve) * 0.55)
    return out


def whoosh(seconds=0.7):
    n = int(RATE * seconds)
    noise = [random.uniform(-1.0, 1.0) for _ in range(n)]
    out = []
    prev = 0.0
    for i in range(n):
        t = i / n
        # Sweeping the filter cutoff is what makes noise read as motion.
        alpha = 0.02 + 0.30 * math.sin(math.pi * t)
        prev += alpha * (noise[i] - prev)
        shape = math.sin(math.pi * t) ** 1.5
        out.append(prev * shape * 0.8)
    return out


def thud(seconds=0.22):
    n = int(RATE * seconds)
    out = []
    for i in range(n):
        t = i / RATE
        f = 150.0 * math.exp(-t * 30.0) + 55.0
        v = math.sin(2 * math.pi * f * t) + random.uniform(-0.25, 0.25)
        out.append(v * env(i, n, 0.001, 4.5) * 0.8)
    return out


if __name__ == "__main__":
    random.seed(7)
    write("fire", gunshot())
    write("hit", blip(1500, 1900, 0.06, 6.0, 0.25))
    write("kill", blip(900, 1600, 0.16, 3.0, 0.4))
    write("jump", blip(420, 300, 0.07, 6.0))
    write("land", thud())
    write("slide", whoosh(0.5))
    write("dive", whoosh(0.9))
