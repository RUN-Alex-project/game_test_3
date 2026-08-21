extends RefCounted

const RULES_PATH := "res://data/abyss_finale_story.json"
const REQUIRE_PREREQ := true
const REQUIRE_STAGE := true
const REQUIRE_MAP := true
const BLOCK_DUP_PROBE := true
const BLOCK_DUP_ECHO := true
const VALIDATE_ENUM := true
const REQUIRE_LEDGER := true
const SKIP_SAME_WEEK := true
const SKIP_ONE_TIME := true

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
		"echo_completed_ids": [],
		"totem_completed_ids": [],
		"chosen_allies": [],
		"final_battle_status": "hidden",
		"epilogue_status": "none",
		"one_time_reward_claimed": false,
		"weekly_abyss": {},
		"last_weekly_claim_day": 0,
		"operation_ids": {},
		"abyss_ledger": [],
		"chapter_snapshot_version": int(rules.get("snapshot_version", 1)),
		"probe_ids": [],
		"boss_status": {
			"abyss_echo_assault": "hidden",
			"abyss_echo_guard": "hidden",
			"abyss_echo_mystery": "hidden",
			"abyss_echo_totem": "hidden",
			"abyss_echo_commander": "hidden",
			"abyss_heart_boss": "hidden",
			"abyss_weekly_trial": "hidden",
		},
		"active_session_id": "",
		"active_monster_id": "",
		"prereq_snapshot": {},
		"totem_snapshots": {},
	}


func normalize(raw: Variant) -> Dictionary:
	var chapters: Dictionary = {}
	if raw is Dictionary:
		chapters = (raw as Dictionary).duplicate(true)
	var base := empty_runtime()
	var row: Dictionary = {}
	if chapters.get("abyss_finale") is Dictionary:
		row = (chapters.get("abyss_finale", {}) as Dictionary).duplicate(true)
	for key in base.keys():
		if not row.has(key):
			row[key] = base[key]
	if str(row.get("stage", "")) not in stages:
		row["stage"] = "locked"
	if not row.get("echo_completed_ids") is Array:
		row["echo_completed_ids"] = []
	if not row.get("totem_completed_ids") is Array:
		row["totem_completed_ids"] = []
	if not row.get("chosen_allies") is Array:
		row["chosen_allies"] = []
	if not row.get("probe_ids") is Array:
		row["probe_ids"] = []
	if not row.get("operation_ids") is Dictionary:
		row["operation_ids"] = {}
	if not row.get("abyss_ledger") is Array:
		row["abyss_ledger"] = []
	if not row.get("boss_status") is Dictionary:
		row["boss_status"] = base["boss_status"]
	if not row.get("weekly_abyss") is Dictionary:
		row["weekly_abyss"] = {}
	if not row.get("prereq_snapshot") is Dictionary:
		row["prereq_snapshot"] = {}
	if not row.get("totem_snapshots") is Dictionary:
		row["totem_snapshots"] = {}
	row["chapter_snapshot_version"] = int(rules.get("snapshot_version", 1))
	chapters["abyss_finale"] = row
	return chapters


func runtime_of(expansion: Dictionary) -> Dictionary:
	var chapters: Dictionary = normalize(expansion.get("chapters", {}))
	var row: Variant = chapters.get("abyss_finale", {})
	return (row as Dictionary).duplicate(true) if row is Dictionary else empty_runtime()


func stage_index(stage_id: String) -> int:
	return stages.find(stage_id)


func stage_at_least(expansion: Dictionary, stage_id: String) -> bool:
	return stage_index(str(runtime_of(expansion).get("stage", "locked"))) >= stage_index(stage_id)


func _write(expansion: Dictionary, row: Dictionary) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var chapters: Dictionary = normalize(state.get("chapters", {}))
	chapters["abyss_finale"] = row
	state["chapters"] = chapters
	return state


func _remember_op(row: Dictionary, operation_id: String) -> bool:
	var claims: Dictionary = (row.get("operation_ids", {}) as Dictionary).duplicate(true)
	if claims.has(operation_id):
		return true
	claims[operation_id] = true
	row["operation_ids"] = claims
	return false


func _ledger(row: Dictionary, payload: Dictionary) -> void:
	if not REQUIRE_LEDGER:
		return
	var ledger: Array = (row.get("abyss_ledger", []) as Array).duplicate()
	ledger.append(payload)
	row["abyss_ledger"] = ledger


func validate_save(state: Dictionary) -> Array:
	var chapters: Variant = state.get("chapters", {})
	if not chapters is Dictionary:
		return ["SAVE_ABYSS_STAGE"]
	var row: Variant = (chapters as Dictionary).get("abyss_finale", {})
	if row == null or (row is Dictionary and (row as Dictionary).is_empty()):
		return []
	if not row is Dictionary:
		return ["SAVE_ABYSS_STAGE"]
	var stage := str((row as Dictionary).get("stage", "locked"))
	if VALIDATE_ENUM and not stage.is_empty() and stage not in stages:
		return ["SAVE_ABYSS_STAGE"]
	return []


func count_prereq_types(inputs: Dictionary) -> int:
	var types := 0
	var th := str(inputs.get("treeheart_stage", "locked"))
	var south := str(inputs.get("south_stage", "locked"))
	var ice := str(inputs.get("ice_stage", "locked"))
	var chapter_ok := th in ["tide_shrine_finale", "treeheart_weekly_contract"]
	chapter_ok = chapter_ok or south in ["resolved", "weekly_contract"]
	chapter_ok = chapter_ok or ice in ["aurora_boss", "weekly_element_trial"]
	if chapter_ok:
		types += 1
	if int(inputs.get("max_bond", 0)) >= 2:
		types += 1
	if int(inputs.get("reputation", 0)) >= 1 or int(inputs.get("contribution", 0)) >= 1:
		types += 1
	return types


func try_enter(expansion: Dictionary, inputs: Dictionary, operation_id: String) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	var ops: Dictionary = (row.get("operation_ids", {}) as Dictionary)
	if ops.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var types := count_prereq_types(inputs)
	if REQUIRE_PREREQ and types < 3 and str(row.get("stage", "locked")) == "locked":
		return {"success": false, "code": "ABYSS_PRECONDITION", "expansion": expansion}
	if str(row.get("stage", "locked")) == "locked":
		row["stage"] = "summons"
		row["prereq_snapshot"] = inputs.duplicate(true)
		_ledger(row, {"op": "enter", "types": types})
	_remember_op(row, operation_id)
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}


func set_stage_for_fixture(expansion: Dictionary, stage_id: String) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	row["stage"] = stage_id if stage_id in stages else "locked"
	var bosses: Dictionary = (row.get("boss_status", {}) as Dictionary).duplicate(true)
	for bid in bosses.keys():
		bosses[bid] = "hidden"
	row["echo_completed_ids"] = []
	row["totem_completed_ids"] = []
	row["probe_ids"] = []
	row["final_battle_status"] = "hidden"
	row["epilogue_status"] = "none"
	row["one_time_reward_claimed"] = false
	if stage_index(row["stage"]) >= stage_index("echoes"):
		row["probe_ids"] = ["gate_seal"]
		for echo_id in ["abyss_echo_assault", "abyss_echo_guard", "abyss_echo_mystery", "abyss_echo_totem", "abyss_echo_commander"]:
			bosses[echo_id] = "alive"
	if stage_index(row["stage"]) >= stage_index("totem_trials"):
		row["echo_completed_ids"] = ["abyss_echo_assault", "abyss_echo_guard", "abyss_echo_mystery"]
		for echo_id in ["abyss_echo_assault", "abyss_echo_guard", "abyss_echo_mystery"]:
			bosses[echo_id] = "defeated"
	if stage_index(row["stage"]) >= stage_index("heart_assault"):
		row["totem_completed_ids"] = ["totem_guild", "totem_territory", "totem_bond"]
		row["probe_ids"] = ["gate_seal"]
	if stage_index(row["stage"]) >= stage_index("final_battle"):
		row["probe_ids"] = ["gate_seal", "heart_seal"]
		bosses["abyss_heart_boss"] = "alive"
		row["final_battle_status"] = "alive"
	if stage_index(row["stage"]) >= stage_index("epilogue_pending"):
		bosses["abyss_heart_boss"] = "defeated"
		row["final_battle_status"] = "defeated"
		row["epilogue_status"] = "pending"
	if stage_index(row["stage"]) >= stage_index("completed"):
		row["epilogue_status"] = "done"
		row["one_time_reward_claimed"] = true
	if stage_index(row["stage"]) >= stage_index("weekly_abyss"):
		bosses["abyss_weekly_trial"] = "alive"
	row["boss_status"] = bosses
	return _write(expansion, row)


func talk_npc(expansion: Dictionary, action_id: String, operation_id: String) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	var ops: Dictionary = (row.get("operation_ids", {}) as Dictionary)
	if ops.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var stage := str(row.get("stage", "locked"))
	var allies: Array = (row.get("chosen_allies", []) as Array).duplicate()
	var npc_map := {"abyss_he": "npc_adv_he_ming", "abyss_jiang": "npc_adv_jiang_yue", "abyss_gu": "npc_adv_gu_ning"}
	if npc_map.has(action_id):
		var ally := str(npc_map[action_id])
		if not ally in allies:
			allies.append(ally)
		row["chosen_allies"] = allies
	if action_id == "abyss_he" and stage == "summons":
		row["stage"] = "abyss_entry"
	elif action_id == "abyss_gu" and stage == "heart_assault":
		row["stage"] = "final_battle"
		var bosses: Dictionary = (row.get("boss_status", {}) as Dictionary).duplicate(true)
		bosses["abyss_heart_boss"] = "alive"
		row["boss_status"] = bosses
		row["final_battle_status"] = "alive"
	elif action_id == "abyss_he" and stage == "completed":
		row["stage"] = "weekly_abyss"
		var bosses2: Dictionary = (row.get("boss_status", {}) as Dictionary).duplicate(true)
		bosses2["abyss_weekly_trial"] = "alive"
		row["boss_status"] = bosses2
	elif REQUIRE_STAGE and stage == "locked":
		return {"success": false, "code": "ABYSS_PRECONDITION", "expansion": expansion}
	_remember_op(row, operation_id)
	_ledger(row, {"op": "talk", "npc": action_id, "stage": row.get("stage", "")})
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}


func collect_probe(expansion: Dictionary, probe_id: String, map_id: String, stage: String, operation_id: String) -> Dictionary:
	var spec: Dictionary = probes_by_id.get(probe_id, {})
	if spec.is_empty():
		return {"success": false, "code": "ABYSS_PRECONDITION", "expansion": expansion}
	var row: Dictionary = runtime_of(expansion)
	var ops: Dictionary = (row.get("operation_ids", {}) as Dictionary)
	if ops.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	if REQUIRE_STAGE and str(spec.get("stage", "")) != stage:
		return {"success": false, "code": "ABYSS_PRECONDITION", "expansion": expansion}
	if REQUIRE_MAP and str(spec.get("map_id", "")) != map_id:
		return {"success": false, "code": "TOTEM_WRONG_MAP", "expansion": expansion}
	var ids: Array = (row.get("probe_ids", []) as Array).duplicate()
	if BLOCK_DUP_PROBE and probe_id in ids:
		return {"success": false, "code": "ABYSS_PRECONDITION", "expansion": expansion}
	ids.append(probe_id)
	row["probe_ids"] = ids
	if probe_id == "gate_seal" and stage == "abyss_entry":
		row["stage"] = "echoes"
		var bosses: Dictionary = (row.get("boss_status", {}) as Dictionary).duplicate(true)
		for echo_id in ["abyss_echo_assault", "abyss_echo_guard", "abyss_echo_mystery", "abyss_echo_totem", "abyss_echo_commander"]:
			bosses[echo_id] = "alive"
		row["boss_status"] = bosses
	if probe_id == "heart_seal" and stage == "heart_assault":
		row["stage"] = "final_battle"
		var bosses2: Dictionary = (row.get("boss_status", {}) as Dictionary).duplicate(true)
		bosses2["abyss_heart_boss"] = "alive"
		row["boss_status"] = bosses2
		row["final_battle_status"] = "alive"
	_remember_op(row, operation_id)
	_ledger(row, {"op": "probe", "id": probe_id})
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}


func begin_session(expansion: Dictionary, monster_id: String, session_id: String) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	row["active_session_id"] = session_id
	row["active_monster_id"] = monster_id
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}


func clear_session(expansion: Dictionary) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	row["active_session_id"] = ""
	row["active_monster_id"] = ""
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}


func apply_echo_victory(expansion: Dictionary, monster_id: String, operation_id: String) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	if _remember_op(row, operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var echoes: Array = (row.get("echo_completed_ids", []) as Array).duplicate()
	if BLOCK_DUP_ECHO and monster_id in echoes:
		return {"success": false, "code": "ABYSS_ECHO_DUP", "expansion": expansion}
	echoes.append(monster_id)
	row["echo_completed_ids"] = echoes
	var bosses: Dictionary = (row.get("boss_status", {}) as Dictionary).duplicate(true)
	bosses[monster_id] = "defeated"
	row["boss_status"] = bosses
	row["active_session_id"] = ""
	row["active_monster_id"] = ""
	if echoes.size() >= int(rules.get("echoes_required", 3)) and str(row.get("stage", "")) == "echoes":
		row["stage"] = "totem_trials"
	_ledger(row, {"op": "echo", "id": monster_id})
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}


func mark_totem(expansion: Dictionary, totem_id: String, snapshot: Dictionary, operation_id: String) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	if _remember_op(row, operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var ids: Array = (row.get("totem_completed_ids", []) as Array).duplicate()
	if totem_id in ids:
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	ids.append(totem_id)
	row["totem_completed_ids"] = ids
	var snaps: Dictionary = (row.get("totem_snapshots", {}) as Dictionary).duplicate(true)
	snaps[totem_id] = snapshot.duplicate(true)
	row["totem_snapshots"] = snaps
	if ids.size() >= int(rules.get("totems_required", 3)) and str(row.get("stage", "")) == "totem_trials":
		row["stage"] = "heart_assault"
	_ledger(row, {"op": "totem", "id": totem_id})
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}


func apply_heart_victory(expansion: Dictionary, operation_id: String) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	if _remember_op(row, operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	if REQUIRE_STAGE and str(row.get("stage", "")) != "final_battle":
		return {"success": false, "code": "ABYSS_PRECONDITION", "expansion": expansion}
	var bosses: Dictionary = (row.get("boss_status", {}) as Dictionary).duplicate(true)
	bosses["abyss_heart_boss"] = "defeated"
	row["boss_status"] = bosses
	row["final_battle_status"] = "defeated"
	row["stage"] = "epilogue_pending"
	row["epilogue_status"] = "pending"
	row["active_session_id"] = ""
	row["active_monster_id"] = ""
	_ledger(row, {"op": "heart"})
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}


func week_index(day: int) -> int:
	return int(floor(float(maxi(1, day) - 1) / 7.0))


func claim_weekly(expansion: Dictionary, day: int, operation_id: String) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	if _remember_op(row, operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	if str(row.get("stage", "")) != "weekly_abyss":
		return {"success": false, "code": "ABYSS_PRECONDITION", "expansion": expansion}
	var wk: Dictionary = (row.get("weekly_abyss", {}) as Dictionary).duplicate(true)
	var week := week_index(day)
	if int(wk.get("week", -1)) != week:
		wk = {"week": week, "claimed": false}
	if SKIP_SAME_WEEK and bool(wk.get("claimed", false)):
		return {"success": false, "code": "ABYSS_WEEKLY_DUP", "expansion": expansion}
	wk["claimed"] = true
	wk["week"] = week
	row["weekly_abyss"] = wk
	row["last_weekly_claim_day"] = day
	_ledger(row, {"op": "weekly", "day": day})
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}


func mark_one_time(expansion: Dictionary, operation_id: String) -> Dictionary:
	var row: Dictionary = runtime_of(expansion)
	if SKIP_ONE_TIME and bool(row.get("one_time_reward_claimed", false)):
		return {"success": false, "code": "FINALE_REWARD_DUP", "expansion": expansion}
	if _remember_op(row, operation_id) and SKIP_ONE_TIME:
		return {"success": false, "code": "FINALE_REWARD_DUP", "expansion": expansion}
	row["one_time_reward_claimed"] = true
	_ledger(row, {"op": "one_time"})
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}
