extends RefCounted

const CONFIG_PATH := "res://data/territories.json"

var territories: Dictionary = {}
var challenger_to_map: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("无法读取地图占领配置")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		push_error("地图占领配置格式错误")
		return
	for raw_territory: Variant in parsed:
		if not raw_territory is Dictionary:
			continue
		var territory: Dictionary = raw_territory
		var map_id := str(territory.get("map_id", ""))
		var challenger_id := str(territory.get("challenger_id", ""))
		if map_id.is_empty() or challenger_id.is_empty():
			continue
		territories[map_id] = territory
		challenger_to_map[challenger_id] = map_id


func get_territory(map_id: String) -> Dictionary:
	return territories.get(map_id, {}).duplicate(true)


func map_for_challenger(monster_id: String) -> String:
	return str(challenger_to_map.get(monster_id, ""))


func reward_item_ids(map_id: String) -> Array[String]:
	var result: Array[String] = []
	var territory := get_territory(map_id)
	for raw_reward: Variant in territory.get("rewards", []):
		if not raw_reward is Dictionary:
			continue
		var item_id := str(raw_reward.get("item_id", ""))
		for count in maxi(0, int(raw_reward.get("quantity", 1))):
			result.append(item_id)
	return result
