extends Node

const WorldService = preload("res://scripts/world_service.gd")
const MAPS := ["south_city_gate", "south_city_square", "border_watchpost", "border_supply_route", "border_ruins", "border_command_tent"]

var _errors: Array = []
var _main: Node = null


func _ready() -> void:
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_maps()
	_assert_flow()
	_assert_battles()
	_assert_weekly()
	_assert_save()
	_assert_adjacent()
	if _main != null and _main.scene_battle_controller != null:
		_main.scene_battle_controller.cancel_battle()
	await get_tree().process_frame
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
	GameState.loot_queue.clear()
	GameState._initialize_inventory()


func _stage() -> String:
	return str(GameState.border_runtime().get("stage", "locked"))


func _assert_maps() -> void:
	var maps_file := FileAccess.open("res://data/maps.json", FileAccess.READ)
	var maps_json: Array = JSON.parse_string(maps_file.get_as_text())
	var json_ids: Dictionary = {}
	var watch_targets: Dictionary = {}
	for raw in maps_json:
		if raw is Dictionary:
			json_ids[str(raw.get("id", ""))] = true
			if str(raw.get("id", "")) == "border_watchpost":
				for ex in raw.get("exits", []):
					if ex is Dictionary:
						watch_targets[str(ex.get("target", ""))] = true
	var world := WorldService.new()
	for mid in MAPS:
		if not json_ids.has(mid) or world.get_map(mid).is_empty():
			_fail("MAP_ID_MISMATCH", mid)
	if not watch_targets.has("border_supply_route"):
		_fail("MAP_EXIT_TARGET", "missing supply")
	GameState.current_map_id = "south_city_gate"
	_main._apply_current_map()
	var right: Button = _main.direction_buttons.get("right")
	if right == null or str(right.target_map_id) != "south_city_square":
		_fail("MAP_EXIT_TARGET", "gate right")


func _walk_supply() -> void:
	_reset()
	GameState.talk_border_npc("border_cmd", "cmd1")
	GameState.current_map_id = "border_watchpost"
	GameState.collect_border_scout("scout_tracks", "sc1")
	GameState.current_map_id = "south_city_square"
	GameState.collect_border_scout("scout_banner", "sc2")
	GameState.current_map_id = "border_watchpost"
	var dup: Dictionary = GameState.collect_border_scout("scout_tracks", "sc3")
	if str(dup.get("code", "")) != "BORDER_SCOUT_DUP":
		_fail("BORDER_SCOUT_DUP", str(dup.get("code")))
	GameState.talk_border_npc("border_cmd", "cmd2")
	GameState.add_item("fruit", 2)


func _assert_flow() -> void:
	_reset()
	GameState.current_map_id = "border_watchpost"
	var early_scout: Dictionary = GameState.collect_border_scout("scout_tracks", "early_sc")
	if str(early_scout.get("code", "")) != "BORDER_PRECONDITION":
		_fail("BORDER_PRECONDITION", "early scout %s" % str(early_scout.get("code")))
	var early: Dictionary = GameState.submit_border_supply("early_sup")
	if str(early.get("code", "")) != "BORDER_PRECONDITION":
		_fail("BORDER_PRECONDITION", str(early.get("code")))
	GameState.talk_border_npc("border_cmd", "cmd1")
	if _stage() != "scouting":
		_fail("BORDER_PRECONDITION", "scout stage")
	GameState.current_map_id = "cassano_city"
	var wrong: Dictionary = GameState.collect_border_scout("scout_tracks", "badmap")
	if str(wrong.get("code", "")) not in ["EVIDENCE_WRONG_MAP", "BORDER_PRECONDITION"]:
		_fail("BORDER_PRECONDITION", "wrong map %s" % str(wrong.get("code")))
	_walk_supply()
	if _stage() != "supply":
		_fail("BORDER_PRECONDITION", "supply %s" % _stage())
	var bad_item_state: Dictionary = GameState.expansion_state_service.supply_service.preview_submit(
		GameState.expansion_state, "rose", 9, "supply")
	if str(bad_item_state.get("code", "")) != "BORDER_SUPPLY_ITEM":
		_fail("BORDER_SUPPLY_ITEM", str(bad_item_state.get("code")))
	var qty: Dictionary = GameState.expansion_state_service.supply_service.preview_submit(
		GameState.expansion_state, "fruit", 0, "supply")
	if str(qty.get("code", "")) != "BORDER_SUPPLY_QTY":
		_fail("BORDER_SUPPLY_QTY", str(qty.get("code")))
	var sup: Dictionary = GameState.submit_border_supply("sup1")
	if not bool(sup.get("success", false)) or _stage() != "defense":
		_fail("BORDER_SUPPLY_ITEM", str(sup.get("code")))


func _assert_battles() -> void:
	_reset()
	GameState.apply_border_fixture("defense")
	var sess: Dictionary = GameState.begin_border_session("border_skirmish_a", "sess-a")
	if not bool(sess.get("success", false)):
		_fail("BORDER_PRECONDITION", str(sess.get("code")))
	var wrong_sess: Dictionary = GameState.settle_border_battle("border_skirmish_a", true, "other")
	if str(wrong_sess.get("code", "")) != "BORDER_SESSION":
		_fail("BORDER_SESSION", str(wrong_sess.get("code")))
	GameState.current_map_id = "border_supply_route"
	GameState.player_current_hp = 550
	_main._apply_current_map()
	if not _main.interactive_actors.has("battle:border_skirmish_a"):
		_fail("BATTLE_CANCEL_ADVANCE", "skirmish actor")
	_main._engage_world_monster("battle:border_skirmish_a")
	if not _main.scene_battle_controller.is_active():
		_fail("BATTLE_CANCEL_ADVANCE", "engage")
	_main.scene_battle_controller.cancel_battle()
	if _stage() != "defense":
		_fail("BATTLE_CANCEL_ADVANCE", "cancel advanced")
	var gold0 := GameState.gold
	var death: Dictionary = GameState.settle_border_battle("border_skirmish_a", false, str(GameState.border_runtime().get("active_session_id", "")))
	if str(death.get("code", "")) != "BATTLE_CANCEL_ADVANCE":
		_fail("BATTLE_CANCEL_ADVANCE", str(death.get("code")))
	if GameState.gold != gold0:
		_fail("BATTLE_CANCEL_ADVANCE", "death gold")
	GameState.begin_border_session("border_skirmish_a", "sess-a2")
	var win_a: Dictionary = GameState.settle_border_battle("border_skirmish_a", true, "sess-a2")
	if not bool(win_a.get("success", false)):
		_fail("BORDER_DEFENSE_DUP", str(win_a.get("code")))
	GameState.begin_border_session("border_skirmish_a", "sess-a3")
	var dup: Dictionary = GameState.settle_border_battle("border_skirmish_a", true, "sess-a3")
	if str(dup.get("code", "")) != "BORDER_DEFENSE_DUP":
		_fail("BORDER_DEFENSE_DUP", str(dup.get("code")))
	GameState.begin_border_session("border_skirmish_b", "sess-b")
	GameState.settle_border_battle("border_skirmish_b", true, "sess-b")
	if _stage() != "counterattack":
		_fail("BORDER_PRECONDITION", "counter %s" % _stage())
	GameState.current_map_id = "border_command_tent"
	_main._apply_current_map()
	_main._engage_world_monster("battle:border_command_boss")
	if _main.scene_battle_controller.is_active():
		_main.scene_battle_controller.cancel_battle()
	var merit0 := GameState.military_merit
	GameState.begin_border_session("border_command_boss", "sess-boss")
	var boss: Dictionary = GameState.settle_border_battle("border_command_boss", true, "sess-boss")
	if _stage() != "weekly_contract":
		_fail("BORDER_MERIT_DUP", "stage %s %s" % [_stage(), str(boss.get("code"))])
	if GameState.military_merit != merit0 + 20:
		_fail("BORDER_MERIT_DUP", "merit %d" % GameState.military_merit)
	var ledger_gold := GameState.expansion_state_service.border_story_service.ledger_gold_sum(GameState.expansion_state)
	if ledger_gold != 40:
		_fail("BORDER_LEDGER", "ledger %d" % ledger_gold)
	var spec: Dictionary = GameState.expansion_state_service.border_story_service.rules.get("resolved_reward", {})
	var again: Dictionary = GameState.expansion_state_service.border_story_service.apply_resolved_rewards(
		GameState.expansion_state, int(spec.get("gold", 0)), int(spec.get("military_merit", 0)), int(spec.get("reputation", 0)), int(spec.get("contribution", 0)), GameState.owned_territory)
	if str(again.get("code", "")) != "BORDER_MERIT_DUP":
		_fail("BORDER_MERIT_DUP", str(again.get("code")))


func _assert_weekly() -> void:
	_reset()
	GameState.apply_border_fixture("weekly_contract")
	var first: Dictionary = GameState.claim_border_weekly("bw1")
	if not bool(first.get("success", false)):
		_fail("BORDER_WEEKLY_DUP", str(first.get("code")))
	var second: Dictionary = GameState.claim_border_weekly("bw2")
	if str(second.get("code", "")) != "BORDER_WEEKLY_DUP":
		_fail("BORDER_WEEKLY_DUP", str(second.get("code")))
	_reset()
	GameState.apply_border_fixture("weekly_contract")
	GameState.expansion_state["world_seed"] = 3
	var a: Dictionary = GameState.expansion_state_service.border_weekly_service.ensure_week(GameState.expansion_state, 1)
	_reset()
	GameState.apply_border_fixture("weekly_contract")
	GameState.expansion_state["world_seed"] = 9
	var b: Dictionary = GameState.expansion_state_service.border_weekly_service.ensure_week(GameState.expansion_state, 1)
	var sa := int(a.get("chapters", {}).get("south_border", {}).get("weekly_contract", {}).get("seed", 0))
	var sb := int(b.get("chapters", {}).get("south_border", {}).get("weekly_contract", {}).get("seed", 0))
	if sa == sb:
		_fail("WEEKLY_SEED_DRIFT", "%d==%d" % [sa, sb])


func _snap() -> String:
	var row: Dictionary = GameState.border_runtime()
	var sc: Array = []
	for item in row.get("scout_ids", []):
		sc.append(str(item))
	sc.sort()
	var packed := PackedStringArray()
	for item in sc:
		packed.append(str(item))
	return "%s|%s|%s|%d|%d" % [_stage(), ",".join(packed), str(bool(row.get("supply_submitted", false))), GameState.gold, GameState.military_merit]


func _assert_save() -> void:
	_walk_supply()
	GameState.submit_border_supply("sv_sup")
	var before := _snap()
	if not GameState.save_game():
		_fail("SAVE_BORDER_STAGE", "save")
		return
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	if not GameState.load_game():
		_fail("SAVE_BORDER_STAGE", "load")
		return
	if _snap() != before:
		_fail("SAVE_BORDER_STAGE", "roundtrip")
	var bad: Dictionary = GameState.expansion_state.duplicate(true)
	var chapters: Dictionary = (bad.get("chapters", {}) as Dictionary).duplicate(true)
	var row: Dictionary = (chapters.get("south_border", {}) as Dictionary).duplicate(true)
	row["stage"] = "finale_complete"
	chapters["south_border"] = row
	bad["chapters"] = chapters
	var errs: Array = GameState.expansion_state_service.border_story_service.validate_save(bad)
	if "SAVE_BORDER_STAGE" not in errs:
		_fail("SAVE_BORDER_STAGE", "invalid accepted")
	_reset()
	GameState.save_game()


func _assert_adjacent() -> void:
	_reset()
	GameState.owned_territory = "cassano_city"
	GameState.advance_day()
	GameState.current_map_id = "cassano_city"
	_main._apply_current_map()
	if _main.interactive_actors.has("border_cmd"):
		_fail("MAP_ID_MISMATCH", "cassano border actor")
	_main._open_actor_dialogue("grocery")
	var n := 0
	for child in _main.dialogue_panel.choices.get_children():
		if child is Button:
			n += 1
	if n != 3:
		_fail("MAP_ID_MISMATCH", "grocery %d" % n)


func _fail(code: String, detail: String) -> void:
	_errors.append("%s %s" % [code, detail])


func _finish() -> void:
	if _errors.size() > 0:
		print("REGISTRY_FAIL: " + "; ".join(_errors))
		get_tree().quit(1)
		return
	print("PASS south_border_story: maps stages supply defense bosses weekly save")
	get_tree().quit(0)
