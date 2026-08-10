extends RefCounted

const MAP_DATABASE_PATH := "res://data/maps.json"

var maps: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(MAP_DATABASE_PATH, FileAccess.READ)
	if file == null:
		push_error("无法读取地图数据库")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		push_error("地图数据库格式错误")
		return
	for map_data: Dictionary in parsed:
		maps[str(map_data.get("id", ""))] = map_data


func get_map(map_id: String) -> Dictionary:
	return maps.get(map_id, {})


func can_travel(from_map_id: String, to_map_id: String) -> bool:
	var source := get_map(from_map_id)
	if source.is_empty() or get_map(to_map_id).is_empty():
		return false
	for exit_data: Dictionary in source.get("exits", []):
		if exit_data.get("target", "") == to_map_id:
			return true
	return false


func encounters_for(map_id: String) -> Array[String]:
	var result: Array[String] = []
	for monster_id: Variant in get_map(map_id).get("encounters", []):
		result.append(str(monster_id))
	return result
func shortest_route(from_map_id: String, to_map_id: String) -> Array[String]:
	var route: Array[String] = []
	if not maps.has(from_map_id) or not maps.has(to_map_id):
		return route
	if from_map_id == to_map_id:
		return [from_map_id]
	var adjacency: Dictionary = {}
	for map_id: String in maps:
		adjacency[map_id] = []
	for map_id: String in maps:
		for exit_data: Dictionary in maps[map_id].get("exits", []):
			var target := str(exit_data.get("target", ""))
			if not maps.has(target):
				continue
			if target not in adjacency[map_id]:
				adjacency[map_id].append(target)
			# Some SWF destinations (notably the dungeon) are entered through an NPC,
			# while only the return edge is stored in map data. Include that reverse edge for guidance.
			if map_id not in adjacency[target]:
				adjacency[target].append(map_id)
	var queue: Array[String] = [from_map_id]
	var previous: Dictionary = {from_map_id:""}
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for next_map: String in adjacency.get(current, []):
			if previous.has(next_map):
				continue
			previous[next_map] = current
			if next_map == to_map_id:
				queue.clear()
				break
			queue.append(next_map)
	if not previous.has(to_map_id):
		return route
	var cursor := to_map_id
	while not cursor.is_empty():
		route.push_front(cursor)
		cursor = str(previous.get(cursor, ""))
	return route


func route_names(route: Array[String]) -> Array[String]:
	var names: Array[String] = []
	for map_id: String in route:
		names.append(str(get_map(map_id).get("name", map_id)))
	return names