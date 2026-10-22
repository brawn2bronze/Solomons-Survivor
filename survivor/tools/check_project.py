#!/usr/bin/env python3
"""Static checks for the Godot project (no engine needed).
It cannot prove the game runs - it catches the mistakes that stop a project from loading:
missing resources, audio-spec drift, broken data links, unbalanced brackets, mixed indentation,
and `:=` on Variant expressions (a hard GDScript error)."""
import os, re, sys, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
errors, warns, notes = [], [], []
def err(m): errors.append(m)
def warn(m): warns.append(m)
def note(m): notes.append(m)          # visible in the report, never affects the exit code
def rp(p): return os.path.join(ROOT, p.replace("res://", ""))

try:
    from PIL import Image
except ImportError:                                    # Pillow is optional: the art checks
    Image = None                                       # degrade to a warning, the script still runs
PIL_MISSING = Image is None


def open_image(rel):
    """Open a project image. Returns None when Pillow is missing or the file is unreadable."""
    if PIL_MISSING:
        return None
    try:
        return Image.open(rp(rel))
    except Exception as exc:
        err(f"cannot read image {rel}: {exc}")
        return None

SPEC_AUDIO = """weapons/revolver_shot.wav weapons/katana_slash.wav weapons/hand_cannon.wav weapons/whip_crack.wav weapons/greatsword_swing.wav
weapons/lightning_bolt.wav weapons/fang_bite.wav weapons/horn_swipe.wav weapons/screech.wav weapons/skull_projectile.wav weapons/goose_charge.wav
enemies/goblin_hit.wav enemies/skeleton_hit.wav enemies/dragon_hit.wav enemies/dinosaur_hit.wav enemies/enemy_death.wav enemies/elite_enemy_spawn.wav
player/player_hit.wav player/player_death.wav player/xp_pickup.wav player/level_up.wav player/character_select.wav player/frog-fart.wav player/coin_pickup.wav
music/ambient_loop.ogg music/boss_music.ogg music/menu_music.ogg
music/act1_orchestral.ogg music/act2_glitch.ogg music/act3_choir.ogg music/act4_lucifer.ogg
music/boss_asmodeus.ogg music/boss_malphas.ogg music/boss_belial.ogg
ui/button_click.wav ui/menu_open.wav ui/menu_close.wav ui/upgrade_selected.wav ui/market_unlock.wav ui/market_purchase.wav""".split()
MUSIC_ALLOW_MISSING = set()   # act4_lucifer.ogg now ships as a boss_music placeholder; add paths here only for documented gaps

def wrapped_cast(rhs):
    m = re.match(r'(float|int|bool|String|Vector2|Vector2i|Color|Rect2|clampf|clampi|maxf|maxi|minf|mini|absf|lerpf|sqrt|floori|ceili)\(', rhs)
    if not m: return False
    depth = 0
    for i, ch in enumerate(rhs):
        if ch == "(": depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0: return i == len(rhs) - 1
    return False

gd_files = [f for f in glob.glob(ROOT + "/**/*.gd", recursive=True)]
tres_files = glob.glob(ROOT + "/data/**/*.tres", recursive=True)
all_text = {f: open(f, encoding="utf-8").read() for f in gd_files + tres_files + glob.glob(ROOT + "/**/*.tscn", recursive=True) + [ROOT + "/project.godot"]}

# ---- 1. audio spec ---------------------------------------------------------------------------
for a in SPEC_AUDIO:
    if a in MUSIC_ALLOW_MISSING:
        continue
    if not os.path.exists(os.path.join(ROOT, "audio", a)):
        err(f"audio spec file missing: res://audio/{a}")
am = open(ROOT + "/autoload/audio_manager.gd").read()
events = dict(re.findall(r'"(\w+)":\s*"(res://audio/[^"]+)"', am.split("const MUSIC")[0]))
music = dict(re.findall(r'"(\w+)":\s*"(res://audio/[^"]+)"', am.split("const MUSIC")[1].split("const MIN_GAP")[0]))
for k, p in {**events, **music}.items():
    rel = p.replace("res://audio/", "")
    if rel not in MUSIC_ALLOW_MISSING and not os.path.exists(rp(p)): err(f"AudioManager path missing on disk: {p}")
    if rel not in SPEC_AUDIO: err(f"AudioManager path not in spec: {p}")
for a in SPEC_AUDIO:
    if "res://audio/" + a not in {**events, **music}.values(): err(f"spec path not wired in AudioManager: {a}")
for f, t in all_text.items():
    if f.endswith(".gd"):
        t = "\n".join(l for l in t.split("\n") if not l.strip().startswith("#"))
        for m in re.finditer(r'Audio\.sfx\("(\w+)"', t):
            if m.group(1) not in events: err(f"{os.path.relpath(f, ROOT)}: unknown sfx '{m.group(1)}'")
        for m in re.finditer(r'Audio\.music\("(\w+)"', t):
            if m.group(1) not in music: err(f"{os.path.relpath(f, ROOT)}: unknown music '{m.group(1)}'")
    if f.endswith(".tres"):
        for m in re.finditer(r'audio_event = "(\w+)"', t):
            if m.group(1) not in events: err(f"{os.path.relpath(f, ROOT)}: unknown audio_event '{m.group(1)}'")
        for m in re.finditer(r'hit_event = "(\w+)"', t):
            if m.group(1) not in events: err(f"{os.path.relpath(f, ROOT)}: unknown hit_event '{m.group(1)}'")

# ---- 2. every res:// reference resolves ------------------------------------------------------
ALLOW_MISSING_REFS = {"audio/" + a for a in MUSIC_ALLOW_MISSING}   # documented, not-yet-authored assets
for f, t in all_text.items():
    for m in re.finditer(r'res://[A-Za-z0-9_./-]+\.(?:gd|tscn|tres|png|wav|ogg|gdshader)', t):
        if m.group(0).replace("res://", "") in ALLOW_MISSING_REFS:
            continue
        if not os.path.exists(rp(m.group(0))):
            err(f"{os.path.relpath(f, ROOT)}: dangling {m.group(0)}")

# ---- 3. data integrity ------------------------------------------------------------------------
def parse_tres(path):
    # Single-line fields only (id, behavior, sprite, ...). Multi-line blocks
    # (base/branches edited in the Godot inspector, e.g. turds.tres) are read
    # via span() below; the last single-line match wins for repeated keys.
    d = {}
    for line in open(path, encoding="utf-8"):
        m = re.match(r'(\w+) = (.*)$', line.strip())
        if m: d[m.group(1)] = m.group(2)
    return d


def span(text, key):
    """Balanced `{...}` / `[...]` block after `key = `, inspector-safe (multi-line aware)."""
    m = re.search(r'(?:^|\n)' + key + r' = ', text)
    if not m: return ""
    i = m.end()
    while i < len(text) and text[i] not in "{[":
        i += 1
    if i >= len(text): return ""
    open_c, close_c = (text[i], "}") if text[i] == "{" else (text[i], "]")
    depth, j, instr = 0, i, False
    while j < len(text):
        ch = text[j]
        if ch == '"' and text[j - 1] != "\\":
            instr = not instr
        elif not instr:
            if ch == open_c: depth += 1
            elif ch == close_c:
                depth -= 1
                if depth == 0: return text[i:j + 1]
        j += 1
    return text[i:]
chars = {os.path.basename(p)[:-5]: parse_tres(p) for p in glob.glob(ROOT + "/data/characters/*.tres")}
weapons = {os.path.basename(p)[:-5]: parse_tres(p) for p in glob.glob(ROOT + "/data/weapons/*.tres")}
passives = {os.path.basename(p)[:-5]: parse_tres(p) for p in glob.glob(ROOT + "/data/passives/*.tres")}
enemies = {os.path.basename(p)[:-5]: parse_tres(p) for p in glob.glob(ROOT + "/data/enemies/*.tres")}
if len(chars) != 12: err(f"expected 12 characters, found {len(chars)}")
if len(weapons) < 10: err(f"expected 10+ weapons, found {len(weapons)}")
if len(enemies) < 8: err(f"expected 8+ enemies, found {len(enemies)}")
if not any(e.get("is_elite") == "true" and e.get("height") == "1" for e in enemies.values()): err("no aerial elite enemy")
if not any(e.get("is_elite") == "true" and e.get("can_hit_flying") == "true" for e in enemies.values()): err("no elite that can hit flying units")
behaviors_src = open(ROOT + "/src/abilities/weapon_behaviors.gd").read() + open(ROOT + "/src/abilities/passive_behaviors.gd").read()
keys = set(re.findall(r'"(\w+)": return \w+\.new\(\)', behaviors_src))
for cid, c in chars.items():
    w, p = c["weapon_id"].strip('"'), c["passive_id"].strip('"')
    if w not in weapons: err(f"{cid}: weapon '{w}' missing")
    if p not in passives: err(f"{cid}: passive '{p}' missing")
    sp = c["sprite"].strip('"')
    if not os.path.exists(rp(sp)): err(f"{cid}: sprite missing {sp}")
atext = {}
for p in glob.glob(ROOT + "/data/weapons/*.tres") + glob.glob(ROOT + "/data/passives/*.tres"):
    with open(p, encoding="utf-8") as f:
        atext[os.path.basename(p)[:-5]] = f.read()
for aid, a in {**weapons, **passives}.items():
    b = a["behavior"].strip('"')
    if b not in keys: err(f"{aid}: behavior '{b}' has no implementation")
    if atext.get(aid, "").count('"on_pick"') != 2: err(f"{aid}: needs exactly two branches")
from PIL import Image
for eid, e in enemies.items():
    sp = e["sprite"].strip('"'); im = open_image(sp)
    if im is None: continue
    frames = int(e["frames"])
    if frames < 1 or im.width % frames != 0:
        err(f"{eid}: strip width {im.width} is not divisible by {frames} frames")
    elif im.width // frames not in (48, 64):
        note(f"{eid}: non-standard enemy cell width {im.width // frames}px (48/64 is the norm)")
    num = lambda k, d="0": float(e.get(k, d).strip())
    if num("projectile_count", "1") < 1: err(f"{eid}: projectile_count must be >= 1")
    if num("projectile_spread_deg") < 0 or num("splash_radius") < 0 or num("splash_damage") < 0: err(f"{eid}: fan/splash fields must be >= 0")
    if num("spiral_every") < 0 or num("spiral_projectile_count") < 0: err(f"{eid}: spiral_every/count must be >= 0")
    if num("spiral_every") > 0 and num("spiral_projectile_count") <= 0: err(f"{eid}: spiral_every > 0 needs spiral_projectile_count > 0")
    if num("spiral_cast_time", "0.75") <= 0 or num("spiral_fire_interval", "0.03") <= 0: err(f"{eid}: spiral cast/interval must be > 0")
    if num("spiral_projectile_speed") < 0 or num("spiral_projectile_range") < 0 or num("spiral_splash_radius") < 0 or num("spiral_splash_damage") < 0: err(f"{eid}: spiral fields must be >= 0")
    if not 0.0 < num("enrage_hp_fraction", "0.4") < 1.0 or num("enrage_interval_mult", "0.7") <= 0: err(f"{eid}: enrage_hp_fraction must be 0-1, enrage_interval_mult > 0")
# ---- 3c. act data + director fields ----------------------------------------------------------
def numf(d, k, default="0"):
    try: return float(d.get(k, default).strip())
    except ValueError: return 0.0
acts = {os.path.basename(p)[:-5]: parse_tres(p) for p in glob.glob(ROOT + "/data/acts/*.tres")}
if len(acts) < 4: err(f"expected 4 acts, found {len(acts)}")
prev_clock = -1.0
for aid in sorted(acts, key=lambda k: numf(acts[k], "index")):
    a = acts[aid]
    cs = numf(a, "clock_start")
    if cs <= prev_clock: err(f"{aid}: clock_start must increase ({cs} <= {prev_clock})")
    prev_clock = cs
    bid = a.get("boss_id", "").strip('"')
    sealed = a.get("sealed", "false").strip() == "true"
    if bid and bid not in enemies and not sealed: err(f"{aid}: boss_id '{bid}' has no EnemyDef (sealed acts may omit)")
    mk = a.get("music_key", "").strip('"')
    if mk and mk not in music: err(f"{aid}: music_key '{mk}' not in AudioManager.MUSIC")
    bmk = a.get("boss_music_key", "").strip('"')
    if bmk and bmk not in music: err(f"{aid}: boss_music_key '{bmk}' not in AudioManager.MUSIC")
for eid, e in enemies.items():
    if e.get("behavior", "").strip('"') == "boss_broker":
        if "fan" not in e.get("deck", ""): err(f"{eid}: boss_broker needs a non-empty deck")
        if numf(e, "recover_time", "0") <= 0: err(f"{eid}: recover_time must be > 0")
        if numf(e, "add_cap", "0") <= 0: err(f"{eid}: add_cap must be > 0")
for cid, c in chars.items():
    sp = c["sprite"].strip('"'); im = open_image(sp)
    if im is None: continue
    frames = int(c.get("frames", "6").strip()) if "frames" in c else 6
    if im.size != (64 * frames, 64): err(f"{cid}: character strip should be {64 * frames}x64 ({frames} frames), is {im.size}")
# ---- 3b. card/status art ----------------------------------------------------------------------
for p in glob.glob(ROOT + "/art/weapons/*.png"):
    im = open_image(p)
    if im is None: continue
    if im.height not in (32, 64) or im.width % im.height != 0: err(f"{os.path.relpath(p, ROOT)}: weapon art must be square cells (Wx32 or Wx64 strip), is {im.size}")
for p in glob.glob(ROOT + "/art/status/*.png"):
    im = open_image(p)
    if im is None: continue
    if im.size != (32, 32): err(f"{os.path.relpath(p, ROOT)}: status icon must be 32x32, is {im.size}")
for p in glob.glob(ROOT + "/art/passives/*.png"):
    im = open_image(p)
    if im is None: continue
    if im.size not in ((32, 32), (64, 64)): err(f"{os.path.relpath(p, ROOT)}: passive art must be 32x32 or 64x64, is {im.size}")
for p in ["art/placeholders/silhouette_weapon.png", "art/placeholders/silhouette_passive.png", "art/placeholders/silhouette_upgrade.png"]:
    if not os.path.exists(os.path.join(ROOT, p)): err(f"missing placeholder {p}")
for aid, a in list(weapons.items()) + list(passives.items()):
    if "icon" in a:
        ip = a["icon"].strip('"')
        if ip and not os.path.exists(rp(ip)): err(f"{aid}: icon missing {ip}")

base_keys = set()
for aid in list(weapons.keys()) + list(passives.keys()):
    base_keys |= set(re.findall(r'"(\w+)":', span(atext.get(aid, ""), "base")))
for m in re.finditer(r'p\["(\w+)"\]', behaviors_src):
    if m.group(1) not in base_keys: err(f"behaviors read p['{m.group(1)}'] but no ability defines that base param")
for a_id in list(weapons.keys()) + list(passives.keys()):
    t = atext.get(a_id, "")
    ops_keys = set(re.findall(r'"(\w+)": \["(?:mul|add|set)"', span(t, "level_scaling") + span(t, "branches")))
    unknown = ops_keys - set(re.findall(r'"(\w+)":', span(t, "base")))
    if unknown: err(f"{a_id}: upgrade ops touch params that do not exist in base: {sorted(unknown)}")
for f in gd_files:
    if re.search(r'\.connect\(func\([^)]*\)[^\n]*:\s*\n', all_text[f]): warn(f"{os.path.relpath(f, ROOT)}: multi-line lambda inside connect()")

# ---- 4. GDScript hygiene ---------------------------------------------------------------------------
# The `:=`-on-Variant and unused-parameter rules live in tools/gdscript_lint.py - imported
# here, never re-implemented, so the static tier and the engine tier cannot drift apart.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gdscript_lint
for f in gdscript_lint.lint_project(ROOT):
    if f.severity == "error":
        err(f"{f.path}:{f.line}: {f.message}")
    else:
        warn(f"{f.path}:{f.line}: {f.message}")

class_names = {}
for f in gd_files:
    m = re.search(r'^class_name (\w+)', all_text[f], re.M)
    if m:
        if m.group(1) in class_names: err(f"duplicate class_name {m.group(1)}")
        class_names[m.group(1)] = f
for f in gd_files:
    t = all_text[f]; rel = os.path.relpath(f, ROOT)
    stripped = re.sub(r'"""[\s\S]*?"""', '""', t)
    depth = {"(": 0, "[": 0, "{": 0}; pair = {")": "(", "]": "[", "}": "{"}
    line_no = 0
    for line in stripped.split("\n"):
        line_no += 1
        code = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
        code = code.split("#")[0]
        for ch in code:
            if ch in depth: depth[ch] += 1
            elif ch in pair: depth[pair[ch]] -= 1
        if "\t" in line[:len(line) - len(line.lstrip())] and line.startswith(" "): err(f"{rel}:{line_no}: mixed tabs/spaces")
        lead = len(line) - len(line.lstrip(" "))
        if line.strip() and not line.strip().startswith("#") and lead % 4 != 0 and all(v == 0 for v in depth.values()): warn(f"{rel}:{line_no}: indent {lead} not a multiple of 4")
        # Variant inference and unused parameters are checked by tools/gdscript_lint.py
        # (imported in section 4) - the single owner of those rules.
    if any(v != 0 for v in depth.values()): err(f"{rel}: unbalanced brackets {depth}")
    for m in re.finditer(r'^extends (\w+)', t, re.M):
        base = m.group(1)
        if base[0].isupper() and base not in class_names and base not in ("Node", "Node2D", "Resource", "RefCounted", "Control", "CanvasLayer", "VBoxContainer", "HBoxContainer", "SceneTree"): err(f"{rel}: unknown base class {base}")
# ---- 4b. `:=` using an untyped loop variable (review list, not auto-fail) -------------------------
review = []
for f in gd_files:
    lines_ = all_text[f].split("\n")
    for i, line in enumerate(lines_):
        m = re.match(r'(\s*)for (\w+) in (.+):\s*$', line)
        if not m: continue
        ind, v, it = len(m.group(1)), m.group(2), m.group(3)
        if re.match(r'(range\(|\d|\[|.*\.keys\(\)|.*\.values\(\)|.*\.split\()', it): continue
        for j in range(i + 1, len(lines_)):
            l2 = lines_[j]
            if l2.strip() and len(l2) - len(l2.lstrip()) <= ind: break
            mm = re.search(r':=\s*(.+)$', l2)
            if mm and re.search(r'\b' + v + r'\.', mm.group(1)) and not re.match(r'\s*(float|int)\(', mm.group(1)):
                review.append(f"{os.path.relpath(f, ROOT)}:{j+1}: loop var '{v}' over `{it[:40]}` -> {mm.group(1)[:60]}")
for r in review: print("review:", r)

# ---- 4c. Descent checkpoint (Phase 3) shape ------------------------------------------------------
gd_by_rel = {os.path.relpath(f, ROOT).replace("\\", "/"): all_text[f] for f in gd_files}
def gd(rel):
    return gd_by_rel.get(rel, "")
dsc = gd("src/core/descent.gd")
if dsc == "":
    err("Phase 3: src/core/descent.gd missing")
else:
    if "class_name Descent" not in dsc: err("Phase 3: descent.gd missing class_name Descent")
    if "extends RefCounted" not in dsc: err("Phase 3: descent.gd must extend RefCounted")
    if "SNAP_VERSION" not in dsc: err("Phase 3: descent.gd missing SNAP_VERSION")
    mk = re.search(r'const KEYS\s*:=\s*\[(.*?)\]', dsc, re.S)
    if not mk:
        err("Phase 3: descent.gd missing KEYS const")
    else:
        for k in re.findall(r'"(\w+)"', mk.group(1)):
            if ('"%s":' % k) not in dsc: err(f"Phase 3: descent.gd capture omits snapshot key '{k}'")
    if "static func capture(" not in dsc: err("Phase 3: descent.gd missing capture()")
    if "static func restore(" not in dsc: err("Phase 3: descent.gd missing restore()")
ab = gd("src/abilities/ability.gd")
if "const STATE_KEYS" not in ab: err("Phase 3: ability.gd missing STATE_KEYS")
for fn in ("to_dict", "from_dict"):
    m = re.search(r'^func %s\(.*?(?=^func |^static func |\Z)' % fn, ab, re.S | re.M)
    if not m: err("Phase 3: ability.gd missing %s()" % fn)
    elif "STATE_KEYS" not in m.group(0): err("Phase 3: ability.gd %s() must iterate STATE_KEYS" % fn)
for rel, token in [("autoload/meta.gd", "SEC_DESCENT"), ("autoload/meta.gd", "func get_descent"),
        ("autoload/meta.gd", "func set_descent"), ("autoload/meta.gd", "func has_descent"),
        ("autoload/game.gd", "pending_descent"), ("autoload/game.gd", "run_from_descent"),
        ("src/core/world.gd", "Descent.capture("), ("src/core/world.gd", "Descent.restore("),
        ("src/ui/character_select.gd", "signal continued"), ("src/ui/character_select.gd", "continued.emit("),
        ("src/main.gd", "Meta.get_descent("), ("src/main.gd", "use_descent")]:
    if token not in gd(rel): err("Phase 3: %s missing %s" % (rel, token))

# ---- 5. signal connections: every `.connect(_name)` must resolve to a func in the same file ----
for f in gd_files:
    t = all_text[f]
    funcs = set(re.findall(r'^\s*func (\w+)', t, re.M))
    for m in re.finditer(r'\.connect\((_\w+)[\),]', t):
        if m.group(1) not in funcs: err(f"{os.path.relpath(f, ROOT)}: connects to missing func {m.group(1)}")

if PIL_MISSING:
    warn("Pillow is not installed - the sprite/art size checks were SKIPPED (pip install pillow)")

lines = sum(t.count("\n") for f, t in all_text.items() if f.endswith(".gd"))
print(f"checked {len(gd_files)} scripts ({lines} lines), {len(tres_files)} resources, {len(class_names)} classes")
for w in warns[:20]: print("warn:", w)
for n in notes: print("note:", n)
for e in errors: print("ERROR:", e)
STRICT = "--strict" in sys.argv          # warnings count as failures (used by check_all.ps1 -Strict)
failed = bool(errors) or (STRICT and bool(warns))
print("RESULT:", "FAIL (%d errors, %d warnings)" % (len(errors), len(warns)) if failed else "PASS")
sys.exit(1 if failed else 0)
