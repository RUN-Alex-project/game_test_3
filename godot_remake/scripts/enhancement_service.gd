extends RefCounted

const CONFIG_PATH := "res://data/enhancement.json"

var config: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("无法读取养成配置")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	config = parsed if parsed is Dictionary else {}


func create_equipment_instance(item_id: String) -> Dictionary:
	return {
		"item_id": item_id,
		"quality_level": 0,
		"magic_soul_level": 0,
		"war_soul_active": false,
		"heaven_soul_level": 0,
		"earth_soul_level": 0,
	}


func refine_quality(instance: Dictionary) -> Dictionary:
	var result := instance.duplicate(true)
	result.quality_level = int(result.get("quality_level", 0)) + 1
	return {"success": true, "equipment": result}


func upgrade_magic_soul(instance: Dictionary) -> Dictionary:
	var result := instance.duplicate(true)
	result.magic_soul_level = int(result.get("magic_soul_level", 0)) + 1
	return {"success": true, "equipment": result}


func activate_war_soul(instance: Dictionary, roll: float) -> Dictionary:
	var result := instance.duplicate(true)
	var success := roll < float(config.get("war_soul_crystal_success_rate", 0.5))
	if success:
		result.war_soul_active = true
	return {"success": success, "equipment": result}


func set_soul_levels(instance: Dictionary, heaven_level: int, earth_level: int) -> Dictionary:
	var result := instance.duplicate(true)
	var level_cap := int(config.get("soul_level_cap", 5))
	result.heaven_soul_level = clampi(heaven_level, 0, level_cap)
	result.earth_soul_level = clampi(earth_level, 0, level_cap)
	return result


func soul_bonuses(instance: Dictionary) -> Dictionary:
	if not bool(instance.get("war_soul_active", false)):
		return {"attack_percent": 0, "dodge_percent": 0}
	return {
		"attack_percent": int(instance.get("heaven_soul_level", 0)) * int(config.get("heaven_soul_attack_percent_per_level", 10)),
		"dodge_percent": int(instance.get("earth_soul_level", 0)) * int(config.get("earth_soul_dodge_percent_per_level", 4)),
	}


func rose_affection(rose_count: int) -> int:
	return int(config.get("rose_affection", {}).get(str(rose_count), 0))


func material_for(operation: String) -> String:
	return str(config.get("materials", {}).get(operation, ""))


func stat_multiplier(instance: Dictionary) -> float:
	var quality_bonus := int(instance.get("quality_level", 0)) * int(config.get("quality_stat_percent_per_level", 5))
	var magic_bonus := int(instance.get("magic_soul_level", 0)) * int(config.get("magic_soul_stat_percent_per_level", 3))
	return 1.0 + float(quality_bonus + magic_bonus) / 100.0


func war_soul_combat_power_percent(instance: Dictionary) -> int:
	if not bool(instance.get("war_soul_active", false)):
		return 0
	var lowest_soul_level := mini(
		int(instance.get("heaven_soul_level", 0)),
		int(instance.get("earth_soul_level", 0)),
	)
	return lowest_soul_level * int(config.get("war_soul_combat_power_percent_per_level", 10))
