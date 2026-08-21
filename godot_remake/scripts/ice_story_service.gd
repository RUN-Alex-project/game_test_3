extends RefCounted

const RULES_PATH := "res://data/ice_element_story.json"
const REQUIRE_STAGE := true
const BLOCK_SKIP := true
const REQUIRE_MAP := true
const BLOCK_DUP_PROBE := true
const BLOCK_CONSUME_ON_FAIL := true
const VALIDATE_ENUM := true
const REQUIRE_LEDGER := true

var rules: Dictionary = {}
var stages: Array = []
var probes_by_id: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	rules = parsed if parsed is Dictionary else {}
	stages = (rules.get("stages", []) as Array).duplicate()
	for raw: Variant in rules.get("probes", []):
		if raw is Dictionary:
			probes_by_id[str(raw.get("probe_id", ""))] = raw


func empty_runtime() -> Dictionary:
	return {
		"stage": "locked",
		"probe_ids": [],
		"knowledge_ids": [],
		"boss_status": {"ice_lab_boss": "hidden", "ice_aurora_boss": "hidden", "ice_weekly_trial": "hidden"},
		"active_session_id": "",
		"active_monster_id": "",
		"element_snapshot": {},
		"live_field_id": "",
		"attacker_charge": "",
		"consumable_cd": {},
		"weekly_contract": {},
		"last_weekly_claim_day": 0,
		"reward_claims": {},
		"ice_ledger": [],
		"last_element_report": {},
	}


func normalize(raw: Variant) -> Dictionary:
	var chapters: Dictionary = {}
	if raw is Dictionary:
		chapters = (raw as Dictionary).duplicate(true)
	var base := empty_runtime()
	var row: Dictionary = (chapters.get("ice_element", {}) as Dictionary).duplicate(true) if chapters.get("ice_element") is Dictionary else {}
	for key in base.keys():
		if not row.has(key):
			row[key] = base[key]
	if str(row.get("stage", "")) not in stages:
		row["stage"] = "locked"
	if not row.get("probe_ids") is Array:
		row["probe_ids"] = []
	if not row.get("knowledge_ids") is Array:
		row["knowledge_ids"] = []
	if not row.get("reward_claims") is Dictionary:
		row["reward_claims"] = {}
	if not row.get("ice_ledger") is Array:
		row["ice_ledger"] = []
	if not row.get("boss_status") is Dictionary:
		row["boss_status"] = base["boss_status"]
	if not row.get("weekly_contract") is Dictionary:
		row["weekly_contract"] = {}
	if not row.get("consumable_cd") is Dictionary:
		row["consumable_cd"] = {}
	if not row.get("element_snapshot") is Dictionary:
		row["element_snapshot"] = {}
	if not row.get("last_element_report") is Dictionary:
		row["last_element_report"] = {}
	chapters["ice_element"] = row
	return chapters


func runtime_of(expansion: Dictionary) -> Dictionary:
	return (normalize(expansion.get("chapters", {})).get("ice_element", {}) as Dictionary).duplicate(true)


func stage_index(stage_id: String) -> int:
	return stages.find(stage_id)


func stage_at_least(expansion: Dictionary, stage_id: String) -> bool:
	return stage_index(str(runtime_of(expansion).get("stage", "locked"))) >= stage_index(stage_id)


func _write(expansion: Dictionary, row: Dictionary) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var chapters: Dictionary = normalize(state.get("chapters", {}))
	chapters["ice_element"] = row
	state["chapters"] = chapters
	return state


func _remember_op(row: Dictionary, operation_id: String) -> bool:
	var claims: Dictionary = (row.get("reward_claims", {}) as Dictionary).duplicate(true)
	if claims.has(operation_id):
		return true
	claims[operation_id] = true
	row["reward_claims"] = claims
	return false


func _ledger(row: Dictionary, payload: Dictionary) -> void:
	if not REQUIRE_LEDGER:
		return
	var ledger: Array = (row.get("ice_ledger", []) as Array).duplicate()
	ledger.append(payload)
	row["ice_ledger"] = ledger


func validate_save(state: Dictionary) -> Array:
	var chapters: Variant = state.get("chapters", {})
	if not chapters is Dictionary:
		return ["SAVE_ICE_STAGE"]
	var row: Variant = (chapters as Dictionary).get("ice_element", {})
	if row == null or (row is Dictionary and (row as Dictionary).is_empty()):
		return []
	if not row is Dictionary:
		return ["SAVE_ICE_STAGE"]
	var stage := str((row as Dictionary).get("stage", "locked"))
	if VALIDATE_ENUM and not stage.is_empty() and stage not in stages:
		return ["SAVE_ICE_STAGE"]
	return []


func set_stage_for_fixture(expansion: Dictionary, stage_id: String) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	row["stage"] = stage_id if stage_id in stages else "locked"
	var bosses: Dictionary = (row.get("boss_status", {}) as Dictionary).duplicate(true)
	for bid in bosses.keys():
		bosses[bid] = "hidden"
	if stage_index(row["stage"]) >= stage_index("lab_trial"):
		bosses["ice_lab_boss"] = "alive"
		row["probe_ids"] = ["signal_shard", "rescue_charm", "crystal_key"]
	if stage_index(row["stage"]) >= stage_index("aurora_boss"):
		bosses["ice_lab_boss"] = "defeated"
		bosses["ice_aurora_boss"] = "alive"
	if stage_index(row["stage"]) >= stage_index("weekly_element_trial"):
		bosses["ice_aurora_boss"] = "defeated"
		bosses["ice_weekly_trial"] = "alive"
	row["boss_status"] = bosses
	return _write(expansion, row)


func talk_npc(expansion: Dictionary, action_id: String, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var row: Dictionary = runtime_of(state)
	var claims: Dictionary = (row.get("reward_claims", {}) as Dictionary).duplicate(true)
	if claims.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var stage := str(row.get("stage", "locked"))
	var probes: Array = (row.get("probe_ids", []) as Array).duplicate()
	var knowledge: Array = (row.get("knowledge_ids", []) as Array).duplicate()
	if action_id == "ice_shen":
		for elem_id in rules.get("knowledge", []):
			if not str(elem_id) in knowledge:
				knowledge.append(str(elem_id))
		row["knowledge_ids"] = knowledge
		if stage == "locked":
			row["stage"] = "ice_signal"
		elif stage == "ice_signal" and "signal_shard" in probes:
			row["stage"] = "cold_rescue"
		elif stage == "crystal_key" and "crystal_key" in probes:
			row["stage"] = "lab_trial"
			var bosses: Dictionary = (row.get("boss_status", {}) as Dictionary).duplicate(true)
			bosses["ice_lab_boss"] = "alive"
			row["boss_status"] = bosses
	elif action_id == "ice_bai":
		if stage == "cold_rescue" and "rescue_charm" in probes:
			row["stage"] = "crystal_key"
		elif BLOCK_SKIP and stage_index(stage) < stage_index("cold_rescue"):
			return {"success": false, "code": "ICE_PRECONDITION", "expansion": expansion}
	_remember_op(row, operation_id)
	_ledger(row, {"op": "talk", "npc": action_id})
	return {"success": true, "code": "OK", "expansion": _write(state, row)}


func collect_probe(expansion: Dictionary, probe_id: String, map_id: String, stage: String, have_qty: int, operation_id: String) -> Dictionary:
	var spec: Dictionary = probes_by_id.get(probe_id, {})
	if spec.is_empty():
		return {"success": false, "code": "ICE_PRECONDITION", "expansion": expansion, "consume": false}
	var row: Dictionary = runtime_of(expansion)
	var claims: Dictionary = (row.get("reward_claims", {}) as Dictionary).duplicate(true)
	if claims.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true, "consume": false}
	if REQUIRE_STAGE and str(spec.get("stage", "")) != stage:
		return {"success": false, "code": "ICE_PRECONDITION", "expansion": expansion, "consume": not BLOCK_CONSUME_ON_FAIL}
	if REQUIRE_MAP and str(spec.get("map_id", "")) != map_id:
		return {"success": false, "code": "ICE_WRONG_MAP", "expansion": expansion, "consume": not BLOCK_CONSUME_ON_FAIL}
	var ids: Array = (row.get("probe_ids", []) as Array).duplicate()
	if BLOCK_DUP_PROBE and probe_id in ids:
		return {"success": false, "code": "ICE_PROBE_DUP", "expansion": expansion, "consume": false}
	var need := str(spec.get("requires_item", ""))
	if not need.is_empty() and have_qty < 1:
		return {"success": false, "code": "ICE_PUZZLE_ITEM", "expansion": expansion, "consume": false}
	ids.append(probe_id)
	row["probe_ids"] = ids
	_remember_op(row, operation_id)
	_ledger(row, {"op": "probe", "id": probe_id})
	return {"success": true, "code": "OK", "expansion": _write(expansion, row), "consume": false}


func apply_boss_victory(expansion: Dictionary, monster_id: String, operation_id: String) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	var claims: Dictionary = (row.get("reward_claims", {}) as Dictionary).duplicate(true)
	if claims.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var stage := str(row.get("stage", "locked"))
	var bosses: Dictionary = (row.get("boss_status", {}) as Dictionary).duplicate(true)
	if monster_id == "ice_lab_boss":
		if REQUIRE_STAGE and stage != "lab_trial":
			return {"success": false, "code": "ICE_BOSS_STAGE", "expansion": expansion}
		bosses["ice_lab_boss"] = "defeated"
		bosses["ice_aurora_boss"] = "alive"
		row["stage"] = "aurora_boss"
	elif monster_id == "ice_aurora_boss":
		if REQUIRE_STAGE and stage != "aurora_boss":
			return {"success": false, "code": "ICE_BOSS_STAGE", "expansion": expansion}
		bosses["ice_aurora_boss"] = "defeated"
		bosses["ice_weekly_trial"] = "alive"
		row["stage"] = "weekly_element_trial"
	else:
		return {"success": false, "code": "ICE_BOSS_STAGE", "expansion": expansion}
	row["boss_status"] = bosses
	row["active_session_id"] = ""
	row["active_monster_id"] = ""
	_remember_op(row, operation_id)
	_ledger(row, {"op": "boss", "id": monster_id})
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}


func begin_session(expansion: Dictionary, monster_id: String, session_id: String, snapshot: Dictionary) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	row["active_session_id"] = session_id
	row["active_monster_id"] = monster_id
	row["element_snapshot"] = snapshot.duplicate(true)
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}


func clear_session(expansion: Dictionary) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	row["active_session_id"] = ""
	row["active_monster_id"] = ""
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}
