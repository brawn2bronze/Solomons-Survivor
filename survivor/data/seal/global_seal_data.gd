extends RefCounted
class_name GlobalSealData

# 5 Branches of the Hexagram. 3 Tiers each.
const TREE: Dictionary = {
    # --- BRANCH 1: DEFENSE (Warding Circles) ---
    "reinforced_walls": {
        "name": "Reinforced Walls",
        "desc": "Reduces enemy spawn rate by 5% per level.",
        "max_level": 3,
        "cost_base": 100,
        "cost_mult": 1.5,
        "prerequisites": [],
        "stat_hook": "spawn_rate",
        "stat_value": -0.05
    },
    "iron_citadels": {
        "name": "Iron Citadels",
        "desc": "Further reduces spawn rate by 10%. Grants +5% max HP per level.",
        "max_level": 2,
        "cost_base": 250,
        "cost_mult": 1.8,
        "prerequisites": ["reinforced_walls"],
        "stat_hook": "max_hp",
        "stat_value": 0.05
    },
    "unbroken_covenant": {
        "name": "Unbroken Covenant",
        "desc": "Damage taken reduced by 2% per consecutive second without being hit.",
        "max_level": 1,
        "cost_base": 800,
        "cost_mult": 1.0,
        "prerequisites": ["iron_citadels"],
        "stat_hook": "dmg_mitigation",
        "stat_value": 0.02
    },
    # --- BRANCH 2: OFFENSE (Chains of Judgment) ---
    "enhanced_bindings": {
        "name": "Enhanced Bindings",
        "desc": "Increases damage by 2% per level.",
        "max_level": 3,
        "cost_base": 100,
        "cost_mult": 1.5,
        "prerequisites": [],
        "stat_hook": "damage",
        "stat_value": 0.02
    },
    "consecrated_strikes": {
        "name": "Consecrated Strikes",
        "desc": "Increases damage by 5% and crit chance by 1% per level.",
        "max_level": 2,
        "cost_base": 300,
        "cost_mult": 1.8,
        "prerequisites": ["enhanced_bindings"],
        "stat_hook": "crit_chance",
        "stat_value": 0.01
    },
    "solomonic_decree": {
        "name": "Solomonic Decree",
        "desc": "Execute enemies below 10% HP. +10% damage to Bosses.",
        "max_level": 1,
        "cost_base": 1000,
        "cost_mult": 1.0,
        "prerequisites": ["consecrated_strikes"],
        "stat_hook": "execute_threshold",
        "stat_value": 0.10
    },
    # --- BRANCH 3: KNOWLEDGE (Eyes of the Scribe) ---
    "temporal_loops": {
        "name": "Temporal Loops",
        "desc": "Start runs with +10% XP per level.",
        "max_level": 3,
        "cost_base": 150,
        "cost_mult": 1.5,
        "prerequisites": [],
        "stat_hook": "start_xp",
        "stat_value": 0.10
    },
    "echoes_of_past": {
        "name": "Echoes of the Past",
        "desc": "Start with +20% XP. Gain +5% XP from all sources per level.",
        "max_level": 2,
        "cost_base": 400,
        "cost_mult": 1.8,
        "prerequisites": ["temporal_loops"],
        "stat_hook": "xp_gain",
        "stat_value": 0.05
    },
    "foreseen_victory": {
        "name": "Foreseen Victory",
        "desc": "Start runs with 1 random common weapon mod.",
        "max_level": 1,
        "cost_base": 1200,
        "cost_mult": 1.0,
        "prerequisites": ["echoes_of_past"],
        "stat_hook": "start_mod",
        "stat_value": 1
    },
    # --- BRANCH 4: ECONOMY (Broker's Tithe) ---
    "demons_folly": {
        "name": "Demon's Folly",
        "desc": "Increases Seal Fragment drop chance by 5% per level.",
        "max_level": 3,
        "cost_base": 100,
        "cost_mult": 1.5,
        "prerequisites": [],
        "stat_hook": "drop_chance",
        "stat_value": 0.05
    },
    "soul_siphon": {
        "name": "Soul Siphon",
        "desc": "+10% Fragment drop. +1% move speed per 100 Fragments collected in-run.",
        "max_level": 2,
        "cost_base": 350,
        "cost_mult": 1.8,
        "prerequisites": ["demons_folly"],
        "stat_hook": "move_speed_essence",
        "stat_value": 0.01
    },
    "asmodeus_bargain": {
        "name": "Asmodeus's Bargain",
        "desc": "Forbidden Archive prices reduced by 10%. 5% chance for double Fragment drops.",
        "max_level": 1,
        "cost_base": 900,
        "cost_mult": 1.0,
        "prerequisites": ["soul_siphon"],
        "stat_hook": "market_discount",
        "stat_value": 0.10
    },
    # --- BRANCH 5: WISDOM (Solomon's Wisdom / Bestiary Synergy) ---
    "scholars_focus": {
        "name": "Scholar's Focus",
        "desc": "Bestiary kill requirement reduced by 5 per level (min 20).",
        "max_level": 3,
        "cost_base": 200,
        "cost_mult": 1.6,
        "prerequisites": [],
        "stat_hook": "bestiary_req_reduction",
        "stat_value": 5
    },
    "codex_mastery": {
        "name": "Codex Mastery",
        "desc": "Catalogued demons grant an additional +0.5% move speed per level.",
        "max_level": 2,
        "cost_base": 450,
        "cost_mult": 1.8,
        "prerequisites": ["scholars_focus"],
        "stat_hook": "bestiary_move_bonus",
        "stat_value": 0.005
    },
    "forbidden_knowledge": {
        "name": "Forbidden Knowledge",
        "desc": "Catalogued demons grant an additional +1% damage per level.",
        "max_level": 1,
        "cost_base": 1100,
        "cost_mult": 1.0,
        "prerequisites": ["codex_mastery"],
        "stat_hook": "bestiary_dmg_bonus",
        "stat_value": 0.01
    },
    # --- BRANCH 6: FATE (Draft utility: reroll / skip / banish) ---
    # Three tiers exactly like the other branches: each level on any Fate node
    # grants +1 stock of EACH utility (full clear 3+2+1 = 6 of each per run, §30).
    "fates_intercession": {
        "name": "Fate's Intercession",
        "desc": "Bargain with fate: +1 reroll, skip and banish stock per level for the run.",
        "max_level": 3,
        "cost_base": 175,
        "cost_mult": 1.5,
        "prerequisites": [],
        "stat_hook": "draft_utility",
        "stat_value": 1
    },
    "threads_of_fortune": {
        "name": "Threads of Fortune",
        "desc": "Pull the threads: +1 reroll, skip and banish stock per level for the run.",
        "max_level": 2,
        "cost_base": 400,
        "cost_mult": 1.8,
        "prerequisites": ["fates_intercession"],
        "stat_hook": "draft_utility",
        "stat_value": 1
    },
    "moirais_shears": {
        "name": "Moirai's Shears",
        "desc": "The final cut: +1 reroll, skip and banish stock for the run.",
        "max_level": 1,
        "cost_base": 950,
        "cost_mult": 1.0,
        "prerequisites": ["threads_of_fortune"],
        "stat_hook": "draft_utility",
        "stat_value": 1
    }
}

static func get_node_data(node_id: String) -> Dictionary:
    return TREE.get(node_id, {})

static func get_cost(node_id: String, current_level: int) -> int:
    var data: Dictionary = get_node_data(node_id)
    if data.is_empty():
        return 0
    if current_level >= int(data.get("max_level", 0)):
        return -1 # Maxed
    return int(float(data.get("cost_base", 0)) * pow(float(data.get("cost_mult", 1.0)), current_level))

static func are_prereqs_met(node_id: String, current_levels: Dictionary) -> bool:
    var data: Dictionary = get_node_data(node_id)
    if data.is_empty():
        return false
    for prereq_id in data.get("prerequisites", []):
        if int(current_levels.get(prereq_id, 0)) <= 0:
            return false
    return true
