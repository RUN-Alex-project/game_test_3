extends Node

const LIN := "npc_adv_lin_xia"
const YE := "npc_adv_ye_fei"
const LIANG := "npc_adv_liang_chen"

var _errors: Array = []


func _ready() -> void:
	if GameState == null:
		print("REGISTRY_FAIL: TERRITORY_ID_MISMATCH GameState missing")
		get_tree().quit(1)
		return
	_assert_registry()
	_assert_settle_and_codes()
	_assert_castle_and_ledger()
	_assert_assignments()
	_assert_events_and_seed()
	_assert_ranking()
	_assert_save_load()
	_finish()


func _reset() -> void:
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	GameState.current_day = 1
	GameState.gold = 10000
	GameState.magic_stones = 10000
	GameState.owned_territory = ""
	GameState.nobility_merit = 0
	GameState._initialize_inventory()
	GameState.refresh_rankings()


func _econ() -> Dictionary:
	return GameState.expansion_state.get("territory_economy", {})


func _props() -> Dictionary:
	return GameState.expansion_state.get("properties", {})


func _row(map_id: String) -> Dictionary:
	var raw: Variant = _econ().get("territories", {}).get(map_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func _stock(map_id: String, resource_id: String) -> int:
	return int(_row(map_id).get("stocks", {}).get(resource_id, 0))


func _assert_registry() -> void:
	var report: Dictionary = GameState.expansion_state_service.validate_data_files()
	for err in report.get("errors", []):
		_fail_raw(str(err))
	var prod: Dictionary = {}
	for map_id in GameState.expansion_state_service.territory_economy_service.territory_service.territories.keys():
		prod[str(map_id)] = true
	var data_ids: Dictionary = {}
	for map_id in GameState.expansion_state_service.territory_economy_service.spec_by_map.keys():
		data_ids[str(map_id)] = true
	if prod.size() != 6 or data_ids.size() != 6:
		_fail("TERRITORY_ID_MISMATCH", "size prod=%d data=%d" % [prod.size(), data_ids.size()])
	for map_id in prod.keys():
		if not data_ids.has(str(map_id)):
			_fail("TERRITORY_ID_MISMATCH", "missing data %s" % str(map_id))
	for map_id in data_ids.keys():
		if not prod.has(str(map_id)):
			_fail("TERRITORY_ID_MISMATCH", "extra data %s" % str(map_id))
	if GameState.has_method("transfer_item_to_npc"):
		_fail("TERRITORY_ID_MISMATCH", "transfer_item_to_npc exists")


func _assert_settle_and_codes() -> void:
	_reset()
	var unowned: Dictionary = GameState.expansion_state_service.territory_economy_service.settle_ended_day(
		GameState.expansion_state, 1, "")
	if str(unowned.get("code", "")) != "TERRITORY_NOT_OWNED":
		_fail("TERRITORY_NOT_OWNED", str(unowned.get("code")))
	if _stock("cassano_city", "gold") != 0:
		_fail("TERRITORY_NOT_OWNED", "unowned stock %d" % _stock("cassano_city", "gold"))
	GameState.owned_territory = "cassano_city"
	var locked_state: Dictionary = GameState.expansion_state.duplicate(true)
	var locked_econ: Dictionary = GameState.expansion_state_service.territory_economy_service.normalize(locked_state.get("territory_economy", {}))
	var locked_maps: Dictionary = (locked_econ.get("territories", {}) as Dictionary).duplicate(true)
	var locked_row: Dictionary = (locked_maps.get("cassano_city", {}) as Dictionary).duplicate(true)
	locked_row["locked"] = true
	locked_maps["cassano_city"] = locked_row
	locked_econ["territories"] = locked_maps
	locked_state["territory_economy"] = locked_econ
	var locked: Dictionary = GameState.expansion_state_service.territory_economy_service.settle_ended_day(
		locked_state, 1, "cassano_city")
	if str(locked.get("code", "")) != "TERRITORY_LOCKED":
		_fail("TERRITORY_LOCKED", str(locked.get("code")))
	var first: Dictionary = GameState.advance_day()
	var produced := _stock("cassano_city", "gold")
	if produced <= 0:
		_fail("TERRITORY_NOT_OWNED", "owned produced 0")
	var replay: Dictionary = GameState.expansion_state_service.territory_economy_service.settle_ended_day(
		GameState.expansion_state, 1, "cassano_city")
	if str(replay.get("code", "")) != "ALREADY_APPLIED":
		_fail("TERRITORY_DUP_SETTLE", str(replay.get("code")))
	if _stock("cassano_city", "gold") != produced:
		_fail("TERRITORY_DUP_SETTLE", "dup stock %d" % _stock("cassano_city", "gold"))
	var cap := int(GameState.expansion_state_service.territory_economy_service.spec_of("cassano_city").get("stock_cap", 80))
	var cap_state: Dictionary = GameState.expansion_state.duplicate(true)
	var cap_econ: Dictionary = GameState.expansion_state_service.territory_economy_service.normalize(cap_state.get("territory_economy", {}))
	var cap_maps: Dictionary = (cap_econ.get("territories", {}) as Dictionary).duplicate(true)
	var cap_row: Dictionary = (cap_maps.get("cassano_city", {}) as Dictionary).duplicate(true)
	cap_row["stocks"] = {"gold": cap}
	cap_maps["cassano_city"] = cap_row
	cap_econ["territories"] = cap_maps
	cap_econ["last_settlement_day"] = 0
	cap_state["territory_economy"] = cap_econ
	var capped: Dictionary = GameState.expansion_state_service.territory_economy_service.settle_ended_day(
		cap_state, 2, "cassano_city")
	if str(capped.get("code", "")) != "TERRITORY_STOCK_CAP":
		_fail("TERRITORY_STOCK_CAP", str(capped.get("code")))
	var cap_after := int(capped.expansion.get("territory_economy", {}).get("territories", {}).get("cassano_city", {}).get("stocks", {}).get("gold", 0))
	if cap_after > cap:
		_fail("TERRITORY_STOCK_CAP", "exceeded %d>%d" % [cap_after, cap])
	_reset()
	GameState.owned_territory = "thunder_continent"
	GameState.advance_day()
	var props: Dictionary = GameState.expansion_state_service.property_service.normalize(_props())
	props["warehouse"] = {"fruit": GameState.expansion_state_service.property_service.warehouse_cap(props)}
	GameState.expansion_state["properties"] = props
	var packed: Dictionary = GameState.collect_territory_output("thunder_continent", "collect_full")
	if str(packed.get("code", "")) != "PROPERTY_WAREHOUSE_FULL":
		_fail("PROPERTY_WAREHOUSE_FULL", str(packed.get("code")))
	if _stock("thunder_continent", "soul_crystal") <= 0:
		_fail("PROPERTY_WAREHOUSE_FULL", "output swallowed")
	var codes := PackedStringArray([
		str(unowned.get("code", "")),
		str(locked.get("code", "")),
		str(capped.get("code", "")),
		str(packed.get("code", "")),
	])
	if codes[0] == codes[1] or codes[0] == codes[2] or codes[0] == codes[3] or codes[1] == codes[2] or codes[1] == codes[3] or codes[2] == codes[3]:
		_fail("TERRITORY_LOCKED", "codes not distinct %s" % str(codes))
	if first.is_empty():
		_fail("TERRITORY_NOT_OWNED", "advance_day empty")


func _assert_castle_and_ledger() -> void:
	_reset()
	GameState.owned_territory = "cassano_city"
	var gold0 := GameState.gold
	var up1: Dictionary = GameState.upgrade_castle("up1")
	if not bool(up1.get("success", false)):
		_fail("PROPERTY_UPGRADE_ATOMIC", str(up1.get("code")))
		return
	if int(_props().get("castle_level", 0)) != 2:
		_fail("PROPERTY_UPGRADE_ATOMIC", "level %s" % str(_props().get("castle_level")))
	if GameState.gold != gold0 - 200:
		_fail("PROPERTY_UPGRADE_ATOMIC", "gold %d" % GameState.gold)
	var replay: Dictionary = GameState.upgrade_castle("up1")
	if not bool(replay.get("replayed", false)):
		_fail("PROPERTY_DUP_UPGRADE", str(replay.get("code")))
	if int(_props().get("castle_level", 0)) != 2:
		_fail("PROPERTY_DUP_UPGRADE", "level after replay %s" % str(_props().get("castle_level")))
	GameState.gold = 0
	var failed: Dictionary = GameState.upgrade_castle("up2")
	if str(failed.get("code", "")) != "PROPERTY_UPGRADE_ATOMIC":
		_fail("PROPERTY_UPGRADE_ATOMIC", "fail code %s" % str(failed.get("code")))
	if int(_props().get("castle_level", 0)) != 2 or GameState.gold != 0:
		_fail("PROPERTY_UPGRADE_ATOMIC", "fail mutated level/gold")
	GameState.gold = 10000
	GameState.advance_day()
	var produced := _stock("cassano_city", "gold")
	var found := false
	for raw_row: Variant in _econ().get("ledger", []):
		if raw_row is Dictionary and str(raw_row.get("operation_id", "")) == "settle:1:cassano_city":
			found = true
			if int(raw_row.get("qty_delta", 0)) != produced:
				_fail("LEDGER_AMOUNT", "delta %s vs %d" % [str(raw_row.get("qty_delta")), produced])
	if not found:
		_fail("LEDGER_AMOUNT", "missing settle ledger")


func _assert_assignments() -> void:
	_reset()
	GameState.owned_territory = "cassano_city"
	var a1: Dictionary = GameState.assign_adventurer(LIN, "steward", "asg_lin")
	if not bool(a1.get("success", false)):
		_fail("ASSIGNMENT_BUSY", "lin %s" % str(a1.get("code")))
		return
	var a2: Dictionary = GameState.assign_adventurer(YE, "foreman", "asg_ye")
	if not bool(a2.get("success", false)):
		_fail("ASSIGNMENT_BUSY", "ye %s" % str(a2.get("code")))
	var dup: Dictionary = GameState.assign_adventurer(LIN, "foreman", "asg_lin2")
	if str(dup.get("code", "")) != "ASSIGNMENT_DOUBLE_POST":
		_fail("ASSIGNMENT_DOUBLE_POST", str(dup.get("code")))
	var ids: Dictionary = {}
	for raw_row: Variant in _props().get("assignments", []):
		if raw_row is Dictionary:
			var asg_id := str(raw_row.get("assignment_id", ""))
			if ids.has(asg_id):
				_fail("SAVE_DUP_ASSIGNMENT", asg_id)
			ids[asg_id] = true
	_reset()
	GameState.begin_arena_match(LIANG, "practice", "busy_arena")
	var busy: Dictionary = GameState.assign_adventurer(LIANG, "quartermaster", "asg_busy")
	if str(busy.get("code", "")) != "ASSIGNMENT_BUSY":
		_fail("ASSIGNMENT_BUSY", str(busy.get("code")))
	_reset()
	GameState.owned_territory = "cassano_city"
	GameState.assign_adventurer(LIN, "steward", "asg_rel0")
	GameState.advance_day()
	var qty_low := _stock("cassano_city", "gold")
	_reset()
	GameState.owned_territory = "cassano_city"
	GameState.expansion_state["relationships"][LIN]["value"] = 2
	GameState.assign_adventurer(LIN, "steward", "asg_rel2")
	GameState.advance_day()
	var qty_high := _stock("cassano_city", "gold")
	if qty_high != qty_low + 1:
		_fail("ASSIGNMENT_BUSY", "rel bonus %d vs %d" % [qty_high, qty_low])
	_reset()
	GameState.owned_territory = "cassano_city"
	GameState.assign_adventurer(LIN, "steward", "asg_expire")
	for _i in 3:
		GameState.advance_day()
	var still_active := false
	for raw_row: Variant in _props().get("assignments", []):
		if raw_row is Dictionary and str(raw_row.get("assignment_id", "")) == str(GameState.expansion_state.get("properties", {}).get("assignments", [{}])[0].get("assignment_id", "")):
			if str(raw_row.get("status", "")) == "active":
				still_active = true
	# After duration_days=3, start_day=1 end_day=4; three advances ended 1,2,3 still active; need 4th
	GameState.advance_day()
	still_active = false
	for raw_row: Variant in _props().get("assignments", []):
		if raw_row is Dictionary and str(raw_row.get("status", "")) == "active":
			still_active = true
	if still_active:
		_fail("ASSIGNMENT_DOUBLE_POST", "assignment not expired")


func _assert_events_and_seed() -> void:
	_reset()
	GameState.owned_territory = "cassano_city"
	GameState.advance_day()
	var event_id := str(_row("cassano_city").get("pending_event_id", ""))
	if event_id.is_empty():
		_fail("TERRITORY_DUP_EVENT", "no event")
		return
	var ok: Dictionary = GameState.resolve_territory_event("cassano_city", "handle", "evt_ok")
	if not bool(ok.get("success", false)):
		_fail("TERRITORY_DUP_EVENT", "handle %s" % str(ok.get("code")))
	var dup: Dictionary = GameState.resolve_territory_event("cassano_city", "handle", "evt_dup")
	if str(dup.get("code", "")) != "TERRITORY_DUP_EVENT":
		_fail("TERRITORY_DUP_EVENT", str(dup.get("code")))
	_reset()
	GameState.owned_territory = "cassano_city"
	GameState.gold = 0
	GameState.advance_day()
	var fail_evt: Dictionary = GameState.resolve_territory_event("cassano_city", "fail_pay", "evt_fail")
	if str(fail_evt.get("code", "")) != "TERRITORY_EVENT_FAIL":
		_fail("TERRITORY_EVENT_FAIL", str(fail_evt.get("code")))
	if GameState.gold != 0:
		_fail("TERRITORY_EVENT_FAIL", "gold consumed on fail")
	var service = GameState.expansion_state_service.territory_economy_service
	var seed_a: Dictionary = GameState.expansion_state_service.default_enabled_state()
	seed_a["world_seed"] = 1
	var seed_b: Dictionary = GameState.expansion_state_service.default_enabled_state()
	seed_b["world_seed"] = 2
	var ra: Dictionary = service.settle_ended_day(seed_a, 1, "cassano_city")
	var rb: Dictionary = service.settle_ended_day(seed_b, 1, "cassano_city")
	var roll_a := int(ra.expansion.get("territory_economy", {}).get("territories", {}).get("cassano_city", {}).get("event_roll", 0))
	var roll_b := int(rb.expansion.get("territory_economy", {}).get("territories", {}).get("cassano_city", {}).get("event_roll", 0))
	if roll_a == roll_b:
		_fail("TERRITORY_SEED_DRIFT", "rolls %d" % roll_a)
	var rare_seed := 0
	while rare_seed < 5000:
		if (service.mix(rare_seed, 1, "territory_event", "cassano_city", 0) % 100) < int(service.rules.get("rare_weight", 10)):
			break
		rare_seed += 1
	var rare_state: Dictionary = GameState.expansion_state_service.default_enabled_state()
	rare_state["world_seed"] = rare_seed
	var rare_settle: Dictionary = service.settle_ended_day(rare_state, 1, "cassano_city")
	var rare_id := str(rare_settle.expansion.get("territory_economy", {}).get("territories", {}).get("cassano_city", {}).get("pending_event_id", ""))
	var rare_row: Dictionary = service.events_by_id.get(rare_id, {})
	if str(rare_row.get("rarity", "")) != "rare":
		_fail("TERRITORY_DUP_EVENT", "rare not triggered %s" % rare_id)
	_reset()
	GameState.owned_territory = "cassano_city"
	GameState.advance_day()
	GameState.resolve_territory_event("cassano_city", "handle", "cool1")
	var cool_until := int(_row("cassano_city").get("event_cooldown_until", 0))
	GameState.advance_day()
	if GameState.current_day <= cool_until and not str(_row("cassano_city").get("pending_event_id", "")).is_empty() and int(_row("cassano_city").get("last_event_day", 0)) == 2:
		_fail("TERRITORY_DUP_EVENT", "cooldown ignored")


func _assert_ranking() -> void:
	_reset()
	GameState.owned_territory = "cassano_city"
	GameState.refresh_rankings()
	var board: Dictionary = GameState.get_ranking_board("territory_contribution")
	if bool(board.get("preview", false)):
		_fail("TERRITORY_ID_MISMATCH", "territory board still preview")
	var player_row := {}
	for raw_row: Variant in board.get("entries", []):
		if raw_row is Dictionary and str(raw_row.get("id", "")) == "player":
			player_row = raw_row
			break
	if int(player_row.get("primary", -1)) != 1:
		_fail("TERRITORY_ID_MISMATCH", "owned fallback %s" % str(player_row))
	GameState.advance_day()
	GameState.refresh_rankings()
	board = GameState.get_ranking_board("territory_contribution")
	for raw_row: Variant in board.get("entries", []):
		if raw_row is Dictionary and str(raw_row.get("id", "")) == "player":
			player_row = raw_row
			break
	if int(player_row.get("primary", 0)) != int(_econ().get("contribution", 0)):
		_fail("TERRITORY_ID_MISMATCH", "contrib rank %s vs %s" % [str(player_row.get("primary")), str(_econ().get("contribution"))])


func _assert_save_load() -> void:
	_reset()
	GameState.owned_territory = "cassano_city"
	GameState.assign_adventurer(LIN, "steward", "save_lin")
	GameState.upgrade_castle("save_up")
	GameState.advance_day()
	GameState.resolve_territory_event("cassano_city", "handle", "save_evt")
	var before_snap := _persist_snap()
	GameState.save_path = "user://test_v147_property.json"
	if not GameState.save_game():
		_fail("SAVE_NEG_STOCK", "save failed")
		return
	GameState.owned_territory = ""
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	if not GameState.load_game():
		_fail("SAVE_NEG_STOCK", "load failed")
		return
	var after_snap := _persist_snap()
	if after_snap != before_snap:
		_fail("SAVE_NEG_STOCK", "economy drifted %s vs %s" % [before_snap, after_snap])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.save_path))
	GameState.save_path = GameState.SAVE_PATH
	var bad: Dictionary = GameState.expansion_state.duplicate(true)
	var bad_econ: Dictionary = GameState.expansion_state_service.territory_economy_service.normalize(bad.get("territory_economy", {}))
	var bad_maps: Dictionary = (bad_econ.get("territories", {}) as Dictionary).duplicate(true)
	var bad_row: Dictionary = (bad_maps.get("cassano_city", {}) as Dictionary).duplicate(true)
	bad_row["stocks"] = {"gold": -1}
	bad_maps["cassano_city"] = bad_row
	bad_econ["territories"] = bad_maps
	bad["territory_economy"] = bad_econ
	if not GameState.expansion_state_service.build_from_save(bad).is_empty():
		_fail("SAVE_NEG_STOCK", "negative stock accepted")


func _persist_snap() -> String:
	var asg_ids: Array[String] = []
	for raw_row: Variant in _props().get("assignments", []):
		if raw_row is Dictionary:
			asg_ids.append("%s:%s:%s" % [
				str(raw_row.get("assignment_id", "")),
				str(raw_row.get("adventurer_id", "")),
				str(raw_row.get("status", "")),
			])
	asg_ids.sort()
	var ledger_ids: Array[String] = []
	for raw_row: Variant in _econ().get("ledger", []):
		if raw_row is Dictionary:
			ledger_ids.append(str(raw_row.get("operation_id", "")))
	ledger_ids.sort()
	return "%d|%d|%d|%s|%s|%s|%s" % [
		int(_props().get("castle_level", 0)),
		int(_econ().get("contribution", 0)),
		_stock("cassano_city", "gold"),
		str(_row("cassano_city").get("pending_event_id", "")),
		str(_row("cassano_city").get("event_resolved", false)),
		",".join(asg_ids),
		",".join(ledger_ids),
	]


func _fail(code: String, detail: String) -> void:
	_errors.append("%s %s" % [code, detail])


func _fail_raw(err: String) -> void:
	_errors.append(err)


func _finish() -> void:
	if _errors.size() > 0:
		print("REGISTRY_FAIL: " + "; ".join(_errors))
		get_tree().quit(1)
		return
	print("PASS property_territory_economy: six lands, settle, caps, castle, assignments, events, ranking, save")
	get_tree().quit(0)
