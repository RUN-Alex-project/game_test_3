extends Node

const WorldService = preload("res://scripts/world_service.gd")
const MAPS := ["abyss_gate", "abyss_outer_ring", "abyss_echo_halls", "totem_sanctum", "abyss_heart"]
const STAGES := ["locked", "summons", "abyss_entry", "echoes", "totem_trials", "heart_assault", "final_battle", "epilogue_pending", "completed", "weekly_abyss"]

var _errors: Array = []
var _main: Node = null
var _seen: Dictionary = {}


func _ready() -> void:
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_maps()
	_assert_gates()
	_assert_flow()
	_assert_battles()
	_assert_weekly()
	_assert_save()
	_assert_adjacent()
	if _main != null and _main.scene_battle_controller != null:
		_main.scene_battle_controller.cancel_battle()
	await get_tree().process_frame
	_finish()


func _reset() -> void:
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	GameState.current_day = 1
	GameState.gold = 10000
	GameState.military_merit = 0
	GameState.owned_territory = ""
	GameState.current_map_id = "cassano_city"
	GameState.player_current_hp = 550
	GameState.story_flags["game_won"] = false
	GameState.story_flags["king_rescued"] = true
	GameState.loot_queue.clear()
	GameState._initialize_inventory()


func _stage() -> String:
	return str(GameState.abyss_runtime().get("stage", "locked"))


func _mark() -> void:
	_seen[_stage()] = true


func _fail(code: String, detail: String) -> void:
	_errors.append("%s %s" % [code, detail])
	print(code)


func _assert_maps() -> void:
	var maps_file := FileAccess.open("res://data/maps.json", FileAccess.READ)
	var maps_json: Array = JSON.parse_string(maps_file.get_as_text())
	var json_ids: Dictionary = {}
	var gate_targets: Dictionary = {}
	for raw in maps_json:
		if raw is Dictionary:
			json_ids[str(raw.get("id", ""))] = true
			if str(raw.get("id", "")) == "abyss_gate":
				for ex in raw.get("exits", []):
					if ex is Dictionary:
						gate_targets[str(ex.get("target", ""))] = true
	var world := WorldService.new()
	for mid in MAPS:
		if not json_ids.has(mid) or world.get_map(mid).is_empty():
			_fail("MAP_ID_MISMATCH", mid)
	if not gate_targets.has("abyss_outer_ring"):
		_fail("MAP_ID_MISMATCH", "missing outer")
	GameState.seed_abyss_prereqs()
	GameState.try_enter_abyss("mapenter")
	GameState.current_map_id = "abyss_gate"
	_main._apply_current_map()
	var right: Button = _main.direction_buttons.get("right")
	if right == null or str(right.target_map_id) != "abyss_outer_ring":
		_fail("MAP_ID_MISMATCH", "gate right")


func _assert_gates() -> void:
	_reset()
	var early: Dictionary = GameState.try_enter_abyss("early")
	if str(early.get("code", "")) != "ABYSS_PRECONDITION":
		_fail("ABYSS_PRECONDITION", str(early.get("code")))
	_reset()
	GameState.seed_abyss_prereqs()
	var unk: Dictionary = GameState.begin_abyss_session("abyss_nope", "s0")
	if str(unk.get("code", "")) != "ABYSS_ECHO_UNKNOWN":
		_fail("ABYSS_ECHO_UNKNOWN", str(unk.get("code")))
	_reset()
	GameState.seed_abyss_prereqs()
	GameState.apply_abyss_fixture("totem_trials")
	GameState.add_item("fruit", 2)
	GameState.current_map_id = "cassano_city"
	var wrong: Dictionary = GameState.run_abyss_totem("totem_guild", "badmap")
	if str(wrong.get("code", "")) != "TOTEM_WRONG_MAP":
		_fail("TOTEM_WRONG_MAP", str(wrong.get("code")))
	var svc = GameState.expansion_state_service.totem_trial_service
	var bool_only: Dictionary = svc.run(GameState.expansion_state, "totem_guild", "totem_sanctum", "totem_trials", {"reputation": 2}, {"ok": true}, 2, "bool")
	if str(bool_only.get("code", "")) != "TOTEM_BOOL_ONLY":
		_fail("TOTEM_BOOL_ONLY", str(bool_only.get("code")))
	var snap: Dictionary = svc.run(GameState.expansion_state, "totem_guild", "totem_sanctum", "totem_trials", {"reputation": 2}, {}, 2, "emptysnap")
	if str(snap.get("code", "")) != "TOTEM_SNAPSHOT":
		_fail("TOTEM_SNAPSHOT", str(snap.get("code")))
	var neg: Dictionary = GameState.expansion_state_service.finale_epilogue_service.validate_reward({"gold": -5, "qty": 1})
	if str(neg.get("code", "")) != "FINALE_NEG_REWARD":
		_fail("FINALE_NEG_REWARD", str(neg.get("code")))


func _walk() -> void:
	_reset()
	_seen.clear()
	_mark()
	GameState.seed_abyss_prereqs()
	GameState.add_item("fruit", 3)
	GameState.try_enter_abyss("enter1")
	_mark()
	GameState.talk_abyss_npc("abyss_he", "t1")
	_mark()
	GameState.current_map_id = "abyss_gate"
	GameState.collect_abyss_probe("gate_seal", "p1")
	_mark()
	for echo_id in ["abyss_echo_assault", "abyss_echo_guard", "abyss_echo_mystery"]:
		GameState.begin_abyss_session(echo_id, "e:%s" % echo_id)
		GameState.settle_abyss_battle(echo_id, true, "e:%s" % echo_id, false)
	_mark()
	GameState.current_map_id = "totem_sanctum"
	GameState.run_abyss_totem("totem_guild", "tg")
	GameState.run_abyss_totem("totem_territory", "tt")
	GameState.run_abyss_totem("totem_bond", "tb")
	_mark()
	GameState.talk_abyss_npc("abyss_gu", "tf")
	_mark()
	GameState.begin_abyss_session("abyss_heart_boss", "heart1")
	GameState.settle_abyss_battle("abyss_heart_boss", true, "heart1", false)
	_mark()
	GameState.commit_abyss_epilogue("epi1")
	_mark()
	GameState.talk_abyss_npc("abyss_he", "tw")
	_mark()


func _assert_flow() -> void:
	_walk()
	for sid in STAGES:
		if not _seen.has(sid):
			_fail("ABYSS_PRECONDITION", "missing %s" % sid)
	var extra: Array = []
	for key in _seen.keys():
		if not str(key) in STAGES:
			extra.append(str(key))
	if not extra.is_empty():
		_fail("ABYSS_PRECONDITION", "extra")
	_reset()
	GameState.seed_abyss_prereqs()
	GameState.try_enter_abyss("ledger1")
	if (GameState.abyss_runtime().get("abyss_ledger", []) as Array).is_empty():
		_fail("ABYSS_LEDGER", "empty")
	_reset()
	GameState.seed_abyss_prereqs()
	GameState.apply_abyss_fixture("echoes")
	GameState.begin_abyss_session("abyss_echo_assault", "d1")
	GameState.settle_abyss_battle("abyss_echo_assault", true, "d1", false)
	var dup: Dictionary = GameState.settle_abyss_battle("abyss_echo_assault", true, "d1", false)
	if str(dup.get("code", "")) != "ABYSS_ECHO_DUP" and str(dup.get("code", "")) != "ABYSS_SESSION":
		GameState.begin_abyss_session("abyss_echo_assault", "d2")
		var dup2: Dictionary = GameState.settle_abyss_battle("abyss_echo_assault", true, "d2", false)
		if str(dup2.get("code", "")) != "ABYSS_ECHO_DUP":
			_fail("ABYSS_ECHO_DUP", str(dup2.get("code")))


func _assert_battles() -> void:
	_reset()
	GameState.seed_abyss_prereqs()
	GameState.apply_abyss_fixture("final_battle")
	var sess: Dictionary = GameState.begin_abyss_session("abyss_heart_boss", "hcancel")
	if not bool(sess.get("success", false)):
		_fail("BATTLE_CANCEL_ADVANCE", "begin %s" % str(sess.get("code")))
		return
	var cancel: Dictionary = GameState.settle_abyss_battle("abyss_heart_boss", false, "hcancel", false)
	if str(cancel.get("code", "")) != "BATTLE_CANCEL_ADVANCE":
		_fail("BATTLE_CANCEL_ADVANCE", str(cancel.get("code")))
	if _stage() != "final_battle":
		_fail("BATTLE_CANCEL_ADVANCE", "advanced %s" % _stage())
	GameState.begin_abyss_session("abyss_heart_boss", "hdead")
	var dead: Dictionary = GameState.settle_abyss_battle("abyss_heart_boss", false, "hdead", true)
	if str(dead.get("code", "")) != "ABYSS_DEATH":
		_fail("ABYSS_DEATH", str(dead.get("code")))
	GameState.begin_abyss_session("abyss_heart_boss", "sA")
	GameState.begin_abyss_session("abyss_heart_boss", "sB")
	var olds: Dictionary = GameState.settle_abyss_battle("abyss_heart_boss", true, "sA", false)
	if str(olds.get("code", "")) != "ABYSS_SESSION":
		_fail("ABYSS_SESSION", str(olds.get("code")))
	GameState.begin_abyss_session("abyss_heart_boss", "hwin")
	var win: Dictionary = GameState.settle_abyss_battle("abyss_heart_boss", true, "hwin", false)
	if not bool(win.get("success", false)):
		_fail("FINALE_GAME_WON", "win %s" % str(win.get("code")))
	if bool(GameState.story_flags.get("game_won", false)):
		_fail("FINALE_GAME_WON", "direct")
	if _stage() != "epilogue_pending":
		_fail("FINALE_GAME_WON", "stage %s" % _stage())
	var epi: Dictionary = GameState.commit_abyss_epilogue("epiA")
	if not bool(epi.get("success", false)):
		_fail("FINALE_EPILOGUE_DUP", str(epi.get("code")))
	if not bool(GameState.story_flags.get("game_won", false)):
		_fail("FINALE_GAME_WON", "missing after epi")
	var epi2: Dictionary = GameState.commit_abyss_epilogue("epiB")
	if str(epi2.get("code", "")) != "FINALE_EPILOGUE_DUP":
		_fail("FINALE_EPILOGUE_DUP", str(epi2.get("code")))
	var reward2: Dictionary = GameState.claim_abyss_one_time("ot2")
	if str(reward2.get("code", "")) != "FINALE_REWARD_DUP":
		_fail("FINALE_REWARD_DUP", str(reward2.get("code")))


func _assert_weekly() -> void:
	_reset()
	GameState.seed_abyss_prereqs()
	GameState.apply_abyss_fixture("weekly_abyss")
	var first: Dictionary = GameState.claim_abyss_weekly("w1")
	if not bool(first.get("success", false)):
		_fail("ABYSS_WEEKLY_DUP", str(first.get("code")))
	var second: Dictionary = GameState.claim_abyss_weekly("w2")
	if str(second.get("code", "")) != "ABYSS_WEEKLY_DUP":
		_fail("ABYSS_WEEKLY_DUP", str(second.get("code")))


func _snap() -> String:
	var row: Dictionary = GameState.abyss_runtime()
	return "%s|%s|%s|%d" % [_stage(), str(row.get("one_time_reward_claimed", false)), str(GameState.story_flags.get("game_won", false)), GameState.gold]


func _assert_save() -> void:
	_walk()
	var before := _snap()
	if not GameState.save_game():
		_fail("SAVE_ABYSS_STAGE", "save")
		return
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	if not GameState.load_game():
		_fail("SAVE_ABYSS_STAGE", "load")
		return
	if _snap() != before:
		_fail("SAVE_ABYSS_STAGE", "roundtrip")
	var bad: Dictionary = GameState.expansion_state.duplicate(true)
	var chapters: Dictionary = (bad.get("chapters", {}) as Dictionary).duplicate(true)
	var row: Dictionary = (chapters.get("abyss_finale", {}) as Dictionary).duplicate(true)
	row["stage"] = "not_a_stage"
	chapters["abyss_finale"] = row
	bad["chapters"] = chapters
	var errs: Array = GameState.expansion_state_service.abyss_finale_service.validate_save(bad)
	if "SAVE_ABYSS_STAGE" not in errs:
		_fail("SAVE_ABYSS_STAGE", "invalid accepted")
	_reset()
	GameState.save_game()


func _assert_adjacent() -> void:
	_reset()
	GameState.owned_territory = "cassano_city"
	GameState.advance_day()
	GameState.current_map_id = "cassano_city"
	_main._apply_current_map()
	if _main.interactive_actors.has("abyss_he"):
		_fail("MAP_ID_MISMATCH", "cassano abyss actor")
	_main._open_actor_dialogue("grocery")
	var n := 0
	for child in _main.dialogue_panel.choices.get_children():
		if child is Button:
			n += 1
	if n != 3:
		_fail("MAP_ID_MISMATCH", "grocery %d" % n)
	var combat = preload("res://scripts/combat_service.gd").new(1)
	if int(combat.victory_rewards("snow_cavalry").military_merit) != 20000:
		_fail("FINALE_NEG_REWARD", "merit")
	_main._open_marshal_dialogue()
	var has_south := false
	for child in _main.dialogue_panel.choices.get_children():
		if child is Button and child.text == "\u5357\u90e8\u57ce\u90a6":
			has_south = true
	if not has_south:
		_fail("MAP_ID_MISMATCH", "south missing")


func _finish() -> void:
	if _errors.size() > 0:
		print("REGISTRY_FAIL: " + "; ".join(_errors))
		get_tree().quit(1)
		return
	print("PASS abyss_finale: maps stages echoes totems heart epilogue weekly save")
	get_tree().quit(0)
