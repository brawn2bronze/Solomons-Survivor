# New Character Intake Form

Fill every section. A character is NOT done until all boxes are checked.
Drop finished art in the paths given; add one `.tres` per new weapon/passive in
`data/weapons/`, `data/passives/`, `data/characters/` (copy the closest existing
file) and the DB autoload picks it up with zero code changes.

## 1. Identity (CharacterDef)
- [ ] `id` (lowercase, no spaces, e.g. `plague_doctor`):
- [ ] `display_name`:
- [ ] `title` (e.g. `Herald of Flies`):
- [ ] `roster_order` (next free number, current max is 12):
- [ ] `blurb` (1-2 sentences, shown on character select):
- [ ] `color` (card accent + tile outline, `Color(r, g, b, 1)`):
- [ ] `playstyles[3]` (three viable builds, one line each):
  1.
  2.
  3.

## 2. Base stats (`base_stats` keys)
- [ ] `max_hp` (70 glass / 100 avg / 170 bruiser):
- [ ] `move_speed` (85 slow / 110 avg / 165 goose):
- [ ] `damage` mult (0.75 weak / 1.0 avg / 1.45 spider):
- [ ] `defense` flat (0 / 1 / 2):
- [ ] `regen` hp/s (0 / 1.0 / 1.2):
- [ ] `area` (1.0), `cooldown` mult (1.0, lower = faster), `pickup_radius` (55), `luck` (0.0):
- [ ] `flags`: `flying` (bool) / `knockdown_seconds` (float, flyers only) / `low_hp_scaling` (`{stat: bonus at 0 HP}`) / `{}`:

## 3. Kit (which weapon + passive)
- [ ] `weapon_id`: existing id OR new (define in §4):
- [ ] `passive_id`: existing id OR new (define in §5):
- [ ] If reusing: name the character fantasy that makes the shared kit feel different (stats + playstyles must carry it):

## 4. Weapon spec (WeaponDef — copy nearest `data/weapons/*.tres`)
- [ ] `id`, `display_name`, `description` (shown on cards):
- [ ] `behavior`: existing key (`revolver, cannon, melee_swipe, melee_bite, chain_lightning, wave, skull, goose_charge, pickup_volley, pickup_blast, pickup_caltrops, pickup_buff, pickup_ward, flicker_strike, worm_ride`) OR new (requires a new inner class in `src/abilities/weapon_behaviors.gd` + `make()` entry):
- [ ] `base{}` (every key read as `p["..."]` in the behavior MUST exist here):
- [ ] Branch A `name/desc/on_pick/per_level/flags`:
- [ ] Branch B `name/desc/on_pick/per_level/flags`:
- [ ] `level_scaling{}`, `max_level` (8 kit / 5 chest), `color`, `audio_event` (must exist in `autoload/audio_manager.gd`):
- [ ] Card art: `icon` path (64px cells), `icon_frames`, `icon_fps`, `preview_kind` (`spin` for thrown, `pulse` for placed, `static` otherwise):
- [ ] Branch strips if drawn: `anims = {"wA": {...}, "wB": {...}}`:

## 5. Passive spec (PassiveDef — same shape as §4)
- [ ] `id`, `display_name`, `description`:
- [ ] `behavior`: existing key (`whip, stun_pulse, summon_allies, astral_clone, web, roar, swoop, raise_dead, turds`) OR new (new inner class in `src/abilities/passive_behaviors.gd`):
- [ ] `base{}`, Branch A, Branch B, `level_scaling`, `max_level` (8), `color`, `audio_event`:
- [ ] Card art: `icon` path, `icon_frames`, `icon_fps`, `preview_kind` (`static` unless it spins/pulses):
- [ ] Branch strips if drawn: `anims = {"pA": {...}, "pB": {...}}`:

## 6. Sprites (all 64px cells unless noted — character strips are 64xN horizontal)
- [ ] Base strip `art/characters/<id>.png` (`frames` 6, 8 for flyers: 0-1 idle, 2-5 run, 6-7 fly):
- [ ] `ability_anims.base` `art/characters/<id>_base.png` (pre-branch showcase, shown on character select + Lv 1-3 cards):
- [ ] `ability_anims.wA` `art/characters/<id>_wA.png` (weapon branch A use):
- [ ] `ability_anims.wB` `art/characters/<id>_wB.png` (weapon branch B use):
- [ ] `ability_anims.pA` `art/characters/<id>_pA.png` (passive branch A use):
- [ ] `ability_anims.pB` `art/characters/<id>_pB.png` (passive branch B use):
- [ ] Each strip lists `frames` + `fps` (8.0 default). Undrawn slots may be omitted — silhouette + base icon show until you draw them.
- [ ] New status effect? 32x32 icon in `art/status/<effect>.png` + hook in `src/core/status_icons.gd` (`_enemy_tex` / `_player_tex`):

## 7. Audio + balance targets
- [ ] `audio_event` per ability (existing event or new wav/ogg in `audio/` + entry in `AudioManager`):
- [ ] Time-to-kill vs goblin at Lv 1 / Lv 4 / Lv 8 (both branches):
- [ ] Cooldown / range / area windows that make the kit feel different from its closest sibling:
- [ ] Which elite pressures it (brute grounds you? whelp outranges you?) and the intended answer:

## 8. Definition of done
- [ ] `python3 tools/check_project.py` → PASS (add art-size rows for any new folders you introduce):
- [ ] Character appears in roster, kit text + icons + showcase cycle render on character select:
- [ ] Level-up offers weapon/passive cards with animated previews; branch pair forces at Lv 3:
- [ ] Status icons appear above heads in a live run (stun / fear / poison / rage as applicable):
- [ ] Dev sandbox (`dev_max_build`, chest draft, reroll/skip) exercises the new kit without errors:
