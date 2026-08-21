extends RefCounted

const RULES_PATH := "res://data/warrior_mastery_rules.json"
const ENFORCE_CAP := true
const SKIP_DUP_FEE := true
const REQUIRE_SNAPSHOT := true

var nodes_by_id: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	file.close()
	for raw: Variant in data.get("nodes", []):
		if raw is Dictionary:
			nodes_by_id[str(raw.get("mastery_id", ""))] = raw


func empty_runtime() -> Dictionary:
	return {"ranks": {}, "operation_ids": {}, "mastery_ledger": []}


func normalize(raw: Variant) -> Dictionary:
	var base := empty_runtime()
	var row: Dictionary = {}
	if raw is Dictionary:
		row = (raw as Dictionary).duplicate(true)
	for key in base.keys():
		if not row.has(key):
			row[key] = base[key]
	if not row.get("ranks") is Dictionary:
		row["ranks"] = {}
	if not row.get("operation_ids") is Dictionary:
		row["operation_ids"] = {}
	if not row.get("mastery_ledger") is Array:
		row["mastery_ledger"] = []
	return row


func validate_save(_state: Dictionary) -> Array:
	return []


func _write(expansion: Dictionary, row: Dictionary) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	state["warrior_mastery"] = row
	return state


func unlock(expansion: Dictionary, mastery_id: String, learned: Dictionary, gold: int, fruit: int, operation_id: String) -> Dictionary:
	var spec: Dictionary = nodes_by_id.get(mastery_id, {})
	if spec.is_empty():
		return {"success": false, "code": "MASTERY_CAP", "expansion": expansion, "consume": false}
	var row: Dictionary = normalize(expansion.get("warrior_mastery", {}))
	var ops: Dictionary = (row.get("operation_ids", {}) as Dictionary).duplicate(true)
	if ops.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true, "consume": false}
	var ranks: Dictionary = (row.get("ranks", {}) as Dictionary).duplicate(true)
	var cur := int(ranks.get(mastery_id, 0))
	var cap := int(spec.get("max_rank", 1))
	var extra: Array = spec.get("require_skills", []) if spec.get("require_skills") is Array else []
	for req: Variant in extra:
		if int(learned.get(str(req), 0)) <= 0:
			return {"success": false, "code": "MASTERY_CAP", "expansion": expansion, "consume": false}
	var skill_id := str(spec.get("skill_id", ""))
	var extra_req: Array = spec.get("require_skills", []) if spec.get("require_skills") is Array else []
	if extra_req.is_empty() and not skill_id.is_empty() and int(learned.get(skill_id, 0)) <= 0:
		return {"success": false, "code": "MASTERY_CAP", "expansion": expansion, "consume": false}
	if cur >= cap and SKIP_DUP_FEE:
		return {"success": false, "code": "MASTERY_DUP_FEE", "expansion": expansion, "consume": false}
	var cost_gold := int(spec.get("cost_gold", 0))
	var cost_item := str(spec.get("cost_item", ""))
	var cost_qty := int(spec.get("cost_qty", 0))
	if gold < cost_gold:
		return {"success": false, "code": "MASTERY_CAP", "expansion": expansion, "consume": false}
	if not cost_item.is_empty() and fruit < cost_qty:
		return {"success": false, "code": "MASTERY_CAP", "expansion": expansion, "consume": false}
	if ENFORCE_CAP:
		ranks[mastery_id] = mini(cur + 1, cap)
	else:
		ranks[mastery_id] = cur + 1
	row["ranks"] = ranks
	ops[operation_id] = true
	row["operation_ids"] = ops
	var ledger: Array = (row.get("mastery_ledger", []) as Array).duplicate()
	ledger.append({"op": "unlock", "id": mastery_id})
	row["mastery_ledger"] = ledger
	return {
		"success": true,
		"code": "OK",
		"expansion": _write(expansion, row),
		"consume": not cost_item.is_empty(),
		"consume_item": cost_item,
		"consume_qty": cost_qty,
		"gold_cost": cost_gold,
	}


func ranks_of(expansion: Dictionary) -> Dictionary:
	return normalize(expansion.get("warrior_mastery", {})).get("ranks", {})


func bonus_for(expansion: Dictionary, skill_id: String) -> float:
	var challenges: Dictionary = {}
	if expansion.get("challenges") is Dictionary:
		challenges = expansion.get("challenges", {})
	var source: Dictionary = ranks_of(expansion)
	var in_session := not str(challenges.get("active_challenge_id", "")).is_empty() or not str(challenges.get("active_session_id", "")).is_empty()
	if REQUIRE_SNAPSHOT and in_session:
		var snap: Variant = challenges.get("mastery_snapshot", {})
		if snap is Dictionary:
			source = snap
		else:
			source = {}
	var total := 0.0
	for mid in nodes_by_id.keys():
		var spec: Dictionary = nodes_by_id[mid]
		if int(source.get(str(mid), 0)) < 1:
			continue
		var sid := str(spec.get("skill_id", ""))
		if sid == skill_id or sid == "fighting_spirit" or skill_id.is_empty() and sid == "fighting_spirit":
			total += float(spec.get("bonus", 0.0))
		elif sid == "fighting_spirit":
			total += float(spec.get("bonus", 0.0))
	return total
