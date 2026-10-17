# PHASE 1 of 3 - Act director core (Solomon's Survivor final demo update)

Paste this whole file into opencode. Work in `survivor/` (master). Never touch `../Solomon's Survivor Demo/`.

## 0. Read first, obey always

Read `workbench.md` fully before editing. Sections 3 (coding rules), 7, 9, 10 and 11 are binding. The ones that bite:

- Indentation is per-file. Look each file up in the §3 tab/spaces/CRLF lists before touching it. Reveal the indent byte pre-edit, rescan `^ * +\t|^\t* +\t` (expect 0) **immediately after every file edit**. Never rewrite `.gd` via PowerShell `Set-Content`/redirection; use the file-edit tool.
- Known: tabs = `world.gd game.gd main.gd player.gd dev_menu.gd dev_overlay.gd fx_manager.gd`; spaces = `enemy_manager.gd projectile_manager.gd ground_layer.gd hud.gd meta.gd audio_manager.gd gameover_screen.gd character_select.gd coin_manager.gd ability.gd`; CRLF = `ground_layer.gd hud.gd projectile_manager.gd`. `levelup_screen.gd`, `ui.gd`, `db.gd`, `fx_layer.gd`, `pause_menu.gd`, `enemy_def.gd` are in neither list: detect, classify, add them to the workbench list.
- New files: LF, spaces (4), and classify them in the §3 lists on creation.
- GDScript typing: `:=` must be explicitly typed; never `:=` on an expression rooted at an untyped ref (`world`, `Game`, `DB`, `player`...). Write `var a: ActDef = world.acts.current()`.
- Do NOT ask the author to run checkers, F5, exports or syncs. Update checkers statically, report static state, stop. After any headless run restore with `git checkout -- survivor/.godot/`.
- Display strings say "Fragments" / "Seal Fragments", never coins/essence.
- Do not retune the §9 perf levers. No new full-screen screen-texture shaders.

## 1. Locked design (do not redesign)

One cumulative clock, 30 minutes of normal play. Each act is a slice; each act's boss spawns at the END of its slice, and the **clock and director freeze at boss spawn** and resume only when the next act begins (Phase 2 adds the Descend/Withdraw choice in between).

| Act | idx | Name | clock_start | boss_id | boss_time |
|---|---|---|---|---|---|
| I | 0 | THE BONE MARKET | 0 | bone_broker (Asmodeus) | 450 |
| II | 1 | THE CORRUPTED ARCHIVE | 450 | hellfire_devil (Malphas) | 900 |
| III | 2 | THE BRAZIER HALLS | 900 | belial (placeholder, new) | 1350 |
| IV | 3 | THE FOURTH GATE | 1350 | lucifer (does not exist yet) | 1800 |

Act IV is `sealed = true`: authored as data, never playable in the demo.

## 2. ActDef resource + data

Create `data/defs/act_def.gd` (`class_name ActDef extends Resource`) and `data/acts/act1.tres` .. `act4.tres`. Register them in `DB` (`DB.acts`, sorted by `index`; read `db.gd` and follow its loading pattern).

Exports: `id, index, display_name ("ACT I"), title, subtitle, clock_start, boss_id, sealed, music_key, boss_music_key = "boss_music", hp_mult, dmg_mult, speed_mult, spawn_rate_mult, reward_mult, elite_cooldown, floor_a, floor_b, crack_col, flame_core, flame_glow, glow_col, brazier_bonus (0..1 extra brazier density), vignette_tint, vignette_pulse (Hz, 0 = off), enemy_tint, ambient ("ash"|"glitch"|"embers"|"gold"), intro_flash (Color)`.

Starting values (all tunable in the .tres, balance is untuned). The director already ramps HP `1+t/240` and damage `1+t/600` with time, so act multipliers are deliberately small steps ON TOP of that ramp:

| | hp | dmg | speed | spawn rate | elite cooldown | reward |
|---|---|---|---|---|---|---|
| I | 1.00 | 1.00 | 1.00 | 1.00 | 60 | 1.0 |
| II | 1.10 | 1.10 | 1.04 | 1.10 | 45 | 1.5 |
| III | 1.20 | 1.20 | 1.08 | 1.20 | 30 | 2.2 |
| IV | 1.30 | 1.30 | 1.12 | 1.30 | 30 | 3.0 |

Palettes (one hue per act; I = existing violet arena):
- I: floor_a (0.14,0.10,0.20) floor_b (0.18,0.12,0.26) crack (0.05,0.03,0.09); flame core (0.6,0.25,1.0) glow (0.55,0.25,1.0); vignette_tint (0.015,0.02,0.06); enemy_tint white; ambient "ash".
- II (cyan glitch): floor (0.07,0.13,0.17)/(0.09,0.18,0.24) crack (0.02,0.07,0.10); flame (0.25,0.95,0.95) glow (0.2,0.9,0.95); vignette (0.0,0.04,0.07); enemy_tint (0.88,1.0,1.05); ambient "glitch".
- III (crimson braziers): floor (0.17,0.07,0.09)/(0.23,0.09,0.11) crack (0.07,0.02,0.03); flame (1.0,0.3,0.2) glow (1.0,0.3,0.2); brazier_bonus 0.6; vignette (0.07,0.01,0.02); enemy_tint (1.0,0.92,0.9); ambient "embers".
- IV (gold): floor (0.10,0.09,0.07)/(0.15,0.13,0.08) crack (0.04,0.03,0.02); flame (1.0,0.85,0.4) glow (1.0,0.8,0.35); vignette (0.06,0.05,0.01), vignette_pulse 0.35; ambient "gold".

Title text (author edits later): I "THE BONE MARKET" / "Every soul has a price." II "THE CORRUPTED ARCHIVE" / "The seals are failing. The text rewrites itself." III "THE BRAZIER HALLS" / "Something is burning the old oaths." IV "THE FOURTH GATE" / "Not yet."
Music keys: `act1_orchestral`, `act2_glitch`, `act3_choir`, `act4_lucifer`. Intro flashes: low-alpha tint of the act hue.

## 3. ActManager (new `src/core/act_manager.gd`, `class_name ActManager extends Node`)

Child of World, created in `World.start()` after the player and before `enemies.setup`. API:

- `acts: Array`, `idx: int`, `clock_held: bool`, `held_boss_id: String`; signals `act_changed(idx)`, `boss_spawned(def)`, `boss_slain(def)`.
- `current() -> ActDef`, `act_at(i) -> ActDef`, `next_act() -> ActDef` (null past the end), `next_is_playable() -> bool` (exists and not sealed), `act_for_time(t) -> int`.
- `hold_for_boss(def)`: `clock_held = true`, `held_boss_id = def.id`.
- `begin_act(i, set_clock := true)`: sets `idx`, releases the hold, sets `world.run_time = clock_start` when `set_clock`, calls `world.set_arena_theme(act, instant)`, swaps music, shows the banner, flashes. First call at run start uses `instant = true` (no tween).
- Dev guard: when `Game.dev_active` and not held, once per second re-derive the act from `run_time` so DevOverlay time-skips keep the act in sync.

`World._process`: `run_time` only advances while `sim_running and not acts.clock_held`.

## 4. EnemyManager integration (spaces file)

- **Director gate:** `_tick_director` returns immediately while `world.acts.clock_held`, and also during a `_breather_t` timer (add `breather(seconds)`; Phase 2 uses it).
- **Boss spawn:** only the current act's boss may spawn: replace the "every due boss" loop with: `def = DB.enemies.get(act.boss_id)`; skip if null (Lucifer) or already in `_boss_spawned` or `t < def.boss_time`. On spawn call `world.acts.hold_for_boss(def)`. Keep the announce/shake/sfx. Manual `spawn_around_id` bosses (dev) never hold the clock.
- **Multipliers:** director spawns use `(1 + t/240) * act.hp_mult`, `(1 + t/600) * act.dmg_mult`; the elite and bat-ring paths likewise; `_spawn_acc` rate multiplied by `act.spawn_rate_mult`; in `spawn()` apply `act.speed_mult` to `e.speed` only when `def.boss_time <= 0`. Bosses keep def HP (no ramp).
- **Elite pacing:** no elite before t=180. An elite def whose timer is due spawns only if `t - _last_elite_time >= act.elite_cooldown`; otherwise leave `_elite_next` untouched so it fires when allowed. Set `_last_elite_time` on spawn.
- **`wipe_quiet()`**: iterate a copy of `active`, kill each with `quiet = true` but WITHOUT the per-enemy `death_burst`/`signature_kill` (a 150-enemy burst storm would spike the frame): add a `silent` parameter or sibling path, and emit at most ~12 bursts total. Also fix the latent bug in `clear_to()` (its loop never shrinks `active`, so it hangs): kill via `_kill(active.back(), true)`.
- `boss_alive() -> bool` (any active with `def.boss_time > 0`).
- **Tint:** cache `_act_tint` (updated on `act_changed`); the resting modulate becomes `base * def.tint * _act_tint` (see §6 for `EnemyDef.tint`). Status tints (stun/slow/fear/burn) still override as today.
- **Summoned adds** (§5): add `E.summoned := false`; summoned enemies drop no Fragments (skip `coins.on_enemy_killed`) but still drop gems.
- Fragment reward scaling: read `coin_manager.gd`; if enemy-kill drop values come from one place, multiply by `act.reward_mult` (min 1, int). If there is no single point, skip and report.

## 5. Asmodeus rework (new attack kit, behavior `boss_broker`)

Why: the old kit is a lone radial ring plus a dash, flat and clunky next to Malphas's spiral. Malphas keeps the Vaal-style spiral as Act II's identity; Asmodeus gets a readable, telegraphed, **ground-and-spread** kit that teaches the player what bosses are.

New `EnemyDef` exports (documented, with defaults that do nothing for other defs): `deck: PackedStringArray`, `fan_bursts=3`, `fan_burst_gap=0.14`, `zone_count=6`, `zone_radius=34.0`, `zone_damage=28.0`, `zone_delay=0.9`, `ring_bullets=24`, `ring_gaps=3`, `add_def_id=""`, `add_count=4`, `add_cap=8`, `add_interval=14.0`, `recover_time=0.9`, `tint: Color = Color.WHITE`. Reuse existing fields: `projectile_count` (fan shots), `projectile_spread_deg`, `projectile_style = "bone"`, `shoot_speed`, `shoot_damage`, `enrage_hp_fraction`, `enrage_interval_mult` (scales recover time).

Add one `match` arm `"boss_broker"` + `_boss_broker(e, delta, dir, dist)` in `enemy_manager.gd`. The boss runs a **shuffled attack deck**, never the same kind twice in a row, one attack at a time: telegraph (>= 0.6s) -> execute -> recover. Stalks the player at 0.6x speed between attacks, rooted during telegraph/execute. E gets minimal new fields (`atk, atk_phase, atk_t, deck_bag, last_atk, add_t, burst_left, burst_t, aim`).

Attacks:
1. **fan - Loaded Dice.** Aim wedge cue (`cue_wedge`) tracks the player, locks 0.15s before firing. Then `fan_bursts` bursts of `projectile_count` bone shards across `projectile_spread_deg`, `fan_burst_gap` apart, each burst re-aimed. Shard speed `shoot_speed*1.15`, damage `shoot_damage*0.7`.
2. **ledger - Debt Collection.** `zone_count` ground zones in a line from the boss through the player's position at cast time (spacing ~38px, extending 2 zones past the player), armed `zone_delay`s with +0.1s stagger per zone so the spikes march. Zones telegraph themselves visibly the whole time. Flying players are immune to zones (`air = false`).
3. **gap_ring - Bankruptcy.** Converge cue 0.6s, then two rings of `ring_bullets` with `ring_gaps` evenly spaced safe gaps (~28 deg each), random phase, second ring 0.55s later with the gaps rotated so the player must weave.
4. **foreclose - Foreclosure.** 0.6s lane telegraph, then the stock 0.45s 3.4x dash, dropping a smaller zone (radius*0.7, damage*0.7, delay*0.8) every ~0.1s along the path.
5. **summon - Creditors** (not in the deck; injected when `add_t <= 0` and alive adds < `add_cap`). Sigil ring, then `add_count` of `add_def_id` at 90-140px, spawned with hp x0.6 / dmg x0.8 and `summoned = true`. First summon ~6s after the boss appears (the director is frozen, so this is what keeps the arena alive).
- **Enrage** (hp < `enrage_hp_fraction`): recover time x `enrage_interval_mult`; fan +1 burst; ledger adds a second line at +/-25 deg; gap_ring 3 rings; summon +2 adds (cap still applies). Fire `world.fx.enrage_feel` once.
- Telegraphs use the existing cue API (`cue_wedge`/`cue_converge`/`ring`); refresh every frame, never retime an attack by a telegraph. Reuse existing sfx keys only.

ProjectileManager (spaces + CRLF): add `Kind.ZONE` (append to the enum) and `spawn_zone(pos, radius, dmg, delay, opts)`. A zone reuses the pool; `life = delay`; it never hits enemies and never contact-hits the player; on expiry it deals `dmg` once if the player is within `radius` (`take_damage(dmg, false, "Bone Spikes")`), then ring + sparks + small `Game.shake`. Make sure the `_hit_enemies` branch skips `ZONE`. Draw: a pale-bone outline arc at full radius plus an inner disc growing with `age / (age + life)` and brightening toward the pop; no trail. Also add `style == "bone"` to `spawn_hostile` (radius 5, color (0.93, 0.9, 0.8)).

`bone_broker.tres` values (starting point for the 7:30 slot, was 8000 HP at 25:00): `max_hp 3200, speed 46, contact_damage 40, behavior "boss_broker", boss_time 450, spawn_start 450, boss_unlock "black_market"` (unchanged, the Archive unlock is already wired, do not touch it), `tint (1.0, 0.88, 0.6)`, `deck ["fan","ledger","gap_ring","foreclose"]`, `projectile_count 5, projectile_spread_deg 36, projectile_style "bone", shoot_speed 170, shoot_damage 22, zone_count 6, zone_radius 34, zone_damage 28, zone_delay 0.9, ring_bullets 24, ring_gaps 3, add_def_id "skeleton", add_count 4, add_cap 8, add_interval 14, recover_time 0.9, enrage_hp_fraction 0.5, enrage_interval_mult 0.7, coin_drop 160`. Still the reused `skeleton.png` at scale 3.0 (dedicated art pending).

## 6. Other boss + enemy data

- `hellfire_devil.tres` (Malphas): `boss_time 900`, `spawn_start 900`, everything else unchanged. Its `_boss` kit is not touched.
- **New `data/enemies/belial.tres`** (placeholder for the author's Act III boss, to be replaced later): id `belial`, display_name "Belial, Prince of Braziers", family by chosen sprite, `behavior "boss"` (stock kit), `is_elite true`, `can_hit_flying true`, `boss_time 1350`, `spawn_start 1350`, `max_hp 9500`, `speed 52`, `contact_damage 45`, `radius 28`, `sprite_scale 3.0`, `xp 500`, `coin_drop 220`, `boss_unlock ""`, `shoot_interval 2.2, shoot_speed 180, shoot_damage 26`, `projectile_style "fireball"`, `projectile_count 5`, `projectile_spread_deg 50`, `splash_radius 40`, `splash_damage 20`, `splash_falloff true`, `spiral_every 0`, `enrage_hp_fraction 0.5`, `enrage_interval_mult 0.7`, `tint (1.0, 0.45, 0.4)`. Sprite: inspect `art/enemies/` and reuse the biggest-feeling existing strip that is not already a boss sprite (candidates: the brute or raptor strip); set `frames` from the image width and respect the 48/64px cell validator. Record it as a placeholder in the workbench §4 TODO column.
- Do NOT create `lucifer.tres`. Act IV's `boss_id = "lucifer"` must be tolerated as missing everywhere.
- `EnemyDef.tint` (default white) is applied multiplicatively wherever the resting sprite modulate is set.
- **Window rescale x0.75** (40-min plan -> 30-min plan): for every non-boss enemy def multiply `spawn_start` and `spawn_end` (skip 9999) by 0.75, rounded. Do it in `tools/gen_data.py` (source of truth for generated defs) AND the generated `.tres`, and directly in the hand-added `.tres` (glitch_goblin 600->450, snake 360->270, mummy 150->112 ...). Leave `elite_every` alone. Update `tools/check_project.py` if it asserts old windows.

## 7. Visuals

- **GroundLayer** (spaces + CRLF): refactor `_make_floor()` to take `(a, b, crack)` with the same RNG seed so geometry stays identical across acts. `apply_theme(act: ActDef, instant: bool)`: build/cache one texture per act (4 x 128x128, one-shot), crossfade over 4s by drawing the previous floor at full alpha and the new one at rising alpha. Flame colors and glow color come from the act. Extract `_is_brazier(r: int) -> bool` used by BOTH `_prop` and `draw_glow` (currently duplicated as `r % 11 == 5`); with `brazier_bonus > 0` additional hash residues (e.g. 1,2,3 gated by `(r >> 12) % 100 < bonus*100`) also count as braziers.
- **World** (tabs): `set_arena_theme(act, instant)` calls `ground.apply_theme`, tweens the vignette tint, tells the ambient layer, and refreshes the enemy tint. Make the LIGHT_SHADER base tint a uniform (`base_tint`) instead of the hardcoded `vec3(0.015,0.02,0.06)`; add an `edge_glow` uniform mixed in at the vignette edge for the Act IV gold pulse (`vignette_pulse`, driven from script with `sin`). The shader string keeps its legal spaces-in-tabs.
- **ActAmbient** (new `src/core/act_ambient.gd`, `CanvasLayer` at layer 4, below the vignette layer 5 and the HUD): one `_draw` batch, ~70 particles in screen space, no per-frame allocation, circles/rects/lines only. Presets: `ash` (slow pale-violet drift), `glitch` (cyan/magenta rects with stepped jitter plus an occasional 1-2 frame thin horizontal "tear" bar at alpha <= 0.12, skipped if `Game.fx_flash <= 0`), `embers` (crimson/orange rising), `gold` (slow gold motes). Preset swaps fade out/in over ~1.5s. Mirror the menu's ember look.
- **ActBanner** (new `src/ui/act_banner.gd`, `CanvasLayer` layer 12, `PROCESS_MODE_ALWAYS`): `show_act(act)`: "ACT II" (UI.GOLD, 64), title (UI.TEXT, 40), subtitle (UI.DIM, 20), outline style from `UI.label`; fade in 0.4s, hold ~2.6s, fade out 0.6s; placed around y=230 so it clears the existing announce label at y=150. Shown at run start (Act I) and at every `begin_act`.

## 8. Music + HUD + Meta

- `audio_manager.gd` (spaces): add to `MUSIC`: `act1_orchestral`, `act2_glitch`, `act3_choir`, `act4_lucifer` -> `res://audio/music/<key>.ogg`. The three act OGGs (`act1_orchestral.ogg`, `act2_glitch.ogg`, `act3_choir.ogg`) are already placed in `audio/music/` by the author as seamless loops; never regenerate them and never touch `menu_music.ogg`. `act4_lucifer.ogg` does not exist yet (the missing-file warning path is fine). Leave `ambient_loop`/`boss_music` keys in place.
- `world.gd` music: the 1s poll currently picks `boss_music` whenever ANY elite is alive, which with 30-60s elite cooldowns would thrash the music. Change it: unique bosses only (`enemies.boss_alive()`) get `act.boss_music_key`; otherwise `act.music_key`. `_set_music(key, fade := 1.2)`; act transitions use fade 3.0. Reset `_music_key` when music is stopped so the next key plays.
- `hud.gd` (spaces + CRLF): the timer shows the act numeral beside the time (e.g. `II  07:30`); while `world.acts.clock_held` it pulses crimson. Keep `_set_text` change-guarding.
- `meta.gd` (spaces): `unlock_hint()` currently prints the boss's clock time, which is wrong with the freeze. Build it from the act whose `boss_id` carries the unlock: `"Defeat %s to end %s"` (boss display name, act display_name), e.g. "Defeat Asmodeus, Broker of Bones to end ACT I".

## 9. Dev + run start

- `World.start`: create `acts`, ambient and banner; after `_apply_dev_config()` / `sim_running = true`, call `acts.begin_act(start_idx, set_clock)`: normal runs `begin_act(0, true)`; dev runs derive `act_for_time(start_time)` and keep the jump-in clock (`set_clock = false`). `EnemyManager.apply_dev_config` must also clear `_boss_spawned` and `_last_elite_time` as today.
- Bosses spawned by the dev panel never hold the clock and never trigger the clear flow (the clear logic only fires when `acts.held_boss_id == e.def.id`).

## 10. Boss death, PHASE-2 SHIM

In `World.on_kill`: if `acts.held_boss_id == String(e.def.id)`, call `acts.boss_slain(e.def)` (after the existing `boss_unlock` handling, which stays exactly as is; add a plain "SLAIN" announce when the boss has no unlock). Temporary behavior in `ActManager.boss_slain` (clearly commented `# PHASE-2 SHIM`): stop music, `enemies.wipe_quiet()`, `gems.attract_all()`, wait 2.5s, then `begin_act(next)` if `next_is_playable()`; otherwise announce "THE FOURTH GATE HOLDS" and leave the director idle. Phase 2 replaces this with the Act Cleared screen.

## 11. Finish

- Update `tools/check_project.py` statically: act data validity (monotonic `clock_start`, `boss_id`s exist except sealed Act IV's, music keys exist in `Audio.MUSIC`), new EnemyDef fields.
- Workbench, per its hygiene rules (merge-and-update, no new sections, flag growth > ~100 lines): fold into §7 line G (30-min schedule above), §3 lists (new files + the unclassified ones), §4 enemy row (Asmodeus kit, Belial placeholder), §10 (`boss_broker`, summoned adds, `Kind.ZONE`), §11 (replace the "Director pacing TODO" with the built rule). Ignore the obsolete 40-min numbers.
- Report the static state and stop. Do not ask the author to run anything.
