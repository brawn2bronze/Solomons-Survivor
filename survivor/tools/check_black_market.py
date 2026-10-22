#!/usr/bin/env python3
"""Static sanity checks for the Black Market feature. Complements tools/check_project.py (run that one too).
Run from the project root:  python tools/check_black_market.py
It cannot compile GDScript; it catches the mistakes that are cheap to catch without Godot."""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
errors, warnings = [], []


def read(rel):
    with open(os.path.join(ROOT, rel), "rb") as f:
        return f.read().decode("utf-8")


def scripts():
    for base, _dirs, files in os.walk(ROOT):
        if "/.godot" in base or "\\.godot" in base:
            continue
        for fn in files:
            if fn.endswith(".gd"):
                yield os.path.relpath(os.path.join(base, fn), ROOT).replace("\\", "/")


# 1. one indentation style per file (Godot rejects mixed tabs/spaces in a block)
def code_lines(text):
    """(line number, line) for real code only - lines inside a \"\"\" block are skipped.

    Shader source and other multi-line strings are written with their own indentation
    (tabs in a space file, spaces in a tab file) and say nothing about the file's style.
    """
    in_str = False
    for i, l in enumerate(text.split("\n"), 1):
        if l.count('"""') % 2 == 1:      # opens or closes a multi-line string
            in_str = not in_str
            continue
        if in_str:
            continue
        yield i, l


for rel in scripts():
    text = read(rel).replace("\r\n", "\n")
    tab_lines = [i for i, l in code_lines(text) if l.startswith("\t")]
    space_lines = [i for i, l in code_lines(text) if l.startswith("    ")]
    if tab_lines and space_lines:
        errors.append(f"{rel}: mixes tab and space indentation (tab lines {tab_lines[:3]}, space lines {space_lines[:3]})")

# 2. ':=' on a Variant expression - the rule lives in tools/gdscript_lint.py (single owner,
#    imported by check_project.py too). Delegating keeps the two checkers from drifting apart
#    and removes the false positives of the old regex here (typed array subscripts are fine).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gdscript_lint
for f in gdscript_lint.lint_project(ROOT):
    if f.code in ("GDS101", "GDS102"):
        warnings.append(f"{f.path}:{f.line}: {f.message}")

# 3. no lambdas in tweens
for rel in scripts():
    for i, line in enumerate(read(rel).split("\n"), 1):
        if "tween_callback(func" in line:
            errors.append(f"{rel}:{i}: lambda in a tween")

# 4. every Audio.sfx/music key used is registered in audio_manager.gd EVENTS, and every EVENTS path exists
am = read("autoload/audio_manager.gd")
events = dict(re.findall(r'"([a-z0-9_]+)":\s*"(res://[^"]+)"', am))
used = set()
for rel in scripts():
    code = "\n".join(l for l in read(rel).split("\n") if not l.strip().startswith("#"))
    for key in re.findall(r'Audio\.(?:sfx|music)\(\s*"([a-z0-9_]+)"', code):
        used.add((key, rel))
for key, rel in sorted(used):
    if key not in events:
        errors.append(f"{rel}: Audio key '{key}' is not registered in audio_manager.gd")
for key in ("coin_pickup", "market_unlock", "market_purchase"):
    path = events.get(key)
    if path is None:
        errors.append(f"audio_manager.gd: missing event '{key}'")
    elif not os.path.exists(os.path.join(ROOT, path.replace("res://", ""))):
        errors.append(f"{path} does not exist on disk")

# 5. every res:// reference in files of this feature resolves (only checks files shipped in this package)
feature_files = [r for r in scripts() if r in (
    "autoload/meta.gd", "src/core/coin_manager.gd", "src/ui/black_market_screen.gd", "src/ui/coin_icon.gd", "data/defs/market_item_def.gd")]
feature_files += [os.path.join("data/market", f).replace("\\", "/") for f in os.listdir(os.path.join(ROOT, "data/market"))]
feature_files.append("data/enemies/bone_broker.tres")
for rel in feature_files:
    for ref in re.findall(r'res://[A-Za-z0-9_./-]+', read(rel)):
        if not os.path.exists(os.path.join(ROOT, ref.replace("res://", ""))):
            if ref != "res://art/enemies/skeleton.png":   # reused existing art, not shipped here
                warnings.append(f"{rel}: {ref} not found")

# 6. market listings: 9 common rentals + >= 9 common mods, one rental per common chest weapon,
# every common chest weapon has a mod; rares need a rental only (no mods); legendaries need a
# rental only (no mods) and stay silhouette-locked until Player.is_legendary_unlocked
chest = ["pickup_aa12", "pickup_blunderbuss", "pickup_caltrops", "pickup_cloak", "pickup_dynamite",
         "pickup_energy_food", "pickup_keg", "pickup_rifle", "pickup_shurikens"]
rare_chest = ["pickup_shamir_tooth"]
legend_chest = ["pickup_shamir"]
rentals, mods, ids = {}, {}, set()
for fn in sorted(os.listdir(os.path.join(ROOT, "data/market"))):
    t = read("data/market/" + fn)
    get = lambda k: (re.search(r'^%s = (.+)$' % k, t, re.M) or [None, ""])[1].strip().strip('"')
    iid, kind, wid, cost = get("id"), get("kind"), get("weapon_id"), get("cost")
    if iid in ids:
        errors.append(f"{fn}: duplicate id {iid}")
    ids.add(iid)
    if not cost.isdigit() or int(cost) <= 0:
        errors.append(f"{fn}: cost must be a positive integer")
    if wid not in chest and wid not in rare_chest and wid not in legend_chest:
        errors.append(f"{fn}: weapon_id {wid} is not a chest weapon")
    (rentals if kind == "0" else mods).setdefault(wid, []).append((iid, int(cost) if cost.isdigit() else 0))
for w in chest:
    if w not in rentals:
        errors.append(f"no rental listing for {w}")
    if w not in mods:
        errors.append(f"no permanent upgrade for {w}")
for w in rare_chest:
    if w not in rentals:
        errors.append(f"no rental listing for rare {w}")
for w in legend_chest:
    if w not in rentals:
        errors.append(f"no rental listing for legendary {w}")
    if w in mods:
        errors.append(f"legendary {w} must not have a permanent upgrade listing")
for w, lst in mods.items():
    for iid, c in lst:
        rc = max((x[1] for x in rentals.get(w, [(0, 0)])), default=0)
        if c <= rc * 3:
            warnings.append(f"{iid}: permanent upgrade ({c}) is not 'much higher' than its rental ({rc})")

# 7. every flag key read via mod_f()/has_mod() in behaviors has a listing that sets it (and vice versa)
wb = read("src/abilities/weapon_behaviors.gd")
read_keys = set(re.findall(r'(?:mod_f|has_mod)\("([a-z_]+)"', wb))
set_keys = set()
for fn in os.listdir(os.path.join(ROOT, "data/market")):
    m = re.search(r'^flags = \{(.*)\}$', read("data/market/" + fn), re.M)
    if m:
        set_keys |= set(re.findall(r'"([a-z_]+)":', m.group(1)))
for k in sorted(read_keys - set_keys):
    # optional per-mod tuning keys fall back to defaults and are fine; the trigger keys must be set by some listing
    if k not in ("heavy_mult", "heavy_pierce", "burn_time", "ring_count", "slow_time", "pulse_stun", "pulse_knock"):
        errors.append(f"behavior reads mod flag '{k}' but no listing sets it")
for k in sorted(set_keys - read_keys):
    errors.append(f"a listing sets flag '{k}' that no behavior reads")

# 8. boss def sanity
# The black market boss uses the "boss_broker" behavior (enemy_manager.gd match arm), not the
# plain "boss" one - the old expectation here was stale and flagged a correct file.
boss = read("data/enemies/bone_broker.tres")
for need in ('is_elite = true', 'boss_time = ', 'boss_unlock = "black_market"', 'behavior = "boss_broker"', 'can_hit_flying = true'):
    if need not in boss:
        errors.append(f"bone_broker.tres missing: {need}")

# 9. autoload registered
pg = read("project.godot")
if 'Meta="*res://autoload/meta.gd"' not in pg:
    errors.append("project.godot: Meta autoload is not registered")

for w in warnings:
    print("WARN ", w)
for e in errors:
    print("ERROR", e)
STRICT = "--strict" in sys.argv          # warnings count as failures (used by check_all.ps1 -Strict)
failed = bool(errors) or (STRICT and bool(warnings))
print(f"\n{len(errors)} error(s), {len(warnings)} warning(s)")
sys.exit(1 if failed else 0)
