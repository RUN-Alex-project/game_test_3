extends RefCounted

const CONFIG_PATH := "res://data/pet_config.json"
const DATABASE_PATH := "res://data/pets.json"

var config: Dictionary = {}
var pet_database: Dictionary = {}


func _init() -> void:
	var config_file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if config_file != null:
		var parsed_config: Variant = JSON.parse_string(config_file.get_as_text())
		config = parsed_config if parsed_config is Dictionary else {}
	var database_file := FileAccess.open(DATABASE_PATH, FileAccess.READ)
	if database_file != null:
		var parsed_database: Variant = JSON.parse_string(database_file.get_as_text())
		if parsed_database is Array:
			for definition: Dictionary in parsed_database:
				pet_database[str(definition.get("id", ""))] = definition


func create_pet(template_id: String, instance_id: int, quality_score: float = -1.0) -> Dictionary:
	var definition: Dictionary = pet_database.get(template_id, {})
	if definition.is_empty():
		return {}
	var pet := {
		"instance_id": instance_id,
		"template_id": template_id,
		"custom_name": str(definition.get("name", template_id)),
		"level": 1,
		"experience": 0,
		"reincarnations": 0,
		"deployed": false,
		"combined": false,
		"quality_score": float(definition.get("base_quality_score", 0)) if quality_score < 0.0 else quality_score,
		"base_hp": int(definition.get("base_hp", 1)),
		"base_attack": int(definition.get("base_attack", 1)),
		"base_defense": int(definition.get("base_defense", 0)),
		"growth_hp": int(definition.get("growth_hp", 1)),
		"growth_attack": int(definition.get("growth_attack", 1)),
		"growth_defense": int(definition.get("growth_defense", 1)),
	}
	pet["current_hp"] = int(pet.base_hp)
	return pet


func normalize_pet(raw_pet: Dictionary) -> Dictionary:
	var template_id := str(raw_pet.get("template_id", ""))
	var instance_id := maxi(1, int(raw_pet.get("instance_id", 1)))
	var pet := create_pet(template_id, instance_id, float(raw_pet.get("quality_score", -1.0)))
	if pet.is_empty():
		return {}
	pet.custom_name = str(raw_pet.get("custom_name", pet.custom_name))
	pet.level = clampi(int(raw_pet.get("level", 1)), 1, int(config.get("max_level", 50)))
	pet.experience = maxi(0, int(raw_pet.get("experience", 0)))
	pet.reincarnations = maxi(0, int(raw_pet.get("reincarnations", 0)))
	pet.deployed = bool(raw_pet.get("deployed", false))
	pet.combined = bool(raw_pet.get("combined", false)) and pet.deployed
	for field_name in ["base_hp", "base_attack", "base_defense", "growth_hp", "growth_attack", "growth_defense"]:
		pet[field_name] = maxi(0, int(raw_pet.get(field_name, pet[field_name])))
	pet.current_hp = clampi(int(raw_pet.get("current_hp", get_stats(pet).max_hp)), 0, int(get_stats(pet).max_hp))
	return pet


func experience_to_next_level(level: int) -> int:
	return maxi(1, level * int(config.get("experience_per_level_base", 200)))


func grant_experience(raw_pet: Dictionary, amount: int, player_level: int) -> Dictionary:
	var pet := raw_pet.duplicate(true)
	if amount <= 0:
		return {"pet": pet, "levels_gained": 0}
	var level_limit := mini(
		int(config.get("max_level", 50)),
		maxi(1, player_level + int(config.get("player_level_headroom", 10))),
	)
	if int(pet.get("level", 1)) >= level_limit:
		return {"pet": pet, "levels_gained": 0}
	pet.experience = int(pet.get("experience", 0)) + amount
	var levels_gained := 0
	while int(pet.level) < level_limit and int(pet.experience) >= experience_to_next_level(int(pet.level)):
		pet.experience = int(pet.experience) - experience_to_next_level(int(pet.level))
		pet.level = int(pet.level) + 1
		levels_gained += 1
	if int(pet.level) >= level_limit:
		pet.experience = mini(int(pet.experience), experience_to_next_level(int(pet.level)) - 1)
	if levels_gained > 0:
		pet.current_hp = int(get_stats(pet).max_hp)
	return {"pet": pet, "levels_gained": levels_gained}


func get_stats(pet: Dictionary) -> Dictionary:
	var level_offset := maxi(0, int(pet.get("level", 1)) - 1)
	var max_hp := int(pet.get("base_hp", 1)) + int(pet.get("growth_hp", 1)) * level_offset
	var attack := int(pet.get("base_attack", 1)) + int(pet.get("growth_attack", 1)) * level_offset
	var defense := int(pet.get("base_defense", 0)) + int(pet.get("growth_defense", 1)) * level_offset
	var combat_power := attack * 2 + defense + int(max_hp / 10) + roundi(float(pet.get("quality_score", 0.0)) / 100.0)
	return {"max_hp":max_hp, "attack":attack, "defense":defense, "combat_power":combat_power}


func fusion_requirement(main_pet: Dictionary) -> int:
	var score := float(main_pet.get("quality_score", 0.0))
	if score < 1500.0:
		return 0
	return floori((score - 500.0) / 2.0)


func fuse(main_pet: Dictionary, secondary_pet: Dictionary) -> Dictionary:
	if int(main_pet.get("instance_id", 0)) == int(secondary_pet.get("instance_id", 0)):
		return {"success":false, "reason":"same_pet"}
	if bool(main_pet.get("deployed", false)) or bool(secondary_pet.get("deployed", false)):
		return {"success":false, "reason":"deployed"}
	if int(main_pet.get("level", 1)) < int(config.get("fusion_main_level", 50)):
		return {"success":false, "reason":"main_level"}
	if float(secondary_pet.get("quality_score", 0.0)) < fusion_requirement(main_pet):
		return {"success":false, "reason":"secondary_score"}
	var result := main_pet.duplicate(true)
	var initial_inherit := float(config.get("fusion_initial_stat_inherit", 0.9))
	var growth_inherit := float(config.get("fusion_growth_inherit", 0.85))
	for field_name in ["base_hp", "base_attack", "base_defense"]:
		var difference := int(secondary_pet.get(field_name, 0)) - int(result.get(field_name, 0))
		if difference > 0:
			result[field_name] = int(result.get(field_name, 0)) + roundi(difference * initial_inherit)
	for field_name in ["growth_hp", "growth_attack", "growth_defense"]:
		var difference := int(secondary_pet.get(field_name, 0)) - int(result.get(field_name, 0))
		if difference > 0:
			result[field_name] = int(result.get(field_name, 0)) + roundi(difference * growth_inherit)
	var score_difference := float(secondary_pet.get("quality_score", 0.0)) - float(result.get("quality_score", 0.0))
	result.quality_score = float(result.get("quality_score", 0.0)) + maxf(1.0, snappedf(maxf(0.0, score_difference) * initial_inherit, 0.1))
	result.reincarnations = int(result.get("reincarnations", 0)) + 1
	result.level = 1
	result.experience = 0
	result.current_hp = int(get_stats(result).max_hp)
	return {"success":true, "pet":result}


func default_research_state() -> Dictionary:
	var research: Dictionary = config.get("research", {})
	return {
		"technology_level": float(research.get("initial_technology_level", 10.0)),
		"production_rate": int(research.get("initial_production_rate", 0)),
		"stock": int(research.get("initial_stock", 0)),
		"vip_level": 0,
	}


func normalize_research(raw_state: Dictionary) -> Dictionary:
	var state := default_research_state()
	var research: Dictionary = config.get("research", {})
	state.technology_level = clampf(float(raw_state.get("technology_level", state.technology_level)), 0.0, float(research.get("technology_level_cap", 300.0)))
	state.production_rate = clampi(int(raw_state.get("production_rate", state.production_rate)), 0, int(research.get("production_rate_cap", 6)))
	state.stock = clampi(int(raw_state.get("stock", state.stock)), 0, int(research.get("stock_cap", 100)))
	state.vip_level = maxi(0, int(raw_state.get("vip_level", 0)))
	return state


func fund_research(raw_state: Dictionary, levels: float = 1.0) -> Dictionary:
	var state := normalize_research(raw_state)
	var research: Dictionary = config.get("research", {})
	var previous_level := float(state.technology_level)
	state.technology_level = minf(float(research.get("technology_level_cap", 300.0)), previous_level + maxf(0.0, levels))
	if previous_level < float(research.get("production_unlock_level", 20.0)) and float(state.technology_level) >= float(research.get("production_unlock_level", 20.0)) and int(state.production_rate) == 0:
		state.production_rate = 1
	return state


func advance_week(raw_state: Dictionary) -> Dictionary:
	var state := normalize_research(raw_state)
	var weekly_growth := float(config.get("research", {}).get("weekly_growth_rate", 0.10))
	return fund_research(state, float(state.technology_level) * weekly_growth)


func produce(raw_state: Dictionary, days: int = 1) -> Dictionary:
	var state := normalize_research(raw_state)
	var research: Dictionary = config.get("research", {})
	if days <= 0 or float(state.technology_level) < float(research.get("production_unlock_level", 20.0)):
		return state
	state.stock = mini(int(research.get("stock_cap", 100)), int(state.stock) + int(state.production_rate) * days)
	return state


func production_task_cost(raw_state: Dictionary) -> int:
	var state := normalize_research(raw_state)
	return int(state.production_rate) + 1


func complete_production_task(raw_state: Dictionary) -> Dictionary:
	var state := normalize_research(raw_state)
	var research: Dictionary = config.get("research", {})
	if int(state.production_rate) >= int(research.get("production_rate_cap", 6)):
		return {"success":false, "reason":"rate_cap", "state":state}
	state.production_rate = mini(
		int(research.get("production_rate_cap", 6)),
		int(state.production_rate) + int(research.get("production_task_increment", 2)),
	)
	state.vip_level = int(state.vip_level) + 1
	return {"success":true, "state":state, "experience_reward":105000 * int(state.production_rate)}


func research_pet_quality(raw_state: Dictionary) -> float:
	var state := normalize_research(raw_state)
	var factor := float(config.get("research", {}).get("research_pet_score_factor", 75.0))
	return snappedf(float(state.technology_level) * factor, 0.01)


func research_pet_price(raw_state: Dictionary) -> int:
	var state := normalize_research(raw_state)
	var displayed_stars := research_pet_quality(state) / 100.0
	var base_price := roundi((displayed_stars - 10.0) * int(config.get("research", {}).get("research_pet_price_per_star", 200)))
	var discount := maxf(0.1, 1.0 - float(state.vip_level) / 10.0)
	return maxi(1, roundi(base_price * discount))
