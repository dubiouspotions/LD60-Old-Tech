"""Writes placeholder sound effects and a march loop as 16-bit mono WAV into audio/.

Stdlib only. Run from the Godot folder:  python -I dev/synth_placeholder_audio.py [--no-music] [--only-night]
Designers replace these files (or point the SoundEffect resources at new ones).
"""
import math
import os
import random
import struct
import sys
import wave

RATE = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
rng = random.Random(60)


def write(path, samples):
    path = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = 0.89 / peak if peak > 0.89 else 1.0
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))


def n(sec):
    return int(sec * RATE)


def env(i, total, attack=0.005, curve=3.0):
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    return a * (1 - i / total) ** curve


def noise_burst(sec, lp=0.2, curve=3.0, attack=0.002):
    out, y, total = [], 0.0, n(sec)
    for i in range(total):
        y += lp * (rng.uniform(-1, 1) - y)
        out.append(y * env(i, total, attack, curve))
    return out


def tone(freq, sec, curve=2.0, wave_fn=math.sin, sweep=0.0, attack=0.004):
    out, ph, total = [], 0.0, n(sec)
    for i in range(total):
        f = freq * (1 + sweep * i / total)
        ph += 2 * math.pi * f / RATE
        out.append(wave_fn(ph) * env(i, total, attack, curve))
    return out


def mix(*tracks):
    length = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(length)]


def gain(t, g):
    return [s * g for s in t]


def square(ph):
    return 1.0 if math.sin(ph) >= 0 else -1.0


def tri(ph):
    return 2 / math.pi * math.asin(math.sin(ph))


def at(track, offset_sec, length):
    out = [0.0] * length
    o = n(offset_sec)
    for i, s in enumerate(track):
        if o + i < length:
            out[o + i] += s
    return out


def sfx():
    write("sfx/dig.wav", mix(noise_burst(0.12, 0.25, 4), gain(tone(90, 0.1, 4), 0.6)))
    write("sfx/fill_land.wav", mix(noise_burst(0.18, 0.08, 3), gain(tone(70, 0.16, 3, sweep=-0.3), 0.9)))
    write("sfx/log_place.wav", mix(gain(tone(220, 0.15, 6, tri), 0.8), gain(tone(330, 0.1, 8, tri), 0.4), gain(noise_burst(0.04, 0.6, 2), 0.3)))
    write("sfx/rope_place.wav", mix(gain(tone(180, 0.25, 2, tri, sweep=0.15), 0.6), gain(noise_burst(0.2, 0.05, 2), 0.3)))
    write("sfx/member_snap.wav", mix(noise_burst(0.22, 0.7, 5, 0.0005), gain(tone(140, 0.2, 5, sweep=-0.5), 0.5)))
    write("sfx/arrow_shot.wav", mix(gain(noise_burst(0.25, 0.35, 1.5, 0.05), 0.6), gain(tone(700, 0.08, 6, tri, sweep=-0.4), 0.2)))
    write("sfx/arrow_hit.wav", mix(gain(tone(260, 0.08, 6, tri), 0.7), gain(noise_burst(0.05, 0.5, 4), 0.4)))
    write("sfx/soldier_hurt.wav", gain(tone(320, 0.14, 2, tri, sweep=-0.35), 0.7))
    write("sfx/soldier_death.wav", mix(gain(tone(300, 0.4, 2, tri, sweep=-0.6), 0.7), gain(noise_burst(0.1, 0.3, 4), 0.3)))
    write("sfx/tree_fell.wav", mix(noise_burst(0.7, 0.12, 2, 0.02), gain(tone(110, 0.5, 3, tri, sweep=-0.3), 0.5)))
    write("sfx/crystal.wav", mix(gain(tone(1320, 0.5, 3), 0.4), gain(tone(1980, 0.4, 4), 0.25), gain(tone(2640, 0.3, 5), 0.15)))
    write("sfx/collapse.wav", mix(noise_burst(0.9, 0.05, 1.8, 0.03), gain(tone(48, 0.9, 2, sweep=-0.2), 0.7)))
    write("sfx/tower_down.wav", mix(noise_burst(1.0, 0.07, 2, 0.02), gain(tone(90, 0.7, 2, square, sweep=-0.5), 0.25)))
    fan = 0.12
    write("sfx/checkpoint.wav", mix(*[at(gain(tone(f, 0.35, 2, tri), 0.5), k * fan, n(0.8)) for k, f in enumerate([392, 523, 659, 784])]))
    write("sfx/lost.wav", mix(*[at(gain(tone(f, 0.5, 2, tri), 0.5), k * 0.28, n(1.5)) for k, f in enumerate([392, 349, 311, 262])]))
    write("sfx/victory.wav", mix(*[at(gain(tone(f, 0.5, 2, tri), 0.5), k * 0.15, n(1.6)) for k, f in enumerate([523, 659, 784, 1047, 784, 1047])]))
    write("sfx/ui_click.wav", gain(tone(1200, 0.03, 4, tri), 0.4))


def music():
    bpm = 112
    beat = 60 / bpm
    bars = 8
    length = n(bars * 4 * beat)
    tracks = []
    snare = noise_burst(0.12, 0.5, 4)
    kick = tone(60, 0.18, 4, sweep=-0.5)
    for b in range(bars * 4):
        tracks.append(at(gain(kick, 0.7), b * beat, length) if b % 2 == 0 else at(gain(snare, 0.35), b * beat, length))
        tracks.append(at(gain(snare, 0.12), (b + 0.75) * beat, length))
    # fife melody, A minor march
    notes = [440, 523, 587, 659, 587, 523, 494, 440,
             392, 440, 494, 523, 494, 440, 392, 330,
             440, 523, 587, 659, 784, 659, 587, 523,
             494, 523, 587, 494, 440, 0, 440, 0]
    for k, f in enumerate(notes):
        if f:
            tracks.append(at(gain(tone(f, beat * 0.9, 1.2, tri), 0.22), k * beat, length))
    bass = [110, 110, 98, 82, 110, 110, 98, 110]
    for k, f in enumerate(bass):
        for q in range(4):
            tracks.append(at(gain(tone(f, beat * 0.8, 2, square), 0.08), (k * 4 + q) * beat, length))
    write("music/march_loop.wav", mix(*tracks))


def night():
    """Camp: fire crackle loop, a quiet night tune, and the dawn bugle."""
    length = n(4.0)
    crackle = [x * 0.15 for x in noise_burst(4.0, 0.03, 0.0, 0.0)]
    tracks = [crackle]
    for _ in range(26):
        tracks.append(at(gain(noise_burst(0.03 + rng.random() * 0.05, 0.6, 6, 0.0005), 0.3 + rng.random() * 0.5), rng.random() * 3.9, length))
    write("sfx/campfire_loop.wav", mix(*tracks))
    beat = 0.75
    notes = [330, 392, 440, 392, 330, 294, 262, 294, 330, 392, 330, 294, 262, 0, 262, 0]
    length = n(len(notes) * beat)
    tracks = []
    for k, f in enumerate(notes):
        if f:
            tracks.append(at(gain(tone(f, beat * 1.4, 1.5, tri, attack=0.08), 0.18), k * beat, length))
    for k, f in enumerate([131, 110, 131, 98]):
        tracks.append(at(gain(tone(f, beat * 4, 1.0, math.sin, attack=0.3), 0.12), k * 4 * beat, length))
    write("music/night_loop.wav", mix(*tracks))
    write("sfx/dawn_bugle.wav", mix(*[at(gain(tone(f, d, 1.2, tri, attack=0.01), 0.5), t, n(1.8))
                                      for t, f, d in [(0, 392, 0.2), (0.22, 523, 0.2), (0.44, 659, 0.2), (0.66, 784, 0.9)]]))


if __name__ == "__main__":
    if "--only-night" in sys.argv:
        night()
        sys.exit()
    sfx()
    night()
    if "--no-music" not in sys.argv:
        music()
    print("wrote placeholder audio to", os.path.normpath(ROOT))
