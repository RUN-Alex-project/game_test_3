extends RefCounted

const CAT_PATH := "res://data/challenge_catalog.json"
const REWARD_PATH := "res://data/challenge_rewards.json"
const REQUIRE_UNLOCK := true
const REQUIRE_VICTORY := true
const REQUIRE_SESSION := true
const BLOCK_TRAIN_REWARD := true
const SKIP_FIRST_DUP := true
const SKIP_WEEKLY_DUP := true
const VALIDATE_CATALOG := true
const REQUIRE_LEDGER := true
const REQUIRE_UNIQUE_OP := true

var catalog: Dictionary = {}
var by_id: Dictionary = {}
var rewards: Dictionary = {}
var monsters_by_id: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(CAT_PATH, FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		catalog = parsed if parsed is Dictionary else {}
		file.close()
	for raw: Variant in catalog.get("challenges", []):
		if raw is Dictionary:
			var cid := str(raw.get("challenge_id", ""))
			by_id[cid] = raw
			monsters_by_id[str(raw.get("monster_id", ""))] = cid
	var rf := FileAccess.open(REWARD_PATH, FileAccess.READ)
	if rf != null:
		var rp: Variant = JSON.parse_string(rf.get_as_text())
		rewards = rp if rp is Dictionary else {}
		rf.close()


func empty_runtime() -> Dictionary:
	return {
		"records": {},
		"first_claimed": {},
		"weekly_claimed": {},
		"active_challenge_id": "",
		"active_session_id": "",
		"active_mode": "",
		"mastery_snapshot": {},
		"input_snapshot": {},
		"reports": [],
		"operation_ids": {},
		"challenge_ledger": [],
	}


func normalize(raw: Variant) -> Dictionary:
	var base := empty_runtime()
	var row: Dictionary = {}
	if raw is Dictionary:
		row = (raw as Dictionary).duplicate(true)
	for key in base.keys():
		if not row.has(key):
			row[key] = base[key]
	if not row.get("records") is Dictionary:
		row["records"] = {}
	if not row.get("first_claimed") is Dictionary:
		row["first_claimed"] = {}
	if not row.get("weekly_claimed") is Dictionary:
		row["weekly_claimed"] = {}
	if not row.get("operation_ids") is Dictionary:
		row["operation_ids"] = {}
	if not row.get("challenge_ledger") is Array:
		row["challenge_ledger"] = []
	if not row.get("reports") is Array:
		row["reports"] = []
	if not row.get("mastery_snapshot") is Dictionary:
		row["mastery_snapshot"] = {}
	if not row.get("input_snapshot") is Dictionary:
		row["input_snapshot"] = {}
	return row


func validate_catalog() -> Array:
	var rows: Array = catalog.get("challenges", [])
	var ids: Dictionary = {}
	if VALIDATE_CATALOG and rows.size() != int(catalog.get("expected_count", 9)):
		return ["CHALLENGE_COUNT"]
	for raw: Variant in rows:
		if not raw is Dictionary:
			return ["CHALLENGE_COUNT"]
		var cid := str((raw as Dictionary).get("challenge_id", ""))
		if cid.is_empty():
			return ["CHALLENGE_COUNT"]
		if ids.has(cid):
			return ["CHALLENGE_DUP_ID"]
		ids[cid] = true
	if VALIDATE_CATALOG and ids.size() != 9:
		return ["CHALLENGE_COUNT"]
	return []


func validate_save(state: Dictionary) -> Array:
	var row: Variant = state.get("challenges", {})
	if not row is Dictionary:
		return []
	if not REQUIRE_UNIQUE_OP:
		return []
	var seen: Dictionary = {}
	for raw: Variant in (row as Dictionary).get("challenge_ledger", []):
		if not raw is Dictionary:
			continue
		var oid := str((raw as Dictionary).get("operation_id", ""))
		if oid.is_empty():
			continue
		if seen.has(oid):
			return ["SAVE_DUP_OP"]
		seen[oid] = true
	return []


func spec_of(challenge_id: String) -> Dictionary:
	var raw: Variant = by_id.get(challenge_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func is_challenge_unit(monster_id: String) -> bool:
	return monsters_by_id.has(monster_id)


func challenge_id_of(monster_id: String) -> String:
	return str(monsters_by_id.get(monster_id, ""))


func visible(expansion: Dictionary, monster_id: String) -> bool:
	var row: Dictionary = normalize(expansion.get("challenges", {}))
	if str(row.get("active_challenge_id", "")) == "":
		return false
	return challenge_id_of(monster_id) == str(row.get("active_challenge_id", ""))


func _write(expansion: Dictionary, row: Dictionary) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	state["challenges"] = row
	return state


func _remember(row: Dictionary, operation_id: String) -> bool:
	var ops: Dictionary = (row.get("operation_ids", {}) as Dictionary).duplicate(true)
	if REQUIRE_UNIQUE_OP and ops.has(operation_id):
		return true
	ops[operation_id] = true
	row["operation_ids"] = ops
	return false


func _ledger(row: Dictionary, payload: Dictionary) -> void:
	if not REQUIRE_LEDGER:
		return
	var ledger: Array = (row.get("challenge_ledger", []) as Array).duplicate()
	ledger.append(payload)
	row["challenge_ledger"] = ledger


func unlocked(spec: Dictionary, ctx: Dictionary) -> bool:
	if not REQUIRE_UNLOCK:
		return true
	var kind := str(spec.get("unlock", "always"))
	if kind == "always":
		return int(ctx.get("level", 1)) >= int(spec.get("min_level", 1))
	if kind == "level":
		return int(ctx.get("level", 1)) >= int(spec.get("min_level", 10))
	if kind == "contribution":
		return int(ctx.get("contribution", 0)) >= int(spec.get("min_contribution", 1))
	if kind == "treeheart":
		return bool(ctx.get("treeheart_ok", false))
	if kind == "harbor":
		return bool(ctx.get("harbor_ok", false))
	if kind == "border":
		return bool(ctx.get("border_ok", false))
	if kind == "ice":
		return bool(ctx.get("ice_ok", false))
	if kind == "abyss":
		return bool(ctx.get("abyss_ok", false))
	if kind == "king":
		return bool(ctx.get("king_rescued", false))
	return false


func begin(expansion: Dictionary, challenge_id: String, mode: String, session_id: String, ctx: Dictionary, mastery_snap: Dictionary, operation_id: String) -> Dictionary:
	var spec: Dictionary = spec_of(challenge_id)
	if spec.is_empty():
		return {"success": false, "code": "CHALLENGE_LOCKED", "expansion": expansion}
	if not unlocked(spec, ctx):
		return {"success": false, "code": "CHALLENGE_LOCKED", "expansion": expansion}
	if mode != "training" and mode != "official":
		mode = "official"
	var consume := str(spec.get("consume_item", ""))
	var consume_qty := int(spec.get("consume_qty", 0))
	if not consume.is_empty() and mode == "official" and int(ctx.get("fruit", 0)) < consume_qty:
		return {"success": false, "code": "CHALLENGE_LOCKED", "expansion": expansion}
	var row: Dictionary = normalize(expansion.get("challenges", {}))
	if _remember(row, operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	row["active_challenge_id"] = challenge_id
	row["active_session_id"] = session_id
	row["active_mode"] = mode
	row["mastery_snapshot"] = mastery_snap.duplicate(true)
	row["input_snapshot"] = {
		"gold": int(ctx.get("gold", 0)),
		"contribution": int(ctx.get("contribution", 0)),
		"fruit": int(ctx.get("fruit", 0)),
		"level": int(ctx.get("level", 1)),
		"week": int(ctx.get("week", 0)),
	}
	_ledger(row, {"op": "begin", "id": challenge_id, "mode": mode, "operation_id": operation_id})
	return {
		"success": true,
		"code": "OK",
		"expansion": _write(expansion, row),
		"map_id": str(spec.get("map_id", "")),
		"monster_id": str(spec.get("monster_id", "")),
		"consume": not consume.is_empty() and mode == "official",
		"consume_item": consume,
		"consume_qty": consume_qty,
	}


func attach_session(expansion: Dictionary, monster_id: String, session_id: String) -> Dictionary:
	if not is_challenge_unit(monster_id):
		return {"success": false, "code": "NOT_CHALLENGE", "expansion": expansion}
	var row: Dictionary = normalize(expansion.get("challenges", {}))
	if str(row.get("active_challenge_id", "")) != challenge_id_of(monster_id):
		return {"success": false, "code": "CHALLENGE_SESSION", "expansion": expansion}
	row["active_session_id"] = session_id
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}


func settle(expansion: Dictionary, monster_id: String, victory: bool, session_id: String, weekly_ids: Array) -> Dictionary:
	if not is_challenge_unit(monster_id):
		return {"success": false, "code": "NOT_CHALLENGE", "expansion": expansion}
	var row: Dictionary = normalize(expansion.get("challenges", {}))
	if REQUIRE_SESSION and str(row.get("active_session_id", "")) != session_id:
		return {"success": false, "code": "CHALLENGE_SESSION", "expansion": expansion}
	if REQUIRE_VICTORY and not victory:
		return {"success": false, "code": "BATTLE_CANCEL_ADVANCE", "expansion": expansion, "grant_reward": false}
	var cid := str(row.get("active_challenge_id", ""))
	var spec: Dictionary = spec_of(cid)
	if spec.is_empty() or challenge_id_of(monster_id) != cid:
		return {"success": false, "code": "CHALLENGE_LOCKED", "expansion": expansion}
	var snap: Dictionary = row.get("input_snapshot", {})
	if int(spec.get("min_gold", 0)) > 0 and int(snap.get("gold", 0)) < int(spec.get("min_gold", 0)):
		return {"success": false, "code": "CHALLENGE_LOCKED", "expansion": expansion}
	if int(spec.get("min_contribution", 0)) > 0 and int(snap.get("contribution", 0)) < int(spec.get("min_contribution", 0)):
		return {"success": false, "code": "CHALLENGE_LOCKED", "expansion": expansion}
	var need_m := str(spec.get("need_mastery", ""))
	if not need_m.is_empty():
		var ms: Dictionary = row.get("mastery_snapshot", {})
		if int(ms.get(need_m, 0)) < 1:
			return {"success": false, "code": "MASTERY_SNAPSHOT", "expansion": expansion}
	var mode := str(row.get("active_mode", "official"))
	var records: Dictionary = (row.get("records", {}) as Dictionary).duplicate(true)
	records[cid] = int(records.get(cid, 0)) + 1
	row["records"] = records
	var reports: Array = (row.get("reports", []) as Array).duplicate()
	reports.append({"challenge_id": cid, "mode": mode, "victory": true})
	row["reports"] = reports
	var grant_first := false
	var grant_weekly := false
	if mode == "training":
		if not BLOCK_TRAIN_REWARD:
			grant_first = true
	else:
		var first: Dictionary = (row.get("first_claimed", {}) as Dictionary).duplicate(true)
		if first.has(cid):
			if SKIP_FIRST_DUP:
				pass
			else:
				grant_first = true
		else:
			first[cid] = true
			row["first_claimed"] = first
			grant_first = true
		if cid in weekly_ids:
			var wk: Dictionary = (row.get("weekly_claimed", {}) as Dictionary).duplicate(true)
			var week := int(snap.get("week", 0))
			var key := "%s:%d" % [cid, week]
			if wk.has(key) and SKIP_WEEKLY_DUP:
				pass
			elif wk.has(key) and not SKIP_WEEKLY_DUP:
				grant_weekly = true
			else:
				wk[key] = true
				row["weekly_claimed"] = wk
				grant_weekly = true
	row["active_challenge_id"] = ""
	row["active_session_id"] = ""
	row["active_mode"] = ""
	_ledger(row, {"op": "settle", "id": cid, "mode": mode})
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
		"mode": mode,
		"challenge_id": cid,
	}


func clear_session(expansion: Dictionary) -> Dictionary:
	var row: Dictionary = normalize(expansion.get("challenges", {}))
	row["active_challenge_id"] = ""
	row["active_session_id"] = ""
	row["active_mode"] = ""
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}
