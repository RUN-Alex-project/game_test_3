extends RefCounted

const RULES_PATH := "res://data/pet_trial_rules.json"
const ROT_PATH := "res://data/pet_weekly_rotation.json"
const REQUIRE_PREREQ := true
const REQUIRE_VICTORY := true
const REQUIRE_SESSION := true
const SKIP_WEEKLY_DUP := true
const REQUIRE_WHITELIST := true
const REQUIRE_LEDGER := true

var by_id: Dictionary = {}
var monster_to_trial: Dictionary = {}
var rewards: Dictionary = {}
var weeks: Array = []


func _init() -> void:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var data: Dictionary = parsed if parsed is Dictionary else {}
	file.close()
	rewards = data
	for raw: Variant in data.get("trials", []):
		if raw is Dictionary:
			var tid := str(raw.get("trial_id", ""))
			by_id[tid] = raw
			monster_to_trial[str(raw.get("monster_id", ""))] = tid
	var rf := FileAccess.open(ROT_PATH, FileAccess.READ)
	if rf != null:
		var rp: Variant = JSON.parse_string(rf.get_as_text())
		var rd: Dictionary = rp if rp is Dictionary else {}
		weeks = (rd.get("weeks", []) as Array).duplicate(true)
		rf.close()


func normalize(raw: Variant) -> Dictionary:
	return preload("res://scripts/pet_collection_service.gd").new().normalize(raw)


func validate_save(_state: Dictionary) -> Array:
	return []


func spec_of(trial_id: String) -> Dictionary:
	var raw: Variant = by_id.get(trial_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func is_trial_unit(monster_id: String) -> bool:
	return monster_to_trial.has(monster_id)


func trial_of(monster_id: String) -> String:
	return str(monster_to_trial.get(monster_id, ""))


func visible(expansion: Dictionary, monster_id: String) -> bool:
	var row: Dictionary = normalize(expansion.get("pet_endgame", {}))
	return trial_of(monster_id) == str(row.get("active_trial_id", "")) and not str(row.get("active_trial_id", "")).is_empty()


func week_index(day: int) -> int:
	return int(floor(float(maxi(1, day) - 1) / 7.0))


func weekly_ids(day: int) -> Array:
	if weeks.is_empty():
		return []
	var idx := week_index(day) % weeks.size()
	var row: Variant = weeks[idx]
	return (row as Array).duplicate() if row is Array else []


func _write(expansion: Dictionary, row: Dictionary) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	state["pet_endgame"] = row
	return state


func begin(expansion: Dictionary, trial_id: String, session_id: String, ctx: Dictionary, support_snap: Dictionary, operation_id: String) -> Dictionary:
	var spec: Dictionary = spec_of(trial_id)
	if spec.is_empty():
		return {"success": false, "code": "PET_TRIAL_KING", "expansion": expansion}
	if bool(spec.get("need_king", false)) and REQUIRE_PREREQ:
		var first: Dictionary = normalize(expansion.get("pet_endgame", {})).get("first_claimed", {})
		var n := 0
		for tid in ["pet_trial_1", "pet_trial_2", "pet_trial_3"]:
			if first.has(tid):
				n += 1
		if n < 3:
			return {"success": false, "code": "PET_TRIAL_KING", "expansion": expansion}
	if int(ctx.get("level", 1)) < int(spec.get("min_level", 1)):
		return {"success": false, "code": "PET_TRIAL_KING", "expansion": expansion}
	var row: Dictionary = normalize(expansion.get("pet_endgame", {}))
	var ops: Dictionary = (row.get("operation_ids", {}) as Dictionary).duplicate(true)
	if ops.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	ops[operation_id] = true
	row["operation_ids"] = ops
	row["active_trial_id"] = trial_id
	row["active_session_id"] = session_id
	row["support_snapshot"] = support_snap.duplicate(true)
	if REQUIRE_LEDGER:
		var ledger: Array = (row.get("pet_ledger", []) as Array).duplicate()
		ledger.append({"op": "begin_trial", "id": trial_id, "operation_id": operation_id})
		row["pet_ledger"] = ledger
	return {
		"success": true,
		"code": "OK",
		"expansion": _write(expansion, row),
		"map_id": str(spec.get("map_id", "")),
		"monster_id": str(spec.get("monster_id", "")),
	}


func attach_session(expansion: Dictionary, monster_id: String, session_id: String) -> Dictionary:
	if not is_trial_unit(monster_id):
		return {"success": false, "code": "NOT_PET_TRIAL", "expansion": expansion}
	var row: Dictionary = normalize(expansion.get("pet_endgame", {}))
	if str(row.get("active_trial_id", "")) != trial_of(monster_id):
		return {"success": false, "code": "PET_TRIAL_CANCEL", "expansion": expansion}
	row["active_session_id"] = session_id
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}


func settle(expansion: Dictionary, monster_id: String, victory: bool, session_id: String, weekly: Array, week: int = 0) -> Dictionary:
	if not is_trial_unit(monster_id):
		return {"success": false, "code": "NOT_PET_TRIAL", "expansion": expansion}
	var row: Dictionary = normalize(expansion.get("pet_endgame", {}))
	if REQUIRE_SESSION and str(row.get("active_session_id", "")) != session_id:
		return {"success": false, "code": "PET_TRIAL_CANCEL", "expansion": expansion}
	if REQUIRE_VICTORY and not victory:
		return {"success": false, "code": "PET_TRIAL_CANCEL", "expansion": expansion, "grant": false}
	var tid := str(row.get("active_trial_id", ""))
	if trial_of(monster_id) != tid:
		return {"success": false, "code": "PET_TRIAL_KING", "expansion": expansion}
	var rec: Dictionary = (row.get("trial_records", {}) as Dictionary).duplicate(true)
	rec[tid] = int(rec.get(tid, 0)) + 1
	row["trial_records"] = rec
	var grant_first := false
	var grant_weekly := false
	var first: Dictionary = (row.get("first_claimed", {}) as Dictionary).duplicate(true)
	if not first.has(tid):
		first[tid] = true
		row["first_claimed"] = first
		grant_first = true
	if tid in weekly:
		var wk: Dictionary = (row.get("weekly_claimed", {}) as Dictionary).duplicate(true)
		var key := "%s:%d" % [tid, week]
		if wk.has(key) and SKIP_WEEKLY_DUP:
			pass
		elif wk.has(key) and not SKIP_WEEKLY_DUP:
			grant_weekly = true
		else:
			wk[key] = true
			row["weekly_claimed"] = wk
			grant_weekly = true
	row["active_trial_id"] = ""
	row["active_session_id"] = ""
	var first_spec: Dictionary = rewards.get("first", {})
	var weekly_spec: Dictionary = rewards.get("weekly", {})
	return {
		"success": true,
		"code": "OK",
		"expansion": _write(expansion, row),
		"grant_first": grant_first,
		"grant_weekly": grant_weekly,
		"first_gold": int(first_spec.get("gold", 0)) if grant_first else 0,
		"weekly_gold": int(weekly_spec.get("gold", 0)) if grant_weekly else 0,
		"item_id": str(first_spec.get("item_id", "fruit")) if grant_first or grant_weekly else "",
		"qty": (int(first_spec.get("qty", 1)) if grant_first else 0) + (int(weekly_spec.get("qty", 1)) if grant_weekly else 0),
	}
