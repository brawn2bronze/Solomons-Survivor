extends RefCounted
class_name HeroSealData

# Format: { "hero_id": { "node_id": { data } } }
# Opencode/Author will populate this.
const HERO_TREES: Dictionary = {
    # "vanguard": {
    #     "vanguard_anvil": {
    #         "name": "Solomon's Anvil",
    #         "desc": "Enemies dying in melee range have a 15% chance to explode.",
    #         "max_level": 1,
    #         "cost_base": 500,
    #         "cost_mult": 1.0,
    #         "prerequisites": [],
    #         "stat_hook": "melee_death_explosion_chance",
    #         "stat_value": 0.15
    #     }
    # }
}

static func get_hero_tree(hero_id: String) -> Dictionary:
    return HERO_TREES.get(hero_id, {})

static func get_hero_node_data(hero_id: String, node_id: String) -> Dictionary:
    var tree: Dictionary = get_hero_tree(hero_id)
    return tree.get(node_id, {})

static func get_hero_cost(hero_id: String, node_id: String, current_level: int) -> int:
    var data: Dictionary = get_hero_node_data(hero_id, node_id)
    if data.is_empty():
        return 0
    if current_level >= int(data.get("max_level", 0)):
        return -1
    return int(float(data.get("cost_base", 0)) * pow(float(data.get("cost_mult", 1.0)), current_level))
