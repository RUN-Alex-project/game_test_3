extends Node

var _errors: Array = []
var _main: Node = null
var _ops: int = 0


func _op(tag: String) -> String:
	_ops += 1
	return "%s:%d" % [tag, _ops]


func _ready() -> void:
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_cycle()
	_assert_contracts()
	_assert_epilogue()
	_assert_save()
	_assert_adjacent()
	_finish()


func _fail(code: String, detail: String = "") -> void:
	_errors.append(code)
	print(code)
	if not detail.is_empty():
		print(detail)


func _reset() -> void:
	GameState.gold = 50
	GameState.level = 30
	GameState.current_day = 1
	GameState.owned_territory = ""
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	GameState.expansion_state = GameState.expansion_state_service.season_cycle_service.ensure(
		GameState.expansion_state, 1, int(GameState.expansion_state.get("world_seed", 1)))


func _svc():
	return GameState.expansion_state_service.season_cycle_service


func _assert_cycle() -> void:
	_reset()
	if _svc().CYCLE_DAYS != 14 or _svc().themes.size() < 2:
		_fail("SEASON_PERIOD")
	var row: Dictionary = GameState.season_runtime()
	if int(row.get("day_index", 0)) < 1 or int(row.get("day_index", 0)) > 14:
		_fail("SEASON_DAY")
	var probe: Dictionary = GameState.expansion_state.duplicate(true)
	var se: Dictionary = (probe.get("season", {}) as Dictionary).duplicate(true)
	se["day_index"] = 99
	probe["season"] = se
	var verr: Array = _svc().validate_save(probe)
	if verr.is_empty() or str(verr[0]) != "SEASON_DAY":
		_fail("SEASON_DAY", str(verr))
	var n0 := (GameState.season_runtime().get("season_ledger", []) as Array).size()
	GameState.season_rollover()
	var n1 := (GameState.season_runtime().get("season_ledger", []) as Array).size()
	GameState.season_rollover()
	var n2 := (GameState.season_runtime().get("season_ledger", []) as Array).size()
	if n2 > n1:
		_fail("SEASON_ROLLOVER")
	var s0 := int(GameState.season_runtime().get("seed", 0))
	GameState.advance_day()
	var s1 := int(GameState.season_runtime().get("seed", 0))
	if s1 != s0:
		_fail("SEASON_CLOCK")
	var daily: Array = GameState.season_runtime().get("daily_contract_ids", [])
	if daily.size() > 3:
		_fail("CONTRACT_CAP")
	_reset()
	var sid0 := int(GameState.season_runtime().get("season_id", 1))
	var seed0 := int(GameState.season_runtime().get("seed", 0))
	for _i in 14:
		GameState.advance_day()
	var after: Dictionary = GameState.season_runtime()
	if int(after.get("season_id", 0)) != sid0 + 1:
		_fail("SEASON_SETTLE", str(after.get("season_id", 0)))
	if (after.get("season_history", []) as Array).is_empty():
		_fail("SEASON_SETTLE", "hist")
	if int(after.get("seed", 0)) == seed0:
		_fail("SEASON_SEED")
	if str(after.get("theme_id", "")) == "theme_harvest":
		_fail("SEASON_SETTLE", "theme")
	for _j in 56:
		GameState.advance_day()
	if (GameState.season_runtime().get("season_history", []) as Array).size() > 4:
		_fail("SEASON_HISTORY")


func _assert_contracts() -> void:
	_reset()
	GameState.gold = 0
	var daily: Array = GameState.season_runtime().get("daily_contract_ids", [])
	if daily.is_empty():
		_fail("CONTRACT_CAP", "empty")
		return
	var poor: Dictionary = GameState.complete_season_contract(str(daily[0]), _op("poor"))
	if bool(poor.get("success", false)) or str(poor.get("code", "")) != "CONTRACT_SOURCE":
		_fail("CONTRACT_SOURCE")
	_reset()
	GameState.seed_season_prereqs()
	for cid in ["sc_market", "sc_territory", "sc_challenge", "sc_pet", "sc_abyss"]:
		var live_src: Dictionary = GameState.expansion_state.duplicate(true)
		var se_src: Dictionary = (live_src.get("season", {}) as Dictionary).duplicate(true)
		se_src["daily_contract_ids"] = [cid]
		live_src["season"] = se_src
		GameState.expansion_state = live_src
		var src_ok: Dictionary = GameState.complete_season_contract(str(cid), _op("src%s" % cid))
		if not bool(src_ok.get("success", false)):
			_fail("CONTRACT_SOURCE", "%s %s" % [cid, str(src_ok.get("code", ""))])
	_reset()
	GameState.seed_season_prereqs()
	daily = GameState.season_runtime().get("daily_contract_ids", [])
	var gold0 := GameState.gold
	var ok: Dictionary = GameState.complete_season_contract(str(daily[0]), _op("c1"))
	if not bool(ok.get("success", false)):
		_fail("CONTRACT_SOURCE", str(ok.get("code", "")))
	if GameState.gold < gold0:
		_fail("SEASON_REWARD", "gold")
	var dup: Dictionary = GameState.complete_season_contract(str(daily[0]), _op("c1dup"))
	if bool(dup.get("success", false)) or str(dup.get("code", "")) != "SEASON_REWARD":
		_fail("SEASON_REWARD")
	var live: Dictionary = GameState.expansion_state.duplicate(true)
	var se: Dictionary = (live.get("season", {}) as Dictionary).duplicate(true)
	se["season_mode"] = "training"
	live["season"] = se
	GameState.expansion_state = live
	var snap0 := int((GameState.season_runtime().get("season_rank_snapshot", {}) as Dictionary).get("score", 0))
	if daily.size() > 1:
		var tr: Dictionary = GameState.complete_season_contract(str(daily[1]), _op("train"))
		var snap1 := int((GameState.season_runtime().get("season_rank_snapshot", {}) as Dictionary).get("score", 0))
		if bool(tr.get("success", false)) and snap1 > snap0:
			_fail("SEASON_TRAIN")
	var snap: Dictionary = GameState.season_runtime().get("season_rank_snapshot", {})
	if str(snap.get("text", "")) == "fixed" or not bool(snap.get("live", true)):
		_fail("RANK_TEXT")
	_reset()
	GameState.seed_season_prereqs()
	var mail: Dictionary = GameState.claim_season_mail(_op("mail"))
	if not bool(mail.get("success", false)):
		_fail("CONTRACT_MAIL", str(mail.get("code", "")))
	var mail2: Dictionary = GameState.claim_season_mail(_op("mail2"))
	if bool(mail2.get("success", false)) or str(mail2.get("code", "")) != "CONTRACT_MAIL":
		_fail("CONTRACT_MAIL")


func _assert_epilogue() -> void:
	_reset()
	var locked: Dictionary = GameState.run_epilogue_event("ep_lin", _op("eplock"))
	if bool(locked.get("success", false)) or str(locked.get("code", "")) != "EPILOGUE_LOCK":
		_fail("EPILOGUE_LOCK")
	GameState.seed_season_prereqs()
	var before := int((GameState.expansion_state.get("relationships", {}).get("npc_adv_lin_xia", {}) as Dictionary).get("value", 0))
	var ok: Dictionary = GameState.run_epilogue_event("ep_lin", _op("eplin"))
	if not bool(ok.get("success", false)):
		_fail("EPILOGUE_LOCK", str(ok.get("code", "")))
	var after := int((GameState.expansion_state.get("relationships", {}).get("npc_adv_lin_xia", {}) as Dictionary).get("value", 0))
	if after - before >= 100:
		_fail("EPILOGUE_REL")
	for eid in ["ep_su", "ep_qin", "ep_ye", "ep_liang", "ep_jiang", "ep_gu", "ep_bai"]:
		var r: Dictionary = GameState.run_epilogue_event(str(eid), _op("ep%s" % eid))
		if not bool(r.get("success", false)):
			_fail("EPILOGUE_LOCK", "%s %s" % [eid, str(r.get("code", ""))])


func _assert_save() -> void:
	_reset()
	GameState.seed_season_prereqs()
	GameState.advance_day()
	if not GameState.save_game():
		_fail("SAVE_SEASON", "save")
	var before: Dictionary = GameState.season_runtime().duplicate(true)
	if not GameState.load_game():
		_fail("SAVE_SEASON", "load")
	if int(GameState.season_runtime().get("season_id", 0)) != int(before.get("season_id", -1)):
		_fail("SAVE_SEASON", "id")
	var probe: Dictionary = GameState.expansion_state.duplicate(true)
	var se: Dictionary = (probe.get("season", {}) as Dictionary).duplicate(true)
	se["season_id"] = "bad"
	probe["season"] = se
	var verr: Array = _svc().validate_save(probe)
	if verr.is_empty() or str(verr[0]) != "SAVE_SEASON":
		_fail("SAVE_SEASON")
	if GameState.SAVE_SCHEMA_KEYS.size() != 39:
		_fail("SAVE_SEASON", "schema")


func _assert_adjacent() -> void:
	_reset()
	GameState.seed_pet_endgame_prereqs()
	var col: Dictionary = GameState.claim_collection_reward("col_year_pig", _op("adjcol"))
	if not bool(col.get("success", false)):
		_fail("SEASON_PERIOD", str(col.get("code", "")))
	if _main.world.maps.size() != 50:
		_fail("SEASON_PERIOD", "maps")
	var gro := 0
	_main._open_actor_dialogue("grocery")
	for child in _main.dialogue_panel.choices.get_children():
		if child is Button:
			gro += 1
	if gro != 3:
		_fail("SEASON_PERIOD", "grocery")
	if not GameState.expansion_state.get("season", {}).has("arena_seed_state"):
		_fail("SAVE_SEASON", "arena")


func _finish() -> void:
	if _errors.is_empty():
		print("PASS season epilogue")
		get_tree().quit(0)
	else:
		print("FAIL %s" % ",".join(_errors))
		get_tree().quit(1)
