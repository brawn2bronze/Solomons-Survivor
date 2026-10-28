from ._common import option as E

OPTIONS = [
    # Hurled Pumpkin (behavior 'cannon', shared with Hand-Cannon)  A = Cluster Harvest, B = Grand Gourd
    E('pumpkin_hurl', 'a', 1, 'seeking_seeds', 'Seeking Seeds', 'Shrapnel seeds curve toward the nearest enemy instead of scattering.', 'Pumpkin seeds arcing toward a target', turn_rate=3.0, seek_range=160.0),
    E('pumpkin_hurl', 'a', 1, 'pumpkin_patch', 'Pumpkin Patch', 'Pumpkins that end their flight sprout a patch for 6s that lobs seeds at enemies (max 3).', 'Small pumpkin sprouting on a vine', life=6.0, max_patches=3, seed_interval=1.0, seed_mult=0.4),
    E('pumpkin_hurl', 'a', 2, 'trick_or_treat', 'Trick or Treat', 'Every 3rd pumpkin is a mystery pumpkin: a random Trick (blast, hex or bats) or Treat (heal candy).', 'Pumpkin with a swirl of mixed colors', every=3, tell=0.4, treat_chance=0.4, heal_pct=0.1, blast_mult=2.0),
    E('pumpkin_hurl', 'a', 2, 'murder_of_crows', 'Murder of Crows', 'Every 12s six crows dive on your toughest nearby enemies, pecking each in turn and marking it.', 'Crow silhouette mid-dive', every=12.0, crows=6, mult=0.5, mark_time=4.0, taken=1.15),
    E('pumpkin_hurl', 'b', 1, 'rolling_gourd', 'Rolling Gourd', 'The pumpkin lands and rolls on for 2.5s, crushing everything in its path.', 'Pumpkin with motion streaks', roll_time=2.5, roll_speed=140.0, rehit=0.5),
    E('pumpkin_hurl', 'b', 1, 'lantern_lure', 'Lantern Lure', 'The pumpkin lands glowing: enemies within ~220px are drawn toward it for 1.5s, then it detonates.', 'Glowing jack-o-lantern with inward arrows', lure_range=220.0, lure_time=1.5, pull_px=60.0, blast_mult=1.3),
    E('pumpkin_hurl', 'b', 2, 'colossal_gourd', 'Colossal Gourd', 'Every 5th pumpkin is colossal (0.6s ring tell): x2.5 blast radius and x3 damage.', 'Giant pumpkin casting a huge shadow', every=5, tell=0.6, radius_mult=2.5, dmg_mult=3.0),
    E('pumpkin_hurl', 'b', 2, 'rotten_pulp', 'Rotten Pulp', 'Blasts leave a pulp pool for 5s: enemies in it are slowed 40% and take +20% damage.', 'Splattered rotten pumpkin pool', life=5.0, slow=0.6, taken=1.2, radius_mult=1.0),
    # Candy Trail (behavior 'turds', shared with Goose's Turds)  A = Sticky Toffee, B = Hexed Sweets
    E('candy_trail', 'a', 1, 'sugar_rush', 'Sugar Rush', 'Walking over your own candy grants +25% move speed for 2s (refreshes).', 'Candy wrapper with speed lines', speed_bonus=0.25, duration=2.0),
    E('candy_trail', 'a', 1, 'toffee_strands', 'Toffee Strands', 'Neighboring candies link with sticky strands that slow enemies crossing them 40%.', 'Two candies joined by a toffee string', link_range=120.0, slow=0.6, width=8.0),
    E('candy_trail', 'a', 2, 'gingerbread_brigade', 'Gingerbread Brigade', 'Every 5th candy hatches a gingerbread soldier that fights for 10s (max 3).', 'Gingerbread man with a candy-cane sword', every_n=5, life=10.0, max_alive=3, mult=0.5),
    E('candy_trail', 'a', 2, 'sugar_bomb', 'Sugar Bomb', 'With 4+ enemies within 150px, every candy on the ground pops: stun and knockback (10s cooldown).', 'Candy bursting into sparkles', min_enemies=4, radius=150.0, cooldown=10.0, stun=0.8, knockback=140.0),
    E('candy_trail', 'b', 1, 'hex_mark', 'Hex Mark', 'Enemies poisoned by your candy are Hexed: +20% damage from all sources for 5s.', 'Candy with a purple hex glyph', taken=1.2, duration=5.0),
    E('candy_trail', 'b', 1, 'poison_apple', 'Poison Apple', 'Every 4th candy is a poison apple lobbed at the densest cluster ahead; it bursts into a 3s cloud.', 'Shiny green-red poison apple', every_n=4, throw_range=160.0, cloud_life=3.0, radius=50.0),
    E('candy_trail', 'b', 2, 'witching_hour', 'Witching Hour', 'Every 25s a 6s witching hour: candy drops 3x faster and poison ticks twice as hard.', 'Crescent moon over a witch hat', every=25.0, duration=6.0, drop_mult=3.0, poison_mult=2.0),
    E('candy_trail', 'b', 2, 'bat_swarm', 'Bat Swarm', 'Poisoned enemies that die release a bat that poisons the nearest clean enemy (max 6 bats).', 'Bat carrying a green drip', max_bats=6, seek_range=200.0, life=4.0),
]

CAPS = {
    'pumpkin_hurl': {'reload_time': {'min': 1.60}, 'shrapnel': {'max': 6}, 'pierce': {'max': 5}, 'radius': {'max': 22.0}},
    'candy_trail': {'max_turds': {'max': 6}, 'interval': {'min': 2.0}, 'stun': {'max': 1.5}, 'radius': {'max': 28.0}, 'poison_dps': {'max': 12.0}},
}
