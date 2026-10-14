#!/usr/bin/env python3
"""Synthesizes placeholder audio at every path the game references.
Each sound is intentionally different (pitch/noise/envelope) so gameplay is readable by ear before
real assets arrive. Replace any file with real audio of the same name - no code changes needed."""
import os, wave, struct, subprocess, shutil
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SR = 44100
rng = np.random.default_rng(7)


def t(d): return np.linspace(0, d, int(SR * d), endpoint=False)
def env(n, a=0.005, r=0.1):
    e = np.ones(n); na, nr = int(SR * a), int(SR * r)
    if na: e[:na] = np.linspace(0, 1, na)
    if nr: e[-nr:] = np.linspace(1, 0, min(nr, n))[: len(e[-nr:])]
    return e
def noise(d, lp=0.0):
    x = rng.uniform(-1, 1, int(SR * d))
    if lp:
        for i in range(1, len(x)): x[i] = x[i - 1] * lp + x[i] * (1 - lp)
        x /= max(1e-6, np.abs(x).max())
    return x
def sweep(f0, f1, d, wave_="sin"):
    tt = t(d); f = np.linspace(f0, f1, len(tt)); ph = 2 * np.pi * np.cumsum(f) / SR
    return {"sin": np.sin(ph), "sq": np.sign(np.sin(ph)) * 0.6, "saw": 2 * ((ph / (2 * np.pi)) % 1) - 1}[wave_]
def decay(d, k=8): return np.exp(-k * t(d) / d)

def write_wav(path, x, gain=0.8):
    x = np.clip(x / max(1e-6, np.abs(x).max()) * gain, -1, 1)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())

def pad(*parts):
    n = max(len(p) for p in parts); out = np.zeros(n)
    for p in parts: out[: len(p)] += p
    return out

SFX = {
    "weapons/revolver_shot":   lambda: pad(noise(.16) * decay(.16, 14), sweep(220, 60, .16) * decay(.16, 9)),
    "weapons/katana_slash":    lambda: noise(.22, .55) * np.sin(np.pi * np.linspace(0, 1, int(SR * .22))) ** 2 * 0.9,
    "weapons/hand_cannon":     lambda: pad(noise(.5, .8) * decay(.5, 6), sweep(110, 32, .5) * decay(.5, 5) * 1.4),
    "weapons/whip_crack":      lambda: pad(noise(.1) * decay(.1, 22), sweep(2400, 400, .08, "saw") * decay(.08, 12) * .5),
    "weapons/greatsword_swing":lambda: noise(.4, .7) * np.sin(np.pi * np.linspace(0, 1, int(SR * .4))) ** 1.5 + sweep(140, 70, .4) * .3,
    "weapons/lightning_bolt":  lambda: pad(noise(.3) * decay(.3, 10) * .8, sweep(1800, 200, .3, "saw") * decay(.3, 7) * .5),
    "weapons/fang_bite":       lambda: pad(sweep(900, 350, .09, "sq") * decay(.09, 10), noise(.06) * decay(.06, 18) * .5),
    "weapons/horn_swipe":      lambda: pad(noise(.28, .8) * decay(.28, 5), sweep(90, 55, .28) * decay(.28, 4) * .9),
    "weapons/screech":         lambda: sweep(2600, 3400, .35) * (1 + .4 * np.sin(2 * np.pi * 40 * t(.35))) * env(int(SR * .35), .02, .15),
    "weapons/skull_projectile":lambda: sweep(300, 520, .35) * (0.6 + .4 * np.sin(2 * np.pi * 7 * t(.35))) * env(int(SR * .35), .05, .2) + noise(.35, .9) * .15,
    "weapons/goose_charge":    lambda: sweep(420, 300, .4, "sq") * (0.5 + .5 * np.sin(2 * np.pi * 14 * t(.4))) * env(int(SR * .4), .01, .1),
    "enemies/goblin_hit":      lambda: sweep(520, 240, .12, "sq") * decay(.12, 8),
    "enemies/skeleton_hit":    lambda: pad(noise(.09) * decay(.09, 16), sweep(1500, 900, .07) * decay(.07, 10) * .6),
    "enemies/dragon_hit":      lambda: pad(sweep(150, 60, .3, "saw") * decay(.3, 6), noise(.3, .9) * decay(.3, 8) * .6),
    "enemies/dinosaur_hit":    lambda: pad(sweep(220, 90, .22, "saw") * decay(.22, 5), noise(.22, .7) * decay(.22, 9) * .4),
    "enemies/enemy_death":     lambda: pad(sweep(400, 80, .22, "sq") * decay(.22, 6), noise(.22, .6) * decay(.22, 8) * .5),
    "enemies/elite_enemy_spawn": lambda: pad(sweep(70, 130, .9, "saw") * env(int(SR * .9), .2, .4), sweep(72, 136, .9, "saw") * env(int(SR * .9), .2, .4) * .7),
    "player/player_hit":       lambda: pad(sweep(200, 70, .2, "sq") * decay(.2, 7), noise(.12) * decay(.12, 12) * .5),
    "player/player_death":     lambda: pad(sweep(400, 40, 1.2, "saw") * decay(1.2, 3), noise(1.2, .95) * decay(1.2, 4) * .6),
    "player/xp_pickup":        lambda: sweep(880, 1320, .07) * decay(.07, 6),
    "player/level_up":         lambda: np.concatenate([sweep(f, f, .11) * decay(.11, 4) for f in (523, 659, 784, 1046)] + [sweep(1046, 1046, .35) * decay(.35, 4)]),
    "player/character_select": lambda: pad(sweep(330, 440, .18, "sq") * decay(.18, 5), sweep(660, 880, .18) * decay(.18, 5) * .5),
    "ui/button_click":         lambda: sweep(700, 500, .05, "sq") * decay(.05, 8),
    "ui/menu_open":            lambda: sweep(300, 600, .14) * env(int(SR * .14), .01, .06),
    "ui/menu_close":           lambda: sweep(600, 300, .14) * env(int(SR * .14), .01, .06),
    "ui/upgrade_selected":     lambda: np.concatenate([sweep(f, f, .08, "sq") * decay(.08, 4) for f in (392, 587, 784)]),
}


def music(kind, bars):
    """Small looping chiptune-ish bed. ambient: dark drone + slow arp. boss: faster minor riff. menu: warm pad."""
    bpm = {"ambient": 78, "boss": 148, "menu": 66}[kind]
    beat = 60 / bpm; root = {"ambient": 55.0, "boss": 65.4, "menu": 73.4}[kind]
    scale = [0, 3, 5, 7, 10, 12, 15]
    out = np.zeros(int(SR * beat * 4 * bars))
    for b in range(bars * 4):
        note = root * 2 ** (scale[(b * 3 + (b // 4) * 2) % len(scale)] / 12)
        n = t(beat * (1 if kind == "boss" else 2)); v = np.sin(2 * np.pi * note * n) * env(len(n), .01, .3) * .5
        v += np.sin(2 * np.pi * note * 2.005 * n) * env(len(n), .02, .4) * .18
        i = int(b * beat * SR); out[i: i + len(v)] += v[: len(out) - i]
        if kind != "menu":
            k = sweep(120, 45, .2) * decay(.2, 9); j = int(b * beat * SR); out[j: j + len(k)] += k[: len(out) - j] * .7
        if kind == "boss":
            h = noise(.05) * decay(.05, 18) * .3; jj = int((b + .5) * beat * SR); out[jj: jj + len(h)] += h[: max(0, len(out) - jj)]
    drone = np.sin(2 * np.pi * root / 2 * t(len(out) / SR)) * .25
    return out + drone


def main():
    for k, fn in SFX.items():
        write_wav(os.path.join(ROOT, "audio", k + ".wav"), fn())
    ff = shutil.which("ffmpeg")
    for name, bars in (("ambient_loop", 8), ("boss_music", 8), ("menu_music", 6)):
        wavp = os.path.join(ROOT, "audio/music", name + ".wav")
        write_wav(wavp, music(name.split("_")[0], bars), 0.6)
        oggp = wavp[:-4] + ".ogg"
        r = subprocess.run([ff, "-y", "-loglevel", "error", "-i", wavp, "-c:a", "libvorbis", "-q:a", "3", oggp], capture_output=True, text=True) if ff else None
        if r is None or r.returncode != 0:
            print("ffmpeg/libvorbis failed:", r.stderr if r else "no ffmpeg"); continue
        os.remove(wavp)
    print("audio written:", sum(len(f) for _, _, f in os.walk(os.path.join(ROOT, "audio"))), "files")


if __name__ == "__main__":
    main()
