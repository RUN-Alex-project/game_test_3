extends RefCounted

const RULES_PATH := "res://data/south_border_story.json"
const REQUIRE_STAGE := true
const BLOCK_SKIP := true
const BLOCK_DUP_SCOUT := true
const REQUIRE_MAP := true
const BLOCK_DUP_MERIT := true
const REQUIRE_LEDGER := true

var rules: Dictionary = {}
var stages: Array = []


func _init() -> void:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	rules = parsed if parsed is Dictionary else {}
	stages = (rules.get("stages", []) as Array).duplicate()


func empty_runtime() -> Dictionary:
	return {
		"stage": "locked",
		"scout_ids": [],
		"supply_submitted": false,
		"defense_ops": [],
		"boss_status": {"border_command_boss": "hidden", "border_weekly_elite": "hidden"},
		"active_session_id": "",
		"active_monster_id": "",
		"weekly_contract": {},
		"last_weekly_claim_day": 0,
		"reward_claims": {},
		"border_ledger": [],
		"merit_granted": false,
	}


func normalize(raw: Variant) -> Dictionary:
	var chapters: Dictionary = {}
	if raw is Dictionary:
		chapters = (raw as Dictionary).duplicate(true)
	var base := empty_runtime()
	var row: Dictionary = (chapters.get("south_border", {}) as Dictionary).duplicate(true) if chapters.get("south_border") is Dictionary else {}
	for key in base.keys():
		if not row.has(key):
			row[key] = base[key]
	if str(row.get("stage", "")) not in stages:
		row["stage"] = "locked"
	if not row.get("scout_ids") is Array:
		row["scout_ids"] = []
	if not row.get("defense_ops") is Array:
		row["defense_ops"] = []
	if not row.get("reward_claims") is Dictionary:
		row["reward_claims"] = {}
	if not row.get("border_ledger") is Array:
		row["border_ledger"] = []
	if not row.get("boss_status") is Dictionary:
		row["boss_status"] = base["boss_status"]
	if not row.get("weekly_contract") is Dictionary:
		row["weekly_contract"] = {}
	chapters["south_border"] = row
	return chapters


func runtime_of(expansion: Dictionary) -> Dictionary:
	return (normalize(expansion.get("chapters", {})).get("south_border", {}) as Dictionary).duplicate(true)


func stage_index(stage_id: String) -> int:
	return stages.find(stage_id)


func stage_at_least(expansion: Dictionary, stage_id: String) -> bool:
	return stage_index(str(runtime_of(expansion).get("stage", "locked"))) >= stage_index(stage_id)


func _write(expansion: Dictionary, row: Dictionary) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var chapters: Dictionary = normalize(state.get("chapters", {}))
	chapters["south_border"] = row
	state["chapters"] = chapters
	return state


func _ledger(row: Dictionary, payload: Dictionary) -> void:
	if not REQUIRE_LEDGER:
		return
	var ledger: Array = (row.get("border_ledger", []) as Array).duplicate()
	ledger.append(payload)
	row["border_ledger"] = ledger


func talk_npc(expansion: Dictionary, action_id: String, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var row: Dictionary = runtime_of(state)
	var ops: Array = (row.get("defense_ops", []) as Array).duplicate()
	if operation_id in (row.get("reward_claims", {}) as Dictionary).keys():
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var claims: Dictionary = (row.get("reward_claims", {}) as Dictionary).duplicate(true)
	if operation_id in claims:
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	claims[operation_id] = action_id
	row["reward_claims"] = claims
	var stage := str(row.get("stage", "locked"))
	if action_id == "border_cmd":
		if stage == "locked":
			row["stage"] = "scouting"
		elif stage == "scouting":
			var scouts: Array = row.get("scout_ids", [])
			if "scout_tracks" in scouts and "scout_banner" in scouts:
				row["stage"] = "supply"
			elif REQUIRE_STAGE:
				return {"success": false, "code": "BORDER_PRECONDITION", "expansion": expansion}
		elif BLOCK_SKIP and stage_index(stage) < stage_index("scouting"):
			return {"success": false, "code": "BORDER_PRECONDITION", "expansion": expansion}
	_ledger(row, {"operation_id": operation_id, "reason": "talk:%s" % action_id, "stage": row.get("stage", "")})
	state = _write(state, row)
	return {"success": true, "code": "OK", "expansion": state, "stage": str(row.get("stage", ""))}


func collect_scout(expansion: Dictionary, scout_id: String, map_id: String, stage: String, operation_id: String) -> Dictionary:
	var spec: Dictionary = {}
	for raw in rules.get("scouts", []):
		if raw is Dictionary and str(raw.get("scout_id", "")) == scout_id:
			spec = raw
	if spec.is_empty():
		return {"success": false, "code": "BORDER_SCOUT_DUP", "expansion": expansion}
	if REQUIRE_MAP and str(spec.get("map_id", "")) != map_id:
		return {"success": false, "code": "EVIDENCE_WRONG_MAP", "expansion": expansion}
	if REQUIRE_STAGE and str(spec.get("stage", "")) != stage:
		return {"success": false, "code": "BORDER_PRECONDITION", "expansion": expansion}
	var row: Dictionary = runtime_of(expansion)
	var scouts: Array = (row.get("scout_ids", []) as Array).duplicate()
	if BLOCK_DUP_SCOUT and scout_id in scouts:
		return {"success": false, "code": "BORDER_SCOUT_DUP", "expansion": expansion}
	scouts.append(scout_id)
	row["scout_ids"] = scouts
	_ledger(row, {"operation_id": operation_id, "reason": "scout:%s" % scout_id, "stage": stage})
	return {"success": true, "code": "OK", "expansion": _write(expansion, row), "scout_id": scout_id}


func apply_defense_op(expansion: Dictionary, monster_id: String, operation_id: String) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	if str(row.get("stage", "")) != "defense" and REQUIRE_STAGE:
		return {"success": false, "code": "BORDER_PRECONDITION", "expansion": expansion}
	var ops: Array = (row.get("defense_ops", []) as Array).duplicate()
	if monster_id in ops:
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	ops.append(monster_id)
	row["defense_ops"] = ops
	var needed: Array = rules.get("defense_ops", [])
	var ready := true
	for item in needed:
		if not str(item) in ops:
			ready = false
	if ready:
		row["stage"] = "counterattack"
		var bosses: Dictionary = (row.get("boss_status", {}) as Dictionary).duplicate(true)
		bosses["border_command_boss"] = "alive"
		row["boss_status"] = bosses
	_ledger(row, {"operation_id": operation_id, "reason": "defense:%s" % monster_id, "stage": row.get("stage", "")})
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}


func apply_boss_victory(expansion: Dictionary, monster_id: String, operation_id: String) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	if BLOCK_SKIP and str(row.get("stage", "")) != "counterattack":
		return {"success": false, "code": "BORDER_PRECONDITION", "expansion": expansion}
	var bosses: Dictionary = (row.get("boss_status", {}) as Dictionary).duplicate(true)
	bosses[monster_id] = "defeated"
	row["boss_status"] = bosses
	row["stage"] = "resolved"
	_ledger(row, {"operation_id": operation_id, "reason": "boss:%s" % monster_id, "stage": "resolved"})
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}


func apply_resolved_rewards(expansion: Dictionary, gold_delta: int, merit_delta: int, rep_delta: int, contrib_delta: int, owned_territory: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var row: Dictionary = runtime_of(state)
	if BLOCK_DUP_MERIT and bool(row.get("merit_granted", false)):
		return {"success": false, "code": "BORDER_MERIT_DUP", "expansion": expansion}
	row["merit_granted"] = true
	row["stage"] = "weekly_contract"
	var bosses: Dictionary = (row.get("boss_status", {}) as Dictionary).duplicate(true)
	bosses["border_weekly_elite"] = "hidden"
	row["boss_status"] = bosses
	_ledger(row, {"operation_id": "resolved_reward", "reason": "resolved", "gold": gold_delta, "merit": merit_delta})
	state = _write(state, row)
	var market: Dictionary = (state.get("market", {}) as Dictionary).duplicate(true)
	market["reputation"] = int(market.get("reputation", 0)) + rep_delta
	state["market"] = market
	if contrib_delta != 0 and not owned_territory.is_empty():
		var econ: Dictionary = (state.get("territory_economy", {}) as Dictionary).duplicate(true)
		econ["contribution"] = int(econ.get("contribution", 0)) + contrib_delta
		state["territory_economy"] = econ
	return {"success": true, "code": "OK", "expansion": state, "gold": gold_delta, "merit": merit_delta}


func set_stage_for_fixture(expansion: Dictionary, stage_id: String) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	row["stage"] = stage_id if stage_id in stages else "locked"
	var bosses: Dictionary = {"border_command_boss": "hidden", "border_weekly_elite": "hidden"}
	if row["stage"] == "defense":
		row["supply_submitted"] = true
	if row["stage"] == "counterattack":
		row["supply_submitted"] = true
		row["defense_ops"] = (rules.get("defense_ops", []) as Array).duplicate()
		bosses["border_command_boss"] = "alive"
	if stage_index(row["stage"]) >= stage_index("resolved"):
		row["supply_submitted"] = true
		row["defense_ops"] = (rules.get("defense_ops", []) as Array).duplicate()
		bosses["border_command_boss"] = "defeated"
	row["boss_status"] = bosses
	return _write(expansion, row)


func validate_save(expansion: Dictionary) -> Array:
	var errors: Array = []
	var raw_chapters: Variant = expansion.get("chapters", {})
	var raw_row: Variant = {}
	if raw_chapters is Dictionary:
		raw_row = raw_chapters.get("south_border", {})
	if raw_row is Dictionary and raw_row.has("stage"):
		if str(raw_row.get("stage", "locked")) not in stages:
			errors.append("SAVE_BORDER_STAGE")
		var scouts: Array = raw_row.get("scout_ids", []) if raw_row.get("scout_ids") is Array else []
		var seen: Dictionary = {}
		for sid in scouts:
			var key := str(sid)
			if seen.has(key):
				errors.append("SAVE_BORDER_STAGE")
			seen[key] = true
	return errors


func ledger_gold_sum(expansion: Dictionary) -> int:
	var total := 0
	for raw in runtime_of(expansion).get("border_ledger", []):
		if raw is Dictionary:
			total += int(raw.get("gold", 0))
	return total
