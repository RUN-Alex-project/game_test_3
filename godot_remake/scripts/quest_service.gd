extends RefCounted

const DATABASE_PATH := "res://data/quests.json"

var quests: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(DATABASE_PATH, FileAccess.READ)
	if file == null:
		push_error("无法读取任务数据库")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		push_error("任务数据库格式错误")
		return
	for raw_quest: Variant in parsed:
		if raw_quest is Dictionary:
			quests[str(raw_quest.get("id", ""))] = raw_quest


func default_states() -> Dictionary:
	var result := {}
	for quest_id: String in quests:
		result[quest_id] = {"status":"available", "progress":{}}
	return result


func normalize_states(raw_states: Dictionary) -> Dictionary:
	var result := default_states()
	for quest_id: String in quests:
		var raw_state: Variant = raw_states.get(quest_id, {})
		if not raw_state is Dictionary:
			continue
		var status := str(raw_state.get("status", "available"))
		if status not in ["available", "active", "ready", "completed"]:
			status = "available"
		var raw_progress: Variant = raw_state.get("progress", {})
		var progress: Dictionary = raw_progress.duplicate(true) if raw_progress is Dictionary else {}
		result[quest_id] = {"status":status, "progress":progress}
	return result


func accept(states: Dictionary, quest_id: String) -> Dictionary:
	var result := normalize_states(states)
	if not quests.has(quest_id) or str(result[quest_id].status) != "available":
		return {"success":false, "states":result}
	result[quest_id] = {"status":"active", "progress":{}}
	return {"success":true, "states":result}


func record_kill(states: Dictionary, monster_id: String) -> Dictionary:
	var result := normalize_states(states)
	var changed := false
	for quest_id: String in quests:
		if str(result[quest_id].status) != "active":
			continue
		var quest_changed := false
		var progress: Dictionary = result[quest_id].progress
		for goal: Dictionary in quests[quest_id].get("goals", []):
			if goal.get("type", "") != "kill" or goal.get("target", "") != monster_id:
				continue
			var required := int(goal.get("quantity", 1))
			progress[monster_id] = mini(required, int(progress.get(monster_id, 0)) + 1)
			changed = true
			quest_changed = true
		result[quest_id].progress = progress
		if quest_changed and is_ready(result, quest_id):
			result[quest_id].status = "ready"
	return {"changed":changed, "states":result}


func is_ready(states: Dictionary, quest_id: String) -> bool:
	if not quests.has(quest_id) or not states.has(quest_id):
		return false
	var progress: Dictionary = states[quest_id].get("progress", {})
	for goal: Dictionary in quests[quest_id].get("goals", []):
		if goal.get("type", "") == "kill" and int(progress.get(str(goal.get("target", "")), 0)) < int(goal.get("quantity", 1)):
			return false
	return true


func claim(states: Dictionary, quest_id: String) -> Dictionary:
	var result := normalize_states(states)
	if not quests.has(quest_id) or str(result[quest_id].status) != "ready":
		return {"success":false, "states":result}
	result[quest_id].status = "completed"
	return {"success":true, "states":result, "rewards":quests[quest_id].get("rewards", {}).duplicate(true)}


func reset_daily(states: Dictionary) -> Dictionary:
	var result := normalize_states(states)
	for quest_id: String in quests:
		if quests[quest_id].get("repeat", "once") == "daily":
			result[quest_id] = {"status":"available", "progress":{}}
	return result


func progress_lines(states: Dictionary, quest_id: String) -> Array[String]:
	var lines: Array[String] = []
	if not quests.has(quest_id) or not states.has(quest_id):
		return lines
	var progress: Dictionary = states[quest_id].get("progress", {})
	for goal: Dictionary in quests[quest_id].get("goals", []):
		var target := str(goal.get("target", ""))
		lines.append("%s：%d/%d" % [goal.get("label", target), int(progress.get(target, 0)), int(goal.get("quantity", 1))])
	return lines
