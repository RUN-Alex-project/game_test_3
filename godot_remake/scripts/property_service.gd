extends RefCounted

const RULES_PATH := "res://data/property_rules.json"

## v1.47 negative hooks. Production stays true.
const REQUIRE_UPGRADE_COST := true
const BLOCK_DUP_UPGRADE_OP := true
const ENFORCE_WAREHOUSE_CAP := true

var rules: Dictionary = {}


func _init() -> void:
	rules = _read_dict(RULES_PATH)


func default_properties() -> Dictionary:
	return {
		"castle_level": 1,
		"castle_gold": 0,
		"warehouse": {},
		"next_upgrade_seq": 1,
		"next_assignment_id": 1,
		"settled_ops": [],
		"assignments": [],
		"governance_actions_day": 0,
		"governance_actions_used": 0,
	}


func normalize(raw: Variant) -> Dictionary:
	var base: Dictionary = default_properties()
	if not raw is Dictionary:
		return base
	var incoming: Dictionary = raw
	for key in ["castle_level", "castle_gold", "next_upgrade_seq", "next_assignment_id", "governance_actions_day", "governance_actions_used"]:
		if incoming.has(key):
			base[key] = int(incoming.get(key, 0))
	if incoming.get("warehouse") is Dictionary:
		base["warehouse"] = (incoming["warehouse"] as Dictionary).duplicate(true)
	for key in ["settled_ops", "assignments"]:
		if incoming.get(key) is Array:
			base[key] = (incoming[key] as Array).duplicate(true)
	if int(base.get("castle_level", 0)) < 1:
		base["castle_level"] = 1
	return base


func validate_data() -> Array[String]:
	var errors: Array[String] = []
	var levels: Array = rules.get("levels", [])
	if levels.size() < 2:
		errors.append("PROPERTY_UPGRADE_ATOMIC missing levels")
	var seen: Dictionary = {}
	for raw_row: Variant in levels:
		if not raw_row is Dictionary:
			continue
		var level := int(raw_row.get("level", 0))
		if level < 1 or seen.has(level):
			errors.append("PROPERTY_UPGRADE_ATOMIC dup level")
		seen[level] = true
		if int(raw_row.get("warehouse_cap", 0)) < 0:
			errors.append("PROPERTY_WAREHOUSE_FULL cap")
	return errors


func validate_save(state: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var props: Dictionary = normalize(state.get("properties", {}))
	if int(props.get("castle_gold", 0)) < 0:
		errors.append("SAVE_NEG_STOCK castle_gold")
	var warehouse: Dictionary = props.get("warehouse", {})
	for item_id in warehouse.keys():
		if int(warehouse.get(item_id, 0)) < 0:
			errors.append("SAVE_NEG_STOCK %s" % str(item_id))
	return errors


func warehouse_used(props: Dictionary) -> int:
	var total := 0
	var warehouse: Dictionary = props.get("warehouse", {})
	for item_id in warehouse.keys():
		total += maxi(0, int(warehouse.get(item_id, 0)))
	return total


func warehouse_cap(props: Dictionary) -> int:
	return int(level_row(int(props.get("castle_level", 1))).get("warehouse_cap", 10))


func level_row(level: int) -> Dictionary:
	for raw_row: Variant in rules.get("levels", []):
		if raw_row is Dictionary and int(raw_row.get("level", 0)) == level:
			return (raw_row as Dictionary).duplicate(true)
	return {}


func next_level_row(level: int) -> Dictionary:
	return level_row(level + 1)


func upgrade(expansion: Dictionary, nobility_level: int, gold: int, stones: int, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var props: Dictionary = normalize(state.get("properties", {}))
	if operation_id.is_empty():
		return {"success": false, "code": "PROPERTY_DUP_UPGRADE", "expansion": expansion}
	var settled: Array = (props.get("settled_ops", []) as Array).duplicate()
	if operation_id in settled:
		if BLOCK_DUP_UPGRADE_OP:
			return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true, "gold_cost": 0, "stone_cost": 0}
	var current := int(props.get("castle_level", 1))
	var nxt: Dictionary = next_level_row(current)
	if nxt.is_empty():
		return {"success": false, "code": "PROPERTY_UPGRADE_ATOMIC", "expansion": expansion}
	var gold_cost := int(nxt.get("gold_cost", 0))
	var stone_cost := int(nxt.get("stone_cost", 0))
	var need_nobility := int(nxt.get("nobility_level", 0))
	if nobility_level < need_nobility:
		return {"success": false, "code": "PROPERTY_UPGRADE_ATOMIC", "expansion": expansion}
	if not REQUIRE_UPGRADE_COST:
		gold_cost = 0
		stone_cost = 0
	if gold < gold_cost or stones < stone_cost:
		return {"success": false, "code": "PROPERTY_UPGRADE_ATOMIC", "expansion": expansion}
	if BLOCK_DUP_UPGRADE_OP or not (operation_id in settled):
		settled.append(operation_id)
	props["settled_ops"] = settled
	props["castle_level"] = current + 1
	props["next_upgrade_seq"] = int(props.get("next_upgrade_seq", 1)) + 1
	state["properties"] = props
	return {
		"success": true,
		"code": "OK",
		"expansion": state,
		"gold_cost": gold_cost,
		"stone_cost": stone_cost,
		"castle_level": int(props.get("castle_level", 1)),
	}


func collect_to_warehouse(expansion: Dictionary, map_id: String, resource_id: String, qty: int, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var props: Dictionary = normalize(state.get("properties", {}))
	if qty <= 0:
		return {"success": true, "code": "OK", "expansion": state, "moved": 0, "leftover": 0}
	var moved := qty
	var leftover := 0
	if resource_id == "gold":
		props["castle_gold"] = int(props.get("castle_gold", 0)) + moved
	else:
		var used := warehouse_used(props)
		var cap := warehouse_cap(props)
		var room := cap - used
		if ENFORCE_WAREHOUSE_CAP:
			if room <= 0:
				moved = 0
				leftover = qty
			elif qty > room:
				moved = room
				leftover = qty - room
		var warehouse: Dictionary = (props.get("warehouse", {}) as Dictionary).duplicate(true)
		warehouse[resource_id] = int(warehouse.get(resource_id, 0)) + moved
		props["warehouse"] = warehouse
	state["properties"] = props
	var code := "OK"
	if leftover > 0:
		code = "PROPERTY_WAREHOUSE_FULL"
	return {
		"success": true,
		"code": code,
		"expansion": state,
		"moved": moved,
		"leftover": leftover,
		"operation_id": operation_id,
	}


func withdraw_gold(expansion: Dictionary, qty: int, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var props: Dictionary = normalize(state.get("properties", {}))
	var have := int(props.get("castle_gold", 0))
	if qty <= 0 or have < qty:
		return {"success": false, "code": "PROPERTY_UPGRADE_ATOMIC", "expansion": expansion}
	props["castle_gold"] = have - qty
	state["properties"] = props
	return {"success": true, "code": "OK", "expansion": state, "gold_gain": qty, "operation_id": operation_id}


func withdraw_item(expansion: Dictionary, item_id: String, qty: int, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var props: Dictionary = normalize(state.get("properties", {}))
	var warehouse: Dictionary = (props.get("warehouse", {}) as Dictionary).duplicate(true)
	var have := int(warehouse.get(item_id, 0))
	if qty <= 0 or have < qty:
		return {"success": false, "code": "PROPERTY_WAREHOUSE_FULL", "expansion": expansion}
	warehouse[item_id] = have - qty
	props["warehouse"] = warehouse
	state["properties"] = props
	return {"success": true, "code": "OK", "expansion": state, "item_id": item_id, "item_qty": qty, "operation_id": operation_id}


func _read_dict(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
