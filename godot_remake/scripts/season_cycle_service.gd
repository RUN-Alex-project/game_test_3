extends RefCounted

const RULES_PATH := "res://data/season_rules.json"
const THEME_PATH := "res://data/season_themes.json"
const CONTRACT_PATH := "res://data/season_contracts.json"
const RANK_PATH := "res://data/season_rank_rules.json"
const CYCLE_DAYS := 14
const SKIP_SAME_DAY := true
const USE_GAME_DAY := true
const MAX_DAILY_CONTRACTS := 3
const SETTLE_ON_14 := true
const NEW_SEED_NEXT := true
const HISTORY_CAP := 4
const ENFORCE_DAY := true
const REQUIRE_SAVE_ID := true
const BLOCK_TRAIN_SCORE := true
const SKIP_REWARD_DUP := true
const REQUIRE_RANK_LIVE := true
const REQUIRE_SOURCE := true

var rules: Dictionary = {}
var themes: Array = []
var contracts: Array = []
var by_contract: Dictionary = {}
var rank_rules: Dictionary = {}


func _init() -> void:
	_load(RULES_PATH, true)
	var tf := FileAccess.open(THEME_PATH, FileAccess.READ)
	if tf != null:
		var tp: Variant = JSON.parse_string(tf.get_as_text())
		themes = ((tp if tp is Dictionary else {}).get("themes", []) as Array).duplicate(true)
		tf.close()
	var cf := FileAccess.open(CONTRACT_PATH, FileAccess.READ)
	if cf != null:
		var cp: Variant = JSON.parse_string(cf.get_as_text())
		contracts = ((cp if cp is Dictionary else {}).get("contracts", []) as Array).duplicate(true)
		cf.close()
	for raw: Variant in contracts:
		if raw is Dictionary:
			by_contract[str(raw.get("contract_id", ""))] = raw
	var rf := FileAccess.open(RANK_PATH, FileAccess.READ)
	if rf != null:
		var rp: Variant = JSON.parse_string(rf.get_as_text())
		rank_rules = rp if rp is Dictionary else {}
		rf.close()


func _load(path: String, is_rules: bool) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if is_rules and parsed is Dictionary:
		rules = parsed


func empty_cycle() -> Dictionary:
	return {
		"season_id": 1,
		"theme_id": "theme_harvest",
		"day_index": 1,
		"start_day": 1,
		"seed": 0,
		"daily_contract_ids": [],
		"completed_contract_operation_ids": {},
		"claimed_reward_ids": {},
		"npc_schedule_snapshot": {},
		"season_rank_snapshot": {},
		"epilogue_event_ids": {},
		"last_rollover_day": 0,
		"season_ledger": [],
		"season_history": [],
		"season_mode": "official",
		"daily_gold_granted": 0,
		"season_gold_granted": 0,
		"theme_gold_granted": 0,
	}


func normalize(raw: Variant) -> Dictionary:
	var row: Dictionary = empty_cycle()
	if raw is Dictionary:
		for key in (raw as Dictionary).keys():
			row[key] = (raw as Dictionary)[key]
	for key in empty_cycle().keys():
		if not row.has(key):
			row[key] = empty_cycle()[key]
	if not row.get("completed_contract_operation_ids") is Dictionary:
		row["completed_contract_operation_ids"] = {}
	if not row.get("claimed_reward_ids") is Dictionary:
		row["claimed_reward_ids"] = {}
	if not row.get("npc_schedule_snapshot") is Dictionary:
		row["npc_schedule_snapshot"] = {}
	if not row.get("season_rank_snapshot") is Dictionary:
		row["season_rank_snapshot"] = {}
	if not row.get("epilogue_event_ids") is Dictionary:
		row["epilogue_event_ids"] = {}
	if not row.get("season_ledger") is Array:
		row["season_ledger"] = []
	if not row.get("season_history") is Array:
		row["season_history"] = []
	if not row.get("daily_contract_ids") is Array:
		row["daily_contract_ids"] = []
	row["season_id"] = int(row.get("season_id", 1))
	row["day_index"] = int(row.get("day_index", 1))
	row["start_day"] = int(row.get("start_day", 1))
	row["seed"] = int(row.get("seed", 0))
	return row


func validate_save(state: Dictionary) -> Array:
	var row: Variant = state.get("season", {})
	if not row is Dictionary:
		return []
	var sid: Variant = (row as Dictionary).get("season_id", 1)
	if REQUIRE_SAVE_ID and sid is String:
		return ["SAVE_SEASON"]
	if ENFORCE_DAY:
		var di := int((row as Dictionary).get("day_index", 1))
		if di < 1 or di > CYCLE_DAYS:
			return ["SEASON_DAY"]
	if CYCLE_DAYS != 14:
		return ["SEASON_PERIOD"]
	return []


func validate_rules() -> Array:
	if CYCLE_DAYS != 14:
		return ["SEASON_PERIOD"]
	if int(rules.get("cycle_days", 14)) != 14 and CYCLE_DAYS == 14:
		return ["SEASON_PERIOD"]
	return []


func theme_id_of(season_id: int) -> String:
	if themes.is_empty():
		return "theme_harvest"
	var idx := absi(season_id - 1) % themes.size()
	return str((themes[idx] as Dictionary).get("theme_id", "theme_harvest"))


func daily_ids(seed: int, season_id: int, day_index: int) -> Array:
	var ids: Array = []
	for raw: Variant in contracts:
		if raw is Dictionary:
			ids.append(str(raw.get("contract_id", "")))
	if ids.is_empty():
		return []
	var start := absi(seed + season_id * 17 + day_index * 3) % ids.size()
	var out: Array = []
	var n := MAX_DAILY_CONTRACTS
	if n > ids.size():
		n = ids.size()
	for i in n:
		out.append(ids[(start + i) % ids.size()])
	return out


func _write(expansion: Dictionary, row: Dictionary) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var season: Dictionary = {}
	if state.get("season") is Dictionary:
		season = (state["season"] as Dictionary).duplicate(true)
	for key in row.keys():
		season[key] = row[key]
	state["season"] = season
	return state


func ensure(expansion: Dictionary, current_day: int, world_seed: int) -> Dictionary:
	var row: Dictionary = normalize(expansion.get("season", {}))
	if int(row.get("seed", 0)) == 0:
		row["seed"] = world_seed if USE_GAME_DAY else int(Time.get_ticks_usec())
	if int(row.get("start_day", 0)) <= 0:
		row["start_day"] = maxi(1, current_day)
	row["theme_id"] = theme_id_of(int(row.get("season_id", 1)))
	if (row.get("daily_contract_ids", []) as Array).is_empty():
		row["daily_contract_ids"] = daily_ids(int(row.seed), int(row.season_id), int(row.day_index))
	return _write(expansion, row)


func rollover(expansion: Dictionary, current_day: int, world_seed: int) -> Dictionary:
	var row: Dictionary = normalize(expansion.get("season", {}))
	if SKIP_SAME_DAY and int(row.get("last_rollover_day", 0)) == current_day:
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var start := int(row.get("start_day", 1))
	if start <= 0:
		start = 1
		row["start_day"] = 1
	var elapsed := current_day - start
	if elapsed >= CYCLE_DAYS:
		if SETTLE_ON_14:
			var hist: Array = (row.get("season_history", []) as Array).duplicate()
			hist.append({"season_id": int(row.season_id), "theme_id": str(row.theme_id), "ended_day": current_day})
			var cap := HISTORY_CAP
			while hist.size() > cap:
				hist.remove_at(0)
			row["season_history"] = hist
			row["season_id"] = int(row.season_id) + 1
			if NEW_SEED_NEXT:
				row["seed"] = int(row.seed) + 7919 + int(row.season_id)
			row["start_day"] = current_day
			row["day_index"] = 1
			row["daily_gold_granted"] = 0
			row["season_gold_granted"] = 0
			row["theme_gold_granted"] = 0
			row["completed_contract_operation_ids"] = {}
			row["claimed_reward_ids"] = {}
		else:
			row["day_index"] = CYCLE_DAYS
	else:
		row["day_index"] = elapsed + 1
	if not USE_GAME_DAY:
		row["seed"] = int(Time.get_ticks_usec())
	row["theme_id"] = theme_id_of(int(row.season_id))
	row["daily_contract_ids"] = daily_ids(int(row.seed), int(row.season_id), int(row.day_index))
	row["last_rollover_day"] = current_day
	var ledger: Array = (row.get("season_ledger", []) as Array).duplicate()
	ledger.append({"op": "rollover", "day": current_day, "index": int(row.day_index)})
	row["season_ledger"] = ledger
	return {"success": true, "code": "OK", "expansion": _write(expansion, row)}


func source_ready(ctx: Dictionary, source: String) -> bool:
	match source:
		"market":
			return int(ctx.get("gold", 0)) >= 1
		"territory":
			return not str(ctx.get("owned_territory", "")).is_empty()
		"challenge":
			return int(ctx.get("challenge_first", 0)) > 0
		"pet":
			return int(ctx.get("pet_claimed", 0)) > 0
		"abyss":
			return bool(ctx.get("abyss_ok", false))
	return false


func complete_contract(expansion: Dictionary, contract_id: String, ctx: Dictionary, operation_id: String) -> Dictionary:
	var row: Dictionary = normalize(expansion.get("season", {}))
	var ops: Dictionary = (row.get("completed_contract_operation_ids", {}) as Dictionary).duplicate(true)
	if ops.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var daily: Array = row.get("daily_contract_ids", [])
	if not contract_id in daily:
		return {"success": false, "code": "CONTRACT_CAP", "expansion": expansion}
	if not by_contract.has(contract_id):
		return {"success": false, "code": "CONTRACT_SOURCE", "expansion": expansion}
	var spec: Dictionary = by_contract[contract_id]
	var src := str(spec.get("source", ""))
	if REQUIRE_SOURCE and not source_ready(ctx, src):
		return {"success": false, "code": "CONTRACT_SOURCE", "expansion": expansion}
	var gold := int(spec.get("gold", 0))
	var claimed: Dictionary = (row.get("claimed_reward_ids", {}) as Dictionary).duplicate(true)
	var rid := "daily:%s:%d:%d" % [contract_id, int(row.season_id), int(row.day_index)]
	if claimed.has(rid) and SKIP_REWARD_DUP:
		return {"success": false, "code": "SEASON_REWARD", "expansion": expansion}
	if BLOCK_TRAIN_SCORE and str(row.get("season_mode", "official")) != "official":
		gold = 0
	var daily_cap := int(rules.get("daily_reward_gold_cap", 10))
	var season_cap := int(rules.get("season_reward_gold_cap", 40))
	var theme_cap := int(rules.get("theme_reward_gold_cap", 20))
	gold = mini(gold, maxi(0, daily_cap - int(row.get("daily_gold_granted", 0))))
	gold = mini(gold, maxi(0, season_cap - int(row.get("season_gold_granted", 0))))
	gold = mini(gold, maxi(0, theme_cap - int(row.get("theme_gold_granted", 0))))
	claimed[rid] = true
	row["claimed_reward_ids"] = claimed
	ops[operation_id] = true
	row["completed_contract_operation_ids"] = ops
	row["daily_gold_granted"] = int(row.get("daily_gold_granted", 0)) + gold
	row["season_gold_granted"] = int(row.get("season_gold_granted", 0)) + gold
	row["theme_gold_granted"] = int(row.get("theme_gold_granted", 0)) + gold
	var score := gold
	var snap: Dictionary = (row.get("season_rank_snapshot", {}) as Dictionary).duplicate(true)
	if REQUIRE_RANK_LIVE:
		if score > 0:
			snap["score"] = int(snap.get("score", 0)) + score + int(ctx.get("gold", 0)) / int(rank_rules.get("gold_div", 100))
		snap["text"] = "live:%d" % int(snap.get("score", 0))
		snap["live"] = true
	else:
		snap["score"] = 999
		snap["text"] = "fixed"
		snap["live"] = false
	row["season_rank_snapshot"] = snap
	var ledger: Array = (row.get("season_ledger", []) as Array).duplicate()
	ledger.append({"op": "contract", "id": contract_id, "operation_id": operation_id})
	row["season_ledger"] = ledger
	return {"success": true, "code": "OK", "expansion": _write(expansion, row), "gold": gold}


func claim_mail(expansion: Dictionary, operation_id: String) -> Dictionary:
	var row: Dictionary = normalize(expansion.get("season", {}))
	var ops: Dictionary = (row.get("completed_contract_operation_ids", {}) as Dictionary).duplicate(true)
	if ops.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var claimed: Dictionary = (row.get("claimed_reward_ids", {}) as Dictionary).duplicate(true)
	var mid := "mail:%d:%d" % [int(row.season_id), int(row.day_index)]
	if claimed.has(mid) and SKIP_REWARD_DUP:
		return {"success": false, "code": "CONTRACT_MAIL", "expansion": expansion}
	claimed[mid] = true
	row["claimed_reward_ids"] = claimed
	ops[operation_id] = true
	row["completed_contract_operation_ids"] = ops
	return {
		"success": true,
		"code": "OK",
		"expansion": _write(expansion, row),
		"gold": int(rules.get("mail_gold", 2)),
	}
