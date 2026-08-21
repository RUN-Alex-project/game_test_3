extends RefCounted

const POINTS_PATH := "res://data/treeheart_harbor_evidence.json"
const REQUIRE_MAP := true
const REQUIRE_STAGE := true
const BLOCK_DUP_EVIDENCE := true

var points_by_id: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(POINTS_PATH, FileAccess.READ)
	if file == null:
		push_error("missing treeheart_harbor_evidence.json")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	for raw_point: Variant in data.get("points", []):
		if raw_point is Dictionary:
			points_by_id[str(raw_point.get("evidence_id", ""))] = raw_point


func collect(expansion: Dictionary, evidence_id: String, map_id: String, stage: String, operation_id: String) -> Dictionary:
	if not points_by_id.has(evidence_id):
		return {"success": false, "code": "EVIDENCE_DUP", "expansion": expansion}
	var spec: Dictionary = points_by_id[evidence_id]
	if REQUIRE_MAP and str(spec.get("map_id", "")) != map_id:
		return {"success": false, "code": "EVIDENCE_WRONG_MAP", "expansion": expansion}
	if REQUIRE_STAGE and str(spec.get("stage", "")) != stage:
		return {"success": false, "code": "CHAPTER_PRECONDITION", "expansion": expansion}
	var chapters: Dictionary = (expansion.get("chapters", {}) as Dictionary).duplicate(true)
	var row: Dictionary = (chapters.get("treeheart_harbor", {}) as Dictionary).duplicate(true)
	var ops: Array = (row.get("completed_operation_ids", []) as Array).duplicate()
	if operation_id in ops:
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var collected: Array = (row.get("collected_evidence_ids", []) as Array).duplicate()
	if BLOCK_DUP_EVIDENCE and evidence_id in collected:
		return {"success": false, "code": "EVIDENCE_DUP", "expansion": expansion}
	collected.append(evidence_id)
	ops.append(operation_id)
	row["collected_evidence_ids"] = collected
	row["completed_operation_ids"] = ops
	chapters["treeheart_harbor"] = row
	var state: Dictionary = expansion.duplicate(true)
	state["chapters"] = chapters
	return {"success": true, "code": "OK", "expansion": state, "evidence_id": evidence_id}


func points_for_map(map_id: String) -> Array:
	var out: Array = []
	for evid: String in points_by_id.keys():
		var spec: Dictionary = points_by_id[evid]
		if str(spec.get("map_id", "")) == map_id:
			out.append(spec)
	return out
