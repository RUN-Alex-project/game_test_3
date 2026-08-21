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
	_assert_collection()
	_assert_support()
	_assert_trials()
	_assert_contracts()
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
	GameState.loot_queue.clear()
	var dto: Dictionary = GameState._default_pets_dto()
	GameState.pets = dto.pets
	GameState.next_pet_instance_id = int(dto.next_pet_instance_id)
	GameState.research = (dto.research as Dictionary).duplicate(true)
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	GameState.seed_pet_endgame_prereqs()


func _pig_id() -> int:
	for pet: Dictionary in GameState.pets:
		if str(pet.get("template_id", "")) == "year_pig":
			return int(pet.get("instance_id", 0))
	return 0


func _lulu_id() -> int:
	for pet: Dictionary in GameState.pets:
		if str(pet.get("template_id", "")) == "lulu_pet":
			return int(pet.get("instance_id", 0))
	return 0


func _run_trial(tid: String) -> Dictionary:
	var start: Dictionary = GameState.try_start_pet_trial(tid, _op("t:start:%s" % tid))
	if not bool(start.get("success", false)):
		return start
	var spec: Dictionary = GameState.expansion_state_service.pet_trial_service.spec_of(tid)
	var mid := str(spec.get("monster_id", ""))
	var sid := "t:sess:%s:%d" % [tid, _ops]
	var sess: Dictionary = GameState.begin_pet_trial_session(mid, sid)
	if not bool(sess.get("success", false)):
		return sess
	return GameState.settle_pet_trial_battle(mid, true, sid)


func _assert_catalog() -> void:
	var svc = GameState.expansion_state_service.pet_collection_service
	var saved: Array = (svc.catalog.get("entries", []) as Array).duplicate(true)
	if not saved.is_empty():
		var rows: Array = (svc.catalog.get("entries", []) as Array).duplicate(true)
		rows.append((saved[0] as Dictionary).duplicate(true))
		svc.catalog["entries"] = rows
		var errs: Array = svc.validate_catalog()
		svc.catalog["entries"] = saved
		if errs.is_empty():
			_fail("PET_COLLECTION_DUP")
		elif str(errs[0]) != "PET_COLLECTION_DUP":
			_fail("PET_COLLECTION_DUP", str(errs[0]))
	var ok: Array = svc.validate_catalog()
	if not ok.is_empty():
		_fail("PET_COLLECTION_DUP", str(ok[0]))
	if svc.by_id.size() != 6:
		_fail("PET_COLLECTION_DUP", "count")


func _assert_collection() -> void:
	_reset()
	var owned: Dictionary = GameState.expansion_state_service.pet_collection_service.owned_from_pets(GameState.pets)
	if not owned.has("col_ad_light") or not owned.has("col_year_pig"):
		_fail("PET_COLLECTION_FAKE", "owned")
	if owned.has("col_holy"):
		_fail("PET_COLLECTION_FAKE", "holy")
	var miss: Dictionary = GameState.claim_collection_reward("col_nope", _op("colmiss"))
	if bool(miss.get("success", false)) or str(miss.get("code", "")) != "PET_COLLECTION_UNKNOWN":
		_fail("PET_COLLECTION_UNKNOWN")
	var fake: Dictionary = GameState.claim_collection_reward("col_holy", _op("colfake"))
	if bool(fake.get("success", false)) or str(fake.get("code", "")) != "PET_COLLECTION_FAKE":
		_fail("PET_COLLECTION_FAKE")
	var gold0 := GameState.gold
	var ok: Dictionary = GameState.claim_collection_reward("col_ad_light", _op("collight"))
	if not bool(ok.get("success", false)):
		_fail("PET_COLLECTION_UNKNOWN", str(ok.get("code", "")))
	if GameState.gold <= gold0:
		_fail("PET_COLLECTION_UNKNOWN", "gold")
	var dup: Dictionary = GameState.claim_collection_reward("col_ad_light", _op("coldup"))
	if bool(dup.get("success", false)) or str(dup.get("code", "")) != "PET_COLLECTION_REWARD_DUP":
		_fail("PET_COLLECTION_REWARD_DUP")
	var replay: Dictionary = GameState.claim_collection_reward("col_ad_heavy", "same-op")
	var replay2: Dictionary = GameState.claim_collection_reward("col_ad_heavy", "same-op")
	if not bool(replay.get("success", false)) or not bool(replay2.get("replayed", false)):
		_fail("PET_COLLECTION_REWARD_DUP", "replay")


func _assert_support() -> void:
	_reset()
	var miss: Dictionary = GameState.set_pet_support(99999, _op("supmiss"))
	if bool(miss.get("success", false)) or str(miss.get("code", "")) != "PET_SUPPORT_OWNED":
		_fail("PET_SUPPORT_OWNED")
	var dep: Dictionary = GameState.set_pet_support(1, _op("supdep"))
	if bool(dep.get("success", false)) or str(dep.get("code", "")) != "PET_SUPPORT_DEPLOYED":
		_fail("PET_SUPPORT_DEPLOYED")
	var pig := _pig_id()
	var lulu := _lulu_id()
	var a: Dictionary = GameState.set_pet_support(pig, _op("supa"))
	if not bool(a.get("success", false)):
		_fail("PET_SUPPORT_OWNED", str(a.get("code", "")))
	var b: Dictionary = GameState.set_pet_support(lulu, _op("supb"))
	if not bool(b.get("success", false)):
		_fail("PET_SUPPORT_OWNED", str(b.get("code", "")))
	var ids: Array = GameState.pet_endgame_runtime().get("support_ids", [])
	if ids.size() > 1:
		_fail("PET_SUPPORT_SECOND")
	if GameState.support_effect_value("world") != 0:
		_fail("PET_SUPPORT_SCENE")
	if GameState.support_effect_value("trial") != 1:
		_fail("PET_SUPPORT_SCENE", "trial")
	var st: Dictionary = GameState.try_start_pet_trial("pet_trial_1", _op("snapst"))
	if not bool(st.get("success", false)):
		_fail("PET_SUPPORT_SNAPSHOT", str(st.get("code", "")))
	var live: Dictionary = GameState.expansion_state.duplicate(true)
	var pe: Dictionary = (live.get("pet_endgame", {}) as Dictionary).duplicate(true)
	pe["support_effect"] = "explore_log"
	live["pet_endgame"] = pe
	GameState.expansion_state = live
	if GameState.support_effect_value("trial") != 1:
		_fail("PET_SUPPORT_SNAPSHOT")
	var stats: Dictionary = GameState.get_player_stats()
	if (stats.get("battle_pets", []) as Array).size() > 2:
		_fail("PET_SUPPORT_SECOND", "battle_pets")


func _assert_trials() -> void:
	_reset()
	var king0: Dictionary = GameState.try_start_pet_trial("pet_king", _op("king0"))
	if bool(king0.get("success", false)) or str(king0.get("code", "")) != "PET_TRIAL_KING":
		_fail("PET_TRIAL_KING")
	for tid in ["pet_trial_1", "pet_trial_2", "pet_trial_3"]:
		var r: Dictionary = _run_trial(str(tid))
		if not bool(r.get("success", false)):
			_fail("PET_TRIAL_KING", "%s %s" % [tid, str(r.get("code", ""))])
	var king1: Dictionary = _run_trial("pet_king")
	if not bool(king1.get("success", false)):
		_fail("PET_TRIAL_KING", str(king1.get("code", "")))
	_reset()
	var st: Dictionary = GameState.try_start_pet_trial("pet_trial_1", _op("canst"))
	var spec: Dictionary = GameState.expansion_state_service.pet_trial_service.spec_of("pet_trial_1")
	var mid := str(spec.get("monster_id", ""))
	GameState.begin_pet_trial_session(mid, "t:can")
	var gold0 := GameState.gold
	var can: Dictionary = GameState.settle_pet_trial_battle(mid, false, "t:can")
	if bool(can.get("success", false)) or str(can.get("code", "")) != "PET_TRIAL_CANCEL":
		_fail("PET_TRIAL_CANCEL")
	if GameState.gold != gold0:
		_fail("PET_TRIAL_CANCEL", "gold")
	_reset()
	GameState.try_start_pet_trial("pet_trial_1", _op("sess"))
	GameState.begin_pet_trial_session(mid, "t:good")
	var bad: Dictionary = GameState.settle_pet_trial_battle(mid, true, "t:old")
	if str(bad.get("code", "")) != "PET_TRIAL_CANCEL":
		_fail("PET_TRIAL_CANCEL", "old")
	_reset()
	_run_trial("pet_trial_1")
	var gold1 := GameState.gold
	var wdup: Dictionary = _run_trial("pet_trial_1")
	if not bool(wdup.get("success", false)):
		_fail("PET_TRIAL_WEEKLY_DUP", str(wdup.get("code", "")))
	if GameState.gold - gold1 >= 3:
		_fail("PET_TRIAL_WEEKLY_DUP")


func _assert_contracts() -> void:
	_reset()
	while GameState.count_item("soul_king") > 0:
		GameState.consume_item("soul_king", 1)
	var poor: Dictionary = GameState.claim_research_contract("rc_note", _op("rcpoor"))
	if bool(poor.get("success", false)) or str(poor.get("code", "")) != "RESEARCH_CONTRACT_COST":
		_fail("RESEARCH_CONTRACT_COST")
	_reset()
	var rate0 := int(GameState.research.get("production_rate", 0))
	var cap := int(GameState.pet_service.config.get("research", {}).get("technology_level_cap", 0))
	if cap != 300:
		_fail("RESEARCH_CONTRACT_COST", "cap")
	var ok: Dictionary = GameState.claim_research_contract("rc_note", _op("rcok"))
	if not bool(ok.get("success", false)):
		_fail("RESEARCH_CONTRACT_COST", str(ok.get("code", "")))
	if int(GameState.research.get("production_rate", 0)) != rate0:
		_fail("RESEARCH_CONTRACT_COST", "rate")
	var dup: Dictionary = GameState.claim_research_contract("rc_note", _op("rcdup"))
	if bool(dup.get("success", false)):
		_fail("RESEARCH_CONTRACT_COST", "dup")
	var bond: Dictionary = GameState.claim_research_contract("rc_bond", _op("rcbond"))
	if not bool(bond.get("success", false)):
		_fail("RESEARCH_CONTRACT_COST", str(bond.get("code", "")))


func _assert_save() -> void:
	_reset()
	GameState.claim_collection_reward("col_ad_light", _op("svcol"))
	GameState.set_pet_support(_pig_id(), _op("svsup"))
	_run_trial("pet_trial_1")
	if not GameState.save_game():
		_fail("SAVE_PET_ID", "save")
	var before: Dictionary = GameState.expansion_state.duplicate(true)
	if not GameState.load_game():
		_fail("SAVE_PET_ID", "load")
	var after: Dictionary = GameState.expansion_state
	var bpe: Dictionary = before.get("pet_endgame", {})
	var ape: Dictionary = after.get("pet_endgame", {})
	if str((bpe.get("first_claimed", {}) as Dictionary).keys()) != str((ape.get("first_claimed", {}) as Dictionary).keys()):
		_fail("SAVE_PET_ID", "first")
	var probe: Dictionary = after.duplicate(true)
	var pe: Dictionary = (probe.get("pet_endgame", {}) as Dictionary).duplicate(true)
	pe["support_instance_id"] = "bad"
	probe["pet_endgame"] = pe
	var verr: Array = GameState.expansion_state_service.pet_support_service.validate_save(probe)
	if verr.is_empty() or str(verr[0]) != "SAVE_PET_ID":
		_fail("SAVE_PET_ID")
	if GameState.SAVE_SCHEMA_KEYS.size() != 39:
		_fail("SAVE_PET_ID", "schema")


func _assert_adjacent() -> void:
	_reset()
	GameState.seed_challenge_prereqs()
	var ch: Dictionary = GameState.try_start_challenge("ch_arena", "official", _op("adjch"))
	if not bool(ch.get("success", false)):
		_fail("PET_TRIAL_KING", str(ch.get("code", "")))
	if _main.world.maps.size() != 50:
		_fail("PET_COLLECTION_DUP", "maps")
	var gro: int = 0
	_main._open_actor_dialogue("grocery")
	for child in _main.dialogue_panel.choices.get_children():
		if child is Button:
			gro += 1
	if gro != 3:
		_fail("PET_COLLECTION_DUP", "grocery")


func _finish() -> void:
	if _errors.is_empty():
		print("PASS pet endgame")
		get_tree().quit(0)
	else:
		print("FAIL %s" % ",".join(_errors))
		get_tree().quit(1)
