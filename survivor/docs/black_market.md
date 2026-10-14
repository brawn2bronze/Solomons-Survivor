# Black Market — meta-progression (implementation notes)

Implements `brief.md` exactly: coins, a 25:00 unique boss that unlocks the Black Market, one-run weapon rentals, and permanent
per-weapon upgrades for all 9 chest weapons, with a persistent save. Nothing from the earlier generic "meta-progression" prompt
(mastery, heirlooms, bounty ledger, arenas...) was built: the brief is normative and names none of it.

## Status of verification (read this first)
* **Not run in Godot.** The authoring sandbox has no Godot binary and no Python 3 project checker. Everything was reviewed by hand
  and by `tools/check_black_market.py` (indentation, `:=` on Variants, lambdas in tweens, audio keys, listing coverage).
* Run `python tools/check_project.py` (your real checker) and `godot --headless --import` once before playing.
* `ui.gd` and `options_panel.gd` were not in the export. The new screen only uses `UI.*` calls already present elsewhere
  (`label`, `wrap_label`, `button`, `panel`, `bar`, colours `GOLD TEXT DIM RED GREEN PANEL PURPLE INK`).
* The "fresh critic" loop of the original prompt could not be run (no second instance); a manual self-review was done instead.
* All numbers (drop rates, prices, boss stats) are first-pass and **unplaytested**.

## Design decisions on the brief's open items
| Open item | Decision |
|---|---|
| Boss | **Asmodeus, Broker of Bones** (`bone_broker`), run time **25:00** (`boss_time = 1500`), one spawn per run, 8000 hp, no director scaling, ground elite that can hit flyers. Charger wind-up/dash plus a radial bullet ring every 3.2s (14 shots; 22 and faster when below 40% hp, +35% speed). Reuses `skeleton.png` at 3x scale: **needs dedicated art**. |
| Repeat kills | The boss keeps coming every run after the unlock (coin jackpot + chest). |
| Save file | `user://save.cfg`, section-per-feature, so the roster-unlock plan in workbench §11 can add its own section without a second file. `Meta` preserves sections it does not own. |
| Coin banking | Pickups add to the persistent balance immediately; disk writes are batched (12s) and forced on run end, quit, focus loss, purchase and unlock. A crash loses at most ~12s of coins. |
| Rental model | Buy = +1 stock (max 5 per weapon) and arms it; **one armed rental per run**, spent when the run starts (retry/restart spends another). Dev sandbox runs never spend rentals. |
| Permanent mods | Apply whenever the weapon enters a run, rented or found in a chest (`Player.apply_chest_weapon`). |

## Data model (`user://save.cfg`)
```
[meta]
version=1
[market]
coins=412
unlocked=true
armed_rental="pickup_aa12"
mods=["mod_akimbo", "mod_dead_eye"]
[rentals]
pickup_aa12=2
```
Corrupt file: copied to `save.cfg.corrupt`, fresh defaults, warning logged. Missing fields default. Newer `version`: known
fields read, rest preserved. Unknown mod ids are kept (a removed listing never eats a purchase). Writes go to a temp file then rename.

## New files
| File | Role |
|---|---|
| `autoload/meta.gd` | `Meta` autoload: save/load, coins, unlock, rentals, mods, dev helpers |
| `data/defs/market_item_def.gd` | `MarketItemDef` resource (kind RENTAL/MOD, weapon_id, cost, ops, flags, icon) |
| `data/market/*.tres` | 9 rentals (`rent_<weapon>`) + 9 mods (`mod_*`) |
| `data/enemies/bone_broker.tres` | the boss |
| `src/core/coin_manager.gd` | pooled coins: drop rules, magnet, collect, overflow merge |
| `src/ui/black_market_screen.gd` | the shop (tabs, cards, progress bar, footer) |
| `src/ui/coin_icon.gd` | drawn coin used by HUD + shop |
| `audio/player/coin_pickup.wav`, `audio/ui/market_unlock.wav`, `audio/ui/market_purchase.wav` | placeholder tones |
| `art/market/{aa12,cloak,energy_food}.png`, `art/status/burn.png` | placeholder 32x32 icons (grey-box fix for the 3 art-less weapons) |
| `tools/check_black_market.py` | static checks for this feature |

## Modified files (all additive; line endings and indentation of each file preserved)
`project.godot` (Meta autoload) · `autoload/db.gd` (`market`, `market_items()`) · `autoload/audio_manager.gd` (3 events, `coin_pickup()`) ·
`data/defs/enemy_def.gd` (`boss_time`, `boss_unlock`, `coin_drop`, behavior `boss`) · `src/main.gd` · `src/core/enemy_manager.gd`
(burn status, boss director + behavior, coin drop in `_kill`) · `src/core/world.gd` (coins, rental loadout, boss unlock, flush) ·
`src/core/projectile_manager.gd` (burn on hit) · `src/core/status_icons.gd` (burn icon) · `src/player/player.gd` (mods on chest weapons) ·
`src/abilities/ability.gd` (`set_mods/has_mod/mod_f`) · `src/abilities/weapon_behaviors.gd` (the 9 mods) ·
`src/ui/{main_menu,hud,gameover_screen,ability_art,dev_overlay}.gd` · `workbench.md` (section 12).

## Economy (first pass)
* Per-kill coin chance `4% + 16% x luck` (Fortune is +0.1 luck/level: 4% to 12% at max); a coin is worth 2 with chance `30% x luck`.
* Elites: guaranteed shower of 6 coins x 2. Boss: 160 coin jackpot (16 coins x 10).
* Rentals 40-110 (about a third to half of an average run). Permanent upgrades 480-680 (several runs each).
* Coins are finite sinks only (one-time upgrades, consumable rentals): no scaling loop.

## The 9 permanent upgrades
| Weapon | Upgrade | Effect |
|---|---|---|
| Rifle | Dead-Eye | every 4th shot: x3 damage, +3 pierce, bigger slug |
| Shurikens | Storm Nova | every 4th volley also throws a ring of 8 |
| Blunderbuss | Brimstone Breath | pellets ignite (new burn status, 8 dps, 3.5s) |
| AA-12 | Akimbo | second full volley from the off hand (double pellets) |
| Dynamite | Cluster Charges | 3 half-damage aftershocks per blast |
| Keg | Concussion Charge | blast stuns 1.3s (half on elites) |
| Caltrops | Barbed Tangle | stepping enemies are slowed 50% for 2.5s |
| Energy Food | Hearty Meal | each snack heals 30% max hp |
| Cloak | Warding Pulse | raising the ward damages, shoves and stuns nearby enemies |

## Integration flow
1. `EnemyManager._kill` -> `CoinManager.on_enemy_killed` (roll / shower) -> pickup -> `Meta.add_coins` + `world.run_coins`.
2. `EnemyManager._tick_director` spawns any def with `boss_time` once `run_time >= boss_time`; `World.on_kill` sees `boss_unlock` and calls `Meta.unlock_market()`.
3. Main menu button -> `BlackMarketScreen` -> `Meta.buy_item / arm_rental / disarm_rental`.
4. `World.start` -> `_apply_meta_loadout()` -> `Meta.consume_armed_rental()` -> `Player.apply_chest_weapon()` -> `Ability.set_mods(Meta.mod_items_for(id))`.
5. Mods are data (`ops` rewrite numbers through the existing op format; `flags` are read by behaviors via `has_mod()/mod_f()`).

## Extending
* **New rental/upgrade listing:** add a `MarketItemDef` .tres in `data/market/`; if it needs new behavior, read a new flag in the weapon's behavior with `mod_f("key")`.
* **New unlock boss:** an `EnemyDef` with `behavior`, `boss_time`, `boss_unlock = "<key>"`; handle the key in `World._on_boss_defeated`.
* **New meta track (e.g. roster unlocks):** add a section to `user://save.cfg` inside `Meta` (follow `SEC_*` + `load_save/save`), emit a signal, keep gameplay code calling `Meta`.
* **Real audio:** replace the three wavs (same paths) — nothing else changes.

## Things that need your eyes
* `tools/gen_data.py`: nothing here is in the seed. `bone_broker.tres` and `data/market/*.tres` are hand-added (same status as `jack`/`fun_guy`); if the seed regenerates `data/enemies/` wholesale, re-add the boss.
* `check_project.py` was not available. Unknown rules might object to an elite with `elite_every = 0` or a new `behavior` string.
* `chest_manager.gd DROP_CHANCE = 1.0` is untouched test tuning (the boss still drops a chest).
* Generated icons/sprites are placeholders; the boss reuses the skeleton sprite.

## Testing checklist
1. Boot: the DB line ends with `18 market listings`; no parse errors; `user://save.cfg` appears after first coin autosave.
2. Dev run (F1): `+250c`, `Unlock`, quit to menu: Black Market button is live; open it; buy a rental; coin total drops, card shows ARMED, footer shows "Next run".
3. Start a normal run: announcement `SURVIVE - RENTED: ...`; HUD treasure slot shows the weapon with "(rental)"; the rental stock fell by one; a second run starts without it.
4. Buy each upgrade, grant that weapon via dev "Grant chest", confirm its behavior (Dead-Eye heavy slug, Storm Nova ring, burning enemies orange with flame icon, double pellets, aftershocks, stun, slow, heal, pulse).
5. Coins: kill enemies, coins spin and magnetise with rising pitch, HUD counter climbs; with Fortune the drop rate visibly rises; elite kill showers coins.
6. Boss: dev `24:50`, wait 10s (or `Boss` button): warning banner, boss bar and boss music, ring bullets, dash, enrage below 40%; kill it: gold flash, "THE BLACK MARKET IS OPEN", jackpot, menu button unlocks; game over shows coins and the unlock line.
7. Persistence: quit and relaunch: coins, unlock, owned upgrades, armed rental survive. Corrupt `save.cfg` (type garbage): game boots, `.corrupt` copy exists.
8. Regression: all 10 characters start; level-up and chest drafts work; Esc/pause; DevMenu still lists the full roster.
