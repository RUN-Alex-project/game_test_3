extends RefCounted

const PATH := "res://data/season_npc_schedules.json"
const REQUIRE_FINALE := true
const BLOCK_DIRECT_REL := true
const SKIP_DUP := true
const RelationshipServiceScript = preload("res://scripts/relationship_service.gd")
const AbyssFinaleServiceScript = preload("res://scripts/abyss_finale_service.gd")

var events: Array = []
var by_id: Dictionary = {}
var relationship_service = RelationshipServiceScript.new()
var abyss_finale_service = AbyssFinaleServiceScript.new()


func _init() -> void:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	var data: Dictionary = parsed if parsed is Dictionary else {}
	events = (data.get("events", []) as Array).duplicate(true)
	for raw: Variant in events:
		if raw is Dictionary:
			by_id[str(raw.get("event_id", ""))] = raw


func run(expansion: Dictionary, event_id: String, current_day: int, operation_id: String) -> Dictionary:
	if not by_id.has(event_id):
		return {"success": false, "code": "EPILOGUE_LOCK", "expansion": expansion}
	if REQUIRE_FINALE and not abyss_finale_service.stage_at_least(expansion, "completed"):
		return {"success": false, "code": "EPILOGUE_LOCK", "expansion": expansion}
	var cycle = preload("res://scripts/season_cycle_service.gd").new()
	var row: Dictionary = cycle.normalize(expansion.get("season", {}))
	var ops: Dictionary = (row.get("completed_contract_operation_ids", {}) as Dictionary).duplicate(true)
	if ops.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var done: Dictionary = (row.get("epilogue_event_ids", {}) as Dictionary).duplicate(true)
	if done.has(event_id) and SKIP_DUP:
		return {"success": false, "code": "EPILOGUE_LOCK", "expansion": expansion}
	var spec: Dictionary = by_id[event_id]
	var adv_id := str(spec.get("adv_id", ""))
	var delta := int(spec.get("delta", 1))
	var state: Dictionary = expansion.duplicate(true)
	if BLOCK_DIRECT_REL:
		var rel: Dictionary = relationship_service.apply_relationship_reward(
			state, adv_id, delta, current_day, operation_id, "epilogue")
		if not bool(rel.get("success", false)):
			return {"success": false, "code": "EPILOGUE_REL", "expansion": expansion}
		state = rel.expansion
	else:
		var rels: Dictionary = (state.get("relationships", {}) as Dictionary).duplicate(true)
		var rr: Dictionary = {}
		if rels.get(adv_id) is Dictionary:
			rr = (rels[adv_id] as Dictionary).duplicate(true)
		rr["value"] = int(rr.get("value", 0)) + 100
		rels[adv_id] = rr
		state["relationships"] = rels
	row = cycle.normalize(state.get("season", {}))
	done[event_id] = true
	row["epilogue_event_ids"] = done
	ops[operation_id] = true
	row["completed_contract_operation_ids"] = ops
	var ledger: Array = (row.get("season_ledger", []) as Array).duplicate()
	ledger.append({"op": "epilogue", "id": event_id, "operation_id": operation_id})
	row["season_ledger"] = ledger
	var npc_snap: Dictionary = (row.get("npc_schedule_snapshot", {}) as Dictionary).duplicate(true)
	npc_snap[adv_id] = current_day
	row["npc_schedule_snapshot"] = npc_snap
	return {"success": true, "code": "OK", "expansion": cycle._write(state, row)}
