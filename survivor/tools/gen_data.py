#!/usr/bin/env python3
"""Emits every data Resource (.tres) from one readable spec table.

After generation the .tres files are the source of truth: edit them in the Godot inspector, or drop new
files into res://data/<kind>/ and the DB autoload picks them up on next launch with zero code changes.
Re-running this script overwrites the generated files, so treat it as the initial seed.

Ability ops:  {"stat": ["mul"|"add"|"set", value]}
  level_scaling : applied (level-1) times
  branch on_pick: applied once when the branch is chosen
  branch per_level: applied once per level gained AFTER the branch is picked
"""
import json, os
import evo_data

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def col(r, g, b): return f"Color({r/255:.3f}, {g/255:.3f}, {b/255:.3f}, 1)"


def val(v):
    if isinstance(v, str) and v.startswith("Color("): return v
    return json.dumps(v, ensure_ascii=False)


# Window rescale x0.75 (40-min plan -> 30-min plan). 9999 is "stays available
# forever" and must not be scaled. Applies to non-boss enemy defs only; bosses
# are hand-authored in their own .tres files.
def _window(v):
    return float(v) if float(v) >= 9999 else round(float(v) * 0.75, 3)


def emit(kind, cls, script, rid, fields):
    d = os.path.join(ROOT, "data", kind); os.makedirs(d, exist_ok=True)
    lines = [f'[gd_resource type="Resource" script_class="{cls}" load_steps=2 format=3]', "",
             f'[ext_resource type="Script" path="res://data/defs/{script}" id="1_s"]', "", "[resource]", 'script = ExtResource("1_s")']
    for k, v in fields.items(): lines.append(f"{k} = {val(v)}")
    open(os.path.join(d, f"{rid}.tres"), "w", encoding="utf-8").write("\n".join(lines) + "\n")


# ------------------------------------------------------------------------------------------------ characters
# base stat keys: max_hp, move_speed, damage (mult), defense (flat), regen (hp/s), area, cooldown (mult, lower=faster), pickup_radius, luck
def S(hp=100, spd=110, dmg=1.0, defense=1.0, regen=0.0, area=1.0, cd=1.0, pick=55, luck=0.0):
    return dict(max_hp=hp, move_speed=spd, damage=dmg, defense=defense, regen=regen, area=area, cooldown=cd, pickup_radius=pick, luck=luck)


CHARS = [
    dict(id="cowboy", name="Cowboy", title="The Drifter", order=1, color=col(214, 160, 88), weapon="six_shooter", passive="flailing_whip",
         blurb="Balanced all-rounder. Six shots, a reload, and a whip for anything that gets too close.",
         stats=S(), flags={}, playstyles=["Gunslinger: shrink the reload, chain 6-round bursts", "Piercer: line enemies up, shoot through the pack", "Brawler: lean on the whip aura and stay in the crowd"]),
    dict(id="ninja", name="Ninja", title="Shadow Blade", order=2, color=col(150, 70, 220), weapon="katana", passive="flash_bombs",
         blurb="Fastest on foot after the goose. Slashes fast and stuns whole crowds.",
         stats=S(hp=85, spd=150), flags={}, playstyles=["Whirlwind: max radius, cut everything around you", "Blitz: strike speed, single-target shredder", "Controller: bombs stun so everything else is free"]),
    dict(id="pirate", name="Pirate", title="Scourge of the Bay", order=3, color=col(200, 60, 60), weapon="hand_cannon", passive="pirate_crew",
         blurb="Huge HP, slow legs. One enormous piercing shot, and a crew that multiplies it.",
         stats=S(hp=160, spd=92, defense=2.0), flags={}, playstyles=["Artillery: bigger balls, longer lines of pierce", "Shrapnel storm: every hit sprays more shots", "Fleet admiral: stack allies for volley chaos"]),
    dict(id="paladin", name="Paladin", title="Oath of Dawn", order=4, color=col(240, 200, 70), weapon="greatsword", passive="prayer",
         blurb="Slow, sturdy, self-healing. Heavy sword swings and a radiant aura.",
         stats=S(hp=120, spd=98, defense=2.0, regen=1.0), flags={}, playstyles=["Crusader: wave-emitting sword hits at range", "Zealot: focused energy, faster heavier swings", "Saint: aura tank that heals while it burns"]),
    dict(id="wizard", name="Wizard", title="Archmage", order=5, color=col(90, 120, 240), weapon="merlins_book", passive="astral_projection",
         blurb="Glass cannon. Chain lightning and an astral double that duplicates your spells.",
         stats=S(hp=90, spd=110, dmg=1.3, defense=0.0), flags={}, playstyles=["Stormcaller: more chains, more voltage", "Orb mage: lightning orbs that zone the arena", "Astral burst: long-cooldown, massive double-cast windows"]),
    dict(id="spider", name="Spider", title="Weaver of Fear", order=6, color=col(150, 60, 200), weapon="fangs", passive="webs",
         blurb="Fast and vicious but fragile. Paralyzing bites and a single trap web.",
         stats=S(hp=65, spd=140, dmg=1.45), flags={}, playstyles=["Assassin: paralysis chance, lock down elites", "Reach: long fangs, bite from the edge of danger", "Trapper: big sticky webs that hold a whole wave"]),
    dict(id="minotaur", name="Minotaur", title="Labyrinth Lord", order=7, color=col(150, 96, 60), weapon="horns", passive="beasts_roar",
         blurb="Slow bruiser with heavy horn swipes and a roar that grants armor - break it and you're stunned.",
         stats=S(hp=170, spd=85, dmg=1.4, defense=2.0), flags={}, playstyles=["Berserker: rising fury, snowball your stats", "Bulldozer: charges that impale", "Juggernaut: thick armor, long roar windows"]),
    dict(id="harpy", name="Harpy Eagle", title="Queen of the Canopy", order=8, color=col(200, 190, 170), weapon="screech", passive="aerial_strike",
         blurb="Flies: ground melee cannot touch you. Aerial enemies and projectiles knock you down for up to 5s.", frames=8,
         stats=S(spd=115, dmg=0.85), flags={"flying": True, "knockdown_seconds": 5.0}, playstyles=["Sonic: long-range piercing screech waves", "Echo: consecutive screeches for burst", "Assassin dive vs. evasive dodger"]),
    dict(id="necromancer", name="Necromancer", title="Keeper of Bones", order=9, color=col(80, 200, 180), weapon="skull_summon", passive="raise_dead",
         blurb="Sturdy, regenerating, slow. Ghost skulls pierce everything, and the dead fight for you.",
         stats=S(hp=150, spd=90, dmg=0.75, regen=1.2, defense=1.0), flags={}, playstyles=["Skull barrage: many fast skulls", "Grand skull: one huge crushing skull", "Legion: keep a growing army of raised dead"],
         anims={"base": {"sprite": "res://art/characters/necromancer.png", "frames": 6, "fps": 6.0},
                "wA": {"sprite": "res://art/fx/skull_projectile.png", "frames": 2, "fps": 8.0},
                "wB": {"sprite": "res://art/fx/skull_projectile.png", "frames": 2, "fps": 4.0},
                "pA": {"sprite": "res://art/passives/raise_dead.png", "frames": 1, "fps": 8.0},
                "pB": {"sprite": "res://art/passives/raise_dead.png", "frames": 1, "fps": 8.0}}),
    dict(id="goose", name="Goose", title="Menace", order=10, color=col(245, 245, 250), weapon="fear", passive="turds",
         blurb="Very fast and fragile, but gets stronger the lower its health. Terrifies enemies instead of hurting them.",
         stats=S(hp=70, spd=165, dmg=0.8, defense=0.0),
         flags={"low_hp_scaling": {"damage": 0.9, "move_speed": 0.25, "cooldown": -0.35}},
         playstyles=["Honk tank: bigger fear, permanent crowd control", "Charge-and-peck: damage during charges", "Toxic swamp: poison turds cover the arena"]),
]

# Roster availability: 0 = PLAYABLE, 1 = LOCKED_TEASER, 2 = HIDDEN.
# Must match the tags in data/characters/*.tres (regen via this script keeps them).
# First five are polished/playable; spider..goose are locked silhouette teasers.
# jack/fun_guy are hand-added (not in CHARS) and tagged HIDDEN directly in their .tres.
LOCKED_HINT = "Locked - unlocks in the full release."

# ------------------------------------------------------------------------------------------------ abilities
def ability(kind, id, name, desc, behavior, audio, base, branches, level_scaling, color, level_text="", art=None, rarity=0, unlock_hint="", caps=None):
    return dict(kind=kind, id=id, name=name, desc=desc, behavior=behavior, audio=audio, base=base, branches=branches,
                scaling=level_scaling, color=color, level_text=level_text, art=art or {}, rarity=rarity, unlock_hint=unlock_hint,
                caps=caps or {})


# Card/HUD art keyed by ability id. Weapons are 64px cells, passives 32/64px singletons for now.
# preview: spin (shuriken), pulse (caltrops), static (passives), none (silhouette fallback).
# anims slots per character ability: base (pre-branch showcase) + wA/wB/pA/pB branch strips, filled in as drawn.
ART = {
    "pickup_shurikens": dict(icon="res://art/weapons/shuriken.png", icon_frames=3, icon_fps=10.0, preview_kind="spin", anims={}),
    "pickup_caltrops": dict(icon="res://art/weapons/caltrops.png", icon_frames=3, icon_fps=6.0, preview_kind="pulse", anims={}),
    "webs": dict(icon="res://art/passives/webs.png", icon_frames=1, icon_fps=8.0, preview_kind="static", anims={}),
    "raise_dead": dict(icon="res://art/passives/raise_dead.png", icon_frames=1, icon_fps=8.0, preview_kind="static", anims={}),
    "pirate_crew": dict(icon="res://art/passives/pirate_crew.png", icon_frames=1, icon_fps=8.0, preview_kind="static", anims={}),
    "skull_summon": dict(icon="res://art/fx/skull_projectile.png", icon_frames=2, icon_fps=8.0, preview_kind="static", anims={}),
    "pickup_blunderbuss": dict(icon="res://art/weapons/blunderbuss.png", icon_frames=1, icon_fps=8.0, preview_kind="static", anims={}),
    "pickup_rifle": dict(icon="res://art/weapons/rifle.png", icon_frames=1, icon_fps=8.0, preview_kind="static", anims={}),
    "pickup_dynamite": dict(icon="res://art/weapons/dynamite.png", icon_frames=3, icon_fps=8.0, preview_kind="pulse", anims={}),
    "pickup_keg": dict(icon="res://art/weapons/keg.png", icon_frames=3, icon_fps=8.0, preview_kind="pulse", anims={}),
    "greatsword": dict(icon="res://art/weapons/greatsword.png", icon_frames=1, icon_fps=8.0, preview_kind="static", anims={}),
    "prayer": dict(icon="res://art/passives/prayer.png", icon_frames=1, icon_fps=8.0, preview_kind="static", anims={}),
    "merlins_book": dict(icon="res://art/weapons/merlins_book.png", icon_frames=1, icon_fps=8.0, preview_kind="static", anims={}),
    "turds": dict(icon="res://art/passives/turd.png", icon_frames=1, icon_fps=8.0, preview_kind="static", anims={}),
    "pickup_shamir_tooth": dict(icon="res://art/weapons/shamir_tooth.png", icon_frames=1, icon_fps=8.0, preview_kind="static", anims={}),
}

UPGRADE_ART = {
    "might": "res://art/upgrades/might.png",
    "vitality": "res://art/upgrades/vitality.png",
    "swiftness": "res://art/upgrades/swiftness.png",
    "haste": "res://art/upgrades/haste.png",
    "magnet": "res://art/upgrades/magnet.png",
    "recovery": "res://art/upgrades/recovery.png",
    "plating": "res://art/upgrades/plating.png",
    "reach": "res://art/upgrades/reach.png",
    "fortune": "res://art/upgrades/fortune.png",
}


def B(id, name, desc, on_pick=None, per_level=None, flags=None, evo1=None, evo2=None):
    # evo1/evo2: optional hand-authored evolution pairs for this branch, each a
    # [EVO(...), EVO(...)] list (tier at 8 / tier at 16). Omitted = generated
    # branch-flavored fallback at runtime (see Ability.evo_option), so no branch
    # ever offers an empty evolution pair.
    return dict(id=id, name=name, desc=desc, on_pick=on_pick or {}, per_level=per_level or {}, flags=flags or {},
                evo1=evo1 or [], evo2=evo2 or [])


def EVO(id, name, desc, ops=None, ops2=None, ops3=None, flags=None, icon=None, icon_frames=1, icon_fps=8.0):
    d = dict(id=id, name=name, desc=desc, ops=ops or {}, ops2=ops2 or {}, ops3=ops3 or {}, flags=flags or {})
    if icon:
        d["icon"] = icon
        d["icon_frames"] = icon_frames
        d["icon_fps"] = icon_fps
    return d


ABILITIES = [
    # ---- Cowboy
    ability("weapon", "six_shooter", "6-Shooter", "Fires 6 consecutive shots, then reloads.", "revolver", "revolver_shot",
            dict(damage=12.0, shots=6, shot_interval=0.11, reload_time=1.7, pierce=0, range=520.0, speed=640.0, spread_deg=3.0, radius=4.0, count=1),
            [B("a", "Speed Loader", "Decrease reload time.", on_pick={"reload_time": ["mul", 0.8]}, per_level={"reload_time": ["mul", 0.9]},
                evo1=[EVO("running_reload", "Running Reload", "Reload charges 2.5x faster while you move, slower while standing still.", flags={"running_reload": {"moving_rate": 2.5, "still_rate": 0.7}}),
                       EVO("fan_the_hammer", "Fan the Hammer", "With an enemy inside ~80px, the cylinder dumps in a point-blank fan (4s cooldown).", flags={"fan_the_hammer": {"trigger_range": 80.0, "cooldown": 4.0, "fan_deg": 70.0}})],
                evo2=[EVO("quickdraw", "Quickdraw", "First shot after each reload is x3; take no damage during the reload and it pierces everything.", flags={"quickdraw": {"first_mult": 3.0, "perfect_pierce": 99}}),
                       EVO("showdown", "Showdown", "Marks the toughest enemy in range; hits on it gain bonus damage that peaks at mid-range.", flags={"showdown": {"bonus_max": 0.5, "peak": 0.6}})]),
             B("b", "Armor-Piercing Rounds", "Increase piercing.", on_pick={"pierce": ["add", 1]}, per_level={"pierce": ["add", 1]},
                evo1=[EVO("ricochet_rounds", "Ricochet Rounds", "A bullet's final pierce bounces once to the nearest enemy within 140px at 60%.", flags={"ricochet_rounds": {"bounces": 1, "range": 140.0, "mult": 0.6}}),
                       EVO("long_barrel", "Long Barrel", "+25% range; bullets gain damage with distance traveled (capped at +60%).", ops={"range": ["mul", 1.25]}, flags={"long_barrel": {"range_mult": 1.25, "per_100px": 0.1, "cap": 0.6}})],
                evo2=[EVO("dead_eye", "Dead-Eye", "Stand still 0.7s (crosshair tell): the next slug is x3 with unlimited pierce. Moving cancels.", flags={"dead_eye": {"still_time": 0.7, "mult": 3.0, "pierce": 99}}),
                       EVO("dead_mans_hand", "Dead Man's Hand", "The 6th bullet of each cylinder is an explosive Ace (70px burst).", flags={"dead_mans_hand": {"burst_radius": 70.0, "burst_mult": 2.5}})])],
            {"damage": ["mul", 1.07]}, col(255, 214, 120), caps={"cooldown": [0.60, 99.0], "damage": [0.1, 500.0], "shots": [1, 20], "reload_time": [0.9, 10.0], "pierce": [0, 4]}),
    ability("passive", "flailing_whip", "Flailing Whip", "Automatically strikes nearby enemies in melee range.", "whip", "whip_crack",
            dict(damage=9.0, interval=1.0, range=88.0, arc_deg=110.0, tick=0.25),
            [B("a", "Barbed Chain", "Constant low damage to everything within range.", on_pick={"tick": ["set", 0.22], "damage": ["mul", 0.35]}, per_level={"damage": ["mul", 1.14]}, flags={"mode": "aura"},
                evo1=[EVO("twirling_lasso", "Twirling Lasso", "The chain becomes an orbiting ring that spins faster the faster you move.", flags={"twirling_lasso": {"base_spin": 2.0, "spin_per_speed": 0.02, "hit_mult": 0.5}}),
                       EVO("dragging_chain", "Dragging Chain", "Leaves a barbed trail behind you for 2s (ground-only trap).", flags={"dragging_chain": {"life": 2.0, "spacing": 24.0, "dps_mult": 0.4}})],
                evo2=[EVO("roundup", "Roundup", "Every 8s the lasso cinches: everything in range is pulled in and stunned 0.6s (bosses immune).", flags={"roundup": {"every": 8.0, "pull_px": 60.0, "stun": 0.6}}),
                       EVO("barbed_fence", "Barbed Fence", "Every 6s drop a post; chains link the last three, damaging and slowing anything that crosses.", flags={"barbed_fence": {"every": 6.0, "posts": 3, "link_mult": 0.5, "slow": 0.6}})]),
             B("b", "Cracking Lash", "Semi-frequent long, narrow high-damage lashes.", on_pick={"interval": ["set", 1.4], "damage": ["mul", 2.4], "range": ["mul", 1.6]}, per_level={"damage": ["mul", 1.16]}, flags={"mode": "lash"},
                evo1=[EVO("sweet_spot", "Sweet Spot", "The lash becomes a long narrow line; its last 20% crits x2.", flags={"sweet_spot": {"length_mult": 1.6, "arc_deg": 30.0, "tip_frac": 0.2, "tip_mult": 2.0}}),
                       EVO("snap_parry", "Snap Parry", "The lash destroys hostile projectiles it crosses; each one shortens the next lash.", flags={"snap_parry": {"refund": 0.15, "refund_cap": 0.5}})],
                evo2=[EVO("fast_hands", "Fast Hands", "A lash that hits 3 or more enemies instantly reloads the six-shooter.", flags={"fast_hands": {"hits_needed": 3}}),
                       EVO("wanted_poster", "Wanted Poster", "Lashed elites and bosses are marked 8s: +25% damage from all sources while you stay within ~260px.", flags={"wanted_poster": {"mark_time": 8.0, "taken": 1.25, "leash": 260.0}})])],
            {"damage": ["mul", 1.07]}, col(200, 140, 80), caps={"damage": [0.1, 500.0], "interval": [0.5, 10.0], "range": [20.0, 400.0], "tick": [0.2, 5.0]}),
    # ---- Ninja
    ability("weapon", "katana", "Katana", "Close-range area swipe attacks.", "melee_swipe", "katana_slash",
            dict(damage=16.0, cooldown=0.7, radius=72.0, arc_deg=150.0, knockback=60.0, alternate=False),
            [B("a", "Wide Arc", "Increase radius.", on_pick={"radius": ["mul", 1.3]}, per_level={"radius": ["mul", 1.1]},
                evo1=[EVO("wayfinder", "Wayfinder", "Swings aim along your movement direction; standing still targets the nearest enemy.", flags={"wayfinder": {"aim_move": True}}),
                       EVO("momentum_edge", "Momentum Edge", "Moving builds up to 5 stacks of radius; they fade 0.6s after you stop.", flags={"momentum_edge": {"max_stacks": 5, "radius_per_stack": 0.06, "fade": 0.6, "build_per_sec": 2.5}})],
                evo2=[EVO("moonfall_whirl", "Moonfall Whirl", "Every 5th swing is a 360 degree whirl with a ring tell, brief invulnerability and knockback.", flags={"moonfall_whirl": {"every": 5, "tell": 0.4, "invuln": 0.25, "knockback": 160.0, "mult": 1.2}}),
                       EVO("afterimage", "Afterimage", "Each swing repeats from where you stood 0.6s later.", flags={"afterimage": {"delay": 0.6, "mult": 0.7}})]),
             B("b", "Blitz Strikes", "Increase strike speed.", on_pick={"cooldown": ["mul", 0.8]}, per_level={"cooldown": ["mul", 0.9]},
                evo1=[EVO("weaving_blades", "Weaving Blades", "Passing within ~30px of an enemy at speed fires a free slash (per-enemy cooldown).", flags={"weaving_blades": {"pass_radius": 30.0, "min_speed": 60.0, "per_enemy_icd": 1.2, "mult": 0.6}}),
                       EVO("unbroken_combo", "Unbroken Combo", "Hits build a combo; the 6th swing is a finisher. Taking damage resets it.", flags={"unbroken_combo": {"finisher_at": 6, "finisher_mult": 2.2, "reset_on_hurt": True}})],
                evo2=[EVO("thousand_cuts", "Thousand Cuts", "Every 8th swing locks a 1s flurry onto one enemy (elites first); you are slowed meanwhile.", flags={"thousand_cuts": {"every": 8, "duration": 1.0, "cuts": 10, "cut_mult": 0.5, "move_mult": 0.4, "prefer": "elite"}}),
                       EVO("reprisal", "Reprisal", "Getting hit triggers an instant cross-slash with heavy knockback (6s cooldown).", flags={"reprisal": {"cooldown": 6.0, "knockback": 220.0, "mult": 1.5}})])],
            {"damage": ["mul", 1.07]}, col(220, 230, 255), caps={"cooldown": [0.30, 99.0], "damage": [0.1, 500.0], "radius": [20.0, 130.0]}),
    ability("passive", "flash_bombs", "Flash Bombs", "Stuns nearby enemies at intervals.", "stun_pulse", "goblin_hit",
            dict(interval=6.0, radius=95.0, stun=1.2),
            [B("a", "Wide Flash", "Larger stun radius.", on_pick={"radius": ["mul", 1.3]}, per_level={"radius": ["mul", 1.12]},
                evo1=[EVO("smoke_veil", "Smoke Veil", "Leaves a 4s smoke cloud: enemies inside are slowed 40% and deal 30% less contact damage.", flags={"smoke_veil": {"life": 4.0, "slow": 0.6, "contact_mult": 0.7, "radius_mult": 1.0}}),
                       EVO("trailing_mines", "Trailing Mines", "Drops up to 4 flash mines along your path; each stuns when stepped on.", flags={"trailing_mines": {"max_mines": 4, "spacing": 60.0, "arm": 0.3, "stun": 1.0}})],
                evo2=[EVO("vanish", "Vanish", "Each flash makes you untargetable for 0.8s; your next swing within 2s is a x2.5 ambush.", flags={"vanish": {"untargetable": 0.8, "window": 2.0, "ambush_mult": 2.5}}),
                       EVO("cascade_flash", "Cascade Flash", "Stunned enemies that die emit a mini-flash (half radius, one generation only).", flags={"cascade_flash": {"radius_mult": 0.5, "generations": 1}})]),
             B("b", "Lingering Flash", "Longer stun duration.", on_pick={"stun": ["mul", 1.4]}, per_level={"stun": ["mul", 1.12]},
                evo1=[EVO("killing_light", "Killing Light", "The first katana hit on a stunned enemy is x2 and ends the stun. Stun is capped at 2s.", flags={"killing_light": {"hit_mult": 2.0, "stun_cap": 2.0}}),
                       EVO("panic_powder", "Panic Powder", "Enemies flee for 1.5s, then return slowed 30% for 2s.", flags={"panic_powder": {"fear": 1.5, "slow": 0.7, "slow_time": 2.0}})],
                evo2=[EVO("kawarimi", "Kawarimi", "When hit (12s cooldown) a log takes it, you blink ~120px away, and a flash stuns the area.", flags={"kawarimi": {"cooldown": 12.0, "blink": 120.0, "stun": 1.0, "radius_mult": 0.8}}),
                       EVO("five_point_palm", "Five-Point Palm", "Marks the 3 toughest enemies; 4s later each bursts for 20% max HP (elites 8%, bosses 2%).", flags={"five_point_palm": {"targets": 3, "delay": 4.0, "pct": 0.2, "pct_elite": 0.08, "pct_boss": 0.02}})])],
            {"interval": ["mul", 0.975]}, col(255, 255, 200), caps={"interval": [3.0, 30.0], "radius": [30.0, 150.0], "stun": [0.1, 1.8]}),
    # ---- Pirate
    ability("weapon", "hand_cannon", "Hand-Cannon", "Fires one large piercing bullet with a long reload.", "cannon", "hand_cannon",
            dict(damage=46.0, reload_time=3.0, pierce=99, radius=9.0, speed=470.0, range=560.0, shrapnel=0, shrapnel_damage=0.35, count=1),
            [B("a", "Shrapnel", "Extra projectiles on hit.", on_pick={"shrapnel": ["add", 3]}, per_level={"shrapnel": ["add", 1]},
                evo1=[EVO("chain_shot", "Chain Shot", "Fires a linked pair; the chain between the balls sweeps enemies.", flags={"chain_shot": {"spread": 0.12, "chain_width": 6.0, "chain_mult": 0.5}}),
                       EVO("broadside", "Broadside", "While moving, also fires smaller balls port and starboard. Standing still fires forward only.", flags={"broadside": {"side_balls": 2, "side_mult": 0.7, "min_speed": 30.0}})],
                evo2=[EVO("phantom_broadside", "Phantom Broadside", "Every 18s a ghost galleon sails along your heading (fog and horn tell) and rakes a wide lane.", flags={"phantom_broadside": {"every": 18.0, "tell": 1.0, "lane_width": 140.0, "length": 700.0, "mult": 1.5}}),
                       EVO("bombard", "Bombard", "Becomes a mortar: shells land on the densest cluster after 0.7s (ground tell). No piercing line.", flags={"bombard": {"delay": 0.7, "radius_mult": 1.4, "target": "densest", "blast": 64.0}})]),
             B("b", "Heavy Shot", "Projectile size increase.", on_pick={"radius": ["mul", 1.35], "damage": ["mul", 1.1]}, per_level={"radius": ["mul", 1.12]},
                evo1=[EVO("rebound", "Rebound", "The ball swings back at max range, hitting both ways. Catch it to cut your reload.", flags={"rebound": {"catch_radius": 18.0, "reload_refund": 1.0}}),
                       EVO("kickback", "Kickback", "Recoil becomes a 0.15s invulnerable backstep; the muzzle blasts a close cone.", flags={"kickback": {"backstep": 60.0, "time": 0.15, "cone_deg": 50.0, "cone_range": 90.0, "cone_mult": 0.6}})],
                evo2=[EVO("burning_pitch", "Burning Pitch", "The ball leaves a fire trail (patches last 3s, capped count).", flags={"burning_pitch": {"spacing": 40.0, "life": 3.0, "max_patches": 10, "dps_mult": 0.3, "radius": 26.0}}),
                       EVO("primed_powder", "Primed Powder", "Hits prime enemies with a 2s fuse; they explode, hurting neighbors (no chain reactions).", flags={"primed_powder": {"fuse": 2.0, "radius": 50.0, "mult": 0.6, "generations": 1}})])],
            {"damage": ["mul", 1.07]}, col(255, 120, 60), caps={"cooldown": [0.60, 99.0], "damage": [0.1, 1000.0], "reload_time": [1.6, 15.0], "shrapnel": [0, 6]}),
    ability("passive", "pirate_crew", "Pirate Crew", "Summons ally pirates. While the crew fights beside you, your projectiles are multiplied by the number of allies.", "summon_allies", "hand_cannon",
            dict(interval=14.0, allies=2, duration=6.0),
            [B("a", "Press Gang", "More allies spawned.", on_pick={"allies": ["add", 1]}, per_level={"allies": ["add", 1]},
                evo1=[EVO("gun_crew", "Gun Crew", "Each ally fires its own small cannon every 1.5s at its own target (replaces the projectile multiplier).", flags={"gun_crew": {"interval": 1.5, "mult": 0.5, "replaces_multiplier": True, "damage": 18.0}}),
                       EVO("boarding_party", "Boarding Party", "Every 4s an ally leaps onto the densest cluster for an area slam, then returns.", flags={"boarding_party": {"every": 4.0, "leap_range": 240.0, "radius": 60.0, "mult": 1.0}})],
                evo2=[EVO("jolly_roger", "Jolly Roger", "The crew plants a banner for 8s: inside it, reload is x2 and you regenerate.", flags={"jolly_roger": {"life": 8.0, "radius": 100.0, "reload_speed": 2.0, "regen": 2.0}}),
                       EVO("x_marks_the_spot", "X Marks the Spot", "Every 60s a dig spot appears ~300px away; reach it within 12s for a treasure draft.", flags={"x_marks_the_spot": {"every": 60.0, "distance": 300.0, "window": 12.0}})]),
             B("b", "Sea Legs", "Allies last longer.", on_pick={"duration": ["mul", 1.35]}, per_level={"duration": ["mul", 1.15]},
                evo1=[EVO("grog_rations", "Grog Rations", "The crew tosses a rum keg every 6s (one at a time): grab it for a small heal and a 5s damage buff.", flags={"grog_rations": {"every": 6.0, "heal_pct": 0.05, "buff_time": 5.0, "buff_mult": 1.25}}),
                       EVO("human_shield", "Human Shield", "Crew bodies intercept hostile projectiles; each intercepted shot triggers a free return blast.", flags={"human_shield": {"radius": 26.0, "counter_mult": 0.8, "damage": 14.0}})],
                evo2=[EVO("man_overboard", "Man Overboard", "A hit that would hurt you is absorbed by an ally, who respawns after 8s.", flags={"man_overboard": {"respawn": 8.0}}),
                       EVO("release_the_kraken", "Release the Kraken", "When the crew departs, tentacles slam three nearby clusters (0.8s ground tell).", flags={"release_the_kraken": {"slams": 3, "tell": 0.8, "radius": 55.0, "mult": 1.2}})])],
            {"interval": ["mul", 0.96]}, col(220, 80, 80), caps={"interval": [3.0, 60.0], "allies": [1, 4], "duration": [2.0, 10.0]}),
    # ---- Paladin
    ability("weapon", "greatsword", "Greatsword", "Slower than the katana but hits much harder.", "melee_swipe", "greatsword_swing",
            dict(damage=34.0, cooldown=1.5, radius=98.0, arc_deg=160.0, knockback=140.0, alternate=False, wave=False, wave_damage=0.55),
            [B("a", "Holy Wave", "Sword emits a projectile wave on top of the melee attack.", on_pick={}, per_level={"wave_damage": ["mul", 1.12]}, flags={"wave": True}),
             B("b", "Focused Zeal", "Concentrate energy: higher damage and faster swings.", on_pick={"damage": ["mul", 1.25], "cooldown": ["mul", 0.85]}, per_level={"damage": ["mul", 1.1], "cooldown": ["mul", 0.95]})],
            {"damage": ["mul", 1.07]}, col(255, 235, 160), caps={"cooldown": [0.8, 99.0], "damage": [0.1, 500.0], "radius": [20.0, 130.0]}),
    ability("passive", "prayer", "Prayer", "Flashes an illuminated aura at regular intervals.", "whip", "whip_crack",
            dict(damage=7.0, interval=4.5, range=115.0, tick=0.3),
            [B("a", "Sanctified Ground", "Constant low damage within range.", on_pick={"tick": ["set", 0.25], "damage": ["mul", 0.4]}, per_level={"damage": ["mul", 1.14]}, flags={"mode": "aura"}),
             B("b", "Judgement Pulse", "Semi-frequent high-damage pulses.", on_pick={"interval": ["set", 2.6], "damage": ["mul", 3.4], "range": ["mul", 1.2]}, per_level={"damage": ["mul", 1.16]}, flags={"mode": "pulse"})],
            {"damage": ["mul", 1.07]}, col(255, 240, 180), caps={"damage": [0.1, 500.0], "interval": [1.5, 30.0], "range": [20.0, 190.0], "tick": [0.1, 5.0]}),
    # ---- Wizard
    ability("weapon", "merlins_book", "Merlin's Book", "Zaps foes with a lightning bolt that chains to other enemies.", "chain_lightning", "lightning_bolt",
            dict(damage=14.0, cooldown=1.1, chains=2, chain_range=130.0, range=420.0, orb=False, orb_chains=3, orb_damage=0.5, orb_time=3.0),
            [B("a", "Storm Surge", "Stronger voltage and more chains.", on_pick={"damage": ["mul", 1.25], "chains": ["add", 2]}, per_level={"damage": ["mul", 1.05], "chains": ["add", 0.5]}),
             B("b", "Ball Lightning", "Leaves an orb that chains a fixed number of foes (lower damage, stays put).", on_pick={}, per_level={"orb_damage": ["mul", 1.06]}, flags={"orb": True})],
            {"damage": ["mul", 1.07]}, col(120, 200, 255), caps={"cooldown": [0.55, 99.0], "damage": [0.1, 500.0], "chains": [0, 6], "chain_range": [30.0, 400.0]}),
    ability("passive", "astral_projection", "Astral Projection", "Spawns a translucent astral copy that temporarily doubles projectiles.", "astral_clone", "lightning_bolt",
            dict(interval=12.0, duration=5.0, projectile_mult=2.0),
            [B("a", "Deep Trance", "Longer wait between projections, more projectiles while active.", on_pick={"interval": ["mul", 1.5], "projectile_mult": ["set", 3.0]}, per_level={"projectile_mult": ["add", 0.125]}),
             B("b", "Quick Mind", "Shorter intervals, fixed 1.5x projectile multiplier.", on_pick={"interval": ["mul", 0.55], "projectile_mult": ["set", 1.5]}, per_level={"interval": ["mul", 0.95]})],
            {"duration": ["mul", 1.05]}, col(180, 200, 255), caps={"interval": [8.0, 60.0], "duration": [2.0, 8.0], "projectile_mult": [1.0, 2.0]}),
    # ---- Spider
    ability("weapon", "fangs", "Fangs", "Close-range, fast, high damage. Applies paralysis.", "melee_bite", "fang_bite",
            dict(damage=20.0, cooldown=0.42, range=58.0, paralysis_chance=0.2, paralysis_time=0.9),
            [B("a", "Long Fangs", "Increase range.", on_pick={"range": ["mul", 1.3]}, per_level={"range": ["mul", 1.1]}),
             B("b", "Venom Sting", "Increase paralysis hit chance.", on_pick={"paralysis_chance": ["add", 0.15]}, per_level={"paralysis_chance": ["add", 0.08]})],
            {"damage": ["mul", 1.10]}, col(200, 90, 240), caps={"cooldown": [0.3, 99.0], "range": [0.0, 90.0], "paralysis_chance": [0.0, 0.5]}),
    ability("passive", "webs", "Webs", "Leaves a web that slows enemy movement and attack rate. One at a time; breaks after catching a set number of enemies.", "web", "fang_bite",
            dict(interval=8.0, radius=82.0, slow=0.5, capacity=12, lifetime=12.0),
            [B("a", "Wide Webs", "Larger webs.", on_pick={"radius": ["mul", 1.3]}, per_level={"radius": ["mul", 1.1]}),
             B("b", "Sticky Webs", "Stronger webs: stickier, more enemies before breaking.", on_pick={"slow": ["set", 0.32], "capacity": ["mul", 1.6]}, per_level={"capacity": ["mul", 1.15]})],
            {"lifetime": ["mul", 1.05]}, col(230, 230, 240), caps={"radius": [0.0, 130.0], "capacity": [0, 16], "lifetime": [0.0, 14.0]}),
    # ---- Minotaur
    ability("weapon", "horns", "Horns", "Swipe horns left and right: high damage, limited radius.", "melee_swipe", "horn_swipe",
            dict(damage=30.0, cooldown=0.85, radius=64.0, arc_deg=115.0, knockback=110.0, alternate=True, charge=False, charge_interval=6.0, charge_damage=2.5),
            [B("a", "Wild Gore", "Increased radius and attack speed.", on_pick={"radius": ["mul", 1.25], "cooldown": ["mul", 0.85]}, per_level={"radius": ["mul", 1.06], "cooldown": ["mul", 0.95]}),
             B("b", "Bull Rush", "Added charge attack: randomly charges at foes, impaling them on contact.", on_pick={}, per_level={"charge_damage": ["mul", 1.12]}, flags={"charge": True})],
            {"damage": ["mul", 1.10]}, col(238, 226, 190), caps={"cooldown": [0.6, 99.0], "radius": [0.0, 110.0], "charge_damage": [0.0, 4.0], "charge_interval": [4.0, 999.0]}),
    ability("passive", "beasts_roar", "Beast's Roar", "Shout at intervals for temporary stat boosts and armor. If the armor breaks, you're stunned.", "roar", "horn_swipe",
            dict(interval=15.0, duration=5.0, armor_hp=80.0, break_stun=1.5, boost_damage=0.2, boost_speed=0.1),
            [B("a", "Ironhide", "Increased armor and defense duration.", on_pick={"armor_hp": ["mul", 1.5], "duration": ["mul", 1.3]}, per_level={"armor_hp": ["mul", 1.12], "duration": ["mul", 1.06]}),
             B("b", "Rising Fury", "Increased base stat boosts (scales up).", on_pick={"boost_damage": ["add", 0.15], "boost_speed": ["add", 0.06]}, per_level={"boost_damage": ["add", 0.08], "boost_speed": ["add", 0.03]})],
            {"interval": ["mul", 0.96]}, col(220, 120, 60), caps={"armor_hp": [0.0, 160.0], "duration": [0.0, 8.0], "interval": [10.0, 999.0], "boost_damage": [0.0, 0.5], "boost_speed": [0.0, 0.25]}),
    # ---- Harpy
    ability("weapon", "screech", "Screech", "Emits a piercing sound wave that travels a short distance.", "wave", "screech",
            dict(damage=11.0, cooldown=1.2, distance=260.0, width=46.0, speed=420.0, consecutive=1, gap=0.16),
            [B("a", "Far Cry", "Increased distance.", on_pick={"distance": ["mul", 1.4]}, per_level={"distance": ["mul", 1.1]}),
             B("b", "Echo Screech", "Consecutive screeches.", on_pick={"consecutive": ["add", 1]}, per_level={"consecutive": ["add", 0.5]})],
            {"damage": ["mul", 1.10]}, col(255, 240, 200), caps={"distance": [0.0, 420.0], "consecutive": [0, 3], "cooldown": [0.8, 99.0], "width": [0.0, 70.0]}),
    ability("passive", "aerial_strike", "Aerial Strike", "At regular intervals, swoop in on prey with a piercing talon attack.", "swoop", "screech",
            dict(interval=7.0, damage=48.0, swoop_range=320.0, invuln=0.4, attack=True),
            [B("a", "Assassin's Dive", "Specialize for assassin build (higher damage).", on_pick={"damage": ["mul", 1.6], "interval": ["mul", 0.9]}, per_level={"damage": ["mul", 1.15]}),
             B("b", "Evasive Maneuvers", "Limit passive to evasive maneuvers only (invulnerability, no attack).", on_pick={"interval": ["set", 5.0], "invuln": ["set", 0.9]}, per_level={"interval": ["mul", 0.93], "invuln": ["add", 0.08]}, flags={"evasive": True})],
            {"damage": ["mul", 1.12]}, col(220, 200, 150), caps={"interval": [4.0, 999.0], "invuln": [0.0, 0.8]}),
    # ---- Necromancer
    ability("weapon", "skull_summon", "Skull Summon", "Summons an ethereal skull that passes through every enemy for low damage.", "skull", "skull_projectile",
            dict(damage=8.0, cooldown=1.6, count=1, speed=170.0, life=3.2, size=1.0, range=420.0),
            [B("a", "Skull Chorus", "More projectiles and faster attacks.", on_pick={"count": ["add", 1], "cooldown": ["mul", 0.85]}, per_level={"count": ["add", 0.5], "cooldown": ["mul", 0.95]}),
             B("b", "Grand Skull", "A single skull that grows in size and damage.", on_pick={"size": ["mul", 1.4], "damage": ["mul", 1.4]}, per_level={"size": ["mul", 1.1], "damage": ["mul", 1.12]})],
            {"damage": ["mul", 1.10]}, col(110, 240, 220), caps={"count": [0, 4], "cooldown": [0.8, 99.0], "size": [0.0, 2.0]}),
    ability("passive", "raise_dead", "Raise Dead", "Chance to raise an enemy on death (scales with player level). Raised enemies fight for you briefly at base stats. Elites are immune.", "raise_dead", "skull_projectile",
            dict(chance_base=0.06, chance_per_level=0.004, max_minions=3, duration=12.0, stat_mult=1.0),
            [B("a", "Legion", "Increase how many raised dead you can have.", on_pick={"max_minions": ["add", 2]}, per_level={"max_minions": ["add", 1]}),
             B("b", "Undying Bond", "Increase duration and base stats of raised dead.", on_pick={"duration": ["mul", 1.4], "stat_mult": ["add", 0.25]}, per_level={"duration": ["mul", 1.1], "stat_mult": ["add", 0.12]})],
            {"chance_base": ["add", 0.01]}, col(90, 220, 180), caps={"max_minions": [0, 6], "duration": [0.0, 16.0]}),
    # ---- Goose
    ability("weapon", "fear", "Fear", "Charges at enemies. No initial damage - foes in range are intimidated and retreat for a short time.", "goose_charge", "goose_charge",
            dict(interval=4.0, distance=240.0, charge_speed=520.0, fear_radius=130.0, fear_time=2.0, charge_damage=0.0),
            [B("a", "Peck Fury", "Add and scale damage attacks during the charge.", on_pick={"charge_damage": ["set", 14.0]}, per_level={"charge_damage": ["mul", 1.25]}),
             B("b", "Terrifying Honk", "Increase intimidation range and duration.", on_pick={"fear_radius": ["mul", 1.3], "fear_time": ["mul", 1.35]}, per_level={"fear_radius": ["mul", 1.08], "fear_time": ["mul", 1.08]})],
            {"interval": ["mul", 0.95]}, col(255, 255, 255), caps={"interval": [2.5, 999.0], "fear_radius": [0.0, 190.0], "fear_time": [0.0, 1.8]}),
    ability("passive", "turds", "Turds", "Leaves a turd once in a while; enemies who step on it slip (same stun as Flash Bombs).", "turds", "goblin_hit",
            dict(interval=3.5, max_turds=3, stun=1.0, lifetime=15.0, radius=16.0, poison_dps=0.0, poison_time=4.0),
            [B("a", "Volume Discount", "Increase amount of turds on screen.", on_pick={"max_turds": ["add", 2], "interval": ["mul", 0.8]}, per_level={"max_turds": ["add", 1]}),
             B("b", "Toxic Waste", "Cause poison and scaling damage.", on_pick={"poison_dps": ["set", 4.0]}, per_level={"poison_dps": ["mul", 1.25]})],
            {"stun": ["mul", 1.05]}, col(160, 120, 60), caps={"max_turds": [0, 6], "interval": [2.0, 999.0], "stun": [0.0, 1.5]}),
]

# ------------------------------------------------------------------------------------------------ treasure chest pickups
# Ported from the bare-bones-survivor weapon export (update/weapon_pickup_export). Granted via elite
# treasure chests, not character kits. max_level 5; re-picks level the weapon. cloak's missing
# barrier.tscn is replaced by a temp-armor ward (see PickupWard).
PICKUPS = [
    ability("weapon", "pickup_rifle", "Seal-Breaker Musket", "Forbidden weapon. Fires a single long-range piercing slug.", "pickup_volley", "revolver_shot",
            dict(damage=14.0, cooldown=0.35, count=1, spread_deg=0.0, pierce=2, range=520.0, speed=640.0, radius=4.0, knockback=30.0),
            [B("a", "Long Barrel", "Longer range, harder hits.", on_pick={"range": ["mul", 1.25]}, per_level={"damage": ["mul", 1.1]}),
             B("b", "Piercing Slugs", "Shots punch through more enemies.", on_pick={"pierce": ["add", 1]}, per_level={"pierce": ["add", 1]})],
            {"damage": ["mul", 1.12]}, col(230, 230, 230)),
    ability("weapon", "pickup_shurikens", "Shurikens", "Treasure weapon. Throws a fast fan of piercing shurikens.", "pickup_volley", "revolver_shot",
            dict(damage=8.0, cooldown=0.4, count=3, spread_deg=25.0, pierce=1, range=480.0, speed=560.0, radius=3.0, knockback=20.0),
            [B("a", "Fan Throw", "Throw more shurikens per volley.", on_pick={"count": ["add", 1]}, per_level={"damage": ["mul", 1.1]}),
             B("b", "Sharpened", "Harder, more piercing throws.", on_pick={"damage": ["mul", 1.3]}, per_level={"pierce": ["add", 1]})],
            {"damage": ["mul", 1.12]}, col(179, 179, 204)),
    ability("weapon", "pickup_blunderbuss", "Blunderbuss", "Treasure weapon. Short-range scatter blast with heavy knockback.", "pickup_volley", "hand_cannon",
            dict(damage=9.0, cooldown=1.1, count=7, spread_deg=45.0, pierce=0, range=300.0, speed=420.0, radius=8.0, knockback=240.0),
            [B("a", "Scattergun", "More pellets per blast.", on_pick={"count": ["add", 2]}, per_level={"damage": ["mul", 1.08]}),
             B("b", "Heavy Load", "Bigger, harder-hitting pellets.", on_pick={"damage": ["mul", 1.3], "radius": ["mul", 1.15]}, per_level={"damage": ["mul", 1.1]})],
            {"damage": ["mul", 1.12]}, col(255, 204, 128)),
    ability("weapon", "pickup_aa12", "Demon's Scattergun", "Forbidden weapon. Automatic shotgun: a wide volley of pellets.", "pickup_volley", "revolver_shot",
            dict(damage=7.0, cooldown=1.0, count=8, spread_deg=35.0, pierce=0, range=380.0, speed=520.0, radius=3.5, knockback=40.0),
            [B("a", "Drum Mag", "More pellets per volley.", on_pick={"count": ["add", 2]}, per_level={"cooldown": ["mul", 0.95]}),
             B("b", "Rapid Auto", "Faster volleys.", on_pick={"cooldown": ["mul", 0.85]}, per_level={"damage": ["mul", 1.1]})],
            {"damage": ["mul", 1.12]}, col(102, 102, 128)),
    ability("weapon", "pickup_dynamite", "Forbidden Explosives", "Forbidden weapon. Hurls dynamite at the nearest enemy: big area blast.", "pickup_blast", "hand_cannon",
            dict(damage=55.0, cooldown=2.4, radius=120.0, range=520.0),
            [B("a", "Big Bundle", "Much bigger explosions.", on_pick={"damage": ["mul", 1.35]}, per_level={"damage": ["mul", 1.12]}),
             B("b", "Long Fuse", "Wider blast radius.", on_pick={"radius": ["mul", 1.3]}, per_level={"radius": ["mul", 1.08]})],
            {"damage": ["mul", 1.12]}, col(255, 77, 51)),
    ability("weapon", "pickup_keg", "Keg of Gunpowder", "Treasure weapon. A huge slow keg blast that shakes the arena.", "pickup_blast", "hand_cannon",
            dict(damage=90.0, cooldown=4.5, radius=180.0, range=520.0),
            [B("a", "Powder Keg+", "Devastating damage.", on_pick={"damage": ["mul", 1.35]}, per_level={"damage": ["mul", 1.12]}),
             B("b", "Barrel Blast", "Wider blast, shorter fuse.", on_pick={"radius": ["mul", 1.25], "cooldown": ["mul", 0.9]}, per_level={"cooldown": ["mul", 0.95]})],
            {"damage": ["mul", 1.12]}, col(230, 153, 51)),
    ability("weapon", "pickup_caltrops", "Cursed Spikes", "Forbidden weapon. Scatters caltrops that shred enemies who step on them.", "pickup_caltrops", "fang_bite",
            dict(damage=8.0, interval=1.0, lifetime=12.0, max_caltrops=8, radius=14.0, rehit=1.0),
            [B("a", "Rusty Field", "Cover more ground.", on_pick={"max_caltrops": ["add", 3], "radius": ["mul", 1.25]}, per_level={"max_caltrops": ["add", 1]}),
             B("b", "Deep Cuts", "Faster, crueler drops.", on_pick={"damage": ["mul", 1.35], "interval": ["mul", 0.85]}, per_level={"damage": ["mul", 1.12]})],
            {"damage": ["mul", 1.12]}, col(153, 153, 153)),
    ability("weapon", "pickup_energy_food", "Angelic Manna", "Forbidden weapon. A snack break: double damage and faster legs for a few seconds.", "pickup_buff", "level_up",
            dict(damage=0.0, cooldown=18.0, duration=6.0),
            [B("a", "Feast", "The energy lasts longer.", on_pick={"duration": ["add", 2.0]}, per_level={"duration": ["add", 0.5]}),
             B("b", "Quick Snack", "Snack more often.", on_pick={"cooldown": ["mul", 0.8]}, per_level={"cooldown": ["mul", 0.95]})],
            {"duration": ["add", 0.5]}, col(102, 255, 102)),
    ability("weapon", "pickup_cloak", "Solomon's Ward", "Forbidden weapon. A warded cloak that absorbs damage for a few seconds.", "pickup_ward", "horn_swipe",
            dict(damage=0.0, cooldown=25.0, duration=8.0, armor_hp=40.0),
            [B("a", "Iron Lining", "The ward absorbs much more.", on_pick={"armor_hp": ["add", 20.0]}, per_level={"armor_hp": ["add", 10.0]}),
             B("b", "Long Watch", "The ward lasts longer.", on_pick={"duration": ["add", 2.0]}, per_level={"duration": ["add", 0.5]})],
            {"armor_hp": ["add", 8.0]}, col(128, 153, 255)),
    ability("weapon", "pickup_shamir_tooth", "Shamir's Tooth", "Rare treasure weapon. Blinks between the toughest enemies nearby, stabbing each one, then snaps back.", "flicker_strike", "katana_slash",
            dict(damage=35.0, cooldown=6.0, count=5, range=420.0, hop_interval=0.09, return_delay=0.12, retry_delay=0.4, land_offset=20.0, knockback=60.0),
            [B("a", "Deep Cut", "Deeper cuts: much harder stabs.", on_pick={"damage": ["mul", 1.35]}, per_level={"damage": ["mul", 1.12]}),
             B("b", "Long Hunt", "Hunt further, stab more foes.", on_pick={"count": ["add", 1], "range": ["mul", 1.2]}, per_level={"count": ["add", 0.5], "range": ["mul", 1.06]})],
            {"damage": ["mul", 1.12], "count": ["add", 3.0]}, col(150, 220, 255), rarity=1),
    # NOTE: pickup_shamir.tres is hand-maintained (max_level 8, legendary gate); re-apply by hand after any seed regen (same status as bone_broker/market listings).
    ability("weapon", "pickup_shamir", "Shamir", "Legendary treasure weapon. Burst from the earth astride the worm that split stone for Solomon's Temple. Ride fast and shred everything touched: lesser demons die, mighty ones lose chunks of max HP.", "worm_ride", "katana_slash",
            dict(duration=4.0, cooldown=14.0, speed_mult=2.2, trigger_range=480.0, retry_delay=0.5, shred_radius=64.0, hit_interval=0.1, elite_interval=0.5, elite_pct=0.04, boss_pct=0.015, knockback=60.0),
            [B("a", "Deep Maw", "Gnaw deeper chunks from the mighty.", on_pick={"elite_pct": ["mul", 1.35], "boss_pct": ["mul", 1.35]}, per_level={"elite_pct": ["mul", 1.12], "boss_pct": ["mul", 1.12]}),
             B("b", "Long Ride", "Ride longer, wider, sooner.", on_pick={"duration": ["add", 1.5], "cooldown": ["mul", 0.9], "shred_radius": ["add", 12.0]}, per_level={"duration": ["add", 0.25], "cooldown": ["mul", 0.97]})],
            {"duration": ["add", 0.25], "cooldown": ["add", -1.0], "elite_pct": ["mul", 1.15], "boss_pct": ["mul", 1.15]}, col(140, 107, 158), rarity=2, unlock_hint="Locked - bound by a seal yet unwritten."),
]

# ------------------------------------------------------------------------------------------------ enemies
# height: 0 ground / 1 air.  can_hit_flying: attacks that can reach airborne players (knocks Harpy out of flight).
ENEMIES = [
    dict(id="goblin", name="Goblin", family="goblin", hp=14, speed=52, damage=6, xp=1, radius=9, sprite="goblin", frames=4, behavior="chaser", height=0, elite=False, hit="goblin_hit", scale=1.0, weight=10, start=0, end=9999),
    dict(id="bat", name="Cave Bat", family="goblin", hp=8, speed=96, damage=5, xp=1, radius=8, sprite="bat", frames=4, behavior="swarm", height=1, elite=False, hit="goblin_hit", scale=0.75, weight=6, start=45, end=9999),
    dict(id="skeleton", name="Skeleton", family="skeleton", hp=24, speed=46, damage=7, xp=2, radius=9, sprite="skeleton", frames=4, behavior="chaser", height=0, elite=False, hit="skeleton_hit", scale=1.0, weight=7, start=60, end=9999),
    dict(id="zombie", name="Zombie", family="goblin", hp=44, speed=32, damage=9, xp=2, radius=10, sprite="zombie", frames=4, behavior="chaser", height=0, elite=False, hit="goblin_hit", scale=0.85, weight=5, start=90, end=9999),
    dict(id="goblin_assassin", name="Goblin Assassin", family="goblin", hp=12, speed=84, damage=10, xp=2, radius=8, sprite="goblin_assassin", frames=4, behavior="charger", height=0, elite=False, hit="goblin_hit", scale=1.0, weight=4, start=120, end=9999),
    dict(id="spider_enemy", name="Spider", family="goblin", hp=12, speed=88, damage=8, xp=2, radius=8, sprite="spider_enemy", frames=6, behavior="chaser", height=0, elite=False, hit="goblin_hit", scale=1.0, weight=4, start=120, end=9999),
    dict(id="raptor", name="Raptor", family="dinosaur", hp=52, speed=104, damage=12, xp=4, radius=11, sprite="raptor", frames=8, behavior="charger", height=0, elite=False, hit="dinosaur_hit", scale=1.0, weight=4, start=180, end=9999),
    dict(id="mummy", name="Mummy", family="skeleton", hp=60, speed=30, damage=11, xp=3, radius=11, sprite="mummy", frames=4, behavior="chaser", height=0, elite=False, hit="skeleton_hit", scale=1.0, weight=4, start=150, end=9999),
    dict(id="goblin_brute", name="Goblin Brute", family="goblin", hp=420, speed=44, damage=22, xp=40, radius=18, sprite="goblin_brute", frames=4, behavior="chaser", height=0, elite=True, can_hit_flying=True, hit="goblin_hit", scale=1.6, weight=0, start=150, end=9999, elite_every=75),
    dict(id="dragon_whelp", name="Dragon Whelp", family="dragon", hp=320, speed=60, damage=18, xp=60, radius=16, sprite="dragon_whelp", frames=4, behavior="ranged", height=1, elite=True, can_hit_flying=True, hit="dragon_hit", scale=1.5, weight=0, start=240, end=9999, elite_every=110, shoot_interval=2.3, shoot_speed=170, shoot_damage=14),
]

UPGRADES = [
    dict(id="might", name="Might", desc="+15% damage", stat="damage", op="mul", value=1.15, max=5, color=col(230, 90, 70)),
    dict(id="vitality", name="Vitality", desc="+24 max HP (heals 24)", stat="max_hp", op="add", value=24, max=5, color=col(220, 60, 90)),
    dict(id="swiftness", name="Swiftness", desc="+7% move speed", stat="move_speed", op="mul", value=1.07, max=5, color=col(90, 200, 230)),
    dict(id="haste", name="Haste", desc="-7% cooldowns", stat="cooldown", op="mul", value=0.93, max=5, color=col(240, 200, 80)),
    dict(id="magnet", name="Magnet", desc="+30% pickup radius", stat="pickup_radius", op="mul", value=1.3, max=5, color=col(120, 140, 240)),
    dict(id="recovery", name="Recovery", desc="+0.5 HP regen per second", stat="regen", op="add", value=0.5, max=5, color=col(110, 220, 130)),
    dict(id="plating", name="Plating", desc="+1 armor", stat="defense", op="add", value=1, max=5, color=col(170, 176, 190)),
    dict(id="reach", name="Reach", desc="+8% area", stat="area", op="mul", value=1.08, max=5, color=col(200, 120, 240)),
    dict(id="fortune", name="Fortune", desc="+10% luck (better level-up offers)", stat="luck", op="add", value=0.1, max=5, color=col(250, 220, 90)),
]


def main():
    evo_data.apply(ABILITIES, only=("greatsword",))
    for c in CHARS:
        locked = int(c.get("order", 99)) >= 6
        emit("characters", "CharacterDef", "character_def.gd", c["id"], dict(
            id=c["id"], display_name=c["name"], title=c["title"], roster_order=c["order"], blurb=c["blurb"],
            sprite=f"res://art/characters/{c['id'] if c['id'] != 'wizard' else 'wizard'}.png", frames=c.get("frames", 6), frame_size=64,
            weapon_id=c["weapon"], passive_id=c["passive"], base_stats=c["stats"], flags=c["flags"], color=c["color"], playstyles=c["playstyles"],
            ability_anims=c.get("anims", {}),
            roster_status=1 if locked else 0, unlock_hint=LOCKED_HINT if locked else ""))
    for a in ABILITIES:
        cls = "WeaponDef" if a["kind"] == "weapon" else "PassiveDef"
        art = ART.get(a["id"], dict(icon="", icon_frames=1, icon_fps=8.0, preview_kind="none", anims={}))
        emit("weapons" if a["kind"] == "weapon" else "passives", cls, "weapon_def.gd" if a["kind"] == "weapon" else "passive_def.gd", a["id"], dict(
            id=a["id"], display_name=a["name"], description=a["desc"], behavior=a["behavior"], audio_event=a["audio"], base=a["base"],
            branches=a["branches"], level_scaling=a["scaling"], max_level=8, branch_milestones=a.get("milestones", []), color=a["color"],
            icon=art["icon"], icon_frames=art["icon_frames"], icon_fps=art["icon_fps"], preview_kind=art["preview_kind"], anims=art["anims"],
            rarity=a.get("rarity", 0), unlock_hint=a.get("unlock_hint", ""), caps=a.get("caps", {})))
    for a in PICKUPS:
        art = ART.get(a["id"], dict(icon="", icon_frames=1, icon_fps=8.0, preview_kind="none", anims={}))
        emit("weapons", "WeaponDef", "weapon_def.gd", a["id"], dict(
            id=a["id"], display_name=a["name"], description=a["desc"], behavior=a["behavior"], audio_event=a["audio"], base=a["base"],
            branches=a["branches"], level_scaling=a["scaling"], max_level=5, color=a["color"],
            icon=art["icon"], icon_frames=art["icon_frames"], icon_fps=art["icon_fps"], preview_kind=art["preview_kind"], anims=art["anims"],
            rarity=a.get("rarity", 0), unlock_hint=a.get("unlock_hint", "")))
    for e in ENEMIES:
        emit("enemies", "EnemyDef", "enemy_def.gd", e["id"], dict(
            id=e["id"], display_name=e["name"], family=e["family"], max_hp=float(e["hp"]), speed=float(e["speed"]), contact_damage=float(e["damage"]), xp=e["xp"],
            radius=float(e["radius"]), sprite=f"res://art/enemies/{e['sprite']}.png", frames=e["frames"], behavior=e["behavior"], height=e["height"],
            is_elite=e["elite"], can_hit_flying=e.get("can_hit_flying", False), hit_event=e["hit"], sprite_scale=e["scale"], spawn_weight=e["weight"],
            spawn_start=_window(e["start"]), spawn_end=_window(e["end"]), elite_every=float(e.get("elite_every", 0)),
            shoot_interval=float(e.get("shoot_interval", 0)), shoot_speed=float(e.get("shoot_speed", 0)), shoot_damage=float(e.get("shoot_damage", 0))))
    for u in UPGRADES:
        emit("upgrades", "UpgradeDef", "upgrade_def.gd", u["id"], dict(
            id=u["id"], display_name=u["name"], description=u["desc"], stat=u["stat"], op=u["op"], value=float(u["value"]), max_level=u["max"], color=u["color"],
            icon=UPGRADE_ART.get(u["id"], "")))
    print("data written:", {k: len(os.listdir(os.path.join(ROOT, "data", k))) for k in ("characters", "weapons", "passives", "enemies", "upgrades")})


if __name__ == "__main__":
    main()
