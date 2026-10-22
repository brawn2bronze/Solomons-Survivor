# Evolution Overhaul: plan and wiring guide

*Solomon's Survivor. Design approved, nothing implemented yet. October 18, 2026.*

Covers all 10 roster characters: 20 abilities x 2 branches x 2 tiers x 2 options = **160 evolution options**.
Supersedes the Claude Doc "Evolution Overhaul Plan" where they differ (flags are now namespaced per option id, the roster is 10 characters, and the wiring is spelled out here).

## 0. Read this first (for OpenCode)

1. **Source of truth.** `tools/gen_data.py` emits the weapon and passive `.tres` files. Do not hand-edit generated `.tres`. Evolution data lives in `tools/evo_data.py` (this package) and is merged by `gen_data.py`. After any regen, re-add the hand-maintained files from the file map (`jack`, `fun_guy`, `bone_broker.tres`, `hellfire_devil.tres`, `glitch_goblin.tres`, `data/market/*.tres`, `pickup_shamir_tooth.tres`, `pickup_shamir.tres`).
2. **Land code before data.** Once evolution tables exist in the `.tres`, `Ability.evo_option()` will offer them at Lv8 and Lv16 whether or not the behavior exists. Do steps 2-8 first, then regenerate. Steps 3-4 add an allow-list (`EvoRegistry.READY`) so tiers only appear when both of their options are implemented; that is how each slice ships on its own.
3. **Files not reviewed while writing this plan:** `src/ui/ability_art.gd`, `data/defs/weapon_def.gd`, `passive_def.gd`, `ability_def.gd`, `autoload/db.gd`, `src/ui/dev_menu.gd`, `src/ui/dev_overlay.gd`, `src/core/fx_manager.gd`, `tools/check_project.py`. Read them before editing; function names here are proposals and should be adapted to what is there.
4. **Not run in Godot.** Everything below was written against the GDScript that was provided. The Python side (`evo_data.py`, `check_evo.py`, the `gen_data.py` patch) was run and validated; the GDScript sketches were not.
5. **Indentation:** the sketches use 4 spaces. Match each file (`world.gd` uses tabs, most others spaces).

## 1. Goals and rules

1. Movement and positioning matter for the whole run. Enemy scaling and new enemy attack behaviors come through the Acts (separate work). This plan makes the player side bounded and interesting.
2. Multiplicative stacking is capped everywhere (step 3 caps, step 9 floors).
3. Evolutions are behaviors, not stat boosts. Each branch has a Lv8 pair and a Lv16 pair.
4. Every option: changes what the player's feet do or when they commit; has a visible tell; is a sidegrade with a tradeoff; carries hard caps.
5. Tier roles: Lv4 branch = the fantasy (capped one-time bonus). Lv8 pair = a mode shift in how the attack is delivered. Lv16 pair = a signature moment (one commits, one protects).

## 2. What is broken (kit only, Lv16, before stat cards / Seal / Archive)

| Build | Lv1 | Lv16 |
|---|---|---|
| Katana, Blitz: cooldown | 0.70s | 0.067s (about 15 swings/s) |
| Katana, Wide Arc: radius | 72px | about 680px (screen is 640x360 world px) |
| Flash Bombs, Lingering: stun | 1.2s | about 18s, every 2.8s |
| Merlin's Book, Storm Surge: chains | 2 | 24, each hop at a flat 85% |
| Astral, Deep Trance: bolts per cast | x2 | about x7 |

Root causes: (1) per-level ops are geometric or unbounded; (2) milestones at Lv10/13 replay `per_level`, and every evolution is a generated fallback that replays `per_level` or `on_pick` (Deep Trance even resets its `set` ops); (3) weapon and passive multiply each other; (4) stun is uncapped and locks bosses; (5) the draft always offers the best option; (6) enemy scaling is linear (Acts work).

## 3. Package contents

| File | Purpose |
|---|---|
| `docs/evolution_overhaul.md` | This plan. Section 10 is generated. |
| `tools/evo_data.py` | All 160 options (id, name, card text, tuning params, icon brief) and per-ability caps. |
| `tools/check_evo.py` | Validator: counts, ids, text length, caps, icon presence. Run in CI or before each regen. |
| `tools/gen_evo_catalog.py` | Rebuilds section 10 from `evo_data.py`. |
| `tools/gen_data.evo.patch` | The 3-line change to `gen_data.py`. |
| `art/evo/<id>.png` | The 160 icons (to be drawn; see section 9). |

Apply the patch: `cd tools && patch gen_data.py < gen_data.evo.patch`, or make the three edits by hand: `import evo_data` near the top, `evo_data.apply(ABILITIES)` as the first line of `main()`, and `caps=a.get("caps", {})` added to the kit-ability `emit(...)` call.

## 4. Wiring steps (in order)

### Step 1. Data (do last, see section 0.2)
```
python tools/check_evo.py        # must print OK
python tools/gen_data.py         # emits evo1/evo2 tables and `caps`
```
Each generated branch gains `evo1` and `evo2` arrays of `{id, name, desc, ops, ops2, ops3, flags, icon, icon_frames, icon_fps}`. Option parameters are namespaced: `flags = {'wayfinder': {'aim_move': true}}`.

### Step 2. Schema
Add `@export var caps: Dictionary = {}` to `WeaponDef` and `PassiveDef` (or their shared `AbilityDef`). Shape: `{"cooldown": {"min": 0.3}, "radius": {"max": 130.0}}`, either bound optional.

### Step 3. Ability core (`src/abilities/ability.gd`)
```gdscript
var evo_ids: Array = []          # ids of the picked tier-1 and tier-2 options (derived in recompute)
var evo_mods: Array = []         # live EvoModule instances for evo_ids
var _meters: Dictionary = {}
var _counts: Dictionary = {}
var _timers: Array = []          # deferred callbacks [{t, cb}]

func recompute() -> void:
    # ... existing body unchanged ...
    for ops in mod_ops:
        _apply(ops as Dictionary)
    _clamp_p()
    _refresh_evos()

func _clamp_p() -> void:
    var caps = def.get("caps")
    if not (caps is Dictionary) or (caps as Dictionary).is_empty():
        return
    for k in (caps as Dictionary).keys():
        if not p.has(k):
            continue
        var c: Dictionary = (caps as Dictionary)[k]
        var v: float = float(p[k])
        if c.has("min"):
            v = maxf(v, float(c["min"]))
        if c.has("max"):
            v = minf(v, float(c["max"]))
        p[k] = v
```
Remove the milestone replay and the generated fallbacks:
```gdscript
# _apply_milestones(b): inside the loop, replace `_apply(b["per_level"])` with `continue`
# (only hand-authored branch_milestones entries apply).

# evo_option(tier, idx): at the end return {} instead of _fallback_evo(...). Delete _fallback_evo.

func has_authored_evo(tier: int) -> bool:
    if branch < 0:
        return false
    for i in 2:
        var o: Dictionary = evo_option(tier, i)
        if o.is_empty() or not EvoRegistry.is_ready(String(o.get("id", ""))):
            return false
    return true

# needs_evo(tier): add `and has_authored_evo(tier)` to both the tier-1 and tier-2 returns.
```
Evolution modules and helpers:
```gdscript
func _refresh_evos() -> void:
    var want: Array = []
    if branch >= 0:
        if evo1 >= 0:
            want.append(String(evo_option(1, evo1).get("id", "")))
        if evo2 >= 0:
            want.append(String(evo_option(2, evo2).get("id", "")))
    want.erase("")
    if want == evo_ids:
        return
    evo_ids = want
    var keep: Array = []
    for id in evo_ids:
        var m = null
        for old in evo_mods:
            if old.id == id:
                m = old
        if m == null:
            m = EvoRegistry.make(String(id))
            if m == null:
                continue
            m.ab = self
            m.id = String(id)
            m.on_ready()
        keep.append(m)
    evo_mods = keep

func has_evo(id: String) -> bool:
    return evo_ids.has(id)

func hook(name: String, ctx: Dictionary = {}) -> void:        # ctx is mutable: modules may edit it
    for m in evo_mods:
        m.call(name, ctx)

func update_evos(delta: float) -> void:                        # called every frame from Player
    for m in evo_mods:
        m.update(delta)
    for i in range(_timers.size() - 1, -1, -1):
        _timers[i]["t"] = float(_timers[i]["t"]) - delta
        if float(_timers[i]["t"]) <= 0.0:
            var cb: Callable = _timers[i]["cb"]
            _timers.remove_at(i)
            cb.call()

## Value 0..cap that rises while `active` and falls otherwise (movement meters).
func meter(key: String, delta: float, active: bool, up: float, down: float, cap: float) -> float:
    var v: float = clampf(float(_meters.get(key, 0.0)) + (up if active else -down) * delta, 0.0, cap)
    _meters[key] = v
    return v

func meter_spend(key: String) -> float:
    var v: float = float(_meters.get(key, 0.0))
    _meters[key] = 0.0
    return v

## True on every n-th call (every-Nth swing, volley, pulse).
func nth(key: String, n: int) -> bool:
    var c: int = int(_counts.get(key, 0)) + 1
    if c >= n:
        _counts[key] = 0
        return true
    _counts[key] = c
    return false

## Run `cb` after `delay` seconds of sim time (telegraphed strikes, afterimages).
func after(delay: float, cb: Callable) -> void:
    _timers.append({"t": delay, "cb": cb})
```
Note: `Ability.on_kill` and the other overridable hooks are replaced by subclasses, so evolution hooks are **not** routed through them. Player and World call `hook(...)` directly (step 5).

### Step 4. EvoModule, registry and per-ability files
```gdscript
# src/abilities/evo/evo_module.gd
class_name EvoModule
extends RefCounted
var ab: Ability
var id := ""

func p(key: String, fallback: Variant = 0.0) -> Variant:      # this option's own tuning params
    return (ab.flags.get(id, {}) as Dictionary).get(key, fallback)

func on_ready() -> void: pass
func update(_delta: float) -> void: pass
func on_attack(_ctx: Dictionary) -> void: pass        # before an attack resolves; may edit ctx (dir, radius, mult, cancel)
func on_hit(_ctx: Dictionary) -> void: pass           # after a hit: {e, amount}
func on_hurt(_ctx: Dictionary) -> void: pass          # player took damage: {amount}
func on_player_cast(_ctx: Dictionary) -> void: pass   # the OTHER ability fired (Spell Echo, Fast Hands, Hunting Pack)
func on_kill(_e) -> void: pass
func draw(_canvas: Node2D) -> void: pass
```
```gdscript
# src/abilities/evo/evo_registry.gd
class_name EvoRegistry
extends RefCounted
## Ids whose behavior is implemented. A tier is only offered when BOTH its options are listed.
const READY := {}      # e.g. {"wayfinder": true, "momentum_edge": true}

static func is_ready(id: String) -> bool:
    return READY.has(id)

static func make(id: String) -> EvoModule:
    match id:
        "wayfinder": return KatanaEvo.Wayfinder.new()
        # ... one line per option ...
    return null
```
One file per ability (20 files, e.g. `src/abilities/evo/katana_evo.gd` with `class_name KatanaEvo` and one inner class per option), the same style as `weapon_behaviors.gd`. Keep each option's state inside its module.

### Step 5. Player (`src/player/player.gd`)
```gdscript
const COOLDOWN_FLOOR := 0.60
const PROJ_MULT_CAP := 3.0
var moving := false
var speed_ratio := 0.0         # speed / move_speed, 0..1+
var untargetable := 0.0        # seconds; honored by contact, projectiles and enemy aim

# _process, after movement:
moving = vel.length() > 12.0
speed_ratio = vel.length() / maxf(1.0, stat("move_speed"))
# after weapon.update / passive.update:
weapon.update_evos(delta)
passive.update_evos(delta)

# _tick_timers: untargetable = maxf(0.0, untargetable - delta)
# _draw: weapon.hook("draw_evos") is replaced by a loop calling m.draw(self) for both abilities' evo_mods.

# stat(): add to the existing if/elif chain on stat_name:
elif stat_name == "cooldown":
    v = maxf(v, COOLDOWN_FLOOR)         # after low-HP scaling, so Goose cannot bypass it

# projectile_multiplier(): return minf(m, PROJ_MULT_CAP)
# _late_scaled_value(): change the 0.6 late bonus to 0.15 (or remove it).

# take_damage(): early out `if dead or invuln > 0.0 or untargetable > 0.0: return`; after damage is applied
# (both the armor path and the hp path) call:
#   weapon.hook("on_hurt", {"amount": amount}); passive.hook("on_hurt", {"amount": amount})

func blink_to(pos: Vector2, invuln_s: float = 0.2) -> void:
    var from := global_position
    global_position = pos
    invuln = maxf(invuln, invuln_s)
    vel = Vector2.ZERO
    world.fx.ring(from, 4.0, 30.0, 0.2, def.color, 2.0)
    world.fx.ring(pos, 6.0, 40.0, 0.25, def.color, 3.0)
```
`World.on_kill(e)`: after `player.passive.on_kill(e)` add `for m in player.weapon.evo_mods + player.passive.evo_mods: m.on_kill(e)`.
Cross-ability event: whenever a weapon or passive fires its main action, call `player.broadcast_cast(src, ctx)`, which runs `hook("on_player_cast", ctx)` on the other ability.

### Step 6. EnemyManager (`src/core/enemy_manager.gd`)
```gdscript
const CC_MAX := 1.8
const CC_IMMUNITY := 1.5
const HIT_GATE := 0.1

# class E: add
var stun_imm := 0.0
var fear_imm := 0.0
var marks: Dictionary = {}     # id -> {"t": seconds, "stacks": int, "taken": float}
var gate: Dictionary = {}      # source id -> next time it may damage this enemy

# spawn(): reset  e.stun_imm = 0.0; e.fear_imm = 0.0; e.marks.clear(); e.gate.clear()

func stun(e: E, seconds: float) -> void:
    if float(e.def.boss_time) > 0.0 or e.stun_imm > 0.0:
        return
    e.stun = maxf(e.stun, minf(seconds, CC_MAX) * (0.5 if e.is_elite else 1.0))

func fear(e: E, seconds: float, from_pos: Vector2) -> void:    # same pattern with fear_imm
    if float(e.def.boss_time) > 0.0 or e.fear_imm > 0.0:
        return
    e.fear = maxf(e.fear, minf(seconds, CC_MAX) * (0.5 if e.is_elite else 1.0))
    e.fear_from = from_pos

# slow(): for bosses `mult = maxf(mult, 0.7)` before applying.
# _update_enemy(): tick stun_imm / fear_imm down; when stun or fear reaches 0 set the matching *_imm = CC_IMMUNITY.
```
Hit gate and marks:
```gdscript
# damage(): new optional last parameter `src: String = ""`; after the alive / blink / glitch checks:
if src != "":
    var now: float = world.run_time
    if float(e.gate.get(src, -1.0)) > now:
        return
    e.gate[src] = now + HIT_GATE
amount *= taken_mult(e)
# melee and pulse callers pass def.id (MeleeSwipe._swipe, Whip._radial, StunPulse...). DoT bypasses the gate.

func add_mark(e: E, id: String, dur: float, stacks_add: int = 1, max_stacks: int = 1, taken: float = 1.0) -> int:
    var m: Dictionary = e.marks.get(id, {"t": 0.0, "stacks": 0, "taken": taken})
    m["stacks"] = mini(max_stacks, int(m["stacks"]) + stacks_add)
    m["t"] = dur
    e.marks[id] = m
    return int(m["stacks"])

func mark_stacks(e: E, id: String) -> int:
    return int((e.marks.get(id, {}) as Dictionary).get("stacks", 0))

func taken_mult(e: E) -> float:
    var m := 1.0
    for k in e.marks.keys():
        m *= float((e.marks[k] as Dictionary).get("taken", 1.0))
    return m
# _update_enemy(): if e.marks is not empty, decrement each "t"; erase at <= 0 (fire an expiry callback if registered).

func pull(center: Vector2, radius: float, px: float) -> void:
    # knock decays as exp(-8*t), so total travel is knock / 8: multiply px by 8.
    for e in query_circle(center, radius):
        if float(e.def.boss_time) > 0.0:
            continue
        var d := center - e.pos
        e.knock += d.normalized() * minf(px, d.length()) * 8.0
```
Also: `nearest(center, max_r, exclude)` should accept a Dictionary of uids instead of `Array.has` (chains and swipes call it constantly on the APK), and `_boss`/`_ranged`/contact checks should skip when `player.untargetable > 0.0`.

### Step 7. ProjectileManager (`src/core/projectile_manager.gd`)
```gdscript
## mode: "destroy" | "reflect" | "absorb". Returns how many hostile shots were affected.
func intercept(center: Vector2, radius: float, mode: String = "destroy") -> int:
    var n := 0
    var r2 := radius * radius
    for i in range(live.size() - 1, -1, -1):
        var pr: Pr = live[i]
        if pr.kind != Kind.HOSTILE or pr.pos.distance_squared_to(center) > r2:
            continue
        n += 1
        if mode == "reflect":
            pr.kind = Kind.BULLET          # friendly from now on
            pr.vel = -pr.vel
            pr.radius = 5.0
            pr.pierce = 0
            pr.hit.clear()
            pr.color = Color(1.0, 0.95, 0.7)
        else:
            pr.splash_r = 0.0              # a destroyed round must not splash on expiry
            pr.life = 0.0
    return n
```
Also needed by options: `fire(..., opts)` gains `bounce` (Ricochet), `returning` (Rebound), `homing` (Reaper's Skull) and `grow_to` (Splitting Skull) keys. Add them as option-driven behaviors in `_process`, not new kinds.

### Step 8. Card flow (`src/core/world.gd`)
```gdscript
# _owed_cards(), tier > 0 branch: build the text without trailing blank lines and pass the icon through.
var ops_txt := UI.describe_ops(ops)
var desc2: String = String(opt.get("desc", ""))
if ops_txt != "":
    desc2 += "\n\n" + ops_txt
out.append(_card(kind, ab.def.id, String(opt.get("name", "Evolve")), tag, "%s  %s Lv %d (free)" % [ab.def.display_name, ab.branch_name(), ab.level], desc2, ab.def.color,
    {"branch": ab.branch, "evolution": true, "evo_kind": kind, "tier": tier, "evo": e,
     "evo_icon": String(opt.get("icon", "")), "evo_frames": int(opt.get("icon_frames", 1)), "evo_fps": float(opt.get("icon_fps", 8.0))}))

# _card_art(): first lines
var ep := String(ch.get("evo_icon", ""))
if ep != "" and ResourceLoader.exists(ep):
    return {"path": ep, "frames": int(ch.get("evo_frames", 1)), "fps": float(ch.get("evo_fps", 8.0)), "preview": "static", "fallback": false}
# ... existing branch / base art follows, so cards still work before an icon is drawn.
```
`_choice_key` already includes `evo` and `tier`, so banish keys stay unique. The HUD slots keep the ability icon.

### Step 9. Phase-0 tuning fixes (data and small code)
1. **Cooldown floor**: done in step 5 (global 0.60) plus per-ability floors via `caps`.
2. **Chain falloff**: `ChainLightning._zap`: `dmg() * pow(0.8, i)` (compounding) instead of a flat 0.85.
3. **Hit-stop throttle**: `MeleeSwipe._swipe`: allow heavy hit-stop at most once per 0.6s of `run_time` (the Katana counts as "heavy" from about Lv7 and strobes at high swing rates).
4. **Growth re-budget** in `gen_data.py`: kit `level_scaling` damage from x1.10 to about x1.07 per level; Lv4 `per_level` multipliers halved or turned into capped adds. Verify with the simulator (section 8).
5. **CC rules**: step 6.

### Step 10. Dev tooling and checks
- `World.dev_max_build(wb, pb, e1 = 0, e2 = 0)` and `_dev_max_ability(ab, branch_idx, e1, e2)` pass the evolution indices to `apply_evo`.
- DevOverlay: set weapon and passive level, branch, evo A/B, and a "show effective stat" readout (so caps are visible while testing).
- The five characters Spider, Minotaur, Harpy Eagle, Necromancer and Goose are `LOCKED_TEASER`. To sandbox them, let DevMenu pick locked characters or temporarily set their `roster_status = 0`.
- `tools/check_project.py` should call `check_evo.py` and fail on its errors.
- Smoke test: for each ability and each of the 4 evolution routes, run the sandbox 20s at 300 enemies with no script errors.

## 5. Shared primitives (build once, reuse)

| # | Primitive | Sketch | Used by (examples) |
|---|---|---|---|
| 1 | Movement meter | `Ability.meter(...)`; Player `moving`, `speed_ratio` | Running Reload, Momentum Edge, Twirling Lasso, Crusader's March, Static Charge, Pilgrim's Road |
| 2 | Every-Nth counter | `Ability.nth(key, n)` | Quickdraw, Dead Man's Hand, Moonfall Whirl, Thousand Cuts, Dawnbreaker, Final Judgement, Bone Storm, Labrys Whirl |
| 3 | Marks and stacking statuses | `EnemyManager.add_mark / mark_stacks / taken_mult` | Showdown, Wanted Poster, Neurotoxin, Echolocation, Breaking Charge, Hunting Pack, Mass Hysteria, Wrapped Prey, Five-Point Palm |
| 4 | Ground zones | Generalize the Caltrops/Turds decal pattern: radius, life, tick, enter/stay callbacks, `seen` gating | Dragging Chain, Smoke Veil, Trailing Mines, Burning Pitch, Consecration, Pilgrim's Road, Jolly Roger, Sanctuary, Territory Mark, Toxic Swamp |
| 5 | Segment hits | Shared helper over `Geometry2D.get_closest_point_to_segment` (as MyceliumNet) | Barbed Fence, Chain Shot, Lightning Lance, Faraday Cage, Silk Zip |
| 6 | Hostile-projectile hook | `ProjectileManager.intercept(pos, radius, mode)` | Snap Parry, Mirror Wave, Human Shield, Bulwark Stance, Faraday Cage, Warcry Shockwave, Gale Wings, Wing Flap, Honk of Doom |
| 7 | Pull / push | `EnemyManager.pull(center, radius, px)`; bosses immune | Roundup, Hook Swing, Singularity, Sanctuary, Tolling Bell, Silk Tethers, Whirlwind Wake |
| 8 | Blink / dash | `Player.blink_to`, existing `start_dash`, `Player.untargetable` | Holy Leap, Blink Strike, Kawarimi, Boarding Party, Astral Swap, Vanish, Pounce, Silk Zip, Slingshot Web, Rending Chain |
| 9 | Actors | Base class for allies, clones and pets (follow, anchor or mirror; cast callback). Global cap about 12 active | Gun Crew, Astral Anchor, Mirror Image, Spell Echo, Flock Chorus, Egg Sacs, Gosling Parade, Bone Archers, Bone Colossus |
| 10 | Telegraphed strike | `Ability.after(delay, cb)` plus FxManager cues (`ring`, `cue_converge`, `cue_wedge`, `cue_sweep`) | Dawnbreaker, Final Judgement, Bombard, Release the Kraken, Capacitor, Moonfall Whirl, Grave Surge, Shadow Drop, Gaggle, Flyover |
| 11 | Carry / attach | Glue an enemy to the player or a projectile for a duration | Fling, Skewer |
| 12 | Steered / straight-run dash | Dash direction follows input; detect a straight run | Steered Rush, Ramming Speed |
| 13 | Orbit / spiral emitters | Rotating emitters around the player or a point | Skull Spiral, Bone Storm, Orbit Guard, Seraph Ring, Dawnbreaker |
| 14 | Condition triggers | HP-threshold and no-hit-streak hooks | Maniac Mode, Last Stand, Perfect Pitch, Lay on Hands, Death Pact |

## 6. Hook map (ability, behavior class, call sites to add)

| Ability | Class (file) | Notes |
|---|---|---|
| katana, greatsword, horns | `WeaponBehaviors.MeleeSwipe` | One class serves three characters. `update`: meters; `_swipe`: `hook("on_attack", {dir, radius, arc, origin, mult})` before the query and `on_hit` after; `_try_charge` (horns): steer, carry, run-up triggers. Pass `def.id` as the damage `src`. |
| six_shooter | `Revolver` | `update` reload branch needs a rate multiplier; `_shoot` gets `on_attack` (first-shot, 6th-bullet flags); Ricochet is a `bounce` opt in `ProjectileManager.fire`. |
| hand_cannon | `Cannon` | `_fire` gets `on_attack`; Rebound and Chain Shot need new projectile opts; Kickback replaces the `player.impulse` recoil. |
| flailing_whip, prayer | `PassiveBehaviors.Whip` | Shared class (`def.id == "prayer"` already branches). Hooks in the aura tick, the lash branch and `_radial`. |
| flash_bombs | `StunPulse` | After the pulse: `hook("on_attack", {origin, radius, stunned})`. |
| pirate_crew | `SummonAllies` | Gun Crew replaces `player.proj_mults["crew"]`; `_summon` / `_dismiss` hooks. |
| astral_projection | `AstralClone` | Spell Echo needs the weapon's cast event (`on_player_cast`); `_begin` / `_end` hooks. |
| merlins_book | `ChainLightning` | `update` cast, `_zap` (chain count, falloff), `_update_orbs` (orb options). |
| fangs | `MeleeBite` | Bite loop: stacks, lunge counter, hide state. |
| webs | `Web` | Single web becomes a list for Home Turf (max 2). |
| beasts_roar | `Roar` | `_roar` / `_expire` / `on_armor_break` hooks. |
| screech | `Screech` | `_emit_wave` (fan, backward aim, marks). |
| aerial_strike | `Swoop` | `update` (chain, shadow drop) and the evasive branch. |
| skull_summon | `SkullSummon` | `update` volley (spiral, ring, homing every 4th). |
| raise_dead | `RaiseDead` | `on_kill` (failed roll burst, champion), minion update (archers). |
| fear | `GooseCharge` | `update` (chain), `start_dash` callbacks (wing flap, droppings). |
| turds | `Turds` | `_drop` / `update` (golden egg, flyover, gosling, ripe fuse). |

## 7. Build order (vertical slices)

| Slice | Scope | Primitives | Done when |
|---|---|---|---|
| 0 | Steps 2-10 foundation (no options) | none | Lv16 builds within section 8 targets in the simulator; no cooldown below its floor in play |
| 1 | Ninja (Katana + Flash Bombs) | 1, 2, 3, 4, 8, 10 | Each option works in the sandbox with tell and cap; playtested on the APK |
| 2 | Wizard (Merlin's Book + Astral) | 1, 5, 7, 8, 9, 10 | Same |
| 3 | Pirate (replaces the ally multiplier) | 4, 6, 7, 9, 10 | Same |
| 4 | Cowboy | 1, 2, 3, 4, 5, 6, 7 | Same |
| 5 | Paladin | 1, 2, 3, 4, 6, 7, 8, 10 | Same |
| 6 | Minotaur (reuses MeleeSwipe and Roar) | 2, 4, 6, 7, 8, 11, 12 | Same |
| 7 | Spider | 3, 4, 5, 8, 9 | Same |
| 8 | Goose | 4, 6, 8, 9, 10, 14 | Same |
| 9 | Harpy Eagle | 3, 6, 7, 8, 9, 10, 14 | Same |
| 10 | Necromancer | 3, 9, 10, 13, 14 | Same |

Slices 1-5 are by how broken each playable character is; 6-10 are by primitive reuse. Icons are drawn in the same order. A slice ships by adding its option ids to `EvoRegistry.READY`.

## 8. Balance targets and tooling

Proposed starting targets (tune after the Act scaling lands):
- Kit-only DPS index at Lv16 about 5-7x Lv1 for every build (Katana Blitz was about 40x+).
- No cooldown or reload below its floor; at most 7 chain hits and 3 bolts per cast.
- No non-boss enemy under crowd control more than about 60% of the time; bosses 0%.
- Boss fights last long enough that positioning matters.
- Goose: the 0.60 cooldown floor applies after her low-HP scaling.
- Harpy: Shadow Drop and High Altitude require `flying`; a knockdown disables them.
- Active actors (allies, clones, pets) capped at about 12 globally for the APK.

Tooling: a Python simulator (run on the design side, not in OpenCode) reads `gen_data.py` and `evo_data.py` and reports effective DPS index and capped params per level and evolution route. In game: the F3 overlay at 300 enemies for frame time.

## 9. Icon production spec

- **Files:** one PNG per option at `res://art/evo/<id>.png`, 160 total (16 per character). Missing files fall back to the branch or base art, so they can arrive in any order.
- **Format:** transparent PNG, horizontal frame strip, **64x64 px per frame** (matches the weapon icon cells). One frame by default; optional 2-4 frames with `icon_frames` / `icon_fps` set in `evo_data.py` (3 frames at 6-10 fps matches the shuriken and caltrop strips). Use the same import settings as the existing icons.
- **Display:** cards show the icon at 84px inside a 96px backdrop tinted by the ability's accent color, so use no solid background and keep about a 4px margin. Silhouettes should read at 40px.
- **Visual language:** each icon combines the ability's motif (katana, revolver, orb, cannon...) with one glyph for the behavior (arrow, ring, mark, trail, clone...). The card tag band already says EVOLUTION or FINAL, so no tier badges.
- **Delivery order:** Ninja, Wizard, Pirate, Cowboy, Paladin, Minotaur, Spider, Goose, Harpy Eagle, Necromancer.
- **Progress check:** `python tools/check_evo.py` prints icons present out of 160; `--strict-icons` fails on any missing file.
- **Optional (not needed for this overhaul):** 20 Lv4 branch icons, `res://art/evo/branch_<ability>_<a|b>.png`. Those cards currently fall back to the ability's base icon.

## 10. Option catalog (160)

Icon file for each option: `res://art/evo/<id>.png`. The Behavior column is the card text. Tuning parameters are in `tools/evo_data.py`.

<!-- CATALOG:START (generated by tools/gen_evo_catalog.py; edit tools/evo_data.py instead) -->

### 10.1 Cowboy

**6-Shooter** (A = Speed Loader, B = Armor-Piercing Rounds)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `running_reload` | Running Reload | A · Lv8 | Reload charges 2.5x faster while you move, slower while standing still. | Revolver cylinder with motion lines |
| `fan_the_hammer` | Fan the Hammer | A · Lv8 | With an enemy inside ~80px, the cylinder dumps in a point-blank fan (4s cooldown). | Revolver with a fan of six shots |
| `quickdraw` | Quickdraw | A · Lv16 | First shot after each reload is x3; take no damage during the reload and it pierces everything. | Fast-drawn revolver with a big muzzle flash |
| `showdown` | Showdown | A · Lv16 | Marks the toughest enemy in range; hits on it gain bonus damage that peaks at mid-range. | Crosshair over a duel silhouette |
| `ricochet_rounds` | Ricochet Rounds | B · Lv8 | A bullet's final pierce bounces once to the nearest enemy within 140px at 60%. | Bullet path with a bounce angle |
| `long_barrel` | Long Barrel | B · Lv8 | +25% range; bullets gain damage with distance traveled (capped at +60%). | Long barrel with distance ticks |
| `dead_eye` | Dead-Eye | B · Lv16 | Stand still 0.7s (crosshair tell): the next slug is x3 with unlimited pierce. Moving cancels. | Eye with a crosshair pupil |
| `dead_mans_hand` | Dead Man's Hand | B · Lv16 | The 6th bullet of each cylinder is an explosive Ace (70px burst). | Ace of spades with a bullet |

**Flailing Whip** (A = Barbed Chain, B = Cracking Lash)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `twirling_lasso` | Twirling Lasso | A · Lv8 | The chain becomes an orbiting ring that spins faster the faster you move. | Spinning lasso loop |
| `dragging_chain` | Dragging Chain | A · Lv8 | Leaves a barbed trail behind you for 2s (ground-only trap). | Barbed chain trailing behind |
| `roundup` | Roundup | A · Lv16 | Every 8s the lasso cinches: everything in range is pulled in and stunned 0.6s (bosses immune). | Lasso tightening around dots |
| `barbed_fence` | Barbed Fence | A · Lv16 | Every 6s drop a post; chains link the last three, damaging and slowing anything that crosses. | Fence posts joined by barbed wire |
| `sweet_spot` | Sweet Spot | B · Lv8 | The lash becomes a long narrow line; its last 20% crits x2. | Whip with a glowing tip |
| `snap_parry` | Snap Parry | B · Lv8 | The lash destroys hostile projectiles it crosses; each one shortens the next lash. | Whip slicing a projectile |
| `fast_hands` | Fast Hands | B · Lv16 | A lash that hits 3 or more enemies instantly reloads the six-shooter. | Whip coiled around a revolver cylinder |
| `wanted_poster` | Wanted Poster | B · Lv16 | Lashed elites and bosses are marked 8s: +25% damage from all sources while you stay within ~260px. | WANTED poster with a skull |

### 10.2 Ninja

**Katana** (A = Wide Arc, B = Blitz Strikes)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `wayfinder` | Wayfinder | A · Lv8 | Swings aim along your movement direction; standing still targets the nearest enemy. | Katana arc trailing along a curved arrow |
| `momentum_edge` | Momentum Edge | A · Lv8 | Moving builds up to 5 stacks of radius; they fade 0.6s after you stop. | Blade with five stacked speed lines |
| `moonfall_whirl` | Moonfall Whirl | A · Lv16 | Every 5th swing is a 360 degree whirl with a ring tell, brief invulnerability and knockback. | Crescent moon over a full spinning ring |
| `afterimage` | Afterimage | A · Lv16 | Each swing repeats from where you stood 0.6s later. | Katana with a translucent ghost copy |
| `weaving_blades` | Weaving Blades | B · Lv8 | Passing within ~30px of an enemy at speed fires a free slash (per-enemy cooldown). | Zig-zag path through three dots with slash marks |
| `unbroken_combo` | Unbroken Combo | B · Lv8 | Hits build a combo; the 6th swing is a finisher. Taking damage resets it. | Chain of six slashes, the last one larger |
| `thousand_cuts` | Thousand Cuts | B · Lv16 | Every 8th swing locks a 1s flurry onto one enemy (elites first); you are slowed meanwhile. | Many tiny slashes converging on one point |
| `reprisal` | Reprisal | B · Lv16 | Getting hit triggers an instant cross-slash with heavy knockback (6s cooldown). | Bold X slash over a cracked shield |

**Flash Bombs** (A = Wide Flash, B = Lingering Flash)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `smoke_veil` | Smoke Veil | A · Lv8 | Leaves a 4s smoke cloud: enemies inside are slowed 40% and deal 30% less contact damage. | Billowing smoke puff |
| `trailing_mines` | Trailing Mines | A · Lv8 | Drops up to 4 flash mines along your path; each stuns when stepped on. | Row of small glowing mines |
| `vanish` | Vanish | A · Lv16 | Each flash makes you untargetable for 0.8s; your next swing within 2s is a x2.5 ambush. | Fading ninja silhouette with a dagger glint |
| `cascade_flash` | Cascade Flash | A · Lv16 | Stunned enemies that die emit a mini-flash (half radius, one generation only). | Big flash spawning smaller flashes |
| `killing_light` | Killing Light | B · Lv8 | The first katana hit on a stunned enemy is x2 and ends the stun. Stun is capped at 2s. | Shattering star over a blade |
| `panic_powder` | Panic Powder | B · Lv8 | Enemies flee for 1.5s, then return slowed 30% for 2s. | Powder burst with arrows pointing outward |
| `kawarimi` | Kawarimi | B · Lv16 | When hit (12s cooldown) a log takes it, you blink ~120px away, and a flash stuns the area. | Wooden log with a puff of smoke |
| `five_point_palm` | Five-Point Palm | B · Lv16 | Marks the 3 toughest enemies; 4s later each bursts for 20% max HP (elites 8%, bosses 2%). | Open palm with five glowing points |

### 10.3 Pirate

**Hand-Cannon** (A = Shrapnel, B = Heavy Shot)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `chain_shot` | Chain Shot | A · Lv8 | Fires a linked pair; the chain between the balls sweeps enemies. | Two cannonballs joined by a chain |
| `broadside` | Broadside | A · Lv8 | While moving, also fires smaller balls port and starboard. Standing still fires forward only. | Ship hull side with cannon blasts |
| `phantom_broadside` | Phantom Broadside | A · Lv16 | Every 18s a ghost galleon sails along your heading (fog and horn tell) and rakes a wide lane. | Ghostly galleon in fog |
| `bombard` | Bombard | A · Lv16 | Becomes a mortar: shells land on the densest cluster after 0.7s (ground tell). No piercing line. | Arcing shell above a target ring |
| `rebound` | Rebound | B · Lv8 | The ball swings back at max range, hitting both ways. Catch it to cut your reload. | Cannonball with a return arrow |
| `kickback` | Kickback | B · Lv8 | Recoil becomes a 0.15s invulnerable backstep; the muzzle blasts a close cone. | Muzzle blast with a recoil arrow |
| `burning_pitch` | Burning Pitch | B · Lv16 | The ball leaves a fire trail (patches last 3s, capped count). | Cannonball with a flaming trail |
| `primed_powder` | Primed Powder | B · Lv16 | Hits prime enemies with a 2s fuse; they explode, hurting neighbors (no chain reactions). | Powder keg with a lit fuse |

**Pirate Crew** (A = Press Gang, B = Sea Legs)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `gun_crew` | Gun Crew | A · Lv8 | Each ally fires its own small cannon every 1.5s at its own target (replaces the projectile multiplier). | Pirate silhouette with a small cannon |
| `boarding_party` | Boarding Party | A · Lv8 | Every 4s an ally leaps onto the densest cluster for an area slam, then returns. | Pirate leaping with a cutlass |
| `jolly_roger` | Jolly Roger | A · Lv16 | The crew plants a banner for 8s: inside it, reload is x2 and you regenerate. | Skull-and-crossbones flag |
| `x_marks_the_spot` | X Marks the Spot | A · Lv16 | Every 60s a dig spot appears ~300px away; reach it within 12s for a treasure draft. | Treasure map with a red X |
| `grog_rations` | Grog Rations | B · Lv8 | The crew tosses a rum keg every 6s (one at a time): grab it for a small heal and a 5s damage buff. | Rum barrel |
| `human_shield` | Human Shield | B · Lv8 | Crew bodies intercept hostile projectiles; each intercepted shot triggers a free return blast. | Pirate behind a round shield |
| `man_overboard` | Man Overboard | B · Lv16 | A hit that would hurt you is absorbed by an ally, who respawns after 8s. | Life ring with a splash |
| `release_the_kraken` | Release the Kraken | B · Lv16 | When the crew departs, tentacles slam three nearby clusters (0.8s ground tell). | Kraken tentacle rising from water |

### 10.4 Paladin

**Greatsword** (A = Holy Wave, B = Focused Zeal)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `crusaders_march` | Crusader's March | A · Lv8 | Moving steadily builds Advance stacks (max 3), each adding a wave to your swing. | Sword with three wave arcs |
| `mirror_wave` | Mirror Wave | A · Lv8 | Waves reflect hostile projectiles back at enemies. | Wave arc bouncing bolts back |
| `dawnbreaker` | Dawnbreaker | A · Lv16 | Every 5th swing plants the blade: 8 beams rotate for 1.5s (0.4s ring tell). | Planted sword with eight radiating beams |
| `pilgrims_road` | Pilgrim's Road | A · Lv16 | Moving lays radiant ground for 3s that burns enemies and gives you +15% speed while on it. | Glowing footsteps on a road |
| `fervor` | Fervor | B · Lv8 | Hits build Fervor (max 10) for up to +35% swing speed and damage; it decays after 3s without a hit. | Flame wrapped around a sword |
| `retribution` | Retribution | B · Lv8 | Damage taken charges the blade; the next swing releases a knockback nova (capped). | Cracked shield pulsing a shockwave |
| `holy_leap` | Holy Leap | B · Lv16 | Every 7s vault to the toughest enemy within 220px and slam, stunning 0.8s (bosses immune). | Armored knight mid-leap above a landing ring |
| `bulwark_stance` | Bulwark Stance | B · Lv16 | Stand still 1s to raise a shield arc toward the nearest enemy: blocks shots, -60% damage from it. | Tower shield with a guard arc |

**Prayer** (A = Sanctified Ground, B = Judgement Pulse)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `consecration` | Consecration | A · Lv8 | Drops holy ground every 4s (5s life): you heal standing on it, enemies on it burn. | Glowing sigil circle |
| `seraph_ring` | Seraph Ring | A · Lv8 | Three orbs orbit the aura edge, burning and knocking back whatever they touch. | Ring of three light orbs |
| `sanctuary` | Sanctuary | A · Lv16 | Every 20s a hallowed zone (5s) pushes enemies out and halves damage you take inside. | Dome of light |
| `lay_on_hands` | Lay on Hands | A · Lv16 | Below 30% HP (60s cooldown) a burst heals 40% and knocks everything back. | Two glowing hands with a cross |
| `tolling_bell` | Tolling Bell | B · Lv8 | The pulse becomes an expanding ring with knockback; its far edge hits x1.5. | Bell with an expanding ring |
| `verdict_mark` | Verdict Mark | B · Lv8 | The pulse marks the 3 toughest; 1s later marked enemies within 300px take a x2 follow-up strike. | Gavel above a mark |
| `final_judgement` | Final Judgement | B · Lv16 | Every 3rd pulse is screen-wide after a 1.2s sky tell (capped % damage vs elites). | Divine eye inside a sunburst |
| `twin_suns` | Twin Suns | B · Lv16 | The pulse comes from two suns hovering ~150px either side of you. | Two small suns flanking a figure |

### 10.5 Wizard

**Merlin's Book** (A = Storm Surge, B = Ball Lightning)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `static_charge` | Static Charge | A · Lv8 | Moving builds static (up to +4 chains), spent on your next cast. Standing still bleeds it. | Spark-wreathed footprint |
| `lightning_lance` | Lightning Lance | A · Lv8 | The bolt becomes a narrow beam through every enemy on the line to the target. | Straight lightning beam piercing three dots |
| `blink_strike` | Blink Strike | A · Lv16 | Every 8s blink ~200px along your heading, leaving a lightning scar and a thunder ring on arrival. | Two ghost wizards joined by a lightning line |
| `capacitor` | Capacitor | A · Lv16 | Casts fill a meter; at full (0.4s tell) 12 bolts hit the 12 nearest enemies at once. | Glowing coil radiating many bolts |
| `orbit_guard` | Orbit Guard | B · Lv8 | Up to 3 orbs circle you and zap anything that comes within ~130px. | Three orbs on an orbit ring |
| `rolling_thunder` | Rolling Thunder | B · Lv8 | The orb rolls ahead along your heading for 3s, zapping what it passes. | Orb with a motion trail and a forward arrow |
| `singularity` | Singularity | B · Lv16 | With 3 orbs out they fuse and drift toward you for 4s, pulling enemies in, then detonate. | Dark swirling core with inward arrows |
| `faraday_cage` | Faraday Cage | B · Lv16 | Standing inside the triangle of 3 orbs you ignore hostile projectiles; crossing enemies are zapped. | Triangle of three orbs joined by arcs |

**Astral Projection** (A = Deep Trance, B = Quick Mind)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `astral_anchor` | Astral Anchor | A · Lv8 | The clone stays where summoned and casts on its own. Plant it, then run. | Ghostly wizard pinned to a spot |
| `mirror_image` | Mirror Image | A · Lv8 | The clone mirrors your movement across your position. | Wizard and mirrored ghost either side of an axis |
| `astral_swap` | Astral Swap | A · Lv16 | The projection ends with you and the clone swapping places; both spots detonate. | Two wizards with swap arrows |
| `ethereal_walk` | Ethereal Walk | A · Lv16 | You become the projection for 4s: ghost through enemies (no contact damage), spells at half rate. | Translucent wizard walking through silhouettes |
| `spell_echo` | Spell Echo | B · Lv8 | The clone repeats your cast 0.5s later at 70% power (replaces the projectile multiplier). | Bolt followed by a fainter echo bolt |
| `flow_state` | Flow State | B · Lv8 | Kills during a projection extend it 0.3s each (capped at +4s). | Hourglass with a flowing swirl |
| `time_stop` | Time Stop | B · Lv16 | Every 4th projection freezes enemies for 1.5s (bosses immune). | Clock face frozen inside a ring |
| `wild_magic` | Wild Magic | B · Lv16 | The clone casts a random spell (Frost Nova, Meteor, Gravity Pull), each with its own tell. | Three-way swirl of mixed colored sparks |

### 10.6 Spider

**Fangs** (A = Long Fangs, B = Venom Sting)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `pounce` | Pounce | A · Lv8 | Every 4th bite lunges ~90px at the target with brief invulnerability and bites x2 on arrival. | Spider mid-leap with fangs bared |
| `hit_and_run` | Hit and Run | A · Lv8 | Each bite grants a 1s speed burst (stacking to +50%). Dart in, bite, dart out. | Fang with speed lines |
| `silk_zip` | Silk Zip | A · Lv16 | Every 6s a silk line fires at the farthest enemy within 300px and you zip to it, biting everything on it. | Silk line with a spider at its end |
| `ambush` | Ambush | A · Lv16 | Stand still 1s to hide (translucent). The next bite is x3 and paralyzes a small burst. | Faint spider silhouette with glowing eyes |
| `neurotoxin` | Neurotoxin | B · Lv8 | Bites stack venom (max 5, 6s); at 5 stacks the enemy is paralyzed 1.5s (bosses immune). | Fang dripping green venom with stack pips |
| `spreading_venom` | Spreading Venom | B · Lv8 | Venomed enemies pass 1 stack to enemies within ~50px each second (max 6 infected). | Venom drop splitting into smaller drops |
| `toxic_cloud` | Toxic Cloud | B · Lv16 | Venomed enemies that die leave a 4s poison cloud that re-applies venom. | Green poison cloud with a skull |
| `lethal_dose` | Lethal Dose | B · Lv16 | Biting a 5-stack enemy consumes the stacks for 40% of its current HP (elites 15%, bosses 4%). | Syringe over five stack pips |

**Webs** (A = Wide Webs, B = Sticky Webs)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `home_turf` | Home Turf | A · Lv8 | Up to 2 webs at once; on your webs you move 30% faster and enemies are slowed. | Web with a boot print |
| `silk_tethers` | Silk Tethers | A · Lv8 | A web fires 6 strands that leash the farthest enemies and drag them slowly toward it. | Web with strands pulling inward |
| `slingshot_web` | Slingshot Web | A · Lv16 | Stepping onto your web launches you ~150px along your heading with brief invulnerability (3s cooldown). | Web stretched like a slingshot |
| `collapsing_web` | Collapsing Web | A · Lv16 | When a web breaks, caught enemies are cocooned 1s (bosses immune) and crushed for heavy damage. | Web collapsing into a cocoon |
| `wrapped_prey` | Wrapped Prey | B · Lv8 | The toughest enemy in a web is held 1.2s and takes +30% from all sources (once per web). | Silk-wrapped bundle |
| `egg_sacs` | Egg Sacs | B · Lv8 | Enemies that die in a web leave sacs that hatch into 2 spiderlings for 6s (max 6). | Egg sac with tiny spiderlings |
| `feast` | Feast | B · Lv16 | When a web breaks you absorb it: heal 3% max HP per caught enemy (capped at 20%) and +20% speed for 3s. | Spider mouth over a dissolving web |
| `venom_weave` | Venom Weave | B · Lv16 | Webs apply a venom stack to enemies inside every 0.5s (works with Neurotoxin). | Web strands dripping venom |

### 10.7 Minotaur

**Horns** (A = Wild Gore, B = Bull Rush)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `fling` | Fling | A · Lv8 | The last enemy hit by each swing is hurled 220px as a living projectile, damaging those it hits (once). | Horn tossing a tumbling enemy |
| `hook_swing` | Hook Swing | A · Lv8 | Swings pull enemies at the arc edge inward, clumping the pack for the next swing. | Curved horn hooking inward arrows |
| `labrys_whirl` | Labrys Whirl | A · Lv16 | Every 6th swing starts a 1.2s whirl: keep moving at 70% speed, hitting all around every 0.2s. | Double-headed axe spinning |
| `labyrinth_walls` | Labyrinth Walls | A · Lv16 | Every 8s raise a half-ring of stone pillars ahead for 3s: they hurt, knock back and block projectiles. | Arc of stone pillars |
| `steered_rush` | Steered Rush | B · Lv8 | The charge follows the direction you hold; with no input it targets the nearest enemy. | Charging bull with a steering arrow |
| `skewer` | Skewer | B · Lv8 | Charges carry the first non-elite enemy hit on your horns, then slam it at the end for area damage. | Horns impaling an enemy |
| `ramming_speed` | Ramming Speed | B · Lv16 | Run in a straight line for 1s to trigger a 300px charge at x2 damage (4s cooldown); no random timer. | Bull with long speed lines |
| `breaking_charge` | Breaking Charge | B · Lv16 | Enemies hit by a charge are Broken for 5s: +25% damage from all sources. | Cracked armor plate |

**Beast's Roar** (A = Ironhide, B = Rising Fury)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `spiked_hide` | Spiked Hide | A · Lv8 | While armored, enemies that hit you take thorns damage and are knocked back. | Armor plate bristling with spikes |
| `warcry_shockwave` | Warcry Shockwave | A · Lv8 | The roar pushes enemies 100px away and destroys hostile projectiles. | Bull head with a shockwave ring |
| `armor_burst` | Armor Burst | A · Lv16 | When the roar armor breaks you explode in a shock nova and gain 1s invulnerability instead of being stunned. | Shattering armor with a nova |
| `armored_charge` | Armored Charge | A · Lv16 | Each roar launches an armored charge toward the nearest enemy (ignores the charge cooldown). | Armored bull mid-charge |
| `outnumbered` | Outnumbered | B · Lv8 | While roaring, +3% damage per enemy within 120px (capped at +30%). | Bull ringed by small enemies |
| `thundering_hooves` | Thundering Hooves | B · Lv8 | While roaring, every 0.5s of movement stomps a small shock ring around you. | Hoof with a shock ring |
| `bulldozer` | Bulldozer | B · Lv16 | While roaring you grow, cannot be knocked back or stunned, and shove enemies aside as you move. | Huge bull plowing enemies aside |
| `last_stand` | Last Stand | B · Lv16 | Below 30% HP the roar refreshes instantly (40s cooldown) at x1.5 strength. | Bull head with a cracked heart |

### 10.8 Harpy Eagle

**Screech** (A = Far Cry, B = Echo Screech)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `echolocation` | Echolocation | A · Lv8 | Waves mark enemies they hit; each mark (max 3) makes later waves hit harder. | Sound wave pinging a target |
| `gale_wings` | Gale Wings | A · Lv8 | Waves shove enemies back hard and destroy hostile projectiles they cross. | Wing with gust lines |
| `shatterpoint` | Shatterpoint | A · Lv16 | Enemies with 3 marks shatter in a small burst that passes marks to neighbors. | Cracked target shattering |
| `deafening_wail` | Deafening Wail | A · Lv16 | Every 8s you hover and charge 0.8s, then a wide cone stuns 0.6s (bosses immune) and shatters projectiles. | Open beak with a huge cone |
| `harmonic_fan` | Harmonic Fan | B · Lv8 | Consecutive screeches fan out at widening angles (18 degree steps). | Three sound waves fanning out |
| `parting_shot` | Parting Shot | B · Lv8 | While moving, screeches fire backward, opposite your heading. Fire while fleeing. | Eagle flying away, wave behind it |
| `flock_chorus` | Flock Chorus | B · Lv16 | Every 12s two spectral harpies flank you for 6s, screeching in parallel. | Three harpy silhouettes in formation |
| `perfect_pitch` | Perfect Pitch | B · Lv16 | Each volley without taking a hit adds +20% screech damage (up to +100%); getting hit resets it. | Tuning fork with a rising scale |

**Aerial Strike** (A = Assassin's Dive, B = Evasive Maneuvers)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `talon_rake` | Talon Rake | A · Lv8 | The swoop leaves a slash trail for 2s that damages anything crossing it. | Talons with a claw-mark trail |
| `hunters_focus` | Hunter's Focus | A · Lv8 | Swoops prioritize elites and bosses and mark them (+20% damage taken for 6s). | Eagle eye locking on a target |
| `shadow_drop` | Shadow Drop | A · Lv16 | You climb out of reach for 1s, then crash on the toughest enemy (a growing shadow shows where). | Growing shadow beneath a diving eagle |
| `rending_chain` | Rending Chain | A · Lv16 | After impact the swoop re-aims at the next nearest enemy, up to 3 hops. | Three connected dive arrows |
| `tailwind` | Tailwind | B · Lv8 | Each evasion grants +30% move speed for 3s and resets the screech. | Wing with a streaming wind arrow |
| `feather_decoys` | Feather Decoys | B · Lv8 | The evasion leaves 3 decoy feathers that detonate after 1s. | Three feathers with sparks |
| `high_altitude` | High Altitude | B · Lv16 | After an evasion you fly high for 1.2s: untargetable by everything, with x1.5 screech range. | Eagle above clouds |
| `whirlwind_wake` | Whirlwind Wake | B · Lv16 | Evasions leave a 3s cyclone that pulls enemies in and flings hostile projectiles away. | Cyclone spiral |

### 10.9 Necromancer

**Skull Summon** (A = Skull Chorus, B = Grand Skull)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `skull_spiral` | Skull Spiral | A · Lv8 | Skulls fire in a rotating spiral around you instead of at a target. | Skulls in a spiral |
| `ghostfire_trail` | Ghostfire Trail | A · Lv8 | Skulls leave a ghostfire trail that burns for 1.5s. | Skull with teal flame trail |
| `bone_storm` | Bone Storm | A · Lv16 | Every 6th volley (0.5s tell) releases a ring of 14 skulls in all directions. | Ring of skulls radiating out |
| `reapers_skull` | Reaper's Skull | A · Lv16 | Every 4th skull is a homing reaper skull that seeks the toughest enemy and detonates. | Skull with a scythe glint |
| `splitting_skull` | Splitting Skull | B · Lv8 | The grand skull grows as it travels and cracks into 6 mini-skulls at the end. | Big skull cracking into small skulls |
| `skull_totem` | Skull Totem | B · Lv8 | At max range the grand skull plants as a totem for 5s, pulsing damage around it. | Skull on a bone stake |
| `soul_feast` | Soul Feast | B · Lv16 | Kills feed the skull (+10% size, up to x2) and heal you 1% max HP each. | Skull absorbing small souls |
| `haunting` | Haunting | B · Lv16 | The skull sticks to the nearest elite or boss, biting it every 0.5s for 5s. | Skull latched onto a big enemy |

**Raise Dead** (A = Legion, B = Undying Bond)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `bone_archers` | Bone Archers | A · Lv8 | Raised minions hold back and throw bones (range ~220) instead of charging. | Skeleton throwing a bone |
| `corpse_burst` | Corpse Burst | A · Lv8 | A failed raise roll detonates the corpse in a small blast. | Exploding corpse |
| `grave_surge` | Grave Surge | A · Lv16 | Every 20s the ground erupts (0.6s tell) and up to 5 minions rise at nearby enemy positions. | Hands bursting from a grave |
| `death_pact` | Death Pact | A · Lv16 | With 3 or more minions alive you take 25% less damage; dying minions burst. | Skull tethered to minions |
| `raise_champion` | Raise Champion | B · Lv8 | You may raise one elite at a time: x2 stats for 20s. | Crowned skeleton rising |
| `hunting_pack` | Hunting Pack | B · Lv8 | Skull hits mark enemies; minions prioritize marked targets and deal x2 to them. | Minions circling a marked skull |
| `soul_harvest` | Soul Harvest | B · Lv16 | Kills charge a soul meter; at full a soul nova heals 15% max HP and damages nearby enemies. | Soul orb filling up |
| `bone_colossus` | Bone Colossus | B · Lv16 | With 4 or more minions alive they fuse into one huge Bone Colossus for 8s. | Giant skeleton made of bones |

### 10.10 Goose

**Fear** (A = Peck Fury, B = Terrifying Honk)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `goose_chase` | Goose Chase | A · Lv8 | After a charge, an enemy within 160px triggers another charge at once (up to 3 in a row). | Goose with chained dash arrows |
| `wing_flap` | Wing Flap | A · Lv8 | Charges end with a wing-flap wind cone: knockback and destroyed hostile projectiles. | Spread wings with a wind cone |
| `gaggle` | Gaggle | A · Lv16 | Every 10s a V-formation of 5 spectral geese charges along your heading, pecking everything. | V-formation of geese |
| `maniac_mode` | Maniac Mode | A · Lv16 | Below 40% HP charges recharge twice as fast and peck x2; below 15% your charges are invulnerable. | Wild-eyed goose with a red glow |
| `contagious_panic` | Contagious Panic | B · Lv8 | Feared enemies pass fear to enemies they touch (max 6). | Fear lines jumping between enemies |
| `territory_mark` | Territory Mark | B · Lv8 | The honk leaves a 4s ring on the ground; enemies entering it flee. | Ground ring with a goose print |
| `honk_of_doom` | Honk of Doom | B · Lv16 | Every 12s a huge honk (0.5s tell) frightens everything on screen for 1.2s and wipes hostile projectiles. | Open beak with a huge shockwave |
| `mass_hysteria` | Mass Hysteria | B · Lv16 | Fleeing enemies take +20% damage from all sources. | Panicked enemies with a red arrow up |

**Turds** (A = Volume Discount, B = Toxic Waste)

| id | Name | Slot | Behavior (card text) | Icon brief |
|---|---|---|---|---|
| `charge_droppings` | Charge Droppings | A · Lv8 | Charges drop a turd every 60px along the path. | Dash path studded with droppings |
| `golden_egg` | Golden Egg | A · Lv8 | Every 12s you lay a golden egg: grab it to heal 15% and gain a 5s damage buff. | Golden egg with a sparkle |
| `flyover` | Flyover | A · Lv16 | Every 12s a flock passes along your heading (shadow tell), dropping a lane of turds. | Flock shadow over a dotted lane |
| `gosling_parade` | Gosling Parade | A · Lv16 | Every 5th turd hatches a gosling that follows and pecks for 10s (max 3). | Line of goslings |
| `stink_aura` | Stink Aura | B · Lv8 | You emit a 70px stink aura: enemies inside are poisoned and slowed 20%; it grows as your HP drops. | Green stink fumes |
| `ripe_turds` | Ripe Turds | B · Lv8 | A turd left undisturbed for 4s bursts into a 3s poison cloud; stepping on it earlier just stuns. | Swollen turd with fumes |
| `venomous_honk` | Venomous Honk | B · Lv16 | Fear also poisons enemies for 4s. | Honking beak dripping poison |
| `toxic_swamp` | Toxic Swamp | B · Lv16 | Every 20s you create a 140px swamp for 8s: enemies are slowed 50% and poisoned, and you regenerate. | Bubbling green swamp |

<!-- CATALOG:END -->

## 11. Open items and risks

- **X Marks the Spot** (Pirate Crew) touches the chest economy and needs tuning.
- **Vanish, High Altitude, Ethereal Walk** need `Player.untargetable` honored everywhere (contact, projectiles, enemy aim).
- **Lay on Hands** and **Last Stand** are safety nets; check their cooldowns against boss fights.
- **Spread effects** appear three times (Spreading Venom, Contagious Panic, Corpse Burst). Test for screen-clearing chains and cut one if it happens.
- **Pets and clones** (Spider, Necromancer, Goose, Pirate, Wizard, Harpy): enforce the global actor cap.
- **Spell Echo / Fast Hands / Hunting Pack** depend on the cross-ability `on_player_cast` event from step 5.
- **Performance:** many options add per-frame scans over `enemies.active`; prefer `query_circle` and the spatial hash, and re-check FPS at 300 enemies on the APK after each slice.
- **Acts:** enemy-side scaling, CC rules for new enemy types, and boss HP scaling are separate work that this plan assumes.
