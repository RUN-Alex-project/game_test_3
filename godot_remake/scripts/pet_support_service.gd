extends RefCounted

const RULES_PATH := "res://data/pet_support_rules.json"
const REQUIRE_OWNED := true
const BLOCK_DEPLOYED := true
const REQUIRE_ONE_SLOT := true
const APPLY_ONLY_TRIAL := true
const REQUIRE_SNAPSHOT := true
const REQUIRE_SAVE_ID := true

var rules: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	rules = parsed if parsed is Dictionary else {}
	file.close()


func normalize(raw: Variant) -> Dictionary:
	return preload("res://scripts/pet_collection_service.gd").new().normalize(raw)


func validate_save(state: Dictionary) -> Array:
	var row: Variant = state.get("pet_endgame", {})
	if not row is Dictionary:
		return []
	var sid: Variant = (row as Dictionary).get("support_instance_id", 0)
	if not REQUIRE_SAVE_ID:
		return []
	if sid is String:
		return ["SAVE_PET_ID"]
	if int(sid) < 0:
		return ["SAVE_PET_ID"]
	return []


func _write(expansion: Dictionary, row: Dictionary) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	state["pet_endgame"] = row
	return state


func set_support(expansion: Dictionary, instance_id: int, pets: Array, deployed_ids: Array, operation_id: String) -> Dictionary:
	var row: Dictionary = normalize(expansion.get("pet_endgame", {}))
	var ops: Dictionary = (row.get("operation_ids", {}) as Dictionary).duplicate(true)
	if ops.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var found := false
	for raw: Variant in pets:
		if raw is Dictionary and int((raw as Dictionary).get("instance_id", 0)) == instance_id:
			found = true
			break
	if REQUIRE_OWNED and not found:
		return {"success": false, "code": "PET_SUPPORT_OWNED", "expansion": expansion}
	if BLOCK_DEPLOYED and instance_id in deployed_ids:
		return {"success": false, "code": "PET_SUPPORT_DEPLOYED", "expansion": expansion}
	var ids: Array = (row.get("support_ids", []) as Array).duplicate()
	if REQUIRE_ONE_SLOT:
		ids = [instance_id]
		row["support_instance_id"] = instance_id
	else:
		if not instance_id in ids:
			ids.append(instance_id)
		row["support_instance_id"] = instance_id
	row["support_ids"] = ids
	row["support_effect"] = str(rules.get("default_effect", "trial_resist"))
	ops[operation_id] = true
	row["operation_ids"] = ops
	return {"success": true, "code": "OK", "expansion": _write(expansion, row), "slots": ids.size()}


func effect_value(expansion: Dictionary, context: String) -> int:
	var row: Dictionary = normalize(expansion.get("pet_endgame", {}))
	var effect := str(row.get("support_effect", ""))
	var in_trial := context == "trial"
	if REQUIRE_SNAPSHOT and in_trial:
		var snap: Dictionary = row.get("support_snapshot", {})
		if snap is Dictionary and not str(snap.get("effect", "")).is_empty():
			effect = str(snap.get("effect", ""))
	if APPLY_ONLY_TRIAL and not in_trial:
		return 0
	if int(row.get("support_instance_id", 0)) <= 0 and (row.get("support_ids", []) as Array).is_empty():
		return 0
	if effect == "trial_resist":
		return 1
	if effect == "explore_log":
		return 2
	if effect == "contract_note":
		return 3
	return 0
