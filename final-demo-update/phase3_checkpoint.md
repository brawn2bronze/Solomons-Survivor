# PHASE 3 of 3 - Loadout checkpoint + Continue (the riskiest phase)

Prerequisite: Phases 1 and 2 are landed and confirmed zero-error by the author. This phase touches player, draft and save state. If anything here conflicts with a Phase 1-2 invariant, keep the invariant and report the conflict. Work in `survivor/` (master). Never touch `../Solomon's Survivor Demo/`.

## 0. Read first, obey always

Read `workbench.md` (§3 coding rules are binding: per-file tabs/spaces/CRLF lists, pre-edit indent reveal, post-edit rescan after EVERY file edit, no `Set-Content`, typed `:=` only and never on untyped-ref expressions, new files LF + spaces + classified, "Fragments" strings only, never ask the author to run checkers/F5/exports, restore `.godot` after headless runs). Then read: `ability.gd`, `player.gd`, `world.gd`, `levelup_screen.gd`, `meta.gd`, `character_select.gd`, `main.gd`, `game.gd`, `db.gd`, `act_manager.gd`, `dev_menu.gd`, `dev_overlay.gd`.

## 1. Design (locked)

- A checkpoint is written **on Withdraw only** (never on Descend, never on death, never in dev runs). It stores the build at the moment of the clear plus which act comes next.
- One checkpoint per hero. It persists until a later Withdraw by that hero overwrites it. Starting a fresh run does not erase it. Dying in a continued run keeps it, so a hard act can be retried with the same build.
- Continue starts a NEW run at the next act's `clock_start` with the saved build, full HP, and fresh Fragment escrow (run_coins 0).
- If the next act is `sealed` (the Act III clear in the demo) the checkpoint is still written but Continue shows disabled as "ACT IV - THE FOURTH GATE HOLDS". Flipping `sealed` to false later enables it, no code change.

## 2. Snapshot contents (`Descent` static helper, new `src/core/descent.gd`, `class_name Descent extends RefCounted`, spaces LF)

`Descent.capture(world) -> Dictionary` and `Descent.restore(world, snap)`. Keys: `v` (1), `hero`, `next_act` (index), `acts_cleared`, `level`, `xp`, plus:

- **Kit:** weapon and passive: def id, level, branch, evolution picks. Add `Ability.to_dict()` / `Ability.from_dict(d)` in `ability.gd` rather than poking internals from outside; derive the exact state fields from the file (level, branch, branch_level, evo choices, anything `max_level_now()` depends on).
- **Chest weapons:** id + level for each, EXCEPT the Archive rental: skip `player.rented_weapon_id` entirely (rentals strip at Withdraw; otherwise Continue would make a one-battle rental permanent). If the id also happened to be taken via a normal chest it is stripped too; accept this.
- **Stats:** `upgrade_levels` (ranks drive the draft lane weights) and `mods` wholesale (this already contains any Foreseen Victory deltas granted at run start, so Continue must NOT regrant them).
- **Draft state:** `_banished` (the banish list), `_rerolls`, `_skips`, `_banishes` remaining, and `stock_at_snapshot = Meta.get_utility_stock()`.
- Not snapshotted: rentals, HP (restored full), Seal and bestiary bonuses (read live from Meta, so Seal purchases made between acts apply), buffs, run_coins.

Fate-stock top-up on restore: `rerolls/skips/banishes = saved + max(0, Meta.get_utility_stock() - stock_at_snapshot)`.

Restore order in `World.start` when `Game.pending_descent` is non-empty: after `player.setup` and before the first tick: restore kit -> mods/upgrade_levels -> level/xp (`xp_next = Player.xp_for(level)`) -> chest weapons via `apply_chest_weapon` then set level and `set_mods(Meta.mod_items_for(id))` -> `player.refresh()` -> `hp = max_hp` -> draft state. SKIP `_apply_meta_loadout` entirely for a continued run (no rental, no Foreseen regrant, no Temporal Loops XP head start: level is restored). Start the run with `acts.begin_act(snap.next_act, true)`. Announce text: `"CONTINUE - <ACT N>"`.

Validation: if any saved weapon/passive/chest id no longer exists in `DB`, or `v` is unknown, discard the checkpoint silently (push_warning) and treat it as absent.

## 3. Meta persistence (`meta.gd`, spaces)

New section `SEC_DESCENT = "descent"`, `data = {hero_id: snapshot_dict}`. Same pattern as `hero_seals`: direct-dict save, type-guarded load (rebuild each snapshot defensively; drop malformed ones), unknown sections still preserved. Do not bump `SAVE_VERSION` (additive). API: `get_descent(hero_id) -> Dictionary`, `set_descent(hero_id, snap)` (saves immediately), `has_descent(hero_id)`. `dev_wipe()` clears it.

Write the checkpoint inside `World.withdraw()` BEFORE `bank_run()` completes the save, non-dev only. Also update the Phase 2 strings: the Withdraw sub-line on the clear screen and a new victory-screen line `"Loadout saved - continue from Character Select"` (or, when the next act is sealed, `"Loadout saved - the next gate is not yet open"`).

## 4. UI: Continue entry

- `character_select.gd` (spaces): for the highlighted PLAYABLE hero with a valid checkpoint, show a Continue button in the details panel (above the PLAYSTYLES block or beside the hero name), gold, text `"CONTINUE - ACT II"` with a small line `"Lv 14  -  <weapon name> Lv 8 (<branch>)  /  <passive name> Lv 8 (<branch>)"`. Disabled with the sealed wording when the next act is sealed. New signal `continued(id: String)`; the existing Enter/click path still starts a fresh run via `confirmed(id)`. Make the button keyboard-reachable (a hotkey `C` plus normal focus) and touch-friendly like the existing Back button.
- `main.gd` (tabs): `_start_run(id: String, use_descent := false)`; on `continued` set `Game.pending_descent = Meta.get_descent(id)` and `Game.run_from_descent = true`; every other entry sets both to empty/false. Retry from game over/victory reuses `run_from_descent` (a retry of a continued run restarts the Continue); select/menu clear it. Add the two vars to `game.gd` (tabs) and clear `pending_descent` once `World.start` has consumed it.
- Dev runs ignore `pending_descent`, never write checkpoints, and never show Continue effects.

## 5. Dev tooling

In `dev_menu.gd` (tabs) pre-run TIME presets add "Act I / II / III start" (0 / 450 / 900) and "Boss - 10s" (boss_time - 10) so every act and boss is one click away. Keep everything else in the panel intact.

## 6. Edge cases to handle explicitly

- Withdraw during a continued run overwrites the checkpoint with the deeper one (never a shallower one: if `next_act` would be lower than the stored one for that hero, keep the stored one).
- Pending picker/owed pairs are already empty at the clear screen (Phase 2 guarantees it); assert it and skip capture of owed state.
- Banished choice keys are `"type:id"` / `":b<branch>"` / `":e<idx>t<tier>"` strings; store them as-is.
- Rented weapon stripped at capture means the HUD "(unsealed)" tag logic must not run on a continued run (`rented_weapon_id` stays empty).
- The `[descent]` section must survive a save from an older build that does not know it (unknown sections are preserved by the existing load/save).

## 7. Finish

- Update `tools/check_project.py` statically (snapshot shape, `Ability.to_dict` round-trip keys if it is checkable). Workbench per hygiene (merge, no new sections): §8 schema (`[descent]` section), §5/§7 (Continue), §3 lists (new file), §11. Report static state and stop. Do not ask the author to run anything.
