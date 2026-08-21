extends Node

const LongFlowServiceScript = preload("res://scripts/long_flow_service.gd")
const CombatServiceScript = preload("res://scripts/combat_service.gd")

var _errors: Array = []
var _ops: int = 0
var _svc
var _combat
var _main: Node = null
var _leak: Node = null


func _op(tag: String) -> String:
	_ops += 1
	return "%s:%d" % [tag, _ops]


func _fail(code: String, detail: String = "") -> void:
	_errors.append(code)
	print(code)
	if not detail.is_empty():
		print(detail)


func _ready() -> void:
	_svc = LongFlowServiceScript.new()
	_combat = CombatServiceScript.new()
	_assert_hooks()
	_run_all_flows()
	await _assert_adjacent()
	_finish()


func _assert_hooks() -> void:
	var mx: String = _svc.validate_matrix()
	if not mx.is_empty():
		_fail(mx)
	var fr: String = _svc.frozen_error()
	if not fr.is_empty():
		_fail(fr)
	if not _svc.BLOCK_SKIP:
		print("SKIP long flow")
		_fail("RUNNER_SKIP")
	if not _svc.BLOCK_OP_DUP:
		_fail("LEDGER_OP_DUP")
	if not _svc.REQUIRE_BASELINE:
		_fail("DOC_COUNT")
	else:
		var bl: Dictionary = _svc._load_json(_svc.BASELINE_PATH)
		if int(bl.get("total_runs", 0)) != int(bl.get("automated_scenes", -1)) + 1:
			_fail("DOC_COUNT")
	if not _svc.REQUIRE_RC:
		_fail("RC_HASH")
	else:
		var mf: Dictionary = _svc._load_json("res://artifacts/releases/v1.41/build_manifest.json")
		if bool(mf.get("executable_stale", true)):
			_fail("RC_HASH")
	if not _svc.REQUIRE_APP_READY:
		_fail("SMOKE_READY")
	if GameState.SAVE_SCHEMA_KEYS.size() != 39:
		_fail("SAVE_V22_TYPE", "keys")


func _wipe_save(path: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var p: String = path + str(suffix)
		var g: String = ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(g)


func _reset_core() -> void:
	GameState.gold = 50
	GameState.level = 10
	GameState.experience = 0
	GameState.military_merit = 0
	GameState.current_day = 1
	GameState.current_time_used = 0
	GameState.current_map_id = "cassano_city"
	GameState.owned_territory = ""
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	GameState.save_path = "user://test_v155_flow.json"
	GameState.set_save_fault_inject("")
	_wipe_save(GameState.save_path)
	_wipe_save("user://test_v155_probe.json")


func _run_all_flows() -> void:
	var ids: Array = _svc.flow_ids()
	if _svc.REQUIRE_ALL_FLOWS:
		if ids.size() != 10:
			_fail("FLOW_SKIP")
			return
	else:
		_fail("FLOW_SKIP")
		ids = ids.slice(0, 9)
	for fid in ids:
		_reset_core()
		match str(fid):
			"flow_newgame":
				_flow_newgame()
			"flow_v21":
				_flow_v21()
			"flow_v22_mid":
				_flow_v22_mid()
			"flow_territory":
				_flow_territory()
			"flow_treeheart":
				_flow_treeheart()
			"flow_border_ice":
				_flow_border_ice()
			"flow_finale":
				_flow_finale()
			"flow_challenge_pet":
				_flow_challenge_pet()
			"flow_season":
				_flow_season()
			"flow_tight":
				_flow_tight()
			_:
				_fail("FLOW_SET", str(fid))


func _checkpoint(tag: String) -> void:
	if not _svc.REQUIRE_SAVE_POINTS:
		_fail("FLOW_SAVE")
		return
	var rec: Dictionary = _svc.record(_op(tag))
	if not bool(rec.get("success", false)):
		_fail(str(rec.get("code", "LEDGER_OP_DUP")))
	if not GameState.save_game():
		_fail("FLOW_SAVE", tag)
	var gold0 := GameState.gold
	var day0 := GameState.current_day
	if not GameState.load_game():
		_fail("FLOW_SAVE", tag + "load")
	if GameState.gold != gold0 or GameState.current_day != day0:
		_fail("LEDGER_DIFF", tag)


func _flow_newgame() -> void:
	GameState.current_map_id = "cassano_city"
	var rewards: Dictionary = _combat.victory_rewards("spider")
	if rewards.is_empty():
		_fail("FLOW_FAKE", "spider")
		return
	var spider: Dictionary = _combat.get_monster("spider")
	var base_exp := int(spider.get("base_exp", 0))
	if _svc.BLOCK_DOUBLE:
		if int(rewards.get("experience", 0)) != base_exp * 10:
			_fail("VALUE_DOUBLE")
	else:
		_fail("VALUE_DOUBLE")
	GameState.apply_victory_rewards(rewards)
	_checkpoint("newgame_battle")
	if not GameState.add_item("fruit", 1):
		_fail("FLOW_FAKE", "bag")
	GameState.current_map_id = "palace"
	_checkpoint("newgame_palace")
	if _svc.BLOCK_ARBITRAGE:
		var gold0 := GameState.gold
		var bad: Dictionary = GameState.complete_season_contract("sc_market", _op("arb"))
		if bool(bad.get("success", false)) and GameState.gold > gold0 + 40:
			_fail("ARBITRAGE")
	else:
		GameState.gold += 999999
		_fail("ARBITRAGE")


func _flow_v21() -> void:
	var src: String = FileAccess.get_file_as_string(_svc.V21_PATH)
	var dst := FileAccess.open(GameState.save_path, FileAccess.WRITE)
	if dst == null:
		_fail("SAVE_V21", "open")
		return
	dst.store_string(src)
	dst.close()
	GameState.gold = 1
	var mem_gold := GameState.gold
	if not GameState.load_game():
		_fail("SAVE_V21", "load")
		return
	if _svc.REQUIRE_V21:
		if GameState.gold != 321 or GameState.level != 7:
			_fail("SAVE_V21", "core")
		if not GameState.expansion_state is Dictionary:
			_fail("SAVE_V21", "exp")
	else:
		_fail("SAVE_V21")
	if not GameState.save_game():
		_fail("SAVE_V21", "resave")
	var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(GameState.save_path))
	if payload is Dictionary and int((payload as Dictionary).get("version", 0)) != 22:
		_fail("SAVE_V21", "ver")
	if not GameState.load_game():
		_fail("SAVE_V21", "reload")
	if mem_gold == GameState.gold and GameState.gold == 1:
		_fail("SAVE_V21", "unchanged")


func _flow_v22_mid() -> void:
	GameState.refresh_rankings()
	if not GameState.expansion_state.get("season", {}).has("arena_seed_state"):
		_fail("FLOW_FAKE", "arena")
	_checkpoint("v22_rank")


func _flow_territory() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.owned_territory = "cassano_city"
	GameState.advance_day()
	if GameState.owned_territory != "cassano_city":
		_fail("FLOW_FAKE", "territory")
	_checkpoint("territory")


func _flow_treeheart() -> void:
	GameState.apply_chapter_fixture("harbor_lead")
	var wk: Dictionary = GameState.claim_chapter_weekly(_op("chwk"))
	_checkpoint("treeheart")
	if wk.is_empty():
		_fail("FLOW_FAKE", "weekly")


func _flow_border_ice() -> void:
	GameState.apply_border_fixture("scouting")
	GameState.add_item("fruit", 4)
	GameState.submit_border_supply(_op("supply"))
	GameState.apply_ice_fixture("ice_signal")
	GameState.claim_ice_weekly(_op("icewk"))
	_checkpoint("ice")


func _flow_finale() -> void:
	if _svc.BLOCK_FAKE_TERMINAL:
		GameState.apply_abyss_fixture("summons")
		GameState.expansion_state = GameState.expansion_state_service.abyss_finale_service.set_stage_for_fixture(
			GameState.expansion_state, "completed")
		var locked: Dictionary = GameState.run_epilogue_event("ep_lin", _op("eplockok"))
		if not bool(locked.get("success", false)):
			_fail("FLOW_FAKE", str(locked.get("code", "")))
	else:
		GameState.story_flags["game_won"] = true
		_fail("FLOW_FAKE")
	GameState.claim_abyss_weekly(_op("abwk"))
	_checkpoint("finale")


func _flow_challenge_pet() -> void:
	GameState.seed_challenge_prereqs()
	GameState.seed_pet_endgame_prereqs()
	var col: Dictionary = GameState.claim_collection_reward("col_year_pig", _op("col"))
	if not bool(col.get("success", false)):
		_fail("FLOW_FAKE", str(col.get("code", "")))
	var pets: Array = GameState.pets
	var iid := 0
	if not pets.is_empty() and pets[0] is Dictionary:
		iid = int((pets[0] as Dictionary).get("instance_id", 0))
	if iid > 0:
		GameState.set_pet_support(iid, _op("sup"))
	GameState.claim_research_contract("rc_bond", _op("rcb"))
	_checkpoint("pet")


func _flow_season() -> void:
	GameState.seed_season_prereqs()
	var sid0 := int(GameState.season_runtime().get("season_id", 1))
	var n0 := (GameState.season_runtime().get("season_ledger", []) as Array).size()
	GameState.season_rollover()
	if _svc.BLOCK_SEASON_DUP:
		GameState.season_rollover()
		var n1 := (GameState.season_runtime().get("season_ledger", []) as Array).size()
		if n1 - n0 > 1:
			_fail("SEASON_DUP")
	else:
		var live: Dictionary = GameState.expansion_state.duplicate(true)
		var se: Dictionary = (live.get("season", {}) as Dictionary).duplicate(true)
		se["last_rollover_day"] = -1
		live["season"] = se
		GameState.expansion_state = live
		GameState.season_rollover()
		_fail("SEASON_DUP")
	for _i in 30:
		GameState.advance_day()
	var after: Dictionary = GameState.season_runtime()
	if int(after.get("season_id", 0)) < sid0 + 2:
		_fail("SEASON_DUP", "wrap")
	if (after.get("season_history", []) as Array).size() > 4:
		_fail("SEASON_DUP", "hist")
	_checkpoint("season")


func _flow_tight() -> void:
	GameState.gold = 0
	GameState.owned_territory = ""
	var gold0 := GameState.gold
	var poor: Dictionary = GameState.complete_season_contract("sc_market", _op("poor"))
	if bool(poor.get("success", false)):
		_fail("LEDGER_DIFF", "poor")
	if GameState.gold != gold0:
		_fail("LEDGER_DIFF", "side")
	if not _svc.REQUIRE_LEDGER:
		_fail("LEDGER_DIFF")
	if _svc.REQUIRE_ATOMIC:
		if not GameState.save_game():
			_fail("SAVE_ATOMIC", "seed")
		GameState.set_save_fault_inject("write_fail")
		var failed := GameState.save_game()
		GameState.set_save_fault_inject("")
		if failed:
			_fail("SAVE_ATOMIC")
	else:
		_fail("SAVE_ATOMIC")
	var mem_gold := GameState.gold
	var mem_level := GameState.level
	var old_path: String = GameState.save_path
	GameState.save_path = "user://test_v155_probe.json"
	if _svc.REJECT_FUTURE:
		var fut: String = FileAccess.get_file_as_string(_svc.FUTURE_PATH)
		var ff := FileAccess.open(GameState.save_path, FileAccess.WRITE)
		ff.store_string(fut)
		ff.close()
		if GameState.load_game():
			_fail("SAVE_FUTURE")
		if GameState.gold != mem_gold or GameState.level != mem_level:
			_fail("SAVE_FUTURE", "mem")
	else:
		_fail("SAVE_FUTURE")
	if not _svc.REQUIRE_V22_TYPE:
		_fail("SAVE_V22_TYPE")
	else:
		var bad := "{\"version\":22,\"gold\":\"x\",\"level\":1}"
		var bf := FileAccess.open(GameState.save_path, FileAccess.WRITE)
		bf.store_string(bad)
		bf.close()
		if GameState.load_game():
			_fail("SAVE_V22_TYPE", "typed")
		if GameState.gold != mem_gold:
			_fail("SAVE_V22_TYPE", "mem")
	GameState.save_path = old_path
	_checkpoint("tight")


func _assert_adjacent() -> void:
	_reset_core()
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	if _main.world.maps.size() != 50:
		_fail("FLOW_SET", "maps")
	_main._open_actor_dialogue("grocery")
	var gro := 0
	for child in _main.dialogue_panel.choices.get_children():
		if child is Button:
			gro += 1
	if gro != 3:
		_fail("VALUE_OVERRIDE", "grocery")
	if _svc.REQUIRE_NO_LEAK:
		_main.queue_free()
		_main = null
	else:
		_leak = Node.new()
		add_child(_leak)
		_fail("OBJECT_LEAK")


func _finish() -> void:
	if _errors.is_empty():
		print("PASS long flow v155")
		get_tree().quit(0)
	else:
		print("FAIL %s" % ",".join(_errors))
		get_tree().quit(1)
