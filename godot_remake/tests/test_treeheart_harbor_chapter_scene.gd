extends Node

const WorldService = preload("res://scripts/world_service.gd")
const MAPS := ["treeheart_outskirts", "treeheart_core", "harbor_quay", "harbor_market", "sea_cave", "tide_shrine"]
const STAGES := ["locked", "treeheart_rumor", "root_sickness", "harbor_lead", "smuggler_choice", "sea_cave_assault", "tide_shrine_finale", "treeheart_weekly_contract"]

var _errors: Array = []
var _main: Node = null


func _ready() -> void:
	if GameState == null:
		print("REGISTRY_FAIL: MAP_ID_MISMATCH GameState missing")
		get_tree().quit(1)
		return
	_main = preload("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_maps()
	_assert_codes()
	_assert_flow()
	_assert_branches()
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
	GameState.current_map_id = "cassano_city"
	GameState.player_current_hp = 550
	GameState.loot_queue.clear()
	GameState._initialize_inventory()
	GameState.owned_territory = ""


func _th() -> Dictionary:
	return GameState.chapter_runtime()


func _stage() -> String:
	return str(_th().get("stage", "locked"))


func _assert_maps() -> void:
	var maps_file := FileAccess.open("res://data/maps.json", FileAccess.READ)
	if maps_file == null:
		_fail("MAP_ID_MISMATCH", "maps.json")
		return
	var maps_json: Array = JSON.parse_string(maps_file.get_as_text())
	var json_ids: Dictionary = {}
	var outskirts_targets: Dictionary = {}
	for raw in maps_json:
		if raw is Dictionary:
			json_ids[str(raw.get("id", ""))] = true
			if str(raw.get("id", "")) == "treeheart_outskirts":
				for ex in raw.get("exits", []):
					if ex is Dictionary:
						outskirts_targets[str(ex.get("target", ""))] = true
	var reg_file := FileAccess.open("res://docs/world_interaction_registry.json", FileAccess.READ)
	var reg: Dictionary = JSON.parse_string(reg_file.get_as_text())
	var reg_ids: Dictionary = {}
	for raw in reg.get("maps", []):
		if raw is Dictionary:
			reg_ids[str(raw.get("map_id", ""))] = true
	var world := WorldService.new()
	for mid in MAPS:
		if not json_ids.has(mid) or not reg_ids.has(mid):
			_fail("MAP_ID_MISMATCH", mid)
		var row: Dictionary = world.get_map(mid)
		if row.is_empty() or str(row.get("id", "")) != mid:
			_fail("MAP_ID_MISMATCH", "world %s" % mid)
	if not outskirts_targets.has("treeheart_core"):
		_fail("MAP_EXIT_TARGET", "missing core")
	if outskirts_targets.has("cassano_city") and not outskirts_targets.has("treeheart_city"):
		_fail("MAP_EXIT_TARGET", "cassano hijack")
	GameState.current_map_id = "treeheart_outskirts"
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	_main._apply_current_map()
	var right: Button = _main.direction_buttons.get("right")
	if right == null or str(right.target_map_id) != "treeheart_core":
		_fail("MAP_EXIT_TARGET", "runtime right")


func _assert_codes() -> void:
	_reset()
	var early: Dictionary = GameState.choose_smuggler_branch("report", "early_branch")
	if str(early.get("code", "")) != "CHAPTER_PRECONDITION":
		_fail("CHAPTER_PRECONDITION", str(early.get("code")))
	GameState.current_map_id = "cassano_city"
	var wrong: Dictionary = GameState.collect_chapter_evidence("root_bark", "ev_wrong")
	if str(wrong.get("code", "")) != "EVIDENCE_WRONG_MAP":
		_fail("EVIDENCE_WRONG_MAP", str(wrong.get("code")))
	var illegal: Dictionary = GameState.choose_smuggler_branch("steal", "illegal_br")
	if str(illegal.get("code", "")) != "CHAPTER_PRECONDITION" and str(illegal.get("code", "")) != "CHAPTER_BRANCH":
		_fail("CHAPTER_BRANCH", str(illegal.get("code")))


func _walk_to_choice() -> void:
	_reset()
	GameState.talk_chapter_npc("chapter_lin", "lin1")
	GameState.talk_chapter_npc("chapter_lin", "lin2")
	GameState.current_map_id = "treeheart_outskirts"
	GameState.collect_chapter_evidence("root_bark", "ev_bark")
	GameState.collect_chapter_evidence("sick_leaf", "ev_leaf")
	var dup: Dictionary = GameState.collect_chapter_evidence("root_bark", "ev_bark2")
	if str(dup.get("code", "")) != "EVIDENCE_DUP":
		_fail("EVIDENCE_DUP", str(dup.get("code")))
	GameState.current_map_id = "treeheart_core"
	GameState.collect_chapter_evidence("core_resin", "ev_resin")
	GameState.talk_chapter_npc("chapter_qin", "qin1")
	GameState.talk_chapter_npc("chapter_lin", "lin3")
	GameState.current_map_id = "harbor_quay"
	GameState.collect_chapter_evidence("smuggler_ledger", "ev_led")
	GameState.talk_chapter_npc("chapter_su", "su1")


func _assert_flow() -> void:
	_reset()
	if _stage() != "locked":
		_fail("CHAPTER_PRECONDITION", "start %s" % _stage())
	var t1: Dictionary = GameState.talk_chapter_npc("chapter_lin", "lin1")
	if _stage() != "treeheart_rumor":
		_fail("CHAPTER_PRECONDITION", "rumor %s" % _stage())
	GameState.talk_chapter_npc("chapter_lin", "lin2")
	if _stage() != "root_sickness":
		_fail("CHAPTER_PRECONDITION", "sick %s" % _stage())
	if not GameState.can_enter_map("treeheart_core"):
		_fail("CHAPTER_PRECONDITION", "core locked")
	if GameState.can_enter_map("harbor_quay"):
		_fail("CHAPTER_PRECONDITION", "quay open early")
	GameState.current_map_id = "treeheart_outskirts"
	GameState.collect_chapter_evidence("root_bark", "ev_bark")
	GameState.collect_chapter_evidence("sick_leaf", "ev_leaf")
	GameState.current_map_id = "treeheart_core"
	GameState.collect_chapter_evidence("core_resin", "ev_resin")
	GameState.talk_chapter_npc("chapter_lin", "lin3")
	if _stage() != "harbor_lead":
		_fail("CHAPTER_PRECONDITION", "lead %s" % _stage())
	GameState.current_map_id = "harbor_quay"
	GameState.collect_chapter_evidence("smuggler_ledger", "ev_led")
	GameState.talk_chapter_npc("chapter_su", "su1")
	if _stage() != "smuggler_choice":
		_fail("CHAPTER_PRECONDITION", "choice %s" % _stage())
	if t1.is_empty():
		_fail("CHAPTER_PRECONDITION", "empty talk")


func _assert_branches() -> void:
	_walk_to_choice()
	var rel0 := int(GameState.expansion_state.get("relationships", {}).get("npc_adv_lin_xia", {}).get("value", 0))
	var rep0 := int(GameState.expansion_state.get("market", {}).get("reputation", 0))
	var report: Dictionary = GameState.choose_smuggler_branch("report", "br_report")
	if not bool(report.get("success", false)) or _stage() != "sea_cave_assault":
		_fail("CHAPTER_BRANCH", str(report.get("code")))
	var rel1 := int(GameState.expansion_state.get("relationships", {}).get("npc_adv_lin_xia", {}).get("value", 0))
	var rep1 := int(GameState.expansion_state.get("market", {}).get("reputation", 0))
	if rel1 != rel0 + 2 or rep1 != rep0 + 2:
		_fail("CHAPTER_BRANCH", "report deltas")
	var again: Dictionary = GameState.choose_smuggler_branch("track", "br_track_locked")
	if str(again.get("code", "")) != "CHAPTER_BRANCH":
		_fail("CHAPTER_BRANCH", str(again.get("code")))
	_walk_to_choice()
	var su0 := int(GameState.expansion_state.get("relationships", {}).get("npc_adv_su_yan", {}).get("value", 0))
	var track: Dictionary = GameState.choose_smuggler_branch("track", "br_track")
	if not bool(track.get("success", false)):
		_fail("CHAPTER_BRANCH", str(track.get("code")))
	var su1 := int(GameState.expansion_state.get("relationships", {}).get("npc_adv_su_yan", {}).get("value", 0))
	if su1 != su0 + 2:
		_fail("CHAPTER_BRANCH", "track rel")


func _assert_battles() -> void:
	_reset()
	GameState.apply_chapter_fixture("sea_cave_assault")
	GameState.current_map_id = "sea_cave"
	GameState.player_current_hp = 550
	_main._apply_current_map()
	if not _main.interactive_actors.has("battle:chapter_sea_boss"):
		_fail("BATTLE_CANCEL_ADVANCE", "sea actor")
		return
	_main._engage_world_monster("battle:chapter_sea_boss")
	if not _main.scene_battle_controller.is_active():
		_fail("BATTLE_CANCEL_ADVANCE", "engage")
	_main.scene_battle_controller.cancel_battle()
	if _stage() != "sea_cave_assault":
		_fail("BATTLE_CANCEL_ADVANCE", "cancel advanced")
	var gold0 := GameState.gold
	var death: Dictionary = GameState.settle_chapter_boss("chapter_sea_boss", false, "sea_dead")
	if str(death.get("code", "")) != "BATTLE_CANCEL_ADVANCE":
		_fail("BATTLE_CANCEL_ADVANCE", str(death.get("code")))
	if _stage() != "sea_cave_assault":
		_fail("BATTLE_CANCEL_ADVANCE", "death stage")
	if GameState.gold != gold0:
		_fail("BATTLE_CANCEL_ADVANCE", "death gold")
	_main._on_scene_battle_finished("chapter_sea_boss", true)
	_main.scene_battle_controller.cancel_battle()
	if _stage() != "tide_shrine_finale":
		_fail("BATTLE_CANCEL_ADVANCE", "sea win %s" % _stage())
	GameState.talk_chapter_npc("chapter_ye", "ye1")
	GameState.current_map_id = "tide_shrine"
	_main._apply_current_map()
	if not _main.interactive_actors.has("battle:chapter_tide_boss"):
		_fail("BATTLE_CANCEL_ADVANCE", "tide actor")
	_main._engage_world_monster("battle:chapter_tide_boss")
	if not _main.scene_battle_controller.is_active():
		_fail("BATTLE_CANCEL_ADVANCE", "tide engage")
	_main.scene_battle_controller.cancel_battle()
	_main._on_scene_battle_finished("chapter_tide_boss", true)
	if _stage() != "treeheart_weekly_contract":
		_fail("BATTLE_CANCEL_ADVANCE", "tide win %s" % _stage())
	_reset()
	GameState.apply_chapter_fixture("sea_cave_assault")
	var enc = GameState.expansion_state_service.chapter_encounter_service
	var saved: Dictionary = enc.rewards.duplicate(true)
	var table: Dictionary = (enc.rewards.get("boss_rewards", {}) as Dictionary).duplicate(true)
	var sea: Dictionary = (table.get("chapter_sea_boss", {}) as Dictionary).duplicate(true)
	sea["item_id"] = "magic_soul_crystal"
	table["chapter_sea_boss"] = sea
	enc.rewards["boss_rewards"] = table
	var wl: Dictionary = GameState.settle_chapter_boss("chapter_sea_boss", true, "wl_bad")
	enc.rewards = saved
	if str(wl.get("code", "")) != "CHAPTER_REWARD_WHITELIST":
		_fail("CHAPTER_REWARD_WHITELIST", str(wl.get("code")))


func _assert_weekly() -> void:
	_reset()
	GameState.apply_chapter_fixture("treeheart_weekly_contract")
	var first: Dictionary = GameState.claim_chapter_weekly("wk1")
	if not bool(first.get("success", false)):
		_fail("WEEKLY_DUP", str(first.get("code")))
	var second: Dictionary = GameState.claim_chapter_weekly("wk2")
	if str(second.get("code", "")) != "WEEKLY_DUP":
		_fail("WEEKLY_DUP", str(second.get("code")))
	var seed_a := 0
	var seed_b := 0
	_reset()
	GameState.apply_chapter_fixture("treeheart_weekly_contract")
	GameState.expansion_state["world_seed"] = 11
	var st_a: Dictionary = GameState.expansion_state_service.weekly_contract_service.ensure_week(GameState.expansion_state, 1)
	seed_a = int(st_a.get("chapters", {}).get("treeheart_harbor", {}).get("weekly_contract", {}).get("seed", 0))
	_reset()
	GameState.apply_chapter_fixture("treeheart_weekly_contract")
	GameState.expansion_state["world_seed"] = 99
	var st_b: Dictionary = GameState.expansion_state_service.weekly_contract_service.ensure_week(GameState.expansion_state, 1)
	seed_b = int(st_b.get("chapters", {}).get("treeheart_harbor", {}).get("weekly_contract", {}).get("seed", 0))
	if seed_a == seed_b:
		_fail("WEEKLY_SEED_DRIFT", "%d==%d" % [seed_a, seed_b])
	GameState.current_day = 8
	GameState.expansion_state = st_b
	var refreshed: Dictionary = GameState.expansion_state_service.weekly_contract_service.ensure_week(GameState.expansion_state, 8)
	if int(refreshed.get("chapters", {}).get("treeheart_harbor", {}).get("weekly_contract", {}).get("week", -1)) == int(st_b.get("chapters", {}).get("treeheart_harbor", {}).get("weekly_contract", {}).get("week", -2)):
		_fail("WEEKLY_DUP", "week not refreshed")


func _snap() -> String:
	var ev: Array = []
	for item in _th().get("collected_evidence_ids", []):
		ev.append(str(item))
	ev.sort()
	var wk: Dictionary = _th().get("weekly_contract", {})
	return "%s|%s|%s|%s|%s|%d|%d|%s|%d" % [
		_stage(),
		str(_th().get("branch", "")),
		",".join(ev),
		str(_th().get("boss_status", {}).get("chapter_sea_boss", "")),
		str(_th().get("boss_status", {}).get("chapter_tide_boss", "")),
		int(wk.get("week", -1)),
		int(wk.get("seed", 0)),
		str(bool(wk.get("settled", false))),
		GameState.gold,
	]


func _assert_save() -> void:
	_walk_to_choice()
	GameState.choose_smuggler_branch("report", "sv_br")
	GameState.settle_chapter_boss("chapter_sea_boss", true, "sv_sea")
	var before := _snap()
	if not GameState.save_game():
		_fail("SAVE_CHAPTER_STAGE", "save")
		return
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	if not GameState.load_game():
		_fail("SAVE_CHAPTER_STAGE", "load")
		return
	if _snap() != before:
		_fail("SAVE_CHAPTER_STAGE", "roundtrip")
	var bad: Dictionary = GameState.expansion_state.duplicate(true)
	var chapters: Dictionary = (bad.get("chapters", {}) as Dictionary).duplicate(true)
	var row: Dictionary = (chapters.get("treeheart_harbor", {}) as Dictionary).duplicate(true)
	row["stage"] = "finale_complete"
	chapters["treeheart_harbor"] = row
	bad["chapters"] = chapters
	var errs: Array = GameState.expansion_state_service.story_chapter_service.validate_save(bad)
	if "SAVE_CHAPTER_STAGE" not in errs:
		_fail("SAVE_CHAPTER_STAGE", "invalid accepted")
	if not GameState.expansion_state_service.build_from_save(bad).is_empty():
		_fail("SAVE_CHAPTER_STAGE", "build accepted")
	_reset()
	GameState.save_game()


func _assert_adjacent() -> void:
	_reset()
	GameState.owned_territory = "cassano_city"
	var day: Dictionary = GameState.advance_day()
	if day.is_empty():
		_fail("CHAPTER_PRECONDITION", "advance_day")
	GameState.current_map_id = "cassano_city"
	_main._apply_current_map()
	if _main.interactive_actors.has("chapter_lin"):
		_fail("MAP_ID_MISMATCH", "cassano chapter actor")
	_main._open_actor_dialogue("grocery")
	var n := 0
	for child in _main.dialogue_panel.choices.get_children():
		if child is Button:
			n += 1
	if n != 3:
		_fail("MAP_ID_MISMATCH", "grocery %d" % n)
	_main._toggle_quests()
	var footer := str(_main.quest_panel.footer_label.text)
	if "TH " not in footer:
		_fail("CHAPTER_PRECONDITION", "quest footer")


func _fail(code: String, detail: String) -> void:
	_errors.append("%s %s" % [code, detail])


func _finish() -> void:
	if _errors.size() > 0:
		print("REGISTRY_FAIL: " + "; ".join(_errors))
		get_tree().quit(1)
		return
	print("PASS treeheart_harbor_chapter: maps exits stages evidence branches bosses weekly save")
	get_tree().quit(0)
