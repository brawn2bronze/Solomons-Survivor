# ======================================================================================== JACK + FUN-GUY (hand-added characters)
# Paste the E(...) lines before the CAPS block of tools/evo_data.py, and merge the CAPS entries below into CAPS.
#
# WIRING NOTE: jack, fun_guy, pumpkin_hurl, candy_trail, hyphal_net and saprotroph are hand-maintained .tres files
# and are NOT in gen_data.ABILITIES. evo_data.apply() looks every ability up in that list, so before pasting this:
#   1) in apply(): skip ids that are not in by_id (two `if aid not in by_id: continue` guards, one per loop), and
#   2) patch these four .tres through tools/apply_evo.gd (in-Godot patcher), never through gen_data.py regen.

# ======================================================================================== JACK
# Hurled Pumpkin (behavior 'cannon', shared with Hand-Cannon)  A = Cluster Harvest, B = Grand Gourd
E('pumpkin_hurl', 'a', 1, 'seeking_seeds', 'Seeking Seeds', 'Shrapnel seeds curve toward the nearest enemy instead of scattering.', 'Pumpkin seeds arcing toward a target', turn_rate=3.0, seek_range=160.0)
E('pumpkin_hurl', 'a', 1, 'pumpkin_patch', 'Pumpkin Patch', 'Pumpkins that end their flight sprout a patch for 6s that lobs seeds at enemies (max 3).', 'Small pumpkin sprouting on a vine', life=6.0, max_patches=3, seed_interval=1.0, seed_mult=0.4)
E('pumpkin_hurl', 'a', 2, 'trick_or_treat', 'Trick or Treat', 'Every 3rd pumpkin is a mystery pumpkin: a random Trick (blast, hex or bats) or Treat (heal candy).', 'Pumpkin with a swirl of mixed colors', every=3, tell=0.4, treat_chance=0.4, heal_pct=0.1, blast_mult=2.0)
E('pumpkin_hurl', 'a', 2, 'murder_of_crows', 'Murder of Crows', 'Every 12s six crows dive on your toughest nearby enemies, pecking each in turn and marking it.', 'Crow silhouette mid-dive', every=12.0, crows=6, mult=0.5, mark_time=4.0, taken=1.15)
E('pumpkin_hurl', 'b', 1, 'rolling_gourd', 'Rolling Gourd', 'The pumpkin lands and rolls on for 2.5s, crushing everything in its path.', 'Pumpkin with motion streaks', roll_time=2.5, roll_speed=140.0, rehit=0.5)
E('pumpkin_hurl', 'b', 1, 'lantern_lure', 'Lantern Lure', 'The pumpkin lands glowing: enemies within ~220px are drawn toward it for 1.5s, then it detonates.', 'Glowing jack-o-lantern with inward arrows', lure_range=220.0, lure_time=1.5, pull_px=60.0, blast_mult=1.3)
E('pumpkin_hurl', 'b', 2, 'colossal_gourd', 'Colossal Gourd', 'Every 5th pumpkin is colossal (0.6s ring tell): x2.5 blast radius and x3 damage.', 'Giant pumpkin casting a huge shadow', every=5, tell=0.6, radius_mult=2.5, dmg_mult=3.0)
E('pumpkin_hurl', 'b', 2, 'rotten_pulp', 'Rotten Pulp', 'Blasts leave a pulp pool for 5s: enemies in it are slowed 40% and take +20% damage.', 'Splattered rotten pumpkin pool', life=5.0, slow=0.6, taken=1.2, radius_mult=1.0)
# Candy Trail (behavior 'turds', shared with Goose's Turds)  A = Sticky Toffee, B = Hexed Sweets
E('candy_trail', 'a', 1, 'sugar_rush', 'Sugar Rush', 'Walking over your own candy grants +25% move speed for 2s (refreshes).', 'Candy wrapper with speed lines', speed_bonus=0.25, duration=2.0)
E('candy_trail', 'a', 1, 'toffee_strands', 'Toffee Strands', 'Neighboring candies link with sticky strands that slow enemies crossing them 40%.', 'Two candies joined by a toffee string', link_range=120.0, slow=0.6, width=8.0)
E('candy_trail', 'a', 2, 'gingerbread_brigade', 'Gingerbread Brigade', 'Every 5th candy hatches a gingerbread soldier that fights for 10s (max 3).', 'Gingerbread man with a candy-cane sword', every_n=5, life=10.0, max_alive=3, mult=0.5)
E('candy_trail', 'a', 2, 'sugar_bomb', 'Sugar Bomb', 'With 4+ enemies within 150px, every candy on the ground pops: stun and knockback (10s cooldown).', 'Candy bursting into sparkles', min_enemies=4, radius=150.0, cooldown=10.0, stun=0.8, knockback=140.0)
E('candy_trail', 'b', 1, 'hex_mark', 'Hex Mark', 'Enemies poisoned by your candy are Hexed: +20% damage from all sources for 5s.', 'Candy with a purple hex glyph', taken=1.2, duration=5.0)
E('candy_trail', 'b', 1, 'poison_apple', 'Poison Apple', 'Every 4th candy is a poison apple lobbed at the densest cluster ahead; it bursts into a 3s cloud.', 'Shiny green-red poison apple', every_n=4, throw_range=160.0, cloud_life=3.0, radius=50.0)
E('candy_trail', 'b', 2, 'witching_hour', 'Witching Hour', 'Every 25s a 6s witching hour: candy drops 3x faster and poison ticks twice as hard.', 'Crescent moon over a witch hat', every=25.0, duration=6.0, drop_mult=3.0, poison_mult=2.0)
E('candy_trail', 'b', 2, 'bat_swarm', 'Bat Swarm', 'Poisoned enemies that die release a bat that poisons the nearest clean enemy (max 6 bats).', 'Bat carrying a green drip', max_bats=6, seek_range=200.0, life=4.0)

# ======================================================================================== FUN-GUY
# Hyphal Net (behavior 'mycelium_net')  A = Anastomosis (threads on), B = Ballistospore (threads OFF, spores + infection)
E('hyphal_net', 'a', 1, 'mother_cords', 'Mother Cords', 'Each node grows a thick cord to you; enemies crossing a cord are damaged and slowed.', 'Mushroom with cords stretching to nodes', width=10.0, dmg_mult=0.5, slow=0.6)
E('hyphal_net', 'a', 1, 'quorum_pulse', 'Quorum Pulse', 'With 3+ nodes alive they pulse together every 2s, hitting everything near each node.', 'Three nodes linked by a pulsing ring', min_nodes=3, interval=2.0, radius=50.0, mult=0.6)
E('hyphal_net', 'a', 2, 'fairy_ring', 'Fairy Ring', 'Every 10s the area enclosed by 3+ nodes erupts: heavy damage and a 0.8s stun (bosses immune).', 'Ring of mushrooms with a glowing center', every=10.0, min_nodes=3, mult=3.0, stun=0.8)
E('hyphal_net', 'a', 2, 'mother_hub', 'Mother Hub', 'Within ~90px of a node you regenerate 2 HP/s and take 20% less damage (nodes last 50% longer).', 'Mushroom cradled by glowing roots', radius=90.0, regen=2.0, reduce=0.2, life_mult=1.5)
E('hyphal_net', 'b', 1, 'puffball_burst', 'Puffball Burst', 'Spores burst on impact into a 45px infecting cloud that lingers 2s.', 'Puffball releasing a spore cloud', radius=45.0, life=2.0)
E('hyphal_net', 'b', 1, 'spore_trail', 'Spore Trail', 'Infected enemies leave an infectious trail behind them for 1.5s as they move.', 'Footprints of glowing spores', trail_life=1.5, spacing=24.0, max_zones=12)
E('hyphal_net', 'b', 2, 'cordyceps', 'Cordyceps', 'Infected enemies below 40% HP turn on their neighbors for 3s (bosses immune).', 'Ant silhouette with a fungal stalk', hp_frac=0.4, duration=3.0, dmg_mult=1.0)
E('hyphal_net', 'b', 2, 'fruiting_bodies', 'Fruiting Bodies', 'Infected enemies that die sprout a free node (max 2 extra) that launches spores.', 'Mushroom bursting from a corpse', max_extra=2, life=5.0)
# Saprotroph (behavior 'nutrient_bloom')  A = Mycorrhizal Exchange, B = Antibiosis
E('saprotroph', 'a', 1, 'nutrient_relay', 'Nutrient Relay', 'Absorbing a bloom pulses every hyphal node once and refreshes its life by 1s.', 'Bloom feeding a glowing node', pulse_mult=0.5, refresh=1.0)
E('saprotroph', 'a', 1, 'truffle_hunt', 'Truffle Hunt', 'Every 25s a glowing truffle sprouts ~250px away; reach it within 10s for full Nutrient and a 20% heal.', 'Glowing truffle in soil', every=25.0, distance=250.0, window=10.0, heal_pct=0.2)
E('saprotroph', 'a', 2, 'fruiting_burst', 'Fruiting Burst', 'At max Nutrient the stacks convert into a nova (damage per stack) and a heal, then reset.', 'Mushroom cap bursting with spores', nova_per_stack=1.0, heal_pct=0.15, radius=110.0)
E('saprotroph', 'a', 2, 'compost_heap', 'Compost Heap', 'Blooms within 60px of each other merge into one big bloom worth up to x4.', 'Heap of blooms merging into one', merge_radius=60.0, max_mult=4.0)
E('saprotroph', 'b', 1, 'antibiotic_barrier', 'Antibiotic Barrier', 'The aura destroys hostile projectiles that enter it.', 'Aura ring blocking a bolt', destroy_projectiles=True)
E('saprotroph', 'b', 1, 'digestive_enzymes', 'Digestive Enzymes', 'Enemies inside the aura for 2s are Dissolved: +25% damage taken and 20% slower.', 'Dripping enzyme drops', time_in=2.0, taken=1.25, slow=0.8)
E('saprotroph', 'b', 2, 'honey_fungus', 'Honey Fungus', 'Feelers grab the 3 nearest enemies outside the aura and drag them slowly into it.', 'Honey-colored mushrooms with feelers', targets=3, drag_px=40.0, range=220.0)
E('saprotroph', 'b', 2, 'parasitic_siphon', 'Parasitic Siphon', 'An elite or boss inside the aura is siphoned: you regain 1% max HP/s and it takes +15%.', 'Fungal threads draining a big enemy', heal_pct=0.01, taken=1.15)

# ---- merge into CAPS (first pass) -------------------------------------------------------------
CAPS.update({
    'pumpkin_hurl': {'reload_time': {'min': 1.60}, 'shrapnel': {'max': 6}, 'pierce': {'max': 5}, 'radius': {'max': 22.0}},
    'candy_trail': {'max_turds': {'max': 6}, 'interval': {'min': 2.0}, 'stun': {'max': 1.5}, 'radius': {'max': 28.0}, 'poison_dps': {'max': 12.0}},
    'hyphal_net': {'cooldown': {'min': 0.80}, 'max_nodes': {'max': 6}, 'node_life': {'max': 10.0}, 'link_range': {'max': 260.0}, 'links_per_node': {'max': 4}, 'thread_slow': {'max': 0.5}, 'thread_half_width': {'max': 16.0}, 'launch_interval': {'min': 0.5}, 'spores_per_volley': {'max': 3}},
    'saprotroph': {'max_stacks': {'max': 12}, 'bloom_chance': {'max': 0.8}, 'max_blooms': {'max': 40}, 'auto_absorb_radius': {'max': 140.0}, 'aura_radius': {'max': 150.0}, 'shield_cap_pct': {'max': 0.4}, 'dmg_per_stack': {'max': 0.03}, 'speed_per_stack': {'min': -0.02, 'max': 0.015}},
})
