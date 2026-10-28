from ._common import option as E

OPTIONS = [
    # Hyphal Net (behavior 'mycelium_net')  A = Anastomosis (threads on), B = Ballistospore (threads OFF, spores + infection)
    E('hyphal_net', 'a', 1, 'mother_cords', 'Mother Cords', 'Each node grows a thick cord to you; enemies crossing a cord are damaged and slowed.', 'Mushroom with cords stretching to nodes', width=10.0, dmg_mult=0.5, slow=0.6),
    E('hyphal_net', 'a', 1, 'quorum_pulse', 'Quorum Pulse', 'With 3+ nodes alive they pulse together every 2s, hitting everything near each node.', 'Three nodes linked by a pulsing ring', min_nodes=3, interval=2.0, radius=50.0, mult=0.6),
    E('hyphal_net', 'a', 2, 'fairy_ring', 'Fairy Ring', 'Every 10s the area enclosed by 3+ nodes erupts: heavy damage and a 0.8s stun (bosses immune).', 'Ring of mushrooms with a glowing center', every=10.0, min_nodes=3, mult=3.0, stun=0.8),
    E('hyphal_net', 'a', 2, 'mother_hub', 'Mother Hub', 'Within ~90px of a node you regenerate 2 HP/s and take 20% less damage (nodes last 50% longer).', 'Mushroom cradled by glowing roots', radius=90.0, regen=2.0, reduce=0.2, life_mult=1.5),
    E('hyphal_net', 'b', 1, 'puffball_burst', 'Puffball Burst', 'Spores burst on impact into a 45px infecting cloud that lingers 2s.', 'Puffball releasing a spore cloud', radius=45.0, life=2.0),
    E('hyphal_net', 'b', 1, 'spore_trail', 'Spore Trail', 'Infected enemies leave an infectious trail behind them for 1.5s as they move.', 'Footprints of glowing spores', trail_life=1.5, spacing=24.0, max_zones=12),
    E('hyphal_net', 'b', 2, 'cordyceps', 'Cordyceps', 'Infected enemies below 40% HP turn on their neighbors for 3s (bosses immune).', 'Ant silhouette with a fungal stalk', hp_frac=0.4, duration=3.0, dmg_mult=1.0),
    E('hyphal_net', 'b', 2, 'fruiting_bodies', 'Fruiting Bodies', 'Infected enemies that die sprout a free node (max 2 extra) that launches spores.', 'Mushroom bursting from a corpse', max_extra=2, life=5.0),
    # Saprotroph (behavior 'nutrient_bloom')  A = Mycorrhizal Exchange, B = Antibiosis
    E('saprotroph', 'a', 1, 'nutrient_relay', 'Nutrient Relay', 'Absorbing a bloom pulses every hyphal node once and refreshes its life by 1s.', 'Bloom feeding a glowing node', pulse_mult=0.5, refresh=1.0),
    E('saprotroph', 'a', 1, 'truffle_hunt', 'Truffle Hunt', 'Every 25s a glowing truffle sprouts ~250px away; reach it within 10s for full Nutrient and a 20% heal.', 'Glowing truffle in soil', every=25.0, distance=250.0, window=10.0, heal_pct=0.2),
    E('saprotroph', 'a', 2, 'fruiting_burst', 'Fruiting Burst', 'At max Nutrient the stacks convert into a nova (damage per stack) and a heal, then reset.', 'Mushroom cap bursting with spores', nova_per_stack=1.0, heal_pct=0.15, radius=110.0),
    E('saprotroph', 'a', 2, 'compost_heap', 'Compost Heap', 'Blooms within 60px of each other merge into one big bloom worth up to x4.', 'Heap of blooms merging into one', merge_radius=60.0, max_mult=4.0),
    E('saprotroph', 'b', 1, 'antibiotic_barrier', 'Antibiotic Barrier', 'The aura destroys hostile projectiles that enter it.', 'Aura ring blocking a bolt', destroy_projectiles=True),
    E('saprotroph', 'b', 1, 'digestive_enzymes', 'Digestive Enzymes', 'Enemies inside the aura for 2s are Dissolved: +25% damage taken and 20% slower.', 'Dripping enzyme drops', time_in=2.0, taken=1.25, slow=0.8),
    E('saprotroph', 'b', 2, 'honey_fungus', 'Honey Fungus', 'Feelers grab the 3 nearest enemies outside the aura and drag them slowly into it.', 'Honey-colored mushrooms with feelers', targets=3, drag_px=40.0, range=220.0),
    E('saprotroph', 'b', 2, 'parasitic_siphon', 'Parasitic Siphon', 'An elite or boss inside the aura is siphoned: you regain 1% max HP/s and it takes +15%.', 'Fungal threads draining a big enemy', heal_pct=0.01, taken=1.15),
]

CAPS = {
    'hyphal_net': {'cooldown': {'min': 0.80}, 'max_nodes': {'max': 6}, 'node_life': {'max': 10.0}, 'link_range': {'max': 260.0}, 'links_per_node': {'max': 4}, 'thread_slow': {'max': 0.5}, 'thread_half_width': {'max': 16.0}, 'launch_interval': {'min': 0.5}, 'spores_per_volley': {'max': 3}},
    'saprotroph': {'max_stacks': {'max': 12}, 'bloom_chance': {'max': 0.8}, 'max_blooms': {'max': 40}, 'auto_absorb_radius': {'max': 140.0}, 'aura_radius': {'max': 150.0}, 'shield_cap_pct': {'max': 0.4}, 'dmg_per_stack': {'max': 0.03}, 'speed_per_stack': {'min': -0.02, 'max': 0.015}},
}
