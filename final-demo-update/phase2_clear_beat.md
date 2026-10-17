# PHASE 2 of 3 - Act Cleared beat, Descend / Withdraw, Fragment escrow

Prerequisite: Phase 1 is landed and the author has confirmed zero errors. Work in `survivor/` (master). Never touch `../Solomon's Survivor Demo/`.

## 0. Read first, obey always

Read `workbench.md` (§3 coding rules are binding: per-file tabs/spaces/CRLF lists, pre-edit indent reveal, post-edit rescan after EVERY file edit, no `Set-Content`, `:=` typing rules, no `:=` on untyped-ref expressions, new files LF + spaces + classified in the lists, "Fragments" strings only, never ask the author to run checkers/F5/exports, restore `.godot` after headless runs). Then read: `world.gd`, `act_manager.gd`, `gameover_screen.gd`, `pause_menu.gd`, `coin_manager.gd`, `hud.gd`, `meta.gd`, `main.gd`, `ui.gd`.

## 1. Fragment escrow (this is what makes "die and lose them" real)

Today pickups add to `Meta.coins` immediately while `World.run_coins` mirrors the total. New rule for non-dev runs: Fragments picked up live ONLY in `world.run_coins` (escrow, in memory) and enter `Meta.coins` only on **Withdraw**. Death, abandoning the run, or closing the game banks nothing. This also closes the "alt-F4 to keep loot" exploit.

- Read `coin_manager.gd` to find every place that calls `Meta.add_coins` during a run. Route them through one new `World.credit_fragments(n: int)`: `Game.dev_active` -> `Meta.add_coins(n)` as before AND `run_coins += n` (dev sandbox keeps legacy behavior); otherwise `run_coins += n` only.
- `World.bank_run()`: guarded to run once; `Meta.add_coins(run_coins)`, `Meta.flush()`, records `run_banked`. `_exit_tree` must NOT bank.
- On death (`_on_died`, non-dev): `run_lost = run_coins`, `run_coins = 0`, nothing touches Meta. Bestiary kills (`Meta.note_kill`), the Archive unlock and seal levels are unaffected.
- Mid-run abandon: in `pause_menu.gd`, the exits (retry / character select / main menu) show a confirm line when `run_coins > 0` and not dev: "Abandon the run? N unbanked Fragments will be lost." with Confirm/Cancel. Confirming discards the escrow.
- HUD counter and `Meta` autosave logic keep working; `run_coins` stays the single source for HUD/game over.

## 2. Act Cleared beat (replaces the Phase 1 shim in `ActManager.boss_slain`)

Sequence on the unique act boss's death (the existing Asmodeus Archive unlock/flash/announce fires first and stays untouched):

1. Stop music (fade ~1.2s), `enemies.wipe_quiet()`, `gems.attract_all()`, a short `Game.hit_stop`, let the run breathe ~2.2s (sim keeps running so pickups vacuum in).
2. Wait until no picker is open and nothing is pending: add `World.pickers_idle() -> bool` (`not levelup.visible and _pending_levels == 0 and _pending_chests == 0 and _pending_owed.is_empty()`), poll every 0.1s. Boss chests and level-ups resolve BEFORE the choice screen.
3. `World.open_act_clear(def)`: `sim_running = false`, `get_tree().paused = true`, show `ActClearScreen`. Guard the pause hotkey in `_unhandled_input` so Esc cannot open the pause menu over it.

### ActClearScreen (new `src/ui/act_clear_screen.gd`, `class_name ActClearScreen extends CanvasLayer`, layer 40, `PROCESS_MODE_ALWAYS`)

Signals `descend`, `withdraw`. `show_clear(cleared: ActDef, next: ActDef, at_risk: int, forced: bool, boss_name: String)`. Style from `UI` (dark ink panel, gold trim, outlined labels, `UI.button`), staggered pop-in like `LevelUpScreen`, 0.5s "armed" delay before input.

- Title: `"<ACT I> CLEARED"` (gold 72). Sub: `"<boss_name> - slain"`.
- Two large choice buttons side by side:
  - **DESCEND** - "Descend to <next display_name>: <next title>". Under it in crimson: `"Fragments at risk: N. Fall in battle and they are lost."`
  - **WITHDRAW** - "Withdraw - bank N Seal Fragments". Under it in dim: `"Your loadout is saved so you can continue from the next act. Unsealed weapons do not follow you out."` (loadout-saved wording is only truthful after Phase 3; keep the string in one constant so Phase 3 can confirm it).
- Keys: 1 = Descend, 2 = Withdraw, arrows + Enter via focus, mouse hover grabs focus like the other buttons. Initial focus on Withdraw is wrong; focus Descend.
- **Forced** (`forced == true`, i.e. `not acts.next_is_playable()`, which is the Act III clear in the demo): no Descend button. Show the sealed card instead, centered, gold then dim:
  - `THE FOURTH GATE HOLDS.`
  - `The Morning Star has not yet found you worthy.`
  and a single WITHDRAW button. Drive "forced" purely from `ActDef.sealed` of the next act so shipping Lucifer later means flipping a flag.

### Descend

Hide the screen, `get_tree().paused = false`, `sim_running = true`, `acts.begin_act(next.index)` (clock resumes from `next.clock_start`, release the hold, banner, 3s music crossfade, arena theme tween), `enemies.breather(8.0)` (zero director spawns for 8s under the title card), `world.announce` not needed. Rentals stay armed because it is the same run. Build, HP, banishes etc. are untouched, it is simply the same run continuing.

### Withdraw

`World.withdraw()`: guard with `_over`; `_over = true`; `bank_run()`; rentals do not carry (record `rentals_stripped = true`; nothing else to do now, Phase 3 excludes the rented weapon from the checkpoint); `Meta.flush()`; `sim_running = false`; stop music; hide the clear screen; show the victory screen (below). Retry/select/menu from it go through the existing `exit_requested` path.

## 3. Victory + death screens (`gameover_screen.gd`, spaces)

- New `show_victory(world)` reusing the show_result layout with a gold frame (`UI.GOLD`) instead of red. Title: `THE SEAL HOLDS` (the forced Act III clear uses `THE FOURTH GATE HOLDS` with the "Morning Star" line beneath it in `UI.DIM`). Subtitle: `"<hero> - <ACT N> cleared"`. Rows: Time survived, Level reached, Enemies slain, `Fragments banked` (+N), `Fragment balance` (Meta.coins), Weapon, Passive. Keep the "THE ARCHIVE IS UNSEALED" line when `world.market_unlocked_now`. Buttons: Retry / Character Select / Main Menu. Do not mention the checkpoint yet (Phase 3 adds it).
- `show_result` (death): when `world.run_lost > 0` add a red row `Fragments lost` with the amount and a dim hint line `"Withdraw after an act boss to keep your Fragments."`. Keep the existing "Fragments gathered" row but relabel it to `Fragments carried` so the lost row makes sense, or fold it, whichever reads cleaner. No change when nothing was lost.

## 4. Things that must not break

- Archive unlock (`boss_unlock == "black_market"` on Asmodeus) keeps persisting immediately at the kill via `Meta.unlock_market()`; dying afterwards must not revoke it.
- Dev sandbox runs never hit the clear flow (it only fires for `acts.held_boss_id == e.def.id`), never escrow, never forfeit.
- `Meta.flush()` on death and on withdraw; the quit/focus-loss flush is unchanged.
- Perf: nothing allocates per frame in the new screen; no new shaders.

## 5. Finish

- Update `tools/check_project.py` statically if it covers any changed surface. Workbench per hygiene rules (merge, no new sections): §7 G line (escrow + clear beat), §8 (escrow note: run Fragments are in-memory until Withdraw), §3 lists (new file), §11. Report static state and stop; do not ask the author to run anything.
