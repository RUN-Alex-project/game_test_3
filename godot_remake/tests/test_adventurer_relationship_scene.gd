extends Node

const SEED := 1297043285
const LIN := "npc_adv_lin_xia"


func _ready() -> void:
	assert(not GameState.has_method("set_relationship_value"), "ERR_DIRECT_REL_SETTER")
	_assert_stages()
	_assert_dirty_migration()
	_reset_expansion()
	_assert_gifts()
	_reset_expansion()
	_assert_commissions()
	print("PASS adventurer_relationship: v21 migrate seed, gifts, stages, six commissions, operation_id replay")
	get_tree().quit(0)


func _assert_stages() -> void:
	var rel = GameState.expansion_state_service.relationship_service
	assert(str(rel.stage_for(0).get("id", "")) == "acquaintance")
	assert(str(rel.stage_for(9).get("id", "")) == "acquaintance")
	assert(str(rel.stage_for(10).get("id", "")) == "friend")
	assert(str(rel.stage_for(199).get("id", "")) == "friend")
	assert(str(rel.stage_for(200).get("id", "")) == "confidant")
	assert(str(rel.stage_for(499).get("id", "")) == "confidant")
	assert(str(rel.stage_for(500).get("id", "")) == "lover")
	assert(str(rel.stage_for(999).get("id", "")) == "lover")
	assert(str(rel.stage_for(1000).get("id", "")) == "beloved")


func _assert_dirty_migration() -> void:
	GameState.save_path = "user://test_v143_migrate_v21.json"
	GameState.gold = 777777
	GameState.expansion_state["world_seed"] = 777
	var story_before: Dictionary = GameState.story_flags.duplicate(true)
	var file := FileAccess.open(GameState.save_path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"version": 21, "gold": 12345, "level": 4, "magic_stones": 9}))
	file.close()
	assert(GameState.load_game(), "v21 must migrate")
	assert(GameState.gold == 12345, "gold must come from file not runtime 777777")
	assert(int(GameState.expansion_state.get("world_seed", 0)) == SEED, "seed must be contract default not 777")
	assert(GameState.level == 4)
	var ids: Array = GameState.expansion_state.get("adventurers", {}).keys()
	assert(ids.size() == 12, "migrated roster size")
	assert(bool(GameState.story_flags.get("king_rescued", true)) == false)
	assert(story_before.has("king_rescued"))


func _reset_expansion() -> void:
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	GameState.current_day = 3
	GameState.current_map_id = "cassano_city"
	GameState.owned_territory = ""


func _rel_value(adv_id: String) -> int:
	return int(GameState.expansion_state.get("relationships", {}).get(adv_id, {}).get("value", 0))


func _assert_gifts() -> void:
	var story_snap: Dictionary = GameState.story_flags.duplicate(true)
	while GameState.count_item("rose") > 0:
		assert(GameState.consume_item("rose", 1))
	var missing: Dictionary = GameState.gift_adventurer(LIN, "rose", "gift_missing")
	assert(not bool(missing.get("success", true)) and str(missing.get("code", "")) == "ERR_GIFT_MISSING_ITEM")
	assert(GameState.add_item("rose", 5))
	var bound: Dictionary = GameState.gift_adventurer(LIN, "novice_sword", "gift_bound")
	assert(not bool(bound.get("success", true)) and str(bound.get("code", "")) == "ERR_GIFT_BOUND")
	var roses := GameState.count_item("rose")
	var ok: Dictionary = GameState.gift_adventurer(LIN, "rose", "gift_ok_1")
	assert(bool(ok.get("success", false)), str(ok))
	assert(GameState.count_item("rose") == roses - 1)
	assert(_rel_value(LIN) == 5)
	var limited: Dictionary = GameState.gift_adventurer(LIN, "rose", "gift_ok_2")
	assert(not bool(limited.get("success", true)) and str(limited.get("code", "")) == "ERR_GIFT_DAILY_LIMIT")
	assert(GameState.count_item("rose") == roses - 1)
	var replay: Dictionary = GameState.gift_adventurer(LIN, "rose", "gift_ok_1")
	assert(bool(replay.get("success", false)) and bool(replay.get("replayed", false)))
	assert(GameState.count_item("rose") == roses - 1)
	assert(_rel_value(LIN) == 5)
	assert(GameState.story_flags == story_snap)


func _assert_commissions() -> void:
	var story_snap: Dictionary = GameState.story_flags.duplicate(true)
	_run_collect()
	_run_explore()
	_run_kill()
	_run_deliver()
	_run_pet()
	_run_campaign()
	assert(GameState.story_flags == story_snap)


func _run_collect() -> void:
	var comm := "comm_collect_ore"
	assert(bool(GameState.accept_commission(comm, "acc_collect").get("success", false)))
	assert(GameState.add_ore_instance("silver_ore", 5))
	var before := GameState.count_item("silver_ore")
	var rel0 := _rel_value(LIN)
	var claim: Dictionary = GameState.claim_commission(comm, "clm_collect")
	assert(bool(claim.get("success", false)), str(claim))
	assert(GameState.count_item("silver_ore") == before - 1)
	assert(_rel_value(LIN) == rel0 + 3)
	var replay: Dictionary = GameState.claim_commission(comm, "clm_collect")
	assert(bool(replay.get("replayed", false)))
	assert(_rel_value(LIN) == rel0 + 3)
	assert(GameState.count_item("silver_ore") == before - 1)


func _run_explore() -> void:
	var comm := "comm_explore_thunder"
	assert(bool(GameState.accept_commission(comm, "acc_explore").get("success", false)))
	GameState.current_map_id = "thunder_continent"
	GameState.note_map_visit()
	assert(bool(GameState.claim_commission(comm, "clm_explore").get("success", false)))
	GameState.current_map_id = "cassano_city"


func _run_kill() -> void:
	var comm := "comm_kill_spider"
	assert(bool(GameState.accept_commission(comm, "acc_kill").get("success", false)))
	GameState.apply_victory_rewards({"monster_id": "spider", "experience": 0})
	assert(bool(GameState.claim_commission(comm, "clm_kill").get("success", false)))


func _run_deliver() -> void:
	var comm := "comm_deliver_fruit"
	assert(bool(GameState.accept_commission(comm, "acc_deliver").get("success", false)))
	if GameState.count_item("fruit") < 1:
		assert(GameState.add_item("fruit", 1))
	var before := GameState.count_item("fruit")
	assert(bool(GameState.claim_commission(comm, "clm_deliver").get("success", false)))
	assert(GameState.count_item("fruit") == before - 1)


func _run_pet() -> void:
	var comm := "comm_pet_train"
	assert(bool(GameState.accept_commission(comm, "acc_pet").get("success", false)))
	assert(GameState.pets.size() > 0)
	var pet: Dictionary = GameState.pets[0]
	pet["level"] = 2
	GameState.pets[0] = pet
	assert(bool(GameState.claim_commission(comm, "clm_pet").get("success", false)))


func _run_campaign() -> void:
	var comm := "comm_campaign_assist"
	assert(bool(GameState.accept_commission(comm, "acc_camp").get("success", false)))
	GameState.owned_territory = "thunder_continent"
	assert(bool(GameState.claim_commission(comm, "clm_camp").get("success", false)))
