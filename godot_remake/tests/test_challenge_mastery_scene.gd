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
	_assert_catalog()
	_assert_challenges()
	_assert_mastery()
	_assert_equipment()
	_assert_rotation()
	_assert_save()
	_assert_adjacent()
	if _main != null and _main.scene_battle_controller != null:
		_main.scene_battle_controller.cancel_battle()
	await get_tree().process_frame
	_finish()


func _fail(code: String, detail: String = "") -> void:
	_errors.append(code)
	print(code)
	if not detail.is_empty():
		print(detail)


func _reset() -> void:
	GameState.gold = 200
	GameState.level = 30
	GameState.current_day = 1
	GameState.story_flags["king_rescued"] = false
	GameState.learned_skills = {"flying_slash": 1, "star_sword": 1, "fighting_spirit": 1}
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	GameState.seed_challenge_prereqs()
	GameState.add_item("fruit", 8)
	GameState.equipment["weapon"] = GameState.create_item_entry("novice_sword")


func _assert_catalog() -> void:
	var svc = GameState.expansion_state_service.challenge_service
	var errs: Array = svc.validate_catalog()
	if not errs.is_empty():
		_fail(str(errs[0]))
	if svc.by_id.size() != 9:
		_fail("CHALLENGE_COUNT")
	var seen: Dictionary = {}
	for cid in svc.by_id.keys():
		if seen.has(str(cid)):
			_fail("CHALLENGE_DUP_ID")
		seen[str(cid)] = true
	if seen.size() != 9:
		_fail("CHALLENGE_COUNT")


func _run_one(cid: String, mode: String, expect_gold_delta: int) -> Dictionary:
	var gold0 := GameState.gold
	var start: Dictionary = GameState.try_start_challenge(cid, mode, _op("t:start:%s:%s" % [cid, mode]))
	if not bool(start.get("success", false)):
		return start
	var spec: Dictionary = GameState.expansion_state_service.challenge_service.spec_of(cid)
	var mid := str(spec.get("monster_id", ""))
	var sid := "t:sess:%s" % cid
	var sess: Dictionary = GameState.begin_challenge_session(mid, sid)
	if not bool(sess.get("success", false)):
		return sess
	var settled: Dictionary = GameState.settle_challenge_battle(mid, true, sid)
	if expect_gold_delta >= 0 and GameState.gold - gold0 < expect_gold_delta and mode == "official":
		_fail("CHALLENGE_TRAIN_REWARD", cid)
	if mode == "training" and GameState.gold != gold0:
		_fail("CHALLENGE_TRAIN_REWARD")
	return settled


func _assert_challenges() -> void:
	_reset()
	var locked: Dictionary = GameState.try_start_challenge("ch_abyss", "official", "t:lock")
	# after seed, abyss is unlocked. test locked without seed:
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	var locked2: Dictionary = GameState.try_start_challenge("ch_abyss", "official", "t:lock2")
	if str(locked2.get("code", "")) != "CHALLENGE_LOCKED":
		_fail("CHALLENGE_LOCKED")
	_reset()
	var ids: Array = ["ch_arena", "ch_mine", "ch_territory", "ch_treeheart", "ch_harbor", "ch_border", "ch_ice", "ch_abyss", "ch_memory"]
	GameState.unlock_warrior_mastery("mastery_flying_slash", _op("t:prems"))
	for cid in ids:
		var r: Dictionary = _run_one(str(cid), "official", 0)
		if not bool(r.get("success", false)):
			_fail("CHALLENGE_LOCKED", "%s %s" % [cid, str(r.get("code", ""))])
	_reset()
	GameState.unlock_warrior_mastery("mastery_flying_slash", _op("t:prems2"))
	var train: Dictionary = _run_one("ch_arena", "training", 0)
	if not bool(train.get("success", false)):
		_fail("CHALLENGE_TRAIN_REWARD", str(train.get("code", "")))
	_reset()
	_run_one("ch_arena", "official", 8)
	var gold1 := GameState.gold
	var dup: Dictionary = _run_one("ch_arena", "official", 0)
	if GameState.gold > gold1 + 4:
		_fail("CHALLENGE_FIRST_DUP")
	_reset()
	GameState.current_day = 1
	_run_one("ch_arena", "official", 0)
	var gold2 := GameState.gold
	var wdup: Dictionary = _run_one("ch_arena", "official", 0)
	if GameState.gold - gold2 >= 4:
		_fail("CHALLENGE_WEEKLY_DUP")
	_reset()
	var st: Dictionary = GameState.try_start_challenge("ch_arena", "official", "t:cancel")
	var spec: Dictionary = GameState.expansion_state_service.challenge_service.spec_of("ch_arena")
	var mid := str(spec.get("monster_id", ""))
	GameState.begin_challenge_session(mid, "t:can")
	var rec0 := (GameState.challenge_runtime().get("records", {}) as Dictionary).duplicate(true)
	var can: Dictionary = GameState.settle_challenge_battle(mid, false, "t:can")
	if bool(can.get("success", false)) or (GameState.challenge_runtime().get("records", {}) as Dictionary).get("ch_arena", 0) != rec0.get("ch_arena", 0):
		if str(can.get("code", "")) != "BATTLE_CANCEL_ADVANCE":
			_fail("BATTLE_CANCEL_ADVANCE")
	_reset()
	GameState.try_start_challenge("ch_arena", "official", "t:sess")
	GameState.begin_challenge_session(mid, "t:good")
	var bad: Dictionary = GameState.settle_challenge_battle(mid, true, "t:old")
	if str(bad.get("code", "")) != "CHALLENGE_SESSION":
		_fail("CHALLENGE_SESSION")


func _assert_mastery() -> void:
	_reset()
	var miss: Dictionary = GameState.unlock_warrior_mastery("mastery_missing", "t:cap")
	if str(miss.get("code", "")) != "MASTERY_CAP":
		_fail("MASTERY_CAP")
	var gold0 := GameState.gold
	var u1: Dictionary = GameState.unlock_warrior_mastery("mastery_fighting_spirit", "t:ms1")
	if not bool(u1.get("success", false)):
		_fail("MASTERY_CAP", str(u1.get("code", "")))
	var u2: Dictionary = GameState.unlock_warrior_mastery("mastery_fighting_spirit", "t:ms2")
	if str(u2.get("code", "")) != "MASTERY_DUP_FEE":
		_fail("MASTERY_DUP_FEE")
	if GameState.gold < gold0 - 10 - 1:
		_fail("MASTERY_DUP_FEE")
	GameState.unlock_warrior_mastery("mastery_star_sword", "t:ms3")
	GameState.unlock_warrior_mastery("mastery_combo", "t:ms4")
	GameState.try_start_challenge("ch_arena", "official", "t:snap")
	var live: Dictionary = GameState.expansion_state.duplicate(true)
	var wm: Dictionary = (live.get("warrior_mastery", {}) as Dictionary).duplicate(true)
	wm["ranks"] = {}
	live["warrior_mastery"] = wm
	GameState.expansion_state = live
	var bonus := GameState.expansion_state_service.warrior_mastery_service.bonus_for(GameState.expansion_state, "flying_slash")
	if bonus <= 0.0:
		_fail("MASTERY_SNAPSHOT")


func _assert_equipment() -> void:
	_reset()
	var ok: Dictionary = GameState.bind_equipment_affix("weapon", "challenge_mark", "ch_arena", "t:eq1")
	if not bool(ok.get("success", false)):
		_fail("EQUIPMENT_INSTANCE", str(ok.get("code", "")))
	var bad_aff: Dictionary = GameState.bind_equipment_affix("weapon", "random_affix", "ch_arena", "t:eq2")
	if str(bad_aff.get("code", "")) != "EQUIPMENT_AFFIX":
		_fail("EQUIPMENT_AFFIX")
	GameState.equipment["weapon"] = GameState.create_item_entry("novice_armor")
	var mismatch: Dictionary = GameState.unbind_equipment_affix("weapon", "t:eq3")
	if str(mismatch.get("code", "")) != "EQUIPMENT_UNBIND":
		_fail("EQUIPMENT_UNBIND")
	GameState.equipment["weapon"] = GameState.create_item_entry("novice_sword")
	var ub: Dictionary = GameState.unbind_equipment_affix("weapon", "t:eq4")
	if not bool(ub.get("success", false)):
		_fail("EQUIPMENT_UNBIND", str(ub.get("code", "")))
	GameState.equipment["weapon"] = {}
	var noitem: Dictionary = GameState.bind_equipment_affix("weapon", "challenge_mark", "ch_arena", "t:eq5")
	if str(noitem.get("code", "")) != "EQUIPMENT_INSTANCE":
		_fail("EQUIPMENT_INSTANCE")


func _assert_rotation() -> void:
	var rot = GameState.expansion_state_service.challenge_rotation_service
	var a: Array = rot.weekly_ids(1)
	var b: Array = rot.weekly_ids(8)
	if a == b:
		_fail("ROTATION_WEEK")
	var vr: Dictionary = rot.validate_refresh(rot.week_index(1), 8)
	if int(vr.get("week", rot.week_index(1))) == rot.week_index(1):
		_fail("ROTATION_WEEK")


func _assert_save() -> void:
	_reset()
	GameState.unlock_warrior_mastery("mastery_flying_slash", "t:sv1")
	_run_one("ch_arena", "official", 0)
	GameState.bind_equipment_affix("weapon", "challenge_mark", "ch_arena", "t:sveq")
	if not GameState.save_game():
		_fail("SAVE_DUP_OP")
	var before: Dictionary = GameState.expansion_state.duplicate(true)
	if not GameState.load_game():
		_fail("SAVE_DUP_OP")
	var after: Dictionary = GameState.expansion_state
	if str((after.get("challenges", {}) as Dictionary).get("first_claimed", {}).keys()) != str((before.get("challenges", {}) as Dictionary).get("first_claimed", {}).keys()):
		_fail("SAVE_DUP_OP")
	var row: Dictionary = (after.get("challenges", {}) as Dictionary).duplicate(true)
	var ledger: Array = (row.get("challenge_ledger", []) as Array).duplicate()
	if not ledger.is_empty():
		ledger.append((ledger[0] as Dictionary).duplicate(true))
		row["challenge_ledger"] = ledger
		var probe: Dictionary = after.duplicate(true)
		probe["challenges"] = row
		var verr: Array = GameState.expansion_state_service.challenge_service.validate_save(probe)
		if verr.is_empty() or str(verr[0]) != "SAVE_DUP_OP":
			_fail("SAVE_DUP_OP")


func _assert_adjacent() -> void:
	if GameState.SAVE_SCHEMA_KEYS.size() != 39:
		_fail("SAVE_DUP_OP", "schema")
	if _main.world.maps.size() != 50:
		_fail("CHALLENGE_COUNT", "maps")


func _finish() -> void:
	if _errors.is_empty():
		print("PASS challenge mastery")
		get_tree().quit(0)
	else:
		print("FAIL %s" % ",".join(_errors))
		get_tree().quit(1)
