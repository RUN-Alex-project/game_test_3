extends RefCounted

const DATA_PATH := "res://data/adventurer_assignments.json"
const COMMISSIONS_PATH := "res://data/adventurer_commissions.json"
const AdventurerServiceScript = preload("res://scripts/adventurer_service.gd")

## v1.47 negative hooks. Production stays true.
const BLOCK_DOUBLE_POST := true
const REQUIRE_AVAILABLE := true
const REQUIRE_UNIQUE_ASSIGNMENT := true

var rules: Dictionary = {}
var posts: Dictionary = {}
var comm_adventurer: Dictionary = {}
var adventurer_service = AdventurerServiceScript.new()


func _init() -> void:
	rules = _read_dict(DATA_PATH)
	for raw_row: Variant in rules.get("posts", []):
		if not raw_row is Dictionary:
			continue
		var post_id := str(raw_row.get("post_id", ""))
		if not post_id.is_empty():
			posts[post_id] = raw_row
	var file := FileAccess.open(COMMISSIONS_PATH, FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Array:
			for raw_comm: Variant in parsed:
				if raw_comm is Dictionary:
					comm_adventurer[str(raw_comm.get("id", ""))] = str(raw_comm.get("adventurer_id", ""))


func validate_data() -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for raw_row: Variant in rules.get("posts", []):
		if not raw_row is Dictionary:
			errors.append("ASSIGNMENT_DOUBLE_POST bad post")
			continue
		var post_id := str(raw_row.get("post_id", ""))
		var map_id := str(raw_row.get("map_id", ""))
		if post_id.is_empty() or map_id.is_empty() or seen.has(post_id):
			errors.append("ASSIGNMENT_DOUBLE_POST %s" % post_id)
		seen[post_id] = true
	if int(rules.get("duration_days", 0)) < 1:
		errors.append("ASSIGNMENT_DOUBLE_POST duration")
	return errors


func validate_save(state: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var props: Dictionary = state.get("properties", {})
	if not props is Dictionary:
		return errors
	var seen_id: Dictionary = {}
	var seen_npc: Dictionary = {}
	for raw_row: Variant in props.get("assignments", []):
		if not raw_row is Dictionary:
			errors.append("SAVE_DUP_ASSIGNMENT type")
			continue
		var asg_id := str(raw_row.get("assignment_id", ""))
		var adv_id := str(raw_row.get("adventurer_id", ""))
		var post_id := str(raw_row.get("post_id", ""))
		if asg_id.is_empty() or seen_id.has(asg_id):
			errors.append("SAVE_DUP_ASSIGNMENT %s" % asg_id)
		seen_id[asg_id] = true
		if not posts.has(post_id):
			errors.append("SAVE_DUP_ASSIGNMENT bad post %s" % post_id)
		if not adventurer_service.roster.has(adv_id):
			errors.append("SAVE_DUP_ASSIGNMENT bad npc %s" % adv_id)
		if str(raw_row.get("status", "")) == "active":
			if seen_npc.has(adv_id):
				errors.append("SAVE_DUP_ASSIGNMENT npc %s" % adv_id)
			seen_npc[adv_id] = true
	return errors


func duration_days() -> int:
	return maxi(1, int(rules.get("duration_days", 3)))


func post_row(post_id: String) -> Dictionary:
	var raw: Variant = posts.get(post_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func is_npc_busy(expansion: Dictionary, adv_id: String) -> bool:
	var rankings: Variant = expansion.get("rankings", {})
	if rankings is Dictionary:
		var active_id := str(rankings.get("active_match_id", ""))
		if not active_id.is_empty():
			for raw_match: Variant in rankings.get("matches", []):
				if not raw_match is Dictionary:
					continue
				if str(raw_match.get("match_id", "")) != active_id:
					continue
				var opponent: Variant = raw_match.get("opponent_snapshot", {})
				if opponent is Dictionary and str(opponent.get("adventurer_id", "")) == adv_id:
					return true
	return is_commission_busy(expansion, adv_id)


func is_commission_busy(expansion: Dictionary, adv_id: String) -> bool:
	var commissions: Variant = expansion.get("commission_state", {})
	if not commissions is Dictionary:
		return false
	for comm_id in commissions.keys():
		var row: Variant = commissions[comm_id]
		if not row is Dictionary:
			continue
		if str(row.get("status", "")) != "active":
			continue
		if str(comm_adventurer.get(str(comm_id), "")) == adv_id:
			return true
	return false


func assign(expansion: Dictionary, adv_id: String, post_id: String, day: int, relationship_value: int, operation_id: String) -> Dictionary:
	if not adventurer_service.roster.has(adv_id):
		return {"success": false, "code": "ASSIGNMENT_BUSY", "expansion": expansion}
	var spec: Dictionary = post_row(post_id)
	if spec.is_empty():
		return {"success": false, "code": "ASSIGNMENT_DOUBLE_POST", "expansion": expansion}
	var state: Dictionary = expansion.duplicate(true)
	var props: Dictionary = state.get("properties", {})
	if not props is Dictionary:
		props = {}
	else:
		props = props.duplicate(true)
	var assignments: Array = (props.get("assignments", []) as Array).duplicate()
	for raw_row: Variant in assignments:
		if raw_row is Dictionary and str(raw_row.get("operation_id", "")) == operation_id:
			return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	if REQUIRE_AVAILABLE and (is_npc_busy(state, adv_id) or is_commission_busy(state, adv_id)):
		return {"success": false, "code": "ASSIGNMENT_BUSY", "expansion": expansion}
	if BLOCK_DOUBLE_POST:
		for raw_row: Variant in assignments:
			if not raw_row is Dictionary:
				continue
			if str(raw_row.get("status", "")) != "active":
				continue
			if str(raw_row.get("adventurer_id", "")) == adv_id:
				return {"success": false, "code": "ASSIGNMENT_DOUBLE_POST", "expansion": expansion}
			if str(raw_row.get("post_id", "")) == post_id:
				return {"success": false, "code": "ASSIGNMENT_DOUBLE_POST", "expansion": expansion}
	var next_id := int(props.get("next_assignment_id", 1))
	var asg_id := "asg:%d" % next_id
	if REQUIRE_UNIQUE_ASSIGNMENT:
		props["next_assignment_id"] = next_id + 1
	var row := {
		"assignment_id": asg_id,
		"operation_id": operation_id,
		"adventurer_id": adv_id,
		"post_id": post_id,
		"map_id": str(spec.get("map_id", "")),
		"start_day": day,
		"end_day": day + duration_days(),
		"status": "active",
		"relationship_snapshot": relationship_value,
		"min_relationship": 2,
	}
	assignments.append(row)
	props["assignments"] = assignments
	state["properties"] = props
	return {"success": true, "code": "OK", "expansion": state, "assignment_id": asg_id}


func dismiss(expansion: Dictionary, assignment_id: String, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var props: Dictionary = state.get("properties", {})
	if not props is Dictionary:
		return {"success": false, "code": "ASSIGNMENT_BUSY", "expansion": expansion}
	props = props.duplicate(true)
	var assignments: Array = (props.get("assignments", []) as Array).duplicate()
	var found := -1
	for index in assignments.size():
		var raw_row: Variant = assignments[index]
		if raw_row is Dictionary and str(raw_row.get("assignment_id", "")) == assignment_id:
			found = index
			break
	if found < 0:
		return {"success": false, "code": "ASSIGNMENT_BUSY", "expansion": expansion}
	var row: Dictionary = (assignments[found] as Dictionary).duplicate(true)
	if str(row.get("dismiss_operation_id", "")) == operation_id:
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	row["status"] = "dismissed"
	row["dismiss_operation_id"] = operation_id
	assignments[found] = row
	props["assignments"] = assignments
	state["properties"] = props
	return {"success": true, "code": "OK", "expansion": state}


func expire_due(expansion: Dictionary, ended_day: int) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var props: Dictionary = state.get("properties", {})
	if not props is Dictionary:
		return {"success": true, "code": "OK", "expansion": state}
	props = props.duplicate(true)
	var assignments: Array = (props.get("assignments", []) as Array).duplicate()
	for index in assignments.size():
		var raw_row: Variant = assignments[index]
		if not raw_row is Dictionary:
			continue
		var row: Dictionary = (raw_row as Dictionary).duplicate(true)
		if str(row.get("status", "")) != "active":
			continue
		if ended_day < int(row.get("end_day", ended_day + 1)):
			continue
		row["status"] = "expired"
		assignments[index] = row
	props["assignments"] = assignments
	state["properties"] = props
	return {"success": true, "code": "OK", "expansion": state}


func active_for_map(expansion: Dictionary, map_id: String) -> Dictionary:
	var props: Variant = expansion.get("properties", {})
	if not props is Dictionary:
		return {}
	for raw_row: Variant in props.get("assignments", []):
		if not raw_row is Dictionary:
			continue
		if str(raw_row.get("status", "")) != "active":
			continue
		if str(raw_row.get("map_id", "")) == map_id:
			return (raw_row as Dictionary).duplicate(true)
	return {}


func _read_dict(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
