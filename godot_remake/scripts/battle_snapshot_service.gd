extends RefCounted

const OPPONENTS_PATH := "res://data/arena_opponents.json"
const AdventurerServiceScript = preload("res://scripts/adventurer_service.gd")

var templates: Dictionary = {}
var adventurer_service = AdventurerServiceScript.new()


func _init() -> void:
	var file := FileAccess.open(OPPONENTS_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Array:
		for raw_entry: Variant in parsed:
			if raw_entry is Dictionary:
				var adv_id := str(raw_entry.get("adventurer_id", ""))
				if not adv_id.is_empty():
					templates[adv_id] = raw_entry


func monster_id_for(adv_id: String) -> String:
	return "arena_npc:%s" % adv_id


func adventurer_id_from_monster(monster_id: String) -> String:
	if not monster_id.begins_with("arena_npc:"):
		return ""
	return monster_id.substr(10)


func get_template(adv_id: String) -> Dictionary:
	var raw: Variant = templates.get(adv_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func npc_combat(expansion: Dictionary, adv_id: String) -> Dictionary:
	var template: Dictionary = get_template(adv_id)
	if template.is_empty():
		return {}
	var runtime: Dictionary = expansion.get("adventurers", {}).get(adv_id, {})
	var gear := int(runtime.get("gear_bonus", 0)) if runtime is Dictionary else 0
	var display := str(adventurer_service.get_adventurer(adv_id).get("display_name", adv_id))
	return {
		"id": monster_id_for(adv_id),
		"name": display,
		"level": int(template.get("level", 1)),
		"max_hp": int(template.get("max_hp", 1)),
		"attack": int(template.get("attack", 1)),
		"defense": int(template.get("defense", 1)),
		"combat_power": int(template.get("combat_power", 0)) + gear,
		"is_boss": true,
	}


func npc_ratings(expansion: Dictionary, adv_id: String) -> Dictionary:
	var template: Dictionary = get_template(adv_id)
	var runtime: Dictionary = expansion.get("adventurers", {}).get(adv_id, {})
	if not runtime is Dictionary:
		runtime = {}
	var combat: Dictionary = npc_combat(expansion, adv_id)
	return {
		"id": adv_id,
		"stable_id": adv_id,
		"level": int(template.get("level", 1)),
		"combat_power": int(combat.get("combat_power", 0)),
		"pet_power": int(template.get("pet_power", 0)) + int(runtime.get("pet_power", 0)),
		"explore_score": int(template.get("explore_score", 0)) + int(runtime.get("explore_score", 0)),
		"arena_score": int(runtime.get("arena_score", int(template.get("arena_score", 0)))),
		"merchant_reputation": int(runtime.get("merchant_reputation", 0)),
		"territory_contribution": int(runtime.get("territory_contribution", 0)),
	}


func player_snapshot(stats: Dictionary, ratings: Dictionary) -> Dictionary:
	return {
		"combat_power": int(stats.get("combat_power", 0)),
		"attack": int(stats.get("attack", 0)),
		"defense": int(stats.get("defense", 0)),
		"max_hp": int(stats.get("max_hp", 0)),
		"level": int(ratings.get("level", 1)),
		"pet_power": int(stats.get("pet_combat_power", ratings.get("pet_power", 0))),
	}


func validate_templates() -> Array[String]:
	var errors: Array[String] = []
	for adv_id in adventurer_service.all_ids():
		if not templates.has(adv_id):
			errors.append("ERR_ARENA_BAD_OPPONENT missing template %s" % adv_id)
			continue
		var row: Dictionary = templates[adv_id]
		for key in ["max_hp", "attack", "defense", "combat_power"]:
			if int(row.get(key, 0)) <= 0:
				errors.append("ERR_ARENA_BAD_SNAPSHOT %s %s" % [adv_id, key])
	for adv_id in templates.keys():
		if not adventurer_service.roster.has(str(adv_id)):
			errors.append("ERR_ARENA_BAD_OPPONENT extra %s" % str(adv_id))
	return errors
