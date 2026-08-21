extends RefCounted

const RULES_PATH := "res://data/equipment_mastery_rules.json"
const REQUIRE_INSTANCE := true
const REQUIRE_WHITELIST := true
const ATOMIC_UNBIND := true

var rules: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	rules = parsed if parsed is Dictionary else {}
	file.close()


func empty_runtime() -> Dictionary:
	return {"slots": {}, "operation_ids": {}, "equip_ledger": []}


func normalize(raw: Variant) -> Dictionary:
	var base := empty_runtime()
	var row: Dictionary = {}
	if raw is Dictionary:
		row = (raw as Dictionary).duplicate(true)
	for key in base.keys():
		if not row.has(key):
			row[key] = base[key]
	if not row.get("slots") is Dictionary:
		row["slots"] = {}
	if not row.get("operation_ids") is Dictionary:
		row["operation_ids"] = {}
	if not row.get("equip_ledger") is Array:
		row["equip_ledger"] = []
	return row


func validate_save(_state: Dictionary) -> Array:
	return []


func _write(expansion: Dictionary, row: Dictionary) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	state["equipment_mastery"] = row
	return state


func bind(expansion: Dictionary, slot_id: String, item: Dictionary, affix_id: String, challenge_id: String, operation_id: String) -> Dictionary:
	var row: Dictionary = normalize(expansion.get("equipment_mastery", {}))
	var ops: Dictionary = (row.get("operation_ids", {}) as Dictionary).duplicate(true)
	if ops.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	if REQUIRE_INSTANCE and (item.is_empty() or str(item.get("item_id", "")).is_empty()):
		return {"success": false, "code": "EQUIPMENT_INSTANCE", "expansion": expansion}
	var whitelist: Array = rules.get("whitelist", [])
	if REQUIRE_WHITELIST and not affix_id in whitelist:
		return {"success": false, "code": "EQUIPMENT_AFFIX", "expansion": expansion}
	var slots: Dictionary = (row.get("slots", {}) as Dictionary).duplicate(true)
	if slots.size() >= int(rules.get("max_slots", 1)) and not slots.has(slot_id):
		return {"success": false, "code": "EQUIPMENT_INSTANCE", "expansion": expansion}
	var instance_id := "eq:%s:%s" % [slot_id, str(item.get("item_id", ""))]
	if REQUIRE_INSTANCE and slots.has(slot_id):
		var old: Dictionary = slots[slot_id]
		if str(old.get("instance_id", "")) != instance_id and str(old.get("item_id", "")) != str(item.get("item_id", "")):
			return {"success": false, "code": "EQUIPMENT_INSTANCE", "expansion": expansion}
	slots[slot_id] = {
		"instance_id": instance_id,
		"item_id": str(item.get("item_id", "")),
		"affix_id": affix_id,
		"challenge_id": challenge_id,
		"operation_id": operation_id,
	}
	row["slots"] = slots
	ops[operation_id] = true
	row["operation_ids"] = ops
	var ledger: Array = (row.get("equip_ledger", []) as Array).duplicate()
	ledger.append({"op": "bind", "slot": slot_id, "affix": affix_id, "challenge_id": challenge_id})
	row["equip_ledger"] = ledger
	return {"success": true, "code": "OK", "expansion": _write(expansion, row), "instance_id": instance_id}


func unbind(expansion: Dictionary, slot_id: String, item: Dictionary, operation_id: String) -> Dictionary:
	var row: Dictionary = normalize(expansion.get("equipment_mastery", {}))
	var ops: Dictionary = (row.get("operation_ids", {}) as Dictionary).duplicate(true)
	if ops.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var slots: Dictionary = (row.get("slots", {}) as Dictionary).duplicate(true)
	if not slots.has(slot_id):
		return {"success": false, "code": "EQUIPMENT_UNBIND", "expansion": expansion}
	var bound: Dictionary = slots[slot_id]
	var instance_id := "eq:%s:%s" % [slot_id, str(item.get("item_id", ""))]
	if ATOMIC_UNBIND and str(bound.get("instance_id", "")) != instance_id:
		return {"success": false, "code": "EQUIPMENT_UNBIND", "expansion": expansion}
	slots.erase(slot_id)
	row["slots"] = slots
	ops[operation_id] = true
	row["operation_ids"] = ops
	var ledger: Array = (row.get("equip_ledger", []) as Array).duplicate()
	ledger.append({"op": "unbind", "slot": slot_id})
	row["equip_ledger"] = ledger
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}
