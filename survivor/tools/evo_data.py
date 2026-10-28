#!/usr/bin/env python3
"""Authored evolution options (Lv8 pair + Lv16 pair per branch) and ability caps.

gen_data.py calls evo_data.apply(ABILITIES) before emitting: that fills every branch's evo1/evo2 tables
and every ability's `caps`. This file is the source of truth for option ids, names, card text, tuning
parameters and icon briefs (docs/evolution_overhaul.md section 10 is generated from it).

Slots: (ability, branch 'a'|'b', tier 1|2). Tier 1 = Lv8 pair, tier 2 = Lv16 pair, 2 options per slot.

Flags are NAMESPACED by option id so tier-1 and tier-2 options never collide when Ability merges them:
    flags = {'wayfinder': {'aim_move': True, ...}}
Behavior code reads its own params through EvoModule.p('key') (= ab.flags[id]['key']).

Card text (desc) is at most 110 characters. Tuning numbers are first-pass; the simulator and playtests own them.
"""

import os

from evo_plans import PLAN_CAPS, PLAN_OPTIONS
from evo_plans._common import option as _option

ICON_DIR = 'res://art/evo/'

OPTIONS = []


def E(ability, branch, tier, oid, name, desc, brief, **params):
    OPTIONS.append(_option(ability, branch, tier, oid, name, desc, brief, **params))


# ======================================================================================== COWBOY
# 6-Shooter  A = Speed Loader, B = Armor-Piercing Rounds
E('six_shooter', 'a', 1, 'running_reload', 'Running Reload', 'Reload charges 2.5x faster while you move, slower while standing still.', 'Revolver cylinder with motion lines', moving_rate=2.5, still_rate=0.7)
E('six_shooter', 'a', 1, 'fan_the_hammer', 'Fan the Hammer', 'With an enemy inside ~80px, the cylinder dumps in a point-blank fan (4s cooldown).', 'Revolver with a fan of six shots', trigger_range=80.0, cooldown=4.0, fan_deg=70.0)
E('six_shooter', 'a', 2, 'quickdraw', 'Quickdraw', 'First shot after each reload is x3; take no damage during the reload and it pierces everything.', 'Fast-drawn revolver with a big muzzle flash', first_mult=3.0, perfect_pierce=99)
E('six_shooter', 'a', 2, 'showdown', 'Showdown', 'Marks the toughest enemy in range; hits on it gain bonus damage that peaks at mid-range.', 'Crosshair over a duel silhouette', bonus_max=0.5, peak=0.6)
E('six_shooter', 'b', 1, 'ricochet_rounds', 'Ricochet Rounds', "A bullet's final pierce bounces once to the nearest enemy within 140px at 60%.", 'Bullet path with a bounce angle', bounces=1, range=140.0, mult=0.6)
E('six_shooter', 'b', 1, 'long_barrel', 'Long Barrel', '+25% range; bullets gain damage with distance traveled (capped at +60%).', 'Long barrel with distance ticks', range_mult=1.25, per_100px=0.1, cap=0.6)
E('six_shooter', 'b', 2, 'dead_eye', 'Dead-Eye', 'Stand still 0.7s (crosshair tell): the next slug is x3 with unlimited pierce. Moving cancels.', 'Eye with a crosshair pupil', still_time=0.7, mult=3.0, pierce=99)
E('six_shooter', 'b', 2, 'dead_mans_hand', "Dead Man's Hand", 'The 6th bullet of each cylinder is an explosive Ace (70px burst).', 'Ace of spades with a bullet', burst_radius=70.0, burst_mult=2.5)
# Flailing Whip  A = Barbed Chain, B = Cracking Lash
E('flailing_whip', 'a', 1, 'twirling_lasso', 'Twirling Lasso', 'The chain becomes an orbiting ring that spins faster the faster you move.', 'Spinning lasso loop', base_spin=2.0, spin_per_speed=0.02, hit_mult=0.5)
E('flailing_whip', 'a', 1, 'dragging_chain', 'Dragging Chain', 'Leaves a barbed trail behind you for 2s (ground-only trap).', 'Barbed chain trailing behind', life=2.0, spacing=24.0, dps_mult=0.4)
E('flailing_whip', 'a', 2, 'roundup', 'Roundup', 'Every 8s the lasso cinches: everything in range is pulled in and stunned 0.6s (bosses immune).', 'Lasso tightening around dots', every=8.0, pull_px=60.0, stun=0.6)
E('flailing_whip', 'a', 2, 'barbed_fence', 'Barbed Fence', 'Every 6s drop a post; chains link the last three, damaging and slowing anything that crosses.', 'Fence posts joined by barbed wire', every=6.0, posts=3, link_mult=0.5, slow=0.6)
E('flailing_whip', 'b', 1, 'sweet_spot', 'Sweet Spot', 'The lash becomes a long narrow line; its last 20% crits x2.', 'Whip with a glowing tip', length_mult=1.6, arc_deg=30.0, tip_frac=0.2, tip_mult=2.0)
E('flailing_whip', 'b', 1, 'snap_parry', 'Snap Parry', 'The lash destroys hostile projectiles it crosses; each one shortens the next lash.', 'Whip slicing a projectile', refund=0.15, refund_cap=0.5)
E('flailing_whip', 'b', 2, 'fast_hands', 'Fast Hands', 'A lash that hits 3 or more enemies instantly reloads the six-shooter.', 'Whip coiled around a revolver cylinder', hits_needed=3)
E('flailing_whip', 'b', 2, 'wanted_poster', 'Wanted Poster', 'Lashed elites and bosses are marked 8s: +25% damage from all sources while you stay within ~260px.', 'WANTED poster with a skull', mark_time=8.0, taken=1.25, leash=260.0)

# ======================================================================================== NINJA
# Katana  A = Wide Arc, B = Blitz Strikes
E('katana', 'a', 1, 'wayfinder', 'Wayfinder', 'Swings aim along your movement direction; standing still targets the nearest enemy.', 'Katana arc trailing along a curved arrow', aim_move=True)
E('katana', 'a', 1, 'momentum_edge', 'Momentum Edge', 'Moving builds up to 5 stacks of radius; they fade 0.6s after you stop.', 'Blade with five stacked speed lines', max_stacks=5, radius_per_stack=0.06, fade=0.6, build_per_sec=2.5)
E('katana', 'a', 2, 'moonfall_whirl', 'Moonfall Whirl', 'Every 5th swing is a 360 degree whirl with a ring tell, brief invulnerability and knockback.', 'Crescent moon over a full spinning ring', every=5, tell=0.4, invuln=0.25, knockback=160.0, mult=1.2)
E('katana', 'a', 2, 'afterimage', 'Afterimage', 'Each swing repeats from where you stood 0.6s later.', 'Katana with a translucent ghost copy', delay=0.6, mult=0.7)
E('katana', 'b', 1, 'weaving_blades', 'Weaving Blades', 'Passing within ~30px of an enemy at speed fires a free slash (per-enemy cooldown).', 'Zig-zag path through three dots with slash marks', pass_radius=30.0, min_speed=60.0, per_enemy_icd=1.2, mult=0.6)
E('katana', 'b', 1, 'unbroken_combo', 'Unbroken Combo', 'Hits build a combo; the 6th swing is a finisher. Taking damage resets it.', 'Chain of six slashes, the last one larger', finisher_at=6, finisher_mult=2.2, reset_on_hurt=True)
E('katana', 'b', 2, 'thousand_cuts', 'Thousand Cuts', 'Every 8th swing locks a 1s flurry onto one enemy (elites first); you are slowed meanwhile.', 'Many tiny slashes converging on one point', every=8, duration=1.0, cuts=10, cut_mult=0.5, move_mult=0.4, prefer='elite')
E('katana', 'b', 2, 'reprisal', 'Reprisal', 'Getting hit triggers an instant cross-slash with heavy knockback (6s cooldown).', 'Bold X slash over a cracked shield', cooldown=6.0, knockback=220.0, mult=1.5)
# Flash Bombs  A = Wide Flash, B = Lingering Flash
E('flash_bombs', 'a', 1, 'smoke_veil', 'Smoke Veil', 'Leaves a 4s smoke cloud: enemies inside are slowed 40% and deal 30% less contact damage.', 'Billowing smoke puff', life=4.0, slow=0.6, contact_mult=0.7, radius_mult=1.0)
E('flash_bombs', 'a', 1, 'trailing_mines', 'Trailing Mines', 'Drops up to 4 flash mines along your path; each stuns when stepped on.', 'Row of small glowing mines', max_mines=4, spacing=60.0, arm=0.3, stun=1.0)
E('flash_bombs', 'a', 2, 'vanish', 'Vanish', 'Each flash makes you untargetable for 0.8s; your next swing within 2s is a x2.5 ambush.', 'Fading ninja silhouette with a dagger glint', untargetable=0.8, window=2.0, ambush_mult=2.5)
E('flash_bombs', 'a', 2, 'cascade_flash', 'Cascade Flash', 'Stunned enemies that die emit a mini-flash (half radius, one generation only).', 'Big flash spawning smaller flashes', radius_mult=0.5, generations=1)
E('flash_bombs', 'b', 1, 'killing_light', 'Killing Light', 'The first katana hit on a stunned enemy is x2 and ends the stun. Stun is capped at 2s.', 'Shattering star over a blade', hit_mult=2.0, stun_cap=2.0)
E('flash_bombs', 'b', 1, 'panic_powder', 'Panic Powder', 'Enemies flee for 1.5s, then return slowed 30% for 2s.', 'Powder burst with arrows pointing outward', fear=1.5, slow=0.7, slow_time=2.0)
E('flash_bombs', 'b', 2, 'kawarimi', 'Kawarimi', 'When hit (12s cooldown) a log takes it, you blink ~120px away, and a flash stuns the area.', 'Wooden log with a puff of smoke', cooldown=12.0, blink=120.0, stun=1.0, radius_mult=0.8)
E('flash_bombs', 'b', 2, 'five_point_palm', 'Five-Point Palm', 'Marks the 3 toughest enemies; 4s later each bursts for 20% max HP (elites 8%, bosses 2%).', 'Open palm with five glowing points', targets=3, delay=4.0, pct=0.20, pct_elite=0.08, pct_boss=0.02)

# ======================================================================================== PIRATE
# Hand-Cannon  A = Shrapnel, B = Heavy Shot
E('hand_cannon', 'a', 1, 'chain_shot', 'Chain Shot', 'Fires a linked pair; the chain between the balls sweeps enemies.', 'Two cannonballs joined by a chain', spread=0.12, chain_width=6.0, chain_mult=0.5)
E('hand_cannon', 'a', 1, 'broadside', 'Broadside', 'While moving, also fires smaller balls port and starboard. Standing still fires forward only.', 'Ship hull side with cannon blasts', side_balls=2, side_mult=0.7, min_speed=30.0)
E('hand_cannon', 'a', 2, 'phantom_broadside', 'Phantom Broadside', 'Every 18s a ghost galleon sails along your heading (fog and horn tell) and rakes a wide lane.', 'Ghostly galleon in fog', every=18.0, tell=1.0, lane_width=140.0, length=700.0, mult=1.5)
E('hand_cannon', 'a', 2, 'bombard', 'Bombard', 'Becomes a mortar: shells land on the densest cluster after 0.7s (ground tell). No piercing line.', 'Arcing shell above a target ring', delay=0.7, radius_mult=1.4, target='densest', blast=64.0)
E('hand_cannon', 'b', 1, 'rebound', 'Rebound', 'The ball swings back at max range, hitting both ways. Catch it to cut your reload.', 'Cannonball with a return arrow', catch_radius=18.0, reload_refund=1.0)
E('hand_cannon', 'b', 1, 'kickback', 'Kickback', 'Recoil becomes a 0.15s invulnerable backstep; the muzzle blasts a close cone.', 'Muzzle blast with a recoil arrow', backstep=60.0, time=0.15, cone_deg=50.0, cone_range=90.0, cone_mult=0.6)
E('hand_cannon', 'b', 2, 'burning_pitch', 'Burning Pitch', 'The ball leaves a fire trail (patches last 3s, capped count).', 'Cannonball with a flaming trail', spacing=40.0, life=3.0, max_patches=10, dps_mult=0.3, radius=26.0)
E('hand_cannon', 'b', 2, 'primed_powder', 'Primed Powder', 'Hits prime enemies with a 2s fuse; they explode, hurting neighbors (no chain reactions).', 'Powder keg with a lit fuse', fuse=2.0, radius=50.0, mult=0.6, generations=1)
# Pirate Crew  A = Press Gang, B = Sea Legs
E('pirate_crew', 'a', 1, 'gun_crew', 'Gun Crew', 'Each ally fires its own small cannon every 1.5s at its own target (replaces the projectile multiplier).', 'Pirate silhouette with a small cannon', interval=1.5, mult=0.5, replaces_multiplier=True, damage=18.0)
E('pirate_crew', 'a', 1, 'boarding_party', 'Boarding Party', 'Every 4s an ally leaps onto the densest cluster for an area slam, then returns.', 'Pirate leaping with a cutlass', every=4.0, leap_range=240.0, radius=60.0, mult=1.0)
E('pirate_crew', 'a', 2, 'jolly_roger', 'Jolly Roger', 'The crew plants a banner for 8s: inside it, reload is x2 and you regenerate.', 'Skull-and-crossbones flag', life=8.0, radius=100.0, reload_speed=2.0, regen=2.0)
E('pirate_crew', 'a', 2, 'x_marks_the_spot', 'X Marks the Spot', 'Every 60s a dig spot appears ~300px away; reach it within 12s for a treasure draft.', 'Treasure map with a red X', every=60.0, distance=300.0, window=12.0)
E('pirate_crew', 'b', 1, 'grog_rations', 'Grog Rations', 'The crew tosses a rum keg every 6s (one at a time): grab it for a small heal and a 5s damage buff.', 'Rum barrel', every=6.0, heal_pct=0.05, buff_time=5.0, buff_mult=1.25)
E('pirate_crew', 'b', 1, 'human_shield', 'Human Shield', 'Crew bodies intercept hostile projectiles; each intercepted shot triggers a free return blast.', 'Pirate behind a round shield', radius=26.0, counter_mult=0.8, damage=14.0)
E('pirate_crew', 'b', 2, 'man_overboard', 'Man Overboard', 'A hit that would hurt you is absorbed by an ally, who respawns after 8s.', 'Life ring with a splash', respawn=8.0)
E('pirate_crew', 'b', 2, 'release_the_kraken', 'Release the Kraken', 'When the crew departs, tentacles slam three nearby clusters (0.8s ground tell).', 'Kraken tentacle rising from water', slams=3, tell=0.8, radius=55.0, mult=1.2)

# ======================================================================================== PALADIN
# Greatsword  A = Holy Wave, B = Focused Zeal
E('greatsword', 'a', 1, 'crusaders_march', "Crusader's March", 'Moving steadily builds Advance stacks (max 3), each adding a wave to your swing.', 'Sword with three wave arcs', max_stacks=3, build_per_sec=0.7, clear_on_hurt=True)
E('greatsword', 'a', 1, 'mirror_wave', 'Mirror Wave', 'Waves reflect hostile projectiles back at enemies.', 'Wave arc bouncing bolts back', reflect_radius=30.0)
E('greatsword', 'a', 2, 'dawnbreaker', 'Dawnbreaker', 'Every 5th swing plants the blade: 8 beams rotate for 1.5s (0.4s ring tell).', 'Planted sword with eight radiating beams', every=5, beams=8, life=1.5, tell=0.4, turn_rate=0.9, mult=0.6)
E('greatsword', 'a', 2, 'pilgrims_road', "Pilgrim's Road", 'Moving lays radiant ground for 3s that burns enemies and gives you +15% speed while on it.', 'Glowing footsteps on a road', life=3.0, spacing=28.0, dps_mult=0.3, speed_bonus=0.15)
E('greatsword', 'b', 1, 'fervor', 'Fervor', 'Hits build Fervor (max 10) for up to +35% swing speed and damage; it decays after 3s without a hit.', 'Flame wrapped around a sword', max_stacks=10, bonus_cap=0.35, decay=3.0)
E('greatsword', 'b', 1, 'retribution', 'Retribution', 'Damage taken charges the blade; the next swing releases a knockback nova (capped).', 'Cracked shield pulsing a shockwave', charge_per_hp=0.01, charge_cap=1.0, radius=90.0, knockback=200.0, mult_cap=2.0)
E('greatsword', 'b', 2, 'holy_leap', 'Holy Leap', 'Every 7s vault to the toughest enemy within 220px and slam, stunning 0.8s (bosses immune).', 'Armored knight mid-leap above a landing ring', cooldown=7.0, range=220.0, stun=0.8, radius=70.0)
E('greatsword', 'b', 2, 'bulwark_stance', 'Bulwark Stance', 'Stand still 1s to raise a shield arc toward the nearest enemy: blocks shots, -60% damage from it.', 'Tower shield with a guard arc', still_time=1.0, arc_deg=120.0, reduce=0.6)
# Prayer  A = Sanctified Ground, B = Judgement Pulse
E('prayer', 'a', 1, 'consecration', 'Consecration', 'Drops holy ground every 4s (5s life): you heal standing on it, enemies on it burn.', 'Glowing sigil circle', every=4.0, life=5.0, radius_mult=0.9, heal_per_sec=2.0, dps_mult=0.5)
E('prayer', 'a', 1, 'seraph_ring', 'Seraph Ring', 'Three orbs orbit the aura edge, burning and knocking back whatever they touch.', 'Ring of three light orbs', orbs=3, touch_mult=0.5, knockback=80.0)
E('prayer', 'a', 2, 'sanctuary', 'Sanctuary', 'Every 20s a hallowed zone (5s) pushes enemies out and halves damage you take inside.', 'Dome of light', cooldown=20.0, life=5.0, radius_mult=1.5, reduce=0.5)
E('prayer', 'a', 2, 'lay_on_hands', 'Lay on Hands', 'Below 30% HP (60s cooldown) a burst heals 40% and knocks everything back.', 'Two glowing hands with a cross', hp_frac=0.3, cooldown=60.0, heal_pct=0.4, knockback=260.0)
E('prayer', 'b', 1, 'tolling_bell', 'Tolling Bell', 'The pulse becomes an expanding ring with knockback; its far edge hits x1.5.', 'Bell with an expanding ring', ring_speed=220.0, edge_mult=1.5, knockback=100.0)
E('prayer', 'b', 1, 'verdict_mark', 'Verdict Mark', 'The pulse marks the 3 toughest; 1s later marked enemies within 300px take a x2 follow-up strike.', 'Gavel above a mark', targets=3, delay=1.0, leash=300.0, mult=2.0)
E('prayer', 'b', 2, 'final_judgement', 'Final Judgement', 'Every 3rd pulse is screen-wide after a 1.2s sky tell (capped % damage vs elites).', 'Divine eye inside a sunburst', every=3, tell=1.2, mult=3.0, pct_elite=0.08)
E('prayer', 'b', 2, 'twin_suns', 'Twin Suns', 'The pulse comes from two suns hovering ~150px either side of you.', 'Two small suns flanking a figure', suns=2, offset=150.0)

# ======================================================================================== WIZARD
# Merlin's Book  A = Storm Surge, B = Ball Lightning
E('merlins_book', 'a', 1, 'static_charge', 'Static Charge', 'Moving builds static (up to +4 chains), spent on your next cast. Standing still bleeds it.', 'Spark-wreathed footprint', max_bonus_chains=4, build_per_sec=1.0, bleed_per_sec=0.5)
E('merlins_book', 'a', 1, 'lightning_lance', 'Lightning Lance', 'The bolt becomes a narrow beam through every enemy on the line to the target.', 'Straight lightning beam piercing three dots', width=14.0, length=520.0)
E('merlins_book', 'a', 2, 'blink_strike', 'Blink Strike', 'Every 8s blink ~200px along your heading, leaving a lightning scar and a thunder ring on arrival.', 'Two ghost wizards joined by a lightning line', cooldown=8.0, distance=200.0, scar_mult=0.6, ring_radius=60.0, invuln=0.25)
E('merlins_book', 'a', 2, 'capacitor', 'Capacitor', 'Casts fill a meter; at full (0.4s tell) 12 bolts hit the 12 nearest enemies at once.', 'Glowing coil radiating many bolts', meter=10, bolts=12, tell=0.4, bolt_mult=0.6)
E('merlins_book', 'b', 1, 'orbit_guard', 'Orbit Guard', 'Up to 3 orbs circle you and zap anything that comes within ~130px.', 'Three orbs on an orbit ring', orbs=3, orbit_radius=60.0, zap_range=130.0, tick=0.6)
E('merlins_book', 'b', 1, 'rolling_thunder', 'Rolling Thunder', 'The orb rolls ahead along your heading for 3s, zapping what it passes.', 'Orb with a motion trail and a forward arrow', speed=120.0, life=3.0, tick=0.4)
E('merlins_book', 'b', 2, 'singularity', 'Singularity', 'With 3 orbs out they fuse and drift toward you for 4s, pulling enemies in, then detonate.', 'Dark swirling core with inward arrows', orbs_needed=3, drift_time=4.0, pull_px=60.0, radius=110.0, detonate_mult=3.0)
E('merlins_book', 'b', 2, 'faraday_cage', 'Faraday Cage', 'Standing inside the triangle of 3 orbs you ignore hostile projectiles; crossing enemies are zapped.', 'Triangle of three orbs joined by arcs', orbs_needed=3, block_projectiles=True, edge_mult=0.4)
# Astral Projection  A = Deep Trance, B = Quick Mind
E('astral_projection', 'a', 1, 'astral_anchor', 'Astral Anchor', 'The clone stays where summoned and casts on its own. Plant it, then run.', 'Ghostly wizard pinned to a spot', anchored=True)
E('astral_projection', 'a', 1, 'mirror_image', 'Mirror Image', 'The clone mirrors your movement across your position.', 'Wizard and mirrored ghost either side of an axis', mirror=True)
E('astral_projection', 'a', 2, 'astral_swap', 'Astral Swap', 'The projection ends with you and the clone swapping places; both spots detonate.', 'Two wizards with swap arrows', ring_radius=70.0, ring_mult=1.0, invuln=0.2)
E('astral_projection', 'a', 2, 'ethereal_walk', 'Ethereal Walk', 'You become the projection for 4s: ghost through enemies (no contact damage), spells at half rate.', 'Translucent wizard walking through silhouettes', duration=4.0, cast_rate=0.5)
E('astral_projection', 'b', 1, 'spell_echo', 'Spell Echo', 'The clone repeats your cast 0.5s later at 70% power (replaces the projectile multiplier).', 'Bolt followed by a fainter echo bolt', delay=0.5, power=0.7, replaces_multiplier=True)
E('astral_projection', 'b', 1, 'flow_state', 'Flow State', 'Kills during a projection extend it 0.3s each (capped at +4s).', 'Hourglass with a flowing swirl', per_kill=0.3, cap=4.0)
E('astral_projection', 'b', 2, 'time_stop', 'Time Stop', 'Every 4th projection freezes enemies for 1.5s (bosses immune).', 'Clock face frozen inside a ring', every=4, freeze=1.5)
E('astral_projection', 'b', 2, 'wild_magic', 'Wild Magic', 'The clone casts a random spell (Frost Nova, Meteor, Gravity Pull), each with its own tell.', 'Three-way swirl of mixed colored sparks', pool=['frost_nova', 'meteor', 'gravity_pull'], tell=0.5)

# ======================================================================================== SPIDER
# Fangs  A = Long Fangs, B = Venom Sting
E('fangs', 'a', 1, 'pounce', 'Pounce', 'Every 4th bite lunges ~90px at the target with brief invulnerability and bites x2 on arrival.', 'Spider mid-leap with fangs bared', every=4, distance=90.0, invuln=0.2, mult=2.0)
E('fangs', 'a', 1, 'hit_and_run', 'Hit and Run', 'Each bite grants a 1s speed burst (stacking to +50%). Dart in, bite, dart out.', 'Fang with speed lines', per_bite=0.15, cap=0.5, duration=1.0)
E('fangs', 'a', 2, 'silk_zip', 'Silk Zip', 'Every 6s a silk line fires at the farthest enemy within 300px and you zip to it, biting everything on it.', 'Silk line with a spider at its end', cooldown=6.0, range=300.0, width=20.0, mult=1.0)
E('fangs', 'a', 2, 'ambush', 'Ambush', 'Stand still 1s to hide (translucent). The next bite is x3 and paralyzes a small burst.', 'Faint spider silhouette with glowing eyes', still_time=1.0, mult=3.0, burst_radius=50.0, paralysis=1.0)
E('fangs', 'b', 1, 'neurotoxin', 'Neurotoxin', 'Bites stack venom (max 5, 6s); at 5 stacks the enemy is paralyzed 1.5s (bosses immune).', 'Fang dripping green venom with stack pips', max_stacks=5, duration=6.0, paralysis=1.5, replaces_chance=True)
E('fangs', 'b', 1, 'spreading_venom', 'Spreading Venom', 'Venomed enemies pass 1 stack to enemies within ~50px each second (max 6 infected).', 'Venom drop splitting into smaller drops', radius=50.0, interval=1.0, max_infected=6)
E('fangs', 'b', 2, 'toxic_cloud', 'Toxic Cloud', 'Venomed enemies that die leave a 4s poison cloud that re-applies venom.', 'Green poison cloud with a skull', life=4.0, radius=55.0)
E('fangs', 'b', 2, 'lethal_dose', 'Lethal Dose', 'Biting a 5-stack enemy consumes the stacks for 40% of its current HP (elites 15%, bosses 4%).', 'Syringe over five stack pips', stacks=5, pct=0.4, pct_elite=0.15, pct_boss=0.04)
# Webs  A = Wide Webs, B = Sticky Webs
E('webs', 'a', 1, 'home_turf', 'Home Turf', 'Up to 2 webs at once; on your webs you move 30% faster and enemies are slowed.', 'Web with a boot print', max_webs=2, speed_bonus=0.3)
E('webs', 'a', 1, 'silk_tethers', 'Silk Tethers', 'A web fires 6 strands that leash the farthest enemies and drag them slowly toward it.', 'Web with strands pulling inward', strands=6, drag_px=40.0)
E('webs', 'a', 2, 'slingshot_web', 'Slingshot Web', 'Stepping onto your web launches you ~150px along your heading with brief invulnerability (3s cooldown).', 'Web stretched like a slingshot', launch=150.0, cooldown=3.0, invuln=0.2)
E('webs', 'a', 2, 'collapsing_web', 'Collapsing Web', 'When a web breaks, caught enemies are cocooned 1s (bosses immune) and crushed for heavy damage.', 'Web collapsing into a cocoon', cocoon=1.0, mult=2.0)
E('webs', 'b', 1, 'wrapped_prey', 'Wrapped Prey', 'The toughest enemy in a web is held 1.2s and takes +30% from all sources (once per web).', 'Silk-wrapped bundle', hold=1.2, taken=1.3)
E('webs', 'b', 1, 'egg_sacs', 'Egg Sacs', 'Enemies that die in a web leave sacs that hatch into 2 spiderlings for 6s (max 6).', 'Egg sac with tiny spiderlings', spiderlings=2, life=6.0, max_alive=6)
E('webs', 'b', 2, 'feast', 'Feast', 'When a web breaks you absorb it: heal 3% max HP per caught enemy (capped at 20%) and +20% speed for 3s.', 'Spider mouth over a dissolving web', heal_per=0.03, heal_cap=0.2, speed=0.2, speed_time=3.0)
E('webs', 'b', 2, 'venom_weave', 'Venom Weave', 'Webs apply a venom stack to enemies inside every 0.5s (works with Neurotoxin).', 'Web strands dripping venom', tick=0.5)

# ======================================================================================== MINOTAUR
# Horns  A = Wild Gore, B = Bull Rush
E('horns', 'a', 1, 'fling', 'Fling', 'The last enemy hit by each swing is hurled 220px as a living projectile, damaging those it hits (once).', 'Horn tossing a tumbling enemy', distance=220.0, mult=1.0)
E('horns', 'a', 1, 'hook_swing', 'Hook Swing', 'Swings pull enemies at the arc edge inward, clumping the pack for the next swing.', 'Curved horn hooking inward arrows', pull_px=60.0)
E('horns', 'a', 2, 'labrys_whirl', 'Labrys Whirl', 'Every 6th swing starts a 1.2s whirl: keep moving at 70% speed, hitting all around every 0.2s.', 'Double-headed axe spinning', every=6, duration=1.2, move_mult=0.7, tick=0.2, mult=0.5)
E('horns', 'a', 2, 'labyrinth_walls', 'Labyrinth Walls', 'Every 8s raise a half-ring of stone pillars ahead for 3s: they hurt, knock back and block projectiles.', 'Arc of stone pillars', cooldown=8.0, pillars=5, life=3.0, arc_deg=140.0, distance=70.0, mult=0.5)
E('horns', 'b', 1, 'steered_rush', 'Steered Rush', 'The charge follows the direction you hold; with no input it targets the nearest enemy.', 'Charging bull with a steering arrow', steer=True)
E('horns', 'b', 1, 'skewer', 'Skewer', 'Charges carry the first non-elite enemy hit on your horns, then slam it at the end for area damage.', 'Horns impaling an enemy', carry=1, slam_radius=60.0, slam_mult=2.0)
E('horns', 'b', 2, 'ramming_speed', 'Ramming Speed', 'Run in a straight line for 1s to trigger a 300px charge at x2 damage (4s cooldown); no random timer.', 'Bull with long speed lines', run_time=1.0, distance=300.0, mult=2.0, cooldown=4.0)
E('horns', 'b', 2, 'breaking_charge', 'Breaking Charge', 'Enemies hit by a charge are Broken for 5s: +25% damage from all sources.', 'Cracked armor plate', duration=5.0, taken=1.25)
# Beast's Roar  A = Ironhide, B = Rising Fury
E('beasts_roar', 'a', 1, 'spiked_hide', 'Spiked Hide', 'While armored, enemies that hit you take thorns damage and are knocked back.', 'Armor plate bristling with spikes', thorns_mult=1.0, knockback=120.0)
E('beasts_roar', 'a', 1, 'warcry_shockwave', 'Warcry Shockwave', 'The roar pushes enemies 100px away and destroys hostile projectiles.', 'Bull head with a shockwave ring', push_px=100.0, radius=140.0, destroy_projectiles=True)
E('beasts_roar', 'a', 2, 'armor_burst', 'Armor Burst', 'When the roar armor breaks you explode in a shock nova and gain 1s invulnerability instead of being stunned.', 'Shattering armor with a nova', nova_mult=1.5, invuln=1.0)
E('beasts_roar', 'a', 2, 'armored_charge', 'Armored Charge', 'Each roar launches an armored charge toward the nearest enemy (ignores the charge cooldown).', 'Armored bull mid-charge', distance=240.0)
E('beasts_roar', 'b', 1, 'outnumbered', 'Outnumbered', 'While roaring, +3% damage per enemy within 120px (capped at +30%).', 'Bull ringed by small enemies', per_enemy=0.03, radius=120.0, cap=0.3)
E('beasts_roar', 'b', 1, 'thundering_hooves', 'Thundering Hooves', 'While roaring, every 0.5s of movement stomps a small shock ring around you.', 'Hoof with a shock ring', stomp_every=0.5, radius=40.0, mult=0.4)
E('beasts_roar', 'b', 2, 'bulldozer', 'Bulldozer', 'While roaring you grow, cannot be knocked back or stunned, and shove enemies aside as you move.', 'Huge bull plowing enemies aside', scale=1.4, shove_radius=30.0)
E('beasts_roar', 'b', 2, 'last_stand', 'Last Stand', 'Below 30% HP the roar refreshes instantly (40s cooldown) at x1.5 strength.', 'Bull head with a cracked heart', hp_frac=0.3, cooldown=40.0, strength=1.5)

# ======================================================================================== HARPY EAGLE
# Screech  A = Far Cry, B = Echo Screech
E('screech', 'a', 1, 'echolocation', 'Echolocation', 'Waves mark enemies they hit; each mark (max 3) makes later waves hit harder.', 'Sound wave pinging a target', max_marks=3, per_mark=0.15)
E('screech', 'a', 1, 'gale_wings', 'Gale Wings', 'Waves shove enemies back hard and destroy hostile projectiles they cross.', 'Wing with gust lines', knockback=200.0, destroy_projectiles=True)
E('screech', 'a', 2, 'shatterpoint', 'Shatterpoint', 'Enemies with 3 marks shatter in a small burst that passes marks to neighbors.', 'Cracked target shattering', marks=3, radius=50.0, mult=1.0)
E('screech', 'a', 2, 'deafening_wail', 'Deafening Wail', 'Every 8s you hover and charge 0.8s, then a wide cone stuns 0.6s (bosses immune) and shatters projectiles.', 'Open beak with a huge cone', cooldown=8.0, charge=0.8, cone_deg=80.0, range=260.0, stun=0.6)
E('screech', 'b', 1, 'harmonic_fan', 'Harmonic Fan', 'Consecutive screeches fan out at widening angles (18 degree steps).', 'Three sound waves fanning out', step_deg=18.0)
E('screech', 'b', 1, 'parting_shot', 'Parting Shot', 'While moving, screeches fire backward, opposite your heading. Fire while fleeing.', 'Eagle flying away, wave behind it', backward=True)
E('screech', 'b', 2, 'flock_chorus', 'Flock Chorus', 'Every 12s two spectral harpies flank you for 6s, screeching in parallel.', 'Three harpy silhouettes in formation', every=12.0, life=6.0, wingmen=2, power=0.6)
E('screech', 'b', 2, 'perfect_pitch', 'Perfect Pitch', 'Each volley without taking a hit adds +20% screech damage (up to +100%); getting hit resets it.', 'Tuning fork with a rising scale', per_volley=0.2, cap=1.0)
# Aerial Strike  A = Assassin's Dive, B = Evasive Maneuvers
E('aerial_strike', 'a', 1, 'talon_rake', 'Talon Rake', 'The swoop leaves a slash trail for 2s that damages anything crossing it.', 'Talons with a claw-mark trail', trail_life=2.0, mult=0.4)
E('aerial_strike', 'a', 1, 'hunters_focus', "Hunter's Focus", 'Swoops prioritize elites and bosses and mark them (+20% damage taken for 6s).', 'Eagle eye locking on a target', prefer='elite', mark_time=6.0, taken=1.2)
E('aerial_strike', 'a', 2, 'shadow_drop', 'Shadow Drop', 'You climb out of reach for 1s, then crash on the toughest enemy (a growing shadow shows where).', 'Growing shadow beneath a diving eagle', climb=1.0, mult=3.0, radius=70.0, requires_flying=True)
E('aerial_strike', 'a', 2, 'rending_chain', 'Rending Chain', 'After impact the swoop re-aims at the next nearest enemy, up to 3 hops.', 'Three connected dive arrows', hops=3, mult=0.7)
E('aerial_strike', 'b', 1, 'tailwind', 'Tailwind', 'Each evasion grants +30% move speed for 3s and resets the screech.', 'Wing with a streaming wind arrow', speed=0.3, time=3.0, reset_screech=True)
E('aerial_strike', 'b', 1, 'feather_decoys', 'Feather Decoys', 'The evasion leaves 3 decoy feathers that detonate after 1s.', 'Three feathers with sparks', count=3, fuse=1.0, radius=40.0, mult=0.6)
E('aerial_strike', 'b', 2, 'high_altitude', 'High Altitude', 'After an evasion you fly high for 1.2s: untargetable by everything, with x1.5 screech range.', 'Eagle above clouds', time=1.2, range_mult=1.5, requires_flying=True)
E('aerial_strike', 'b', 2, 'whirlwind_wake', 'Whirlwind Wake', 'Evasions leave a 3s cyclone that pulls enemies in and flings hostile projectiles away.', 'Cyclone spiral', life=3.0, radius=70.0, pull_px=100.0, deflect=True)

# ======================================================================================== NECROMANCER
# Skull Summon  A = Skull Chorus, B = Grand Skull
E('skull_summon', 'a', 1, 'skull_spiral', 'Skull Spiral', 'Skulls fire in a rotating spiral around you instead of at a target.', 'Skulls in a spiral', count=8, turns=1.0, mult=0.6)
E('skull_summon', 'a', 1, 'ghostfire_trail', 'Ghostfire Trail', 'Skulls leave a ghostfire trail that burns for 1.5s.', 'Skull with teal flame trail', life=1.5, dps_mult=0.3)
E('skull_summon', 'a', 2, 'bone_storm', 'Bone Storm', 'Every 6th volley (0.5s tell) releases a ring of 14 skulls in all directions.', 'Ring of skulls radiating out', every=6, tell=0.5, count=14, mult=0.6)
E('skull_summon', 'a', 2, 'reapers_skull', "Reaper's Skull", 'Every 4th skull is a homing reaper skull that seeks the toughest enemy and detonates.', 'Skull with a scythe glint', every=4, burst_radius=40.0, mult=2.0)
E('skull_summon', 'b', 1, 'splitting_skull', 'Splitting Skull', 'The grand skull grows as it travels and cracks into 6 mini-skulls at the end.', 'Big skull cracking into small skulls', grow=2.0, splits=6, split_mult=0.4)
E('skull_summon', 'b', 1, 'skull_totem', 'Skull Totem', 'At max range the grand skull plants as a totem for 5s, pulsing damage around it.', 'Skull on a bone stake', life=5.0, tick=0.5, radius=60.0, mult=0.5)
E('skull_summon', 'b', 2, 'soul_feast', 'Soul Feast', 'Kills feed the skull (+10% size, up to x2) and heal you 1% max HP each.', 'Skull absorbing small souls', grow_per_kill=0.1, cap=2.0, heal_pct=0.01)
E('skull_summon', 'b', 2, 'haunting', 'Haunting', 'The skull sticks to the nearest elite or boss, biting it every 0.5s for 5s.', 'Skull latched onto a big enemy', bite_every=0.5, life=5.0, mult=0.6)
# Raise Dead  A = Legion, B = Undying Bond
E('raise_dead', 'a', 1, 'bone_archers', 'Bone Archers', 'Raised minions hold back and throw bones (range ~220) instead of charging.', 'Skeleton throwing a bone', range=220.0, shot_every=1.2, mult=0.5)
E('raise_dead', 'a', 1, 'corpse_burst', 'Corpse Burst', 'A failed raise roll detonates the corpse in a small blast.', 'Exploding corpse', radius=40.0, pct=0.15)
E('raise_dead', 'a', 2, 'grave_surge', 'Grave Surge', 'Every 20s the ground erupts (0.6s tell) and up to 5 minions rise at nearby enemy positions.', 'Hands bursting from a grave', cooldown=20.0, tell=0.6, max_raised=5)
E('raise_dead', 'a', 2, 'death_pact', 'Death Pact', 'With 3 or more minions alive you take 25% less damage; dying minions burst.', 'Skull tethered to minions', min_minions=3, reduce=0.25, burst_mult=1.0)
E('raise_dead', 'b', 1, 'raise_champion', 'Raise Champion', 'You may raise one elite at a time: x2 stats for 20s.', 'Crowned skeleton rising', elite_ok=True, stat_mult=2.0, life=20.0, max_champions=1)
E('raise_dead', 'b', 1, 'hunting_pack', 'Hunting Pack', 'Skull hits mark enemies; minions prioritize marked targets and deal x2 to them.', 'Minions circling a marked skull', prioritize_marked=True, mult=2.0)
E('raise_dead', 'b', 2, 'soul_harvest', 'Soul Harvest', 'Kills charge a soul meter; at full a soul nova heals 15% max HP and damages nearby enemies.', 'Soul orb filling up', per_kill=1, meter=10, heal_pct=0.15, radius=100.0, mult=2.0)
E('raise_dead', 'b', 2, 'bone_colossus', 'Bone Colossus', 'With 4 or more minions alive they fuse into one huge Bone Colossus for 8s.', 'Giant skeleton made of bones', min_minions=4, life=8.0, scale=2.5, mult=3.0)

# ======================================================================================== GOOSE
# Fear  A = Peck Fury, B = Terrifying Honk
E('fear', 'a', 1, 'goose_chase', 'Goose Chase', 'After a charge, an enemy within 160px triggers another charge at once (up to 3 in a row).', 'Goose with chained dash arrows', range=160.0, max_chain=3, gap=1.2)
E('fear', 'a', 1, 'wing_flap', 'Wing Flap', 'Charges end with a wing-flap wind cone: knockback and destroyed hostile projectiles.', 'Spread wings with a wind cone', cone_deg=90.0, range=120.0, knockback=220.0, destroy_projectiles=True)
E('fear', 'a', 2, 'gaggle', 'Gaggle', 'Every 10s a V-formation of 5 spectral geese charges along your heading, pecking everything.', 'V-formation of geese', every=10.0, geese=5, tell=0.5, mult=0.8)
E('fear', 'a', 2, 'maniac_mode', 'Maniac Mode', 'Below 40% HP charges recharge twice as fast and peck x2; below 15% your charges are invulnerable.', 'Wild-eyed goose with a red glow', hp1=0.4, hp2=0.15, cooldown_mult=0.5, peck_mult=2.0)
E('fear', 'b', 1, 'contagious_panic', 'Contagious Panic', 'Feared enemies pass fear to enemies they touch (max 6).', 'Fear lines jumping between enemies', max_spread=6, touch_radius=24.0)
E('fear', 'b', 1, 'territory_mark', 'Territory Mark', 'The honk leaves a 4s ring on the ground; enemies entering it flee.', 'Ground ring with a goose print', life=4.0, radius=70.0)
E('fear', 'b', 2, 'honk_of_doom', 'Honk of Doom', 'Every 12s a huge honk (0.5s tell) frightens everything on screen for 1.2s and wipes hostile projectiles.', 'Open beak with a huge shockwave', cooldown=12.0, tell=0.5, fear=1.2, wipe_projectiles=True)
E('fear', 'b', 2, 'mass_hysteria', 'Mass Hysteria', 'Fleeing enemies take +20% damage from all sources.', 'Panicked enemies with a red arrow up', taken=1.2)
# Turds  A = Volume Discount, B = Toxic Waste
E('turds', 'a', 1, 'charge_droppings', 'Charge Droppings', 'Charges drop a turd every 60px along the path.', 'Dash path studded with droppings', spacing=60.0)
E('turds', 'a', 1, 'golden_egg', 'Golden Egg', 'Every 12s you lay a golden egg: grab it to heal 15% and gain a 5s damage buff.', 'Golden egg with a sparkle', every=12.0, heal_pct=0.15, buff_time=5.0, buff_mult=1.25)
E('turds', 'a', 2, 'flyover', 'Flyover', 'Every 12s a flock passes along your heading (shadow tell), dropping a lane of turds.', 'Flock shadow over a dotted lane', every=12.0, tell=0.8, length=300.0, count=10)
E('turds', 'a', 2, 'gosling_parade', 'Gosling Parade', 'Every 5th turd hatches a gosling that follows and pecks for 10s (max 3).', 'Line of goslings', every_n=5, life=10.0, max_alive=3, mult=0.4)
E('turds', 'b', 1, 'stink_aura', 'Stink Aura', 'You emit a 70px stink aura: enemies inside are poisoned and slowed 20%; it grows as your HP drops.', 'Green stink fumes', radius=70.0, slow=0.8, poison_mult=0.3, low_hp_grow=0.5)
E('turds', 'b', 1, 'ripe_turds', 'Ripe Turds', 'A turd left undisturbed for 4s bursts into a 3s poison cloud; stepping on it earlier just stuns.', 'Swollen turd with fumes', fuse=4.0, cloud_life=3.0, radius=60.0)
E('turds', 'b', 2, 'venomous_honk', 'Venomous Honk', 'Fear also poisons enemies for 4s.', 'Honking beak dripping poison', poison_time=4.0)
E('turds', 'b', 2, 'toxic_swamp', 'Toxic Swamp', 'Every 20s you create a 140px swamp for 8s: enemies are slowed 50% and poisoned, and you regenerate.', 'Bubbling green swamp', cooldown=20.0, life=8.0, radius=140.0, slow=0.5, regen=2.0)

# Hand-added characters live in evo_plans/<character>.py; add their modules to evo_plans.PLAN_MODULES.
OPTIONS.extend(PLAN_OPTIONS)


# ======================================================================================== CAPS
# Per-ability hard limits on the computed `p` params, enforced by Ability._clamp_p() at the end of recompute().
# {'param': {'min': x, 'max': y}}  either bound optional. apply() converts each entry to the
# [min, max] array shape the game reads (Ability._clamp_p, tools/check_evo.py); a missing bound
# becomes 0.0 / 999.0. First-pass values: tune with the simulator.
CAPS = {
    'katana': {'cooldown': {'min': 0.30}, 'radius': {'max': 130.0}},
    'greatsword': {'cooldown': {'min': 0.80, 'max': 99.0}, 'damage': {'min': 0.10, 'max': 500.0}, 'radius': {'min': 20.0, 'max': 130.0}},
    'six_shooter': {'reload_time': {'min': 0.90}, 'pierce': {'max': 4}},
    'hand_cannon': {'reload_time': {'min': 1.60}, 'shrapnel': {'max': 6}},
    'merlins_book': {'cooldown': {'min': 0.55}, 'chains': {'max': 6}},
    'flailing_whip': {'interval': {'min': 0.50}, 'tick': {'min': 0.20}},
    'prayer': {'damage': {'min': 0.10, 'max': 500.0}, 'interval': {'min': 1.50, 'max': 30.0}, 'range': {'min': 20.0, 'max': 190.0}, 'tick': {'min': 0.10, 'max': 5.0}},
    'flash_bombs': {'interval': {'min': 3.0}, 'radius': {'max': 150.0}, 'stun': {'max': 1.8}},
    'pirate_crew': {'allies': {'max': 4}, 'duration': {'max': 10.0}},
    'astral_projection': {'projectile_mult': {'max': 2.0}, 'interval': {'min': 8.0}, 'duration': {'max': 8.0}},
    'fangs': {'cooldown': {'min': 0.30}, 'range': {'max': 90.0}, 'paralysis_chance': {'max': 0.5}},
    'webs': {'radius': {'max': 130.0}, 'capacity': {'max': 16}, 'lifetime': {'max': 14.0}},
    'horns': {'cooldown': {'min': 0.60}, 'radius': {'max': 110.0}, 'charge_damage': {'max': 4.0}, 'charge_interval': {'min': 4.0}},
    'beasts_roar': {'armor_hp': {'max': 160.0}, 'duration': {'max': 8.0}, 'interval': {'min': 10.0}, 'boost_damage': {'max': 0.5}, 'boost_speed': {'max': 0.25}},
    'screech': {'distance': {'max': 420.0}, 'consecutive': {'max': 3}, 'cooldown': {'min': 0.80}, 'width': {'max': 70.0}},
    'aerial_strike': {'interval': {'min': 4.0}, 'invuln': {'max': 0.8}},
    'skull_summon': {'count': {'max': 4}, 'cooldown': {'min': 0.80}, 'size': {'max': 2.0}},
    'raise_dead': {'max_minions': {'max': 6}, 'duration': {'max': 16.0}},
    'fear': {'interval': {'min': 2.5}, 'fear_radius': {'max': 190.0}, 'fear_time': {'max': 1.8}},
    'turds': {'max_turds': {'max': 6}, 'interval': {'min': 2.0}, 'stun': {'max': 1.5}},
}
CAPS.update(PLAN_CAPS)


# ======================================================================================== merge into gen_data
def _option_dict(o):
    icon = ICON_DIR + o['id'] + '.png'
    if not os.path.isfile(os.path.join(os.path.dirname(__file__), '..', 'art', 'evo', o['id'] + '.png')):
        icon = ''
    return dict(id=o['id'], name=o['name'], desc=o['desc'], ops={}, ops2={}, ops3={},
                flags={o['id']: dict(o['params'])},
                icon=icon, icon_frames=1, icon_fps=8.0)


def _cap_pair(c):
    """{'min': x} / {'max': y} -> [min, max] array (the shape Ability._clamp_p reads)."""
    return [float(c.get('min', 0.0)), float(c.get('max', 999.0))]


def apply(abilities, only=None):
    """Fill evo1/evo2 on every branch and `caps` on every ability.

    only: optional iterable of ability ids to receive evo tables (None = every option in OPTIONS).
    Caps always land on every ability in CAPS that is present in `abilities` - clamps are safe before behaviors exist.
    Hand-added abilities live in evo_plans and are skipped here until they appear in the generated list.
    """
    by_id = {a['id']: a for a in abilities}
    slots = {}
    for o in OPTIONS:
        if only is not None and o['ability'] not in only:
            continue
        slots.setdefault((o['ability'], o['branch'], o['tier']), []).append(o)
    for (aid, br, tier), opts in slots.items():
        if aid not in by_id:
            continue
        branch = by_id[aid]['branches'][0 if br == 'a' else 1]
        branch['evo1' if tier == 1 else 'evo2'] = [_option_dict(o) for o in opts]
    for aid, caps in CAPS.items():
        if aid not in by_id:
            continue
        by_id[aid]['caps'] = {k: _cap_pair(c) for k, c in caps.items()}
    return abilities
