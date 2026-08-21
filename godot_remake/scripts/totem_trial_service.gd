extends RefCounted

const RULES_PATH := "res://data/totem_trials.json"
const REQUIRE_MAP := true
const REQUIRE_STAGE := true
const REQUIRE_REAL_INPUT := true
const VALIDATE_TOTEM_SNAPSHOT := true
const BLOCK_CONSUME_ON_FAIL := true

var totems_by_id: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	for raw: Variant in data.get("totems", []):
		if raw is Dictionary:
			totems_by_id[str(raw.get("totem_id", ""))] = raw


func run(expansion: Dictionary, totem_id: String, map_id: String, stage: String, live: Dictionary, snapshot: Dictionary, fruit_qty: int, operation_id: String) -> Dictionary:
	var spec: Dictionary = totems_by_id.get(totem_id, {})
	if spec.is_empty():
		return {"success": false, "code": "TOTEM_SNAPSHOT", "expansion": expansion, "consume": false}
	if REQUIRE_STAGE and stage != "totem_trials":
		return {"success": false, "code": "ABYSS_PRECONDITION", "expansion": expansion, "consume": not BLOCK_CONSUME_ON_FAIL}
	if REQUIRE_MAP and str(spec.get("map_id", "")) != map_id:
		return {"success": false, "code": "TOTEM_WRONG_MAP", "expansion": expansion, "consume": not BLOCK_CONSUME_ON_FAIL}
	if REQUIRE_REAL_INPUT:
		if snapshot.get("ok", null) != null and snapshot.size() == 1:
			return {"success": false, "code": "TOTEM_BOOL_ONLY", "expansion": expansion, "consume": false}
		var need := str(spec.get("need", ""))
		if VALIDATE_TOTEM_SNAPSHOT and not snapshot.has(need):
			return {"success": false, "code": "TOTEM_SNAPSHOT", "expansion": expansion, "consume": false}
		var live_val := int(live.get(need, -1))
		var snap_val := int(snapshot.get(need, -2))
		if VALIDATE_TOTEM_SNAPSHOT and live_val != snap_val:
			return {"success": false, "code": "TOTEM_SNAPSHOT", "expansion": expansion, "consume": false}
		if live_val < int(spec.get("min", 0)):
			return {"success": false, "code": "ABYSS_PRECONDITION", "expansion": expansion, "consume": false}
	var consume_id := str(spec.get("consume_item", ""))
	var consume_qty := int(spec.get("consume_qty", 0))
	if not consume_id.is_empty() and fruit_qty < consume_qty:
		return {"success": false, "code": "ABYSS_PRECONDITION", "expansion": expansion, "consume": false}
	return {
		"success": true,
		"code": "OK",
		"expansion": expansion,
		"consume": not consume_id.is_empty(),
		"consume_item": consume_id,
		"consume_qty": consume_qty,
		"snapshot": snapshot.duplicate(true) if snapshot is Dictionary else {},
		"totem_id": totem_id,
		"operation_id": operation_id,
	}
