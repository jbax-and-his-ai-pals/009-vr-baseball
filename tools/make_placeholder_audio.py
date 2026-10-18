#!/usr/bin/env python3
"""Synthesize placeholder sounds for everything in audio/manifest.json.

Rough, honest stand-ins (a noise burst for a mitt pop, a pitched buzz for a voice) so every hook in
the game can be heard and tested before the real recordings exist. Real files replace them one at a
time: drop `audio/<dir>/<id>_NN.wav` (or .ogg) over the placeholder and nothing else changes.

    python tools/make_placeholder_audio.py            # P0 and P1
    python tools/make_placeholder_audio.py --all      # everything, including P2
    python tools/make_placeholder_audio.py --force    # overwrite files that already exist
    python tools/make_placeholder_audio.py glove_pop  # only ids containing this text

Standard library only. Mono 16-bit 22.05 kHz; long loops and music are cut short (this is a stand-in).
Never overwrites a file unless --force, so recorded replacements are safe. Files carrying the
marker below in their name are not used: placeholders are plain .wav, recordings may be .wav or .ogg
and the game prefers an .ogg when both exist.
"""
import json
import math
import os
import random
import struct
import sys
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 22050
TAU = math.pi * 2.0


# ------------------------------------------------------------------ small DSP toolbox
def n_of(sec):
    return max(1, int(sec * SR))


def noise(rng, n):
    return [rng.uniform(-1.0, 1.0) for _ in range(n)]


def lowpass(x, cutoff):
    a = 1.0 - math.exp(-TAU * cutoff / SR)
    y, s = [], 0.0
    for v in x:
        s += a * (v - s)
        y.append(s)
    return y


def highpass(x, cutoff):
    lp = lowpass(x, cutoff)
    return [v - l for v, l in zip(x, lp)]


def bandpass(x, lo, hi):
    return highpass(lowpass(x, hi), lo)


def env_exp(n, decay, attack=0.002):
    """Fast attack, exponential decay (decay in seconds to about -60 dB)."""
    a = max(1, int(attack * SR))
    out = []
    for i in range(n):
        up = min(1.0, i / a)
        out.append(up * math.exp(-6.9 * (i / SR) / max(decay, 0.001)))
    return out


def env_bell(n, peak=0.4):
    out = []
    for i in range(n):
        u = i / max(n - 1, 1)
        w = u / peak if u < peak else (1.0 - u) / (1.0 - peak)
        out.append(math.sin(w * math.pi / 2.0) ** 2)
    return out


def mul(x, e):
    return [a * b for a, b in zip(x, e)]


def add(*sigs):
    n = max(len(s) for s in sigs)
    out = [0.0] * n
    for s in sigs:
        for i, v in enumerate(s):
            out[i] += v
    return out


def scale(x, g):
    return [v * g for v in x]


def pad(x, n):
    return (x + [0.0] * n)[:n]


def tone(freq, n, sweep=0.0, shape="sin", phase=0.0):
    """freq in Hz, sweep = fractional change over the duration (-0.5 = falls by half)."""
    out, ph = [], phase
    for i in range(n):
        f = freq * (1.0 + sweep * i / n)
        ph += TAU * f / SR
        if shape == "sin":
            out.append(math.sin(ph))
        elif shape == "saw":
            out.append(((ph / TAU) % 1.0) * 2.0 - 1.0)
        elif shape == "square":
            out.append(1.0 if (ph / TAU) % 1.0 < 0.5 else -1.0)
        else:
            out.append(math.sin(ph))
    return out


def vowel(freq, n, rng, formants=((700, 1.0), (1220, 0.5), (2600, 0.25)), contour=0.0):
    """A buzzy voice: a pulse train with a few resonances, enough to be 'a person'."""
    src = tone(freq * (1.0 + rng.uniform(-0.04, 0.04)), n, sweep=contour, shape="saw")
    out = [0.0] * n
    for f, g in formants:
        out = add(out, scale(bandpass(src, f * 0.8, f * 1.25), g))
    return out


def fade_edges(x, ms=8):
    k = int(SR * ms / 1000.0)
    k = min(k, len(x) // 2)
    for i in range(k):
        g = i / k
        x[i] *= g
        x[-1 - i] *= g
    return x


def sparse_ticks(rng, n, count, decay_sec, lo, hi):
    """Random little clicks (rattles, clatter, ball in the seats)."""
    out = [0.0] * n
    for _ in range(count):
        at = rng.randrange(0, max(1, n - int(0.03 * SR)))
        burst = bandpass(noise(rng, int(0.02 * SR)), lo, hi)
        burst = mul(burst, env_exp(len(burst), 0.01))
        amp = rng.uniform(0.3, 1.0) * math.exp(-4.0 * at / max(n, 1) * (1.0 / max(decay_sec, 0.05)) * 0.4)
        for i, v in enumerate(burst):
            if at + i < n:
                out[at + i] += v * amp
    return out


# ------------------------------------------------------------------ recipes: (rng, seconds) -> samples
def r_pop(rng, sec, loud, bright):
    n = n_of(min(sec, 0.5))
    slap = mul(bandpass(noise(rng, n), 900, 5000 if bright else 3000), env_exp(n, 0.035))
    thump = mul(tone(rng.uniform(95, 150), n, sweep=-0.35), env_exp(n, 0.11))
    ring = mul(tone(rng.uniform(1400, 1900), n), env_exp(n, 0.08)) if bright else [0.0] * n
    return add(scale(slap, 1.0), scale(thump, 0.9), scale(ring, 0.18))


def r_thud(rng, sec, freq, soft):
    n = n_of(min(sec, 0.6))
    low = mul(tone(freq * rng.uniform(0.9, 1.1), n, sweep=-0.4), env_exp(n, 0.14))
    body = mul(lowpass(noise(rng, n), 600 if soft else 1500), env_exp(n, 0.06))
    return add(low, scale(body, 0.7))


def r_whoosh(rng, sec, lo, hi):
    n = n_of(min(sec, 1.0))
    x = bandpass(noise(rng, n), lo, hi)
    return mul(x, env_bell(n, 0.55))


def r_crack(rng, sec, base):
    n = n_of(min(sec, 0.8))
    click = mul(highpass(noise(rng, n), 1500), env_exp(n, 0.012, 0.0005))
    body = mul(tone(base, n, sweep=-0.1), env_exp(n, 0.09))
    ring = add(mul(tone(base * 4.1, n), env_exp(n, 0.25)), mul(tone(base * 6.3, n), env_exp(n, 0.18)))
    return add(scale(click, 1.2), scale(body, 0.8), scale(ring, 0.25))


def r_clunk(rng, sec):
    n = n_of(min(sec, 0.4))
    return add(mul(tone(rng.uniform(140, 190), n, sweep=-0.3), env_exp(n, 0.09)),
               scale(mul(lowpass(noise(rng, n), 900), env_exp(n, 0.04)), 0.6))


def r_tick(rng, sec):
    n = n_of(min(sec, 0.12))
    return mul(bandpass(noise(rng, n), 1800, 6000), env_exp(n, 0.02, 0.0005))


def r_click(rng, sec):
    n = n_of(min(sec, 0.2))
    return add(scale(r_tick(rng, 0.1), 0.6), scale(mul(tone(rng.uniform(900, 1300), n), env_exp(n, 0.05)), 0.5))


def r_chime(rng, sec):
    n = n_of(min(sec, 0.8))
    f = rng.uniform(740, 990)
    return add(mul(tone(f, n), env_exp(n, 0.4)), scale(mul(tone(f * 1.5, n), env_exp(n, 0.3)), 0.5))


def r_buzz(rng, sec):
    n = n_of(min(sec, 0.3))
    return mul(scale(tone(140, n, shape="square"), 0.4), env_bell(n, 0.2))


def r_grunt(rng, sec):
    n = n_of(min(sec, 0.5))
    return mul(vowel(rng.uniform(90, 140), n, rng, contour=-0.25), env_bell(n, 0.25))


def r_call(rng, sec):
    n = n_of(min(sec, 1.2))
    form = rng.choice([((800, 1.0), (1200, 0.5), (2500, 0.2)), ((500, 1.0), (1700, 0.5), (2500, 0.2)), ((350, 1.0), (2100, 0.4), (2800, 0.2))])
    return mul(vowel(rng.uniform(105, 150), n, rng, formants=form, contour=rng.uniform(-0.2, 0.15)), env_bell(n, 0.3))


def r_step(rng, sec, cut):
    n = n_of(min(sec, 0.2))
    return mul(lowpass(noise(rng, n), cut), env_exp(n, 0.05, 0.001))


def r_skid(rng, sec):
    n = n_of(min(sec, 1.2))
    x = lowpass(noise(rng, n), 2500)
    return mul(x, [e * (0.6 + 0.4 * math.sin(i / SR * 40.0)) for i, e in enumerate(env_bell(n, 0.15))])


def r_slap(rng, sec):
    n = n_of(min(sec, 0.3))
    return add(mul(bandpass(noise(rng, n), 700, 4000), env_exp(n, 0.05)), scale(mul(tone(180, n), env_exp(n, 0.06)), 0.4))


def r_swish(rng, sec):
    n = n_of(min(sec, 0.6))
    return mul(highpass(noise(rng, n), 2500), env_bell(n, 0.5))


def r_murmur(rng, sec):
    n = n_of(min(sec, 6.0))
    x = bandpass(noise(rng, n), 200, 1800)
    mod = [0.7 + 0.3 * math.sin(i / SR * rng.uniform(0.3, 0.9) + 1.0) for i in range(n)]
    return fade_edges(mul(x, mod), 120)


def r_cheer(rng, sec):
    n = n_of(min(sec, 3.5))
    x = bandpass(noise(rng, n), 400, 3500)
    return mul(x, env_bell(n, 0.25))


def r_groan(rng, sec):
    n = n_of(min(sec, 2.0))
    a = vowel(190, n, rng, contour=-0.45)
    b = vowel(160, n, rng, contour=-0.4)
    return mul(add(a, b), env_bell(n, 0.3))


def r_gasp(rng, sec):
    n = n_of(min(sec, 0.9))
    return mul(bandpass(noise(rng, n), 900, 4500), env_bell(n, 0.7))


def r_rattle(rng, sec):
    n = n_of(min(sec, 1.2))
    return sparse_ticks(rng, n, 22, sec, 1500, 6000)


def r_clatter(rng, sec):
    n = n_of(min(sec, 1.0))
    return add(sparse_ticks(rng, n, 14, sec, 300, 2500), scale(sparse_ticks(rng, n, 10, sec, 2500, 7000), 0.6))


def r_ping(rng, sec):
    n = n_of(min(sec, 1.0))
    return mul(tone(rng.uniform(2300, 2700), n), env_exp(n, 0.6))


def r_horn(rng, sec):
    n = n_of(min(sec, 2.5))
    x = add(tone(220, n, shape="saw"), tone(277, n, shape="saw"), tone(330, n, shape="saw"))
    return mul(scale(lowpass(x, 1800), 0.3), env_bell(n, 0.1))


def r_chord(rng, sec):
    n = n_of(min(sec, 2.5))
    x = add(tone(261.6, n), tone(329.6, n), tone(392.0, n), scale(tone(523.2, n), 0.5))
    return mul(scale(x, 0.3), env_bell(n, 0.1))


def r_boom(rng, sec):
    n = n_of(min(sec, 1.5))
    return add(mul(tone(70, n, sweep=-0.6), env_exp(n, 0.6)), scale(mul(lowpass(noise(rng, n), 500), env_exp(n, 0.4)), 0.5))


def r_rumble(rng, sec):
    n = n_of(min(sec, 1.5))
    return fade_edges(lowpass(noise(rng, n), 300), 60)


def r_breath(rng, sec):
    n = n_of(min(sec, 4.0))
    x = bandpass(noise(rng, n), 300, 2500)
    return fade_edges(mul(x, [0.5 + 0.5 * math.sin(i / SR * 1.4) for i in range(n)]), 100)


def r_arp(rng, sec):
    n = n_of(min(sec, 8.0))
    scale_notes = [261.6, 293.7, 329.6, 392.0, 440.0, 523.2]
    out = [0.0] * n
    step = int(0.25 * SR)
    for k in range(n // step):
        f = scale_notes[rng.randrange(len(scale_notes))] * (0.5 if k % 4 == 0 else 1.0)
        note = mul(scale(tone(f, step, shape="square"), 0.18), env_exp(step, 0.22, 0.004))
        for i, v in enumerate(note):
            out[k * step + i] += v
    return fade_edges(out, 40)


RECIPES = {
    "pop_soft": lambda r, s: r_pop(r, s, 0.6, False),
    "pop_medium": lambda r, s: r_pop(r, s, 0.8, True),
    "pop_hard": lambda r, s: scale(r_pop(r, s, 1.0, True), 1.2),
    "thud_soft": lambda r, s: r_thud(r, s, 90, True),
    "thud_mid": lambda r, s: r_thud(r, s, 120, False),
    "thud_low": lambda r, s: r_thud(r, s, 70, True),
    "thud_rattle": lambda r, s: add(r_thud(r, s, 80, False), pad([0.0] * n_of(0.12) + scale(r_rattle(r, 0.5), 0.5), n_of(0.7))),
    "thud_skip": lambda r, s: add(r_thud(r, s, 85, True), pad([0.0] * n_of(0.18) + scale(r_thud(r, 0.3, 95, True), 0.7), n_of(0.6)),
                                  pad([0.0] * n_of(0.34) + scale(r_thud(r, 0.3, 100, True), 0.5), n_of(0.6))),
    "whoosh_thin": lambda r, s: r_whoosh(r, s, 1500, 7000),
    "whoosh_mid": lambda r, s: r_whoosh(r, s, 500, 4000),
    "crack_hard": lambda r, s: r_crack(r, s, 330),
    "crack_mid": lambda r, s: r_crack(r, s, 260),
    "crack_rattle": lambda r, s: add(r_crack(r, s, 220), pad([0.0] * n_of(0.1) + r_clatter(r, 0.6), n_of(0.8))),
    "clunk": lambda r, s: r_clunk(r, s),
    "tick": lambda r, s: r_tick(r, s),
    "click": lambda r, s: r_click(r, s),
    "chime": lambda r, s: r_chime(r, s),
    "buzz": lambda r, s: r_buzz(r, s),
    "voice_grunt": lambda r, s: r_grunt(r, s),
    "voice_call": lambda r, s: r_call(r, s),
    "step_dirt": lambda r, s: r_step(r, s, 1800),
    "step_grass": lambda r, s: r_step(r, s, 900),
    "skid": lambda r, s: r_skid(r, s),
    "slap": lambda r, s: r_slap(r, s),
    "swish": lambda r, s: r_swish(r, s),
    "murmur": lambda r, s: r_murmur(r, s),
    "cheer": lambda r, s: r_cheer(r, s),
    "groan": lambda r, s: r_groan(r, s),
    "gasp": lambda r, s: r_gasp(r, s),
    "rattle": lambda r, s: r_rattle(r, s),
    "clatter": lambda r, s: r_clatter(r, s),
    "ping": lambda r, s: r_ping(r, s),
    "horn": lambda r, s: r_horn(r, s),
    "chord": lambda r, s: r_chord(r, s),
    "boom": lambda r, s: r_boom(r, s),
    "rumble": lambda r, s: r_rumble(r, s),
    "breath": lambda r, s: r_breath(r, s),
    "arp": lambda r, s: r_arp(r, s),
}


def write_wav(path, samples, peak=0.8):
    top = max((abs(v) for v in samples), default=1.0) or 1.0
    g = peak / top
    frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v * g)) * 32767)) for v in samples)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(frames)


def main():
    args = sys.argv[1:]
    do_all = "--all" in args
    force = "--force" in args
    filt = [a for a in args if not a.startswith("--")]
    with open(os.path.join(ROOT, "audio", "manifest.json"), encoding="utf-8") as f:
        manifest = json.load(f)
    made = skipped = 0
    for s in manifest["sounds"]:
        if not do_all and s["priority"] == "P2":
            continue
        if filt and not any(x in s["id"] for x in filt):
            continue
        recipe = RECIPES.get(s["recipe"])
        if recipe is None:
            print("no recipe '%s' for %s" % (s["recipe"], s["id"]))
            continue
        for v in range(1, s["variants"] + 1):
            path = os.path.join(ROOT, "audio", s["dir"], "%s_%02d.wav" % (s["id"], v))
            ogg = path[:-4] + ".ogg"
            if (os.path.exists(path) or os.path.exists(ogg)) and not force:
                skipped += 1
                continue
            rng = random.Random("%s/%d" % (s["id"], v))
            samples = recipe(rng, float(s["seconds"]))
            write_wav(path, samples, 0.55 if s["bus"] in ("Crowd", "Music") else 0.8)
            made += 1
    print("wrote %d placeholder files, left %d existing" % (made, skipped))


if __name__ == "__main__":
    main()
