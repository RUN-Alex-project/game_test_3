extends Node

const WorldService = preload("res://scripts/world_service.gd")
const MAPS := ["ice_frontier", "frozen_pass", "crystal_cavern", "elemental_laboratory", "aurora_sanctum"]

var _errors: Array = []
var _main: Node = null


func _ready() -> void:
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_maps()
	_assert_element_gates()
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
	return str(GameState.ice_runtime().get("stage", "locked"))


func _assert_maps() -> void:
	var maps_file := FileAccess.open("res://data/maps.json", FileAccess.READ)
	var maps_json: Array = JSON.parse_string(maps_file.get_as_text())
	var json_ids: Dictionary = {}
	var frontier_targets: Dictionary = {}
	for raw in maps_json:
		if raw is Dictionary:
			json_ids[str(raw.get("id", ""))] = true
			if str(raw.get("id", "")) == "ice_frontier":
				for ex in raw.get("exits", []):
					if ex is Dictionary:
						frontier_targets[str(ex.get("target", ""))] = true
	var world := WorldService.new()
	for mid in MAPS:
		if not json_ids.has(mid) or world.get_map(mid).is_empty():
			_fail("MAP_ID_MISMATCH", mid)
	if not frontier_targets.has("frozen_pass"):
		_fail("MAP_ID_MISMATCH", "missing frozen_pass")
	GameState.current_map_id = "ice_frontier"
	_main._apply_current_map()
	var right: Button = _main.direction_buttons.get("right")
	if right == null or str(right.target_map_id) != "frozen_pass":
		_fail("MAP_ID_MISMATCH", "frontier right")


func _assert_element_gates() -> void:
	_reset()
	var svc = GameState.expansion_state_service.element_resolution_service
	var unk: Dictionary = svc.resolve({"base_damage": 100, "attacker_element": "void", "defender_element": "ice", "resist": 0})
	if str(unk.get("code", "")) != "ELEMENT_UNKNOWN":
		_fail("ELEMENT_UNKNOWN", str(unk.get("code")))
	var rng: Dictionary = svc.resolve({"base_damage": 100, "attacker_element": "fire", "defender_element": "ice", "resist": 999})
	if str(rng.get("code", "")) != "ELEMENT_RESIST_RANGE":
		_fail("ELEMENT_RESIST_RANGE", str(rng.get("code")))
	var neg: Dictionary = svc.resolve({"base_damage": 10, "attacker_element": "ice", "defender_element": "fire", "resist": 80, "field_id": "ice_field"})
	if int(neg.get("final", 0)) < 1:
		_fail("ELEMENT_NEG_DAMAGE", str(neg.get("final")))
	var nf: Dictionary = svc.resolve({"base_damage": INF, "attacker_element": "fire", "defender_element": "ice", "resist": 0})
	if str(nf.get("code", "")) != "ELEMENT_NONFINITE":
		_fail("ELEMENT_NONFINITE", str(nf.get("code")))
	var leak: Dictionary = GameState.apply_element_to_damage("snow_cavalry", 100)
	if bool(leak.get("applied", false)) and int(leak.get("final", 100)) != 100:
		_fail("ELEMENT_FIELD_LEAK", str(leak.get("final")))
	GameState.apply_ice_fixture("lab_trial")
	GameState.begin_ice_session("ice_lab_boss", "snap1")
	var a: Dictionary = GameState.apply_element_to_damage("ice_lab_boss", 100)
	GameState.ice_set_live_field("aurora_field")
	var b: Dictionary = GameState.apply_element_to_damage("ice_lab_boss", 100)
	if int(a.get("final", 0)) != int(b.get("final", 1)):
		_fail("ELEMENT_SNAPSHOT", "%s!=%s" % [str(a.get("final")), str(b.get("final"))])
	var legal: Dictionary = svc.resolve({"base_damage": 100, "attacker_element": "fire", "defender_element": "ice", "resist": 40, "field_id": "lab_field", "monster_id": "ice_lab_boss"})
	var report: Dictionary = svc.format_report(legal)
	if str(report.get("rule_id", "")) != str(legal.get("rule_id", "-")):
		_fail("ELEMENT_REPORT", str(report.get("rule_id")))
	GameState.add_item("ember_vial", 2)
	var u1: Dictionary = GameState.use_element_consumable("ember_vial")
	if not bool(u1.get("success", false)):
		_fail("ELEMENT_CONSUMABLE_CD", "first %s" % str(u1.get("code")))
	GameState.begin_ice_session("ice_lab_boss", "snap2")
	var u2: Dictionary = GameState.use_element_consumable("ember_vial")
	if str(u2.get("code", "")) != "ELEMENT_CONSUMABLE_CD":
		_fail("ELEMENT_CONSUMABLE_CD", str(u2.get("code")))


func _walk_key() -> void:
	_reset()
	GameState.talk_ice_npc("ice_shen", "t1")
	GameState.current_map_id = "ice_frontier"
	GameState.collect_ice_probe("signal_shard", "p1")
	GameState.talk_ice_npc("ice_shen", "t2")
	GameState.current_map_id = "frozen_pass"
	GameState.collect_ice_probe("rescue_charm", "p2")
	GameState.talk_ice_npc("ice_bai", "t3")


func _assert_flow() -> void:
	_reset()
	GameState.current_map_id = "ice_frontier"
	var early: Dictionary = GameState.collect_ice_probe("signal_shard", "early")
	if str(early.get("code", "")) != "ICE_PRECONDITION":
		_fail("ICE_PRECONDITION", str(early.get("code")))
	_walk_key()
	if _stage() != "crystal_key":
		_fail("ICE_PRECONDITION", "stage %s" % _stage())
	GameState.add_item("frost_vial", 1)
	var n0 := GameState.count_item("frost_vial")
	GameState.current_map_id = "cassano_city"
	var wrong: Dictionary = GameState.collect_ice_probe("crystal_key", "badmap")
	if GameState.count_item("frost_vial") != n0:
		_fail("ICE_PUZZLE_CONSUME", "consumed")
	if str(wrong.get("code", "")) != "ICE_WRONG_MAP":
		_fail("ICE_PUZZLE_CONSUME", str(wrong.get("code")))
	GameState.current_map_id = "crystal_cavern"
	var okp: Dictionary = GameState.collect_ice_probe("crystal_key", "pkey")
	if not bool(okp.get("success", false)):
		_fail("ICE_PRECONDITION", str(okp.get("code")))
	GameState.talk_ice_npc("ice_shen", "t4")
	if _stage() != "lab_trial":
		_fail("ICE_BOSS_STAGE", "lab %s" % _stage())


func _assert_battles() -> void:
	_reset()
	var early_b: Dictionary = GameState.begin_ice_session("ice_lab_boss", "earlyb")
	if str(early_b.get("code", "")) != "ICE_BOSS_STAGE":
		_fail("ICE_BOSS_STAGE", str(early_b.get("code")))
	_walk_key()
	GameState.add_item("frost_vial", 1)
	GameState.current_map_id = "crystal_cavern"
	GameState.collect_ice_probe("crystal_key", "bk")
	GameState.talk_ice_npc("ice_shen", "tb")
	var sess: Dictionary = GameState.begin_ice_session("ice_lab_boss", "lab1")
	if not bool(sess.get("success", false)):
		_fail("ICE_BOSS_STAGE", "begin %s" % str(sess.get("code")))
	var cancel: Dictionary = GameState.settle_ice_battle("ice_lab_boss", false, "lab1")
	if str(cancel.get("code", "")) != "BATTLE_CANCEL_ADVANCE":
		_fail("BATTLE_CANCEL_ADVANCE", str(cancel.get("code")))
	if _stage() != "lab_trial":
		_fail("BATTLE_CANCEL_ADVANCE", "advanced %s" % _stage())
	GameState.begin_ice_session("ice_lab_boss", "lab2")
	var win: Dictionary = GameState.settle_ice_battle("ice_lab_boss", true, "lab2")
	if not bool(win.get("success", false)):
		_fail("ICE_BOSS_STAGE", "win %s" % str(win.get("code")))
	if _stage() != "aurora_boss":
		_fail("ICE_BOSS_STAGE", "aurora %s" % _stage())
	GameState.begin_ice_session("ice_aurora_boss", "au1")
	GameState.settle_ice_battle("ice_aurora_boss", true, "au1")
	if _stage() != "weekly_element_trial":
		_fail("ICE_BOSS_STAGE", "weekly %s" % _stage())


func _assert_weekly() -> void:
	_reset()
	GameState.apply_ice_fixture("weekly_element_trial")
	var first: Dictionary = GameState.claim_ice_weekly("iw1")
	if not bool(first.get("success", false)):
		_fail("ICE_WEEKLY_DUP", str(first.get("code")))
	var second: Dictionary = GameState.claim_ice_weekly("iw2")
	if str(second.get("code", "")) != "ICE_WEEKLY_DUP":
		_fail("ICE_WEEKLY_DUP", str(second.get("code")))


func _snap() -> String:
	var row: Dictionary = GameState.ice_runtime()
	var ids: Array = []
	for item in row.get("probe_ids", []):
		ids.append(str(item))
	ids.sort()
	var packed := PackedStringArray()
	for item in ids:
		packed.append(str(item))
	return "%s|%s|%d" % [_stage(), ",".join(packed), GameState.gold]


func _assert_save() -> void:
	_walk_key()
	var before := _snap()
	if not GameState.save_game():
		_fail("SAVE_ICE_STAGE", "save")
		return
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	if not GameState.load_game():
		_fail("SAVE_ICE_STAGE", "load")
		return
	if _snap() != before:
		_fail("SAVE_ICE_STAGE", "roundtrip")
	var bad: Dictionary = GameState.expansion_state.duplicate(true)
	var chapters: Dictionary = (bad.get("chapters", {}) as Dictionary).duplicate(true)
	var row: Dictionary = (chapters.get("ice_element", {}) as Dictionary).duplicate(true)
	row["stage"] = "finale_complete"
	chapters["ice_element"] = row
	bad["chapters"] = chapters
	var errs: Array = GameState.expansion_state_service.ice_story_service.validate_save(bad)
	if "SAVE_ICE_STAGE" not in errs:
		_fail("SAVE_ICE_STAGE", "invalid accepted")
	_reset()
	GameState.save_game()


func _assert_adjacent() -> void:
	_reset()
	GameState.owned_territory = "cassano_city"
	GameState.advance_day()
	GameState.current_map_id = "cassano_city"
	_main._apply_current_map()
	if _main.interactive_actors.has("ice_shen"):
		_fail("MAP_ID_MISMATCH", "cassano ice actor")
	_main._open_actor_dialogue("grocery")
	var n := 0
	for child in _main.dialogue_panel.choices.get_children():
		if child is Button:
			n += 1
	if n != 3:
		_fail("MAP_ID_MISMATCH", "grocery %d" % n)
	var combat = preload("res://scripts/combat_service.gd").new(1)
	if int(combat.victory_rewards("snow_cavalry").military_merit) != 20000:
		_fail("ELEMENT_FIELD_LEAK", "merit")


func _fail(code: String, detail: String) -> void:
	_errors.append("%s %s" % [code, detail])


func _finish() -> void:
	if _errors.size() > 0:
		print("REGISTRY_FAIL: " + "; ".join(_errors))
		get_tree().quit(1)
		return
	print("PASS ice_element_chapter: maps elements story bosses weekly save")
	get_tree().quit(0)
