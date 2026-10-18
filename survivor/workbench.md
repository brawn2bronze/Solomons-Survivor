# WORKBENCH — Solomon's Survivor

_Master lives in `survivor/`. Demo copy lives in `../Solomon's Survivor Demo/` (author-owned, opencode never touches it). 1280x720 base._

## 1. Commands

```
godot --headless --path . --import
godot --headless --path . res://tests/smoke.tscn
```

## 2. File map

```
project.godot  main.tscn  workbench.md  export_presets.cfg  icon.svg
autoload/   game.gd  db.gd  audio_manager.gd  meta.gd
data/defs/  character_def.gd  weapon_def.gd  passive_def.gd  enemy_def.gd  upgrade_def.gd  ability_def.gd  market_item_def.gd  act_def.gd
data/       characters/*.tres  weapons/*.tres (23)  passives/*.tres (12)  enemies/*.tres (15)  upgrades/*.tres  market/*.tres (11 rent + 9 mod)
data/seal/  global_seal_data.gd  hero_seal_data.gd
data/acts/  act1-4.tres (ActDef director slices: clock_start, boss_id, music_key, palette, ambient, reward_mult)
src/core/   world.gd  act_manager.gd  act_ambient.gd  descent.gd  enemy_manager.gd  projectile_manager.gd  gem_manager.gd  coin_manager.gd  fx_manager.gd  fx_layer.gd  ground_layer.gd  status_icons.gd  chest_manager.gd  critter_manager.gd
src/player/ player.gd
src/abilities/ ability.gd  weapon_behaviors.gd  passive_behaviors.gd
src/ui/     main_menu.gd  menu_music_curve.gd  character_select.gd  hud.gd  levelup_screen.gd  pause_menu.gd  gameover_screen.gd  options_panel.gd  ability_art.gd  black_market_screen.gd  seal_screen.gd  coin_icon.gd  dev_menu.gd  dev_overlay.gd  ui.gd  act_banner.gd  act_clear_screen.gd
src/        main.gd
art/  weapons/  passives/  status/  upgrades/  market/  placeholders/  characters/  enemies/  fx/  pickups/
audio/  music/  player/  ui/
tools/  gen_data.py  check_project.py  check_black_market.py  new_character_checklist.md
tests/  smoke.tscn
docs/  black_market.md
```

Hand-added (re-add after any `gen_data.py` regen): `jack`, `fun_guy`, `bone_broker.tres`, `hellfire_devil.tres`, `glitch_goblin.tres` (+ `art/enemies/glitch_goblin.png` 4x64px source `../glitch-goblin.png`), `snake.tres` (+ `art/enemies/snake.png` 4x64px chaser fodder @6:00), `data/market/*.tres`, `pickup_shamir_tooth.tres`, `pickup_shamir.tres` (keeps `max_level=8`, seed forces 5), `belial.tres` (placeholder Act III boss, reuses goblin_brute), `data/acts/act1-4.tres`.

## 3. Coding rules

- GDScript: type `:=` explicitly (Variant `:=` is a hard error); never `:=` on expressions rooted at untyped refs (`world`/`Game`/`DB`/etc. — e.g. `world.fx.debug_stats()` killed boot 2026-10-14, fix is `var fx: Dictionary = ...`), use an explicit type or plain `=`; every `p[...]` read must exist in the `.tres` base keys (checkers enforce).
- Art strips: square-cell horizontal strips, cell derived in `AbilityArt.frame_region`; validator accepts Wx32/Wx64 (ability art) and 48/64px cells (enemy strips, e.g. hellfire 4x64px). Currency seal strip (`art/pickups/seal.png` 12x24x28, non-square) is exempt: UI `CoinIcon` animates all 12 frames, world coins draw static frame 0. New art PNGs gain committed `.import` sidecars on first Godot import. PNG size changes reimport on mtime.
- Tabs only: `game.gd`, `gem_manager.gd`, `world.gd`, `player.gd`, `status_icons.gd`, `fx_manager.gd`, `fx_layer.gd`, `critter_manager.gd`, `dev_overlay.gd`, `dev_menu.gd`, `main.gd`, `coin_icon.gd`, `pause_menu.gd` (was unlisted; verified tabs 2026-10-15; `fx_layer.gd` tabs verified 2026-10-17; `pause_menu.gd` moved out of spaces 2026-10-17 - file + HEAD are tabs). Spaces (4) only: `hud.gd`, `projectile_manager.gd`, `weapon_behaviors.gd`, `ground_layer.gd`, `black_market_screen.gd`, `main_menu.gd`, `menu_music_curve.gd`, `audio_manager.gd`, `gameover_screen.gd`, `seal_screen.gd`, `character_select.gd`, `enemy_manager.gd`, `meta.gd`, `coin_manager.gd`, `chest_manager.gd`, `ability.gd`, `fx_gallery.gd`, `levelup_screen.gd`, `ui.gd`, `db.gd`, `act_manager.gd`, `act_ambient.gd`, `act_banner.gd`, `act_clear_screen.gd`, `descent.gd`; no-indent data defs: `enemy_def.gd`, `act_def.gd` (all classified 2026-10-17). CRLF: `gem_manager.gd`, `hud.gd`, `projectile_manager.gd`, `weapon_behaviors.gd`, `ground_layer.gd`. New files LF. Only legal spaces-in-tabs: string literals (e.g. `world.gd` shader block).
- Pre-edit: reveal indent byte (`$_ -replace "`t",'[TAB]'`). Before touching a file, look up its convention in the lists above (every file must appear in exactly one list; classify new files on creation) and write new lines in that convention from the start. Post-edit: rescan `^ * +\t|^\t* +\t` → expect 0 **immediately after each file edit, never batched at the end** — late detection turned a 30-second fix into a multi-step cleanup (2026-10-14: tabs written into spaces files `enemy_manager`/`chest_manager`, spaces into tab file `dev_menu`). Never rewrite `.gd` files via PowerShell `Set-Content`/redirection — it flips whole-file line endings (LF→CRLF); use the file-edit tool, and if a bulk conversion is ever needed, restore LF byte-level afterward and re-verify. Checkers do NOT scan whitespace; only engine/regex catches it. Past causes: spaces in a tab file (twice) → `Could not parse World` → boot dead; tabs in a spaces file (`projectile_manager.gd:31` + cascade across world/weapon_behaviors/ability/player/black_market/main, fixed 2026-10-13).
- Author loop (do not re-ask): opencode never verifies in-engine, never touches demo copies. Author saves a copy folder before each build, reloads in Godot after, checks. Troubleshoot together; no new master copy until zero errors. Never ask author to run checkers/F5/exports/syncs as next steps — report static state and stop. Headless runs dirty `survivor/.godot/` cache files — restore with `git checkout -- survivor/.godot/` afterward so the tree holds only intended edits. Isolated `--check-only --script` cannot resolve autoloads (`Game`/`DB` "Identifier not found" even on untouched files) — verify with `--import` + `smoke.tscn` instead, don't chase those errors.
- `tools/gen_audio.py` overwrites `audio/music/menu_music.ogg` — back it up before running.
- Currency: single currency "Seal Fragments" (short "Fragments" in rows/shop/gameover; full form in headers/glossary). Display strings must never say essence/coins. Code names frozen until A6 (`CoinManager`, `CoinIcon`, `Meta.coins`, `UI.ESSENCE`, `coin_drop`, `run_coins`). Currency sprite pending user supply.
- Workbench hygiene (self-enforcing, soft): every workbench touch is merge-and-update, never append. New info folds into the existing §1-§11 line it belongs to; DONE detail condenses to its rule on landing; no new section without author approval; growth past ~100 lines allowed only if flagged for approval in the same reply. Unmarked/stale lines are delete candidates by default.

## 4. Art contract + sprite matrix (live)

- `AbilityDef`: `icon`, `icon_frames=1`, `icon_fps=8.0`, `preview_kind=none|spin|pulse`, `anims` branch-slot → `{sprite, frames, fps}`, `rarity` 0/1/2, `unlock_hint`, `branch_milestones`. Enemy summon overlay `art/fx/summon.png` (15x64, cosmetic, `FxManager.summon`, dedicated pool 24) + frog critter `art/pickups/frog.png` (8x32, `CritterManager`, eat = `frog_fart` sfx + flat 15 HP).
- `CharacterDef`: `ability_anims` slots `base,wA,wB,pA,pB` (+ optional `wBase/pBase`); `roster_status` + `unlock_hint` (§5); `kill_fx_*` sprite override for `signature_kill` (empty = procedural fallback, isolated test in `tests/fx_gallery.tscn`).
- `UpgradeDef.icon`. All optional with fallbacks. `ability_art.gd` is the single art-resolve rule (real art → silhouette fallback).
- Creation checklist: `tools/new_character_checklist.md` (behaviors include `flicker_strike`, `worm_ride`).

| Set | Done | TODO |
|---|---|---|
| Weapons (23 defs) | shuriken, caltrops, dynamite, keg (3-frame) + blunderbuss, rifle, greatsword, merlins_book (static) + skull_summon code-drawn (9) + fangs, hand_cannon, horns, katana, screech, six_shooter (32px icons) + shamir (legendary art, locked-blackout) + pickup_shamir_tooth (rare, 32px) (17) | fear, hyphal_net, pumpkin_hurl, pickup_aa12, pickup_cloak, pickup_energy_food |
| Passives (12 defs) | webs, raise_dead, pirate_crew, prayer + aerial_strike, flash_bombs, flailing_whip, astral_projection + turds (9) | beasts_roar, candy_trail, saprotroph (3) |
| Enemies (15 defs) | 15 (spider 6-frame, zombie 4-frame + goblin/mummy/brute/assassin/bat/skeleton/raptor/dragon_whelp + hellfire_devil flying boss 4x64px @18:00: 3x fireball fan + splash, spiral every 3rd volley, enrage 50%/0.65x, F5 boot clean 2026-10-13 + glitch_goblin 4x64px Act2 fodder @10:00: freeze+stutter, HP22/spd82/dmg12/xp3 + snake 4x64px chaser fodder @6:00: HP30/spd70/dmg10/xp3 + mummy 4x64px tanky chaser @2:30: HP60/spd30/dmg11/xp3 (raptor strip now 8 frames = 1.0s anim) + boss telegraphs live (phase-3 port 2026-10-15, F5 pending: converge ring + aim wedge pre-volley, sweep marker on spiral casts, cues cleared on kill) + star/disc/wedge/beam shapes + crit/elite/boss feel tiers + kill signatures (phase-4 port 2026-10-15, F5 pending: 10 chars, budget 12 @40/s, elites double-size, jack/fun_guy none) + elite/boss ground auras (amber/red, enraged hotter/faster; elite aura melts via TTL on kill) + Asmodeus `boss_broker` kit built 2026-10-17 (deck fan/ledger/gap_ring/foreclose + injected summon + enrage) + `belial` placeholder (reuses goblin_brute 4x64px, stock `boss` kit)) | bone_broker + belial dedicated art (both reuse existing strips) |
| Upgrades (9) | might, vitality, swiftness, haste, magnet, recovery, plating, reach, fortune (9/9 done) | — |
| Status | stun, poison, fear, rage, burn (+ nutrient/infected) | slow/snare, optional armor/invuln |
| Character strips (5/char) | necromancer 5/5 via reuse | 9 chars fully + necro dedicated; chest branch strips future |

## 5. Roster gating

- `roster_status`: PLAYABLE=0, LOCKED_TEASER=1, HIDDEN=2 (default 0). `DB.playable_roster()` / `DB.visible_roster()`; HIDDEN loadable by id for dev sandbox.
- Tags: PLAYABLE cowboy/ninja/pirate/paladin/wizard; TEASER spider/minotaur/harpy/necromancer/goose (`Locked - unlocks in the full release.`); HIDDEN jack/fun_guy.
- Teasers: blacked-out strip, `???`, kit suppressed, `_confirm()` blocked. Dev menu stays on full `DB.roster()`.
- Future: `[unlocks]` section in `Meta` (`user://save.cfg`), no second save file. Reuses `roster_status/unlock_hint`.

## 6. Demo export (author-owned)

- Master untouched; work only in `Solomon's Survivor Demo/`. Include: `project.godot`, `main.tscn`, `export_presets.cfg`, `icon.svg`, `autoload/`, `data/`, `src/`, `art/`, `audio/` (+ `.uid`/`.import`). Exclude: `.godot/`, `tests/`, `tools/`, `workbench.md`, `audio/music/_legacy/`.
- Demo-only: name `Solomon's Survivor Demo`, `DEV_MODE_ENABLED=false`, branding titles, touch controls. Master preset `export_path=""`.
- Open: F5 import+run in Godot 4.7; install `Godot_v4.7-stable_export_templates.tpz` via Manage Export Templates, verify `%APPDATA%\Godot\export_templates\4.7.stable\`; export Windows Desktop to `../SolomonsSurvivorDemo-export/`; playtest exe; zip folder (`embed_pck=false`, keep exe+pck together).

## 7. Theme Bible (LOCKED — source of truth)

- Names: Seal Fragments (sole currency; short "Fragments" in tight UI) / The Forbidden Archive (shop) / Bound Scribe (flavor NPC) / Asmodeus, Broker of Bones (boss) / Unseal for One Battle (rental) / Permanent Binding (mod). No "essence" or "coins" in display strings (scribe flavor line exempt per author). Phase A display-strings-only; full code rename deferred (needs save migration + checker update + demo re-merge).
- Display done: Archive strings, menu/HUD/gameover fragment strings, boss `Asmodeus, Broker of Bones`, 6 weapon renames (Seal-Breaker Musket, Forbidden Explosives, Demon's Scattergun, Cursed Spikes, Angelic Manna, Solomon's Ward), `Brimstone Breath` mod, menu title `SOLOMON'S`, palette `BRONZE/CRIMSON/DEEP_PURPLE/GLITCH_CYAN` + frozen `ESSENCE` color const, `menu_music.ogg`, seal strip `art/pickups/seal.png` (UI animated via `CoinIcon`, world static frame 0), violet arena. Title screen v2 "The Corrupted Archive" (`main_menu.gd`: rotating Solomon's Seal + roster carousel w/ glitch-slice swaps + glyph rain + god rays/embers + enemy-horde silhouettes + fullscreen glitch shader + ~6s intro; visuals song-synced via `MenuMusicCurve` baked curves read through the `Audio.music_time()` API — if `menu_music.ogg` is swapped, re-bake the curve or sync drifts). Open: A6 full code rename.
- Meta systems (each: Meta section + data + screen + hook): B Seal tree (global 5-branch + Vessel stub — backend + screen done, hero content open) / C Bestiary (backend done, codex UI open) / D Circle / E Stability / F Interrogation. Content: G 4-act director built 2026-10-17 (30-min schedule: Act I 0-7:30 Asmodeus, Broker of Bones / Act II 7:30-15:00 Malphas / Act III 15:00-22:30 Belial / Act IV 22:30-30:00 Lucifer, sealed); `ActDef` in `data/acts/*.tres` + `src/core/act_manager.gd`, per-act music/palette/ambient/banner, boss clock-hold + Act Cleared beat (Phase 2 built 2026-10-17: Fragment escrow in `world.run_coins`, BANK on Withdraw only, Descend/Withdraw `ActClearScreen` layer 41, sealed Act III card, victory summary; Phase 3 built 2026-10-17: Withdraw writes a per-hero loadout checkpoint (`src/core/descent.gd` + `[descent]` in Meta, deeper-overwrites-only), Continue on Character Select resumes at the next act's `clock_start` with the saved build / full HP / fresh escrow, sealed next act shows a disabled "ACT IV - THE FOURTH GATE HOLDS") / H sprite pass / I audio pass (act1_orchestral / act2_glitch / act3_choir / act4_lucifer locked names).
- Palette/motifs: gold/bronze, deep purple, crimson, cyan glitch; hexagrams, grimoire pages, light-chains, per-demon sigils.

## 8. Meta save schema (`user://save.cfg`)

- `[meta]`: fragments balance, market unlocked. `[market]`: owned mods. `[rentals]`: armed rental. `[bestiary]`: `kills={id:n}` (req `max(20, 50 - scholars_focus)`; `note_kill` counts only). `[seal]`: `levels={id:n}`. `[hero_seals]`: `data={hero:{node:n}}`. `[descent]`: `data={hero:snapshot}` (one loadout checkpoint per hero, written on non-dev Withdraw; snapshot keys `v,hero,next_act,acts_cleared,level,xp,weapon,passive,chest,upgrades,mods,banished,rerolls,skips,banishes,stock_at_snapshot`; rentals excluded; malformed snapshots dropped on load). Direct-dict save, type-guarded load, unknown sections preserved. Signals: `coins_changed`, `seal_changed`, `hero_seal_changed(hero_id)`, `bestiary_updated`.
- Helpers: `get_seal_bonus/get_total_seal_bonus(hook)`, `get_utility_stock()` = sum of Fate levels, `get_catalogue_requirement()`, `catalogued_count()`, `get_market_price(base)` (single discount path for display + checkout), `dev_add_coins` / `dev_wipe`. Descent: `get_descent` / `set_descent` (saves immediately) / `has_descent`; `[descent]` cleared by `dev_wipe`.
- Hooks: `World.on_kill` → `Meta.note_kill`; `Player.stat()` adds seal + bestiary (`damage` +1%/demon, `move_speed` +0.5%/demon); crit `0.07 + luck*0.25 + seal`, mult 2.0; execute skips `boss_time>0`; `add_xp` applies `xp_gain`; market buys via discounted price.

## 9. Gameplay constants

- Branch L4, evo1 L8, evo2 L16, cap 16 kit (data max otherwise). No gates; owed pairs are bonus picks after the normal pick (titles CHOOSE A PATH / EVOLUTION / FINAL EVOLUTION). Fallback evos Surge/Focus/Ascension/Transcendence until ~80 hand pairs land. `_choice_key` carries `:b<branch>` + `:e<idx>t<tier>`.
- Draft lanes: POWER (owned kit upgrade) / STAT (weight `1/(1+0.45*rank)`) / WILD (carried chest upgrades only, never fresh weapons; rarity 1.0/0.5/0.25, Fortune lifts rare/legendary) / LUCK BONUS 4th. Capacity ~65 reachable vs ~45 picks/30min — heal card is unreachable safety only. Late damage/area/cooldown ranks 4-5 scale to +60% by 30:00; defenses flat. XP curve tabled until F5 pacing data.
- Chest rarity per slot: Rare 12% base / 25% cap / +10% per luck; Legendary 4% / 10% / +5% per luck. `CHEST_WEAPON_IDS` 9 commons frozen; `RARE_WEAPON_IDS` = shamir_tooth; `LEGENDARY_WEAPON_IDS` = shamir (locked, `is_legendary_unlocked` stub false, rule TBD). Locked legends: blacked-out + `???` + `unlock_hint`, SEALED/disabled. Rentals: rare ~200-350, legendary ~500-800.
- Fate chain: `fates_intercession` (3) → `threads_of_fortune` (2) → `moirais_shears` (1); stock = sum levels (max 6). Banish filters pools BEFORE draw (never punches holes); run-local only.
- Behaviors: raised dead/allies non-damageable, time-limited (passive-side, see §10). Glitch_goblin freeze+stutter, blink reserved (see §10). Goose low-HP: damage +90%, speed +25%, cooldown −35% at 0 HP. Harpy grounded by Bat/Dragon Whelp, aerial projectiles, `can_hit_flying` elites.
- Seal view: full hexagram always visible; `_segment_lit(a,b)` solid only when both ends >0 (ley line = root-owned exception); 6th ray = Fate chain at ~330°; badges 112x46; Vessel tab = stub.
- Perf levers used (do not retune without asking): gems MAX 260 / coins 120, MERGE_R 70/72, halo gate v5/v2, view-cull +96px, batched pickups, `_set_text` guard. If lag returns: enemy/projectile caps or FX density — options first.

## 10. Enemy behaviour catalogue (splice/mix parts for new sprites)

- Movement (`behavior` string in `.tres` → `match` arm in `enemy_manager.gd`; strings NOT allow-listed, unknown falls back to chaser): `chaser` = default straight-line (goblin/brute/zombie/spider/skeleton — NOT a coded arm, it's the `_:` fallback) / `swarm` = sine-wobble chase, inline (bat) / `charger` = stalk, <190px trigger, 0.45s windup w/ flicker, 0.4s 3.4x dash, 1.6-2.6s re-arm (raptor, assassin) / `glitch` = 1.2-2.4s stalk+jitter, 0.5s hard freeze (damage-immune, frame held, knock zeroed, no telegraph), 4x18px homing stutter jerks, contact always on (glitch_goblin; consts `LAG_*`/`GLITCH_JITTER`, random-skip 4-frame @12Hz) / `blink` = reserved hunt-blink, vanish i-frame + player ring, NO def uses it / `ranged` = <340 shoot, <130 retreat 0.8x, else strafe (dragon_whelp) / `boss` = charger base + volley kit (hellfire_devil, belial) + pre-volley telegraphs (converge ring + aim wedge read off the live shoot timer, cosmetic 0.45s window, never retimes; sweep marker during spiral casts; `clear_cues` on kill) + ground auras (`_elite_aura` per-frame `cue_aura` slot 3, no shape-pool cost) / `boss_broker` = Asmodeus ground-and-spread kit (built 2026-10-17): shuffled `deck` of telegraph -> cast attacks (fan bone shards / ledger ground zones / gap_ring safe-gap rings / foreclose dash + trail zones), plus a `summon` of `add_def_id` "Creditors" injected every `add_interval` while adds < `add_cap` (`summoned` adds drop no Fragments, still drop gems); enrage variants; zones are `ProjectileManager.Kind.ZONE` (`spawn_zone`, never hits enemies or contact-hits; pop deals `zone_damage` if the grounded player is inside radius).
- Attack modules (def fields, mix onto any movement): contact (all, 0.75s cd) / `shoot_interval/speed/damage` single shots / volley kit `projectile_count/spread_deg` fan + ring + `spiral_*` every-Nth-volley + `splash_*` / `enrage_hp_fraction` (0.4) + `enrage_interval_mult` (0.7) + speed mult.
- Modifier flags: `height=1` flying (visual lift, shadow, contact needs `can_hit_flying`, weapons skip except webs) / `is_elite` (red tint, 0.35x knockback, half stun/fear, gem+coin showers, chest, spawn announce) / spawn `weight/start/end/elite_every` windows / `boss_time` one-shot events (boss loop is the pre-battle hook: future intro dialogue pauses director there) / `coin_drop`. Director pause = zero spawns (regular/elite/boss/bat; manual `spawn_around_id` exempt for isolation); bat ring respects whitelist; time-skip while paused only moves the clock, due events fire once on unpause.
- Universal pipeline (every behaviour runs inside it): stun/fear override → `×slow` → separation → vel lerp → knock decay; visual priority stun → behaviour anim → slow/fear/burn → elite tint.
- New-sprite recipe: art strip + `.tres` (pick ONE movement string + flags + attack fields) + `spawn_start/end` window; brand-new movement = add one `match` arm reusing `E.state/state_t`, no new fields. Ally summons are passive-side (`RaiseDead`/`SummonAllies` in `passive_behaviors.gd`, non-damageable + time-limited), not enemy behaviours.

## 11. Open TODOs

- HUD pips: 16-pip compression is thin slits — fix TBD (two rows of 8, or compress only when needed). `hud.gd` `_SlotBar._draw()`.
- Codex UI (Ars Goetia: kills 0/req, catalogued glow, bonus table). Seal Vessel hero-tree content (`HERO_TREES` stub). Circle/Stability/Interrogation per §7. Legendary unlock rule for shamir. Evo hand-authoring backlog (~80 pairs). Android preset + templates + landscape lock (author-side, Windows-only today).
- Director pacing (BUILT 2026-10-17): zero elites before 180s (fallback fodder); per-act elite cooldowns 60s (A1) / 45s (A2) / 30s (A3-4) via `ActDef.elite_cooldown`; `ActManager` director + `_tick_director` gates (enemy_manager, spaces) + `world.set_arena_theme()` → `ground_layer.apply_theme()` (world tabs); visuals BUILT: A1 ash / A2 cyan glitch / A3 crimson embers / A4 gold pulse (`vignette_pulse`) + per-act music/banner/ambient.
- Dev panel: DONE pre-run TIME (jump-in + presets Act I/II/III at 0/450/900s + Boss-10s + slow-mo 0.1-1.0 FX-inspection rate, hit-stop restores to baseline) / DIRECTOR (hard pause + spawn mult) / LOCKS (gems/levels/treasures) / SURVIVAL (godmode) + whitelist, all applied atomically pre-tick and mirrored live in F1 (restart-safe). TODO: Fragments deposit row replaces `+250c`+Deposit (theme labels, `ARCHIVE / META` header); per-section `Meta.dev_reset_*()` + F1 `RESETS` block + pre-run seed field/unlock checkbox.
- Limits: engine F5 owned by author (§3); balance untuned; no controller/meta-progression beyond Archive+Seal backend; Asmodeus dedicated art + strips + currency sprite + fireball FX (pending user) + audio passes pending (4 act themes, §4/§7).
