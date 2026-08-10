extends RefCounted

const MONSTER_DATABASE_PATH := "res://data/monsters.json"
const PROGRESSION_PATH := "res://data/progression.json"

var monsters: Dictionary = {}
var progression: Dictionary = {}
var random := RandomNumberGenerator.new()


func _init(seed_value: int = 0) -> void:
	monsters = _load_indexed_array(MONSTER_DATABASE_PATH)
	progression = _load_dictionary(PROGRESSION_PATH)
	if seed_value == 0:
		random.randomize()
	else:
		random.seed = seed_value


func get_monster(monster_id: String) -> Dictionary:
	return monsters.get(monster_id, {})


func calculate_damage(attack: int, defense: int, variance: float = 1.0) -> int:
	var mitigated := maxi(1, attack - int(defense * 0.55))
	return maxi(1, roundi(mitigated * clampf(variance, 0.85, 1.15)))


const FIELD_EQUIPMENT_IDS := ["field_weapon", "field_helmet", "field_necklace", "field_armor", "field_bracelet", "field_boots"]


func loot_multiplier_from_luck(luck: int) -> float:
	return 1.0 + float(maxi(0, luck) + 1) / 100.0


func victory_rewards(monster_id: String, luck: int = 100) -> Dictionary:
	var monster := get_monster(monster_id)
	if monster.is_empty():
		return {}
	var exp_multiplier := int(progression.get("player_experience_multiplier", 1))
	var merit_multiplier := int(progression.get(
		"boss_military_merit_multiplier" if monster.get("is_boss", false) else "normal_military_merit_multiplier",
		1,
	))
	var gold_reward := int(monster.get("base_gold", 0))
	match str(monster.get("loot_profile", "")):
		"native_normal":
			gold_reward = roundi(60.0 * float(20 + int(monster.get("original_level", monster.get("level", 1)))) * loot_multiplier_from_luck(luck))
		"native_boss":
			gold_reward = 1000
	return {
		"experience": int(monster.get("base_exp", 0)) * exp_multiplier,
		"pet_experience": int(monster.get("base_exp", 0)),
		"military_merit": int(monster.get("base_military_merit", 0)) * merit_multiplier,
		"nobility_merit": int(monster.get("base_nobility_merit", 0)),
		"monster_id": monster_id,
		"gold": gold_reward,
		"magic_stones": int(monster.get("base_magic_stones", 0)),
	}


func roll_drops(monster_id: String, forced_rolls: Array[float] = [], luck: int = 100, war_soul_unlocked: bool = false) -> Array[String]:
	var monster := get_monster(monster_id)
	var results: Array[String] = []
	if monster.is_empty():
		return results
	var cursor: Array[int] = [0]
	var baoli := loot_multiplier_from_luck(luck)
	match str(monster.get("loot_profile", "")):
		"spider":
			_roll_spider_drops(results, forced_rolls, cursor, baoli)
			return results
		"spider_queen":
			_roll_queen_drops(results, forced_rolls, cursor, baoli)
			return results
		"native_normal":
			_roll_native_normal_drops(results, monster, forced_rolls, cursor, baoli)
			return results
		"native_boss":
			_roll_native_boss_drops(results, monster, forced_rolls, cursor, baoli, war_soul_unlocked)
			return results
	var multiplier := float(progression.get("drop_rate_multiplier", 1.0))
	var exclusive_drops: Variant = monster.get("exclusive_drops", [])
	if exclusive_drops is Array and not exclusive_drops.is_empty():
		var exclusive_roll := _next_roll(forced_rolls, cursor)
		var cumulative := 0.0
		for exclusive_drop: Dictionary in exclusive_drops:
			cumulative += clampf(float(exclusive_drop.get("chance", 0.0)) * multiplier, 0.0, 1.0)
			if exclusive_roll < cumulative:
				results.append(str(exclusive_drop.get("item_id", "")))
				break
		return results
	for drop: Dictionary in monster.get("drops", []):
		var chance := clampf(float(drop.get("chance", 0.0)) * multiplier, 0.0, 1.0)
		if _next_roll(forced_rolls, cursor) < chance:
			results.append(str(drop.get("item_id", "")))
	return results


func _next_roll(forced_rolls: Array[float], cursor: Array[int]) -> float:
	var index := cursor[0]
	cursor[0] = index + 1
	return clampf(forced_rolls[index], 0.0, 0.999999) if index < forced_rolls.size() else random.randf()


func _roll_int(limit: int, forced_rolls: Array[float], cursor: Array[int]) -> int:
	return mini(limit - 1, floori(_next_roll(forced_rolls, cursor) * float(limit)))


func _append_if(results: Array[String], item_id: String, chance: float, forced_rolls: Array[float], cursor: Array[int]) -> void:
	if _next_roll(forced_rolls, cursor) < clampf(chance, 0.0, 1.0):
		results.append(item_id)


func _roll_spider_drops(results: Array[String], forced_rolls: Array[float], cursor: Array[int], baoli: float) -> void:
	# User modification: skill-book base chances are doubled before the native luck multiplier.
	_append_if(results, "skill_fighting_spirit", 0.30 * baoli, forced_rolls, cursor)
	_append_if(results, "skill_flying_slash", 0.50 * baoli, forced_rolls, cursor)
	_append_if(results, "skill_star_sword", 0.60 * baoli, forced_rolls, cursor)
	_append_if(results, "soul_crystal", 0.30 * baoli, forced_rolls, cursor)
	_append_if(results, "moon_box", 0.05 * baoli, forced_rolls, cursor)


func _roll_queen_drops(results: Array[String], forced_rolls: Array[float], cursor: Array[int], baoli: float) -> void:
	_append_if(results, "advanced_fighting_spirit", 0.40 * baoli, forced_rolls, cursor)
	_append_if(results, "advanced_star_sword", 0.40 * baoli, forced_rolls, cursor)
	_append_if(results, "advanced_flying_slash", 0.20 * baoli, forced_rolls, cursor)
	_append_if(results, "soul_crystal", 0.80 * baoli, forced_rolls, cursor)
	_append_if(results, "soul_king", 0.30 * baoli, forced_rolls, cursor)
	_append_if(results, "illusion_heart", 0.30 * baoli, forced_rolls, cursor)
	_append_if(results, "magic_soul_heart", 0.30 * baoli, forced_rolls, cursor)
	# User modification: enhanced moon box is a fixed 50 percent roll.
	_append_if(results, "enhanced_moon_box", 0.50, forced_rolls, cursor)


func _roll_native_normal_drops(results: Array[String], monster: Dictionary, forced_rolls: Array[float], cursor: Array[int], baoli: float) -> void:
	_append_if(results, "soul_crystal", 0.025 * baoli, forced_rolls, cursor)
	if _next_roll(forced_rolls, cursor) >= 0.25:
		return
	var quality := 0
	if _next_roll(forced_rolls, cursor) < 0.30:
		quality = 1
	if _next_roll(forced_rolls, cursor) < 0.30:
		quality = 2
	if _next_roll(forced_rolls, cursor) < 0.025 * baoli:
		quality = 3
	if _next_roll(forced_rolls, cursor) < 0.025 * baoli:
		quality = 4
	var magic_soul := _roll_int(10, forced_rolls, cursor) if _next_roll(forced_rolls, cursor) < 0.90 else _roll_int(9, forced_rolls, cursor) + 4
	var sockets := _roll_int(2, forced_rolls, cursor) if _next_roll(forced_rolls, cursor) < 0.05 else 0
	var equipment_choice := _roll_int(6, forced_rolls, cursor)
	var native_level := int(monster.get("original_level", monster.get("level", 1)))
	results.append(_equipment_token(equipment_choice, _normalize_equipment_level(native_level), quality, magic_soul, sockets))


func _roll_native_boss_drops(results: Array[String], monster: Dictionary, forced_rolls: Array[float], cursor: Array[int], baoli: float, war_soul_unlocked: bool) -> void:
	if war_soul_unlocked and _next_roll(forced_rolls, cursor) > 0.50:
		results.append("war_soul_crystal")
	else:
		results.append("soul_crystal")
	var native_level := int(monster.get("original_level", monster.get("level", 1)))
	_append_if(results, "soul_king", float(native_level) / 1000.0, forced_rolls, cursor)
	if native_level > 60:
		_append_if(results, "enhanced_moon_box", 0.50, forced_rolls, cursor)
	else:
		_append_if(results, "moon_box", 0.05 * baoli, forced_rolls, cursor)
	var quality := 3 if _next_roll(forced_rolls, cursor) < 0.70 else 4
	var magic_soul := _roll_int(6, forced_rolls, cursor) + 4 if _next_roll(forced_rolls, cursor) < 0.75 else _roll_int(9, forced_rolls, cursor) + 4
	var sockets := 1 if _next_roll(forced_rolls, cursor) < 0.25 else 0
	if _next_roll(forced_rolls, cursor) > 0.80:
		sockets = 2
	var equipment_choice := _roll_int(6, forced_rolls, cursor)
	results.append(_equipment_token(equipment_choice, _normalize_equipment_level(native_level), quality, magic_soul, sockets))


func _normalize_equipment_level(native_level: int) -> int:
	if native_level < 10:
		return 1
	if native_level > 100:
		return 125
	return native_level - native_level % 10


func _equipment_token(equipment_choice: int, item_level: int, quality: int, magic_soul: int, sockets: int) -> String:
	return "loot_equipment|%s|%d|%d|%d|%d" % [FIELD_EQUIPMENT_IDS[clampi(equipment_choice, 0, 5)], item_level, quality, magic_soul, sockets]


func _load_indexed_array(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法读取数据：%s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var indexed := {}
	if parsed is Array:
		for entry: Dictionary in parsed:
			indexed[str(entry.get("id", ""))] = entry
	return indexed


func _load_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法读取数据：%s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
