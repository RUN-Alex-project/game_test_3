extends RefCounted

const TEMPLATE_PATH := "res://data/adventurer_commissions.json"

var templates: Dictionary = {}
var order: Array[String] = []


func _init() -> void:
	var file := FileAccess.open(TEMPLATE_PATH, FileAccess.READ)
	if file == null:
		push_error("?????????")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Array:
		push_error("?????????")
		return
	for raw_entry: Variant in parsed:
		if not raw_entry is Dictionary:
			continue
		var comm_id := str(raw_entry.get("id", ""))
		if comm_id.is_empty():
			continue
		templates[comm_id] = raw_entry
		order.append(comm_id)


func all_ids() -> Array[String]:
	return order.duplicate()


func has_id(comm_id: String) -> bool:
	return templates.has(comm_id)


func get_template(comm_id: String) -> Dictionary:
	var raw: Variant = templates.get(comm_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func default_runtime(_comm_id: String) -> Dictionary:
	return {
		"status": "available",
		"progress": {},
		"accepted_operation_id": "",
		"reward_operation_id": "",
	}


func accept(expansion: Dictionary, comm_id: String, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var commissions: Dictionary = state.get("commission_state", {}).duplicate(true)
	if not commissions.has(comm_id):
		return {"success": false, "code": "ERR_UNKNOWN_COMM", "expansion": expansion}
	var row: Dictionary = (commissions[comm_id] as Dictionary).duplicate(true)
	if str(row.get("accepted_operation_id", "")) == operation_id and str(row.get("status", "")) != "available":
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	if str(row.get("status", "")) != "available":
		return {"success": false, "code": "ERR_COMM_NOT_AVAILABLE", "expansion": expansion}
	row["status"] = "active"
	row["accepted_operation_id"] = operation_id
	row["progress"] = {}
	commissions[comm_id] = row
	state["commission_state"] = commissions
	return {"success": true, "code": "OK", "expansion": state}


func record_kill(expansion: Dictionary, monster_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var commissions: Dictionary = state.get("commission_state", {}).duplicate(true)
	var changed := false
	for comm_id in commissions.keys():
		var template: Dictionary = get_template(str(comm_id))
		var goal: Dictionary = template.get("goal", {})
		if str(goal.get("type", "")) != "kill":
			continue
		if str(goal.get("monster_id", "")) != monster_id:
			continue
		var row: Dictionary = (commissions[comm_id] as Dictionary).duplicate(true)
		if str(row.get("status", "")) != "active":
			continue
		var progress: Dictionary = row.get("progress", {}).duplicate(true)
		var required := int(goal.get("quantity", 1))
		progress[monster_id] = mini(required, int(progress.get(monster_id, 0)) + 1)
		row["progress"] = progress
		if int(progress[monster_id]) >= required:
			row["status"] = "ready"
		commissions[comm_id] = row
		changed = true
	if not changed:
		return {"changed": false, "expansion": expansion}
	state["commission_state"] = commissions
	return {"changed": true, "expansion": state}


func sync_world(expansion: Dictionary, world: Dictionary) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var commissions: Dictionary = state.get("commission_state", {}).duplicate(true)
	var changed := false
	for comm_id in commissions.keys():
		var row: Dictionary = (commissions[comm_id] as Dictionary).duplicate(true)
		if str(row.get("status", "")) != "active":
			continue
		if _goal_met(get_template(str(comm_id)), row, world):
			row["status"] = "ready"
			commissions[comm_id] = row
			changed = true
	if not changed:
		return {"changed": false, "expansion": expansion}
	state["commission_state"] = commissions
	return {"changed": true, "expansion": state}


func _goal_met(template: Dictionary, row: Dictionary, world: Dictionary) -> bool:
	var goal: Dictionary = template.get("goal", {})
	match str(goal.get("type", "")):
		"collect_item", "deliver_item":
			var item_id := str(goal.get("item_id", ""))
			var counts: Dictionary = world.get("item_counts", {})
			return int(counts.get(item_id, 0)) >= int(goal.get("quantity", 1))
		"explore_map":
			return str(world.get("current_map_id", "")) == str(goal.get("map_id", ""))
		"kill":
			var monster_id := str(goal.get("monster_id", ""))
			var progress: Dictionary = row.get("progress", {})
			return int(progress.get(monster_id, 0)) >= int(goal.get("quantity", 1))
		"pet_level":
			return int(world.get("max_pet_level", 1)) >= int(goal.get("min_level", 2))
		"own_territory":
			return not str(world.get("owned_territory", "")).is_empty()
	return false


func claim(expansion: Dictionary, comm_id: String, operation_id: String, world: Dictionary) -> Dictionary:
	var synced: Dictionary = sync_world(expansion, world)
	var state: Dictionary = synced.get("expansion", expansion).duplicate(true)
	var commissions: Dictionary = state.get("commission_state", {}).duplicate(true)
	if not commissions.has(comm_id):
		return {"success": false, "code": "ERR_UNKNOWN_COMM", "expansion": expansion}
	var row: Dictionary = (commissions[comm_id] as Dictionary).duplicate(true)
	if str(row.get("reward_operation_id", "")) == operation_id:
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true, "consume_item_id": "", "consume_quantity": 0}
	if str(row.get("status", "")) != "ready":
		return {"success": false, "code": "ERR_COMM_NOT_READY", "expansion": state}
	var template: Dictionary = get_template(comm_id)
	if not _goal_met(template, row, world):
		return {"success": false, "code": "ERR_COMM_NOT_READY", "expansion": state}
	var goal: Dictionary = template.get("goal", {})
	var consume_id := ""
	var consume_qty := 0
	if str(goal.get("type", "")) in ["collect_item", "deliver_item"]:
		consume_id = str(goal.get("item_id", ""))
		consume_qty = int(goal.get("quantity", 1))
	row["status"] = "completed"
	row["reward_operation_id"] = operation_id
	commissions[comm_id] = row
	state["commission_state"] = commissions
	return {
		"success": true,
		"code": "OK",
		"expansion": state,
		"adventurer_id": str(template.get("adventurer_id", "")),
		"relationship": int(template.get("reward", {}).get("relationship", 0)),
		"consume_item_id": consume_id,
		"consume_quantity": consume_qty,
	}


func validate_templates() -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	var kinds: Dictionary = {}
	var item_ids := _load_id_set("res://data/items.json")
	var monster_ids := _load_id_set("res://data/monsters.json")
	var map_ids := _load_id_set("res://data/maps.json")
	for comm_id in order:
		if seen.has(comm_id):
			errors.append("ERR_DUP_COMM_ID duplicate id: %s" % comm_id)
		seen[comm_id] = true
		var template: Dictionary = templates[comm_id]
		var kind := str(template.get("kind", ""))
		kinds[kind] = true
		var goal: Dictionary = template.get("goal", {})
		var goal_type := str(goal.get("type", ""))
		if goal_type in ["collect_item", "deliver_item"]:
			var item_id := str(goal.get("item_id", ""))
			if item_id.is_empty() or not item_ids.has(item_id):
				errors.append("ERR_COMM_TARGET_UNKNOWN %s item_id=%s" % [comm_id, item_id])
		if goal_type == "kill":
			var monster_id := str(goal.get("monster_id", ""))
			if monster_id.is_empty() or not monster_ids.has(monster_id):
				errors.append("ERR_COMM_TARGET_UNKNOWN %s monster_id=%s" % [comm_id, monster_id])
		if goal_type == "explore_map":
			var map_id := str(goal.get("map_id", ""))
			if map_id.is_empty() or not map_ids.has(map_id):
				errors.append("ERR_COMM_TARGET_UNKNOWN %s map_id=%s" % [comm_id, map_id])
	for required_kind in ["collect", "explore", "kill", "deliver", "pet", "campaign"]:
		if not kinds.has(required_kind):
			errors.append("ERR_COMM_KIND_MISSING missing kind %s" % required_kind)
	return errors


func _load_id_set(path: String) -> Dictionary:
	var ids := {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ids
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Array:
		for raw_entry: Variant in parsed:
			if raw_entry is Dictionary:
				var entry_id := str(raw_entry.get("id", ""))
				if not entry_id.is_empty():
					ids[entry_id] = true
	return ids
