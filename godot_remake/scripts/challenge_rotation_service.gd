extends RefCounted

const ROT_PATH := "res://data/challenge_rotation.json"
const REQUIRE_WEEK_REFRESH := true

var weeks: Array = []


func _init() -> void:
	var file := FileAccess.open(ROT_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	file.close()
	weeks = (data.get("weeks", []) as Array).duplicate(true)


func week_index(day: int) -> int:
	return int(floor(float(maxi(1, day) - 1) / 7.0))


func weekly_ids(day: int) -> Array:
	if weeks.is_empty():
		return []
	var idx := week_index(day) % weeks.size()
	var row: Variant = weeks[idx]
	return (row as Array).duplicate() if row is Array else []


func is_weekly(challenge_id: String, day: int) -> bool:
	return challenge_id in weekly_ids(day)


func validate_refresh(old_week: int, new_day: int) -> Dictionary:
	var now := week_index(new_day)
	if REQUIRE_WEEK_REFRESH and now != old_week and weekly_ids(new_day).is_empty():
		return {"success": false, "code": "ROTATION_WEEK"}
	if REQUIRE_WEEK_REFRESH and now == old_week:
		return {"success": true, "code": "OK", "week": now}
	if not REQUIRE_WEEK_REFRESH:
		return {"success": true, "code": "OK", "week": old_week}
	return {"success": true, "code": "OK", "week": now}
