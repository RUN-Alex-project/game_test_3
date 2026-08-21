extends RefCounted

const RelationshipServiceScript = preload("res://scripts/relationship_service.gd")

const RULES_PATH := "res://data/story_treeheart_harbor.json"
const REQUIRE_STAGE := true
const BLOCK_SKIP_STAGE := true
const LOCK_BRANCH := true

var rules: Dictionary = {}
var relationship_service = RelationshipServiceScript.new()
var stages: Array = []


func _init() -> void:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null:
		push_error("missing story_treeheart_harbor.json")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	rules = parsed if parsed is Dictionary else {}
	stages = (rules.get("stages", []) as Array).duplicate()


func empty_runtime() -> Dictionary:
	return {
		"stage": "locked",
		"branch": "",
		"collected_evidence_ids": [],
		"completed_operation_ids": [],
		"boss_status": {"chapter_sea_boss": "hidden", "chapter_tide_boss": "hidden"},
		"weekly_contract": {},
		"last_weekly_claim_day": 0,
		"npc_snapshot_ids": [],
		"reward_claims": {},
		"chapter_ledger": [],
	}


func normalize(raw: Variant) -> Dictionary:
	var base := empty_runtime()
	if not raw is Dictionary:
		return {"treeheart_harbor": base}
	var chapters: Dictionary = (raw as Dictionary).duplicate(true)
	var row: Dictionary = (chapters.get("treeheart_harbor", {}) as Dictionary).duplicate(true) if chapters.get("treeheart_harbor") is Dictionary else {}
	for key in base.keys():
		if not row.has(key):
			row[key] = base[key]
	if str(row.get("stage", "")) not in stages:
		row["stage"] = "locked"
	if not row.get("collected_evidence_ids") is Array:
		row["collected_evidence_ids"] = []
	if not row.get("completed_operation_ids") is Array:
		row["completed_operation_ids"] = []
	if not row.get("npc_snapshot_ids") is Array:
		row["npc_snapshot_ids"] = []
	if not row.get("reward_claims") is Dictionary:
		row["reward_claims"] = {}
	if not row.get("chapter_ledger") is Array:
		row["chapter_ledger"] = []
	if not row.get("boss_status") is Dictionary:
		row["boss_status"] = base["boss_status"]
	if not row.get("weekly_contract") is Dictionary:
		row["weekly_contract"] = {}
	chapters["treeheart_harbor"] = row
	return chapters


func runtime_of(expansion: Dictionary) -> Dictionary:
	var chapters: Dictionary = normalize(expansion.get("chapters", {}))
	return (chapters.get("treeheart_harbor", {}) as Dictionary).duplicate(true)


func stage_index(stage_id: String) -> int:
	return stages.find(stage_id)


func stage_at_least(expansion: Dictionary, stage_id: String) -> bool:
	return stage_index(str(runtime_of(expansion).get("stage", "locked"))) >= stage_index(stage_id)


func _write_runtime(expansion: Dictionary, row: Dictionary) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var chapters: Dictionary = normalize(state.get("chapters", {}))
	chapters["treeheart_harbor"] = row
	state["chapters"] = chapters
	return state


func _remember_op(row: Dictionary, operation_id: String) -> bool:
	var ops: Array = (row.get("completed_operation_ids", []) as Array).duplicate()
	if operation_id in ops:
		return true
	ops.append(operation_id)
	row["completed_operation_ids"] = ops
	return false


func _append_ledger(row: Dictionary, payload: Dictionary) -> void:
	var ledger: Array = (row.get("chapter_ledger", []) as Array).duplicate()
	ledger.append(payload)
	row["chapter_ledger"] = ledger


func talk_npc(expansion: Dictionary, action_id: String, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var row: Dictionary = runtime_of(state)
	if _remember_op(row, operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var snaps: Array = (row.get("npc_snapshot_ids", []) as Array).duplicate()
	if not action_id in snaps:
		snaps.append(action_id)
		row["npc_snapshot_ids"] = snaps
	var stage := str(row.get("stage", "locked"))
	if action_id == "chapter_lin":
		if stage == "locked":
			row["stage"] = "treeheart_rumor"
		elif stage == "treeheart_rumor":
			row["stage"] = "root_sickness"
		elif stage == "root_sickness":
			var collected: Array = row.get("collected_evidence_ids", [])
			var needed := ["root_bark", "sick_leaf", "core_resin"]
			var ready := true
			for evid: String in needed:
				if not evid in collected:
					ready = false
			if ready:
				row["stage"] = "harbor_lead"
			elif REQUIRE_STAGE:
				state = _write_runtime(state, row)
				return {"success": false, "code": "CHAPTER_PRECONDITION", "expansion": state}
		else:
			if BLOCK_SKIP_STAGE and stage_index(stage) < stage_index("root_sickness"):
				return {"success": false, "code": "CHAPTER_PRECONDITION", "expansion": expansion}
	elif action_id == "chapter_su":
		if stage == "harbor_lead":
			if "smuggler_ledger" in row.get("collected_evidence_ids", []):
				row["stage"] = "smuggler_choice"
			elif REQUIRE_STAGE:
				state = _write_runtime(state, row)
				return {"success": false, "code": "CHAPTER_PRECONDITION", "expansion": state}
		elif REQUIRE_STAGE and stage != "smuggler_choice":
			if stage_index(stage) < stage_index("harbor_lead"):
				return {"success": false, "code": "CHAPTER_PRECONDITION", "expansion": expansion}
	_append_ledger(row, {"operation_id": operation_id, "reason": "talk:%s" % action_id, "stage": row.get("stage", "")})
	state = _write_runtime(state, row)
	return {"success": true, "code": "OK", "expansion": state, "stage": str(row.get("stage", ""))}


func choose_branch(expansion: Dictionary, branch_id: String, day: int, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var row: Dictionary = runtime_of(state)
	if _remember_op(row, operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var stage := str(row.get("stage", "locked"))
	if LOCK_BRANCH and not str(row.get("branch", "")).is_empty():
		return {"success": false, "code": "CHAPTER_BRANCH", "expansion": expansion}
	if REQUIRE_STAGE and stage != "smuggler_choice":
		return {"success": false, "code": "CHAPTER_PRECONDITION", "expansion": expansion}
	var branches: Dictionary = rules.get("branches", {})
	if not branches.has(branch_id):
		return {"success": false, "code": "CHAPTER_BRANCH", "expansion": expansion}
	row["branch"] = branch_id
	row["stage"] = "sea_cave_assault"
	var bosses: Dictionary = (row.get("boss_status", {}) as Dictionary).duplicate(true)
	bosses["chapter_sea_boss"] = "alive"
	row["boss_status"] = bosses
	var spec: Dictionary = branches[branch_id]
	var rel_id := str(spec.get("relationship_id", ""))
	var rel_delta := int(spec.get("relationship_delta", 0))
	if rel_delta != 0 and not rel_id.is_empty():
		var rel_result: Dictionary = relationship_service.apply_relationship_reward(
			state, rel_id, rel_delta, day, operation_id, "chapter_branch:%s" % branch_id)
		if bool(rel_result.get("success", false)):
			state = rel_result.expansion
	var market: Dictionary = (state.get("market", {}) as Dictionary).duplicate(true)
	market["reputation"] = int(market.get("reputation", 0)) + int(spec.get("reputation_delta", 0))
	state["market"] = market
	_append_ledger(row, {"operation_id": operation_id, "reason": "branch:%s" % branch_id, "stage": row["stage"]})
	state = _write_runtime(state, row)
	return {"success": true, "code": "OK", "expansion": state, "branch": branch_id}


func mark_evidence(expansion: Dictionary, evidence_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var row: Dictionary = runtime_of(state)
	var collected: Array = (row.get("collected_evidence_ids", []) as Array).duplicate()
	if not evidence_id in collected:
		collected.append(evidence_id)
		row["collected_evidence_ids"] = collected
	state = _write_runtime(state, row)
	return state


func apply_boss_victory(expansion: Dictionary, monster_id: String, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var row: Dictionary = runtime_of(state)
	if _remember_op(row, operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var expected_stage := ""
	if monster_id == "chapter_sea_boss":
		expected_stage = "sea_cave_assault"
	elif monster_id == "chapter_tide_boss":
		expected_stage = "tide_shrine_finale"
	if BLOCK_SKIP_STAGE and expected_stage != "" and str(row.get("stage", "")) != expected_stage:
		return {"success": false, "code": "CHAPTER_PRECONDITION", "expansion": expansion}
	var bosses: Dictionary = (row.get("boss_status", {}) as Dictionary).duplicate(true)
	bosses[monster_id] = "defeated"
	row["boss_status"] = bosses
	if monster_id == "chapter_sea_boss":
		row["stage"] = "tide_shrine_finale"
		bosses["chapter_tide_boss"] = "alive"
		row["boss_status"] = bosses
	elif monster_id == "chapter_tide_boss":
		row["stage"] = "treeheart_weekly_contract"
	_append_ledger(row, {"operation_id": operation_id, "reason": "boss:%s" % monster_id, "stage": row.get("stage", "")})
	state = _write_runtime(state, row)
	return {"success": true, "code": "OK", "expansion": state, "stage": str(row.get("stage", ""))}


func set_stage_for_fixture(expansion: Dictionary, stage_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var row: Dictionary = runtime_of(state)
	row["stage"] = stage_id if stage_id in stages else "locked"
	var bosses: Dictionary = {"chapter_sea_boss": "hidden", "chapter_tide_boss": "hidden"}
	if stage_index(row["stage"]) >= stage_index("sea_cave_assault") and str(bosses.get("chapter_sea_boss", "")) != "defeated":
		if row["stage"] == "sea_cave_assault":
			bosses["chapter_sea_boss"] = "alive"
		elif stage_index(row["stage"]) > stage_index("sea_cave_assault"):
			bosses["chapter_sea_boss"] = "defeated"
	if row["stage"] == "tide_shrine_finale":
		bosses["chapter_tide_boss"] = "alive"
	elif stage_index(row["stage"]) > stage_index("tide_shrine_finale"):
		bosses["chapter_tide_boss"] = "defeated"
		bosses["chapter_sea_boss"] = "defeated"
	row["boss_status"] = bosses
	return _write_runtime(state, row)


func validate_save(expansion: Dictionary) -> Array:
	var errors: Array = []
	var raw_chapters: Variant = expansion.get("chapters", {})
	var raw_row: Variant = {}
	if raw_chapters is Dictionary:
		raw_row = raw_chapters.get("treeheart_harbor", {})
	var raw_stage := "locked"
	if raw_row is Dictionary:
		raw_stage = str(raw_row.get("stage", "locked"))
	if raw_stage not in stages:
		errors.append("SAVE_CHAPTER_STAGE")
	var collected: Array = []
	if raw_row is Dictionary and raw_row.get("collected_evidence_ids") is Array:
		collected = raw_row.get("collected_evidence_ids", [])
	var seen: Dictionary = {}
	for evid in collected:
		var key := str(evid)
		if seen.has(key):
			errors.append("SAVE_CHAPTER_STAGE")
		seen[key] = true
	return errors
