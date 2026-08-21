extends Node

const LIN := "npc_adv_lin_xia"
const YE := "npc_adv_ye_fei"
const LIANG := "npc_adv_liang_chen"
const TANG := "npc_adv_tang_xue"

var _errors: Array = []


func _ready() -> void:
	if GameState == null:
		print("REGISTRY_FAIL: ERR_RANK_BOARD_MISSING GameState missing")
		get_tree().quit(1)
		return
	_assert_registry()
	_assert_boards_and_order()
	_assert_tie_stable()
	_assert_gear_changes_rank()
	_assert_preview()
	_assert_save_load()
	_assert_explore_and_day()
	_finish()


func _reset() -> void:
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	GameState.current_day = 1
	GameState.owned_territory = ""
	GameState.refresh_rankings()


func _assert_registry() -> void:
	var report: Dictionary = GameState.expansion_state_service.validate_data_files()
	for err in report.get("errors", []):
		_fail_raw(str(err))
	if GameState.has_method("transfer_item_to_npc"):
		_fail("ERR_DIRECT_TRANSFER", "transfer_item_to_npc exists")
	if GameState.has_method("set_combat_power"):
		_fail("ERR_DIRECT_TRANSFER", "set_combat_power exists")
	var src := FileAccess.get_file_as_string("res://scripts/ranking_panel.gd")
	if src.contains("npc_adv_lin_xia"):
		_fail("ERR_RANK_BOARD_MISSING", "ranking_panel hardcodes npc ids")


func _assert_boards_and_order() -> void:
	_reset()
	for board_id in ["combat_power", "pet", "arena", "explore", "merchant_reputation", "territory_contribution"]:
		var board: Dictionary = GameState.get_ranking_board(board_id)
		var entries: Array = board.get("entries", [])
		if entries.size() != 13:
			_fail("ERR_RANK_BOARD_MISSING", "%s size %d" % [board_id, entries.size()])
	var power_npcs: Array = _npc_ids(GameState.get_ranking_board("combat_power").get("entries", []))
	if power_npcs.is_empty() or str(power_npcs[0]) != LIANG:
		_fail("ERR_RANK_TIE_UNSTABLE", "combat top npc %s" % str(power_npcs))
	if str(power_npcs[power_npcs.size() - 1]) != TANG:
		_fail("ERR_RANK_TIE_UNSTABLE", "combat last npc %s" % str(power_npcs))
	var explore_npcs: Array = _npc_ids(GameState.get_ranking_board("explore").get("entries", []))
	if explore_npcs.is_empty() or str(explore_npcs[0]) != "npc_adv_shen_yao":
		_fail("ERR_RANK_TIE_UNSTABLE", "explore top npc %s" % str(explore_npcs))


func _assert_tie_stable() -> void:
	_reset()
	_set_gear(LIN, 5)
	GameState.refresh_rankings()
	var ids: Array = _tied_ids("arena", 0, 45)
	if ids.size() != 2:
		_fail("ERR_RANK_TIE_UNSTABLE", "tie size %s" % str(ids))
		return
	if str(ids[0]) >= str(ids[1]):
		_fail("ERR_RANK_TIE_UNSTABLE", "expected stable_id asc %s" % str(ids))


func _assert_gear_changes_rank() -> void:
	_reset()
	_set_gear(TANG, 200)
	GameState.refresh_rankings()
	var npcs: Array = _npc_ids(GameState.get_ranking_board("combat_power").get("entries", []))
	if npcs.is_empty() or str(npcs[0]) != TANG:
		_fail("ERR_RANK_TIE_UNSTABLE", "gear bonus did not move tang_xue to top npc %s" % str(npcs))


func _assert_preview() -> void:
	_reset()
	GameState.owned_territory = "cassano_city"
	GameState.refresh_rankings()
	var merchant: Dictionary = GameState.get_ranking_board("merchant_reputation")
	if bool(merchant.get("preview", false)):
		_fail("ERR_RANK_BOARD_MISSING", "merchant still preview")
	var territory: Dictionary = GameState.get_ranking_board("territory_contribution")
	if bool(territory.get("preview", false)):
		_fail("ERR_RANK_BOARD_MISSING", "territory still preview")
	var player_row := _entry_by_id(territory.get("entries", []), "player")
	if int(player_row.get("primary", -1)) != 1:
		_fail("ERR_RANK_BOARD_MISSING", "player territory %s" % str(player_row))
	if str(player_row.get("change_reason", "")) == "v1.47":
		_fail("ERR_RANK_BOARD_MISSING", "territory reason %s" % str(player_row.get("change_reason")))


func _assert_save_load() -> void:
	_reset()
	_set_gear(LIANG, 3)
	GameState.refresh_rankings()
	var before := _rank_snap(GameState.get_ranking_board("combat_power").get("entries", []))
	GameState.save_path = "user://test_v145_rank.json"
	if not GameState.save_game():
		_fail("ERR_RANK_BOARD_MISSING", "save failed")
		return
	_set_gear(TANG, 9)
	if not GameState.load_game():
		_fail("ERR_RANK_BOARD_MISSING", "load failed")
		return
	var after := _rank_snap(GameState.get_ranking_board("combat_power").get("entries", []))
	if before != after:
		_fail("ERR_RANK_TIE_UNSTABLE", "save/load ranks drifted")


func _assert_explore_and_day() -> void:
	_reset()
	GameState.current_map_id = "palace"
	GameState.note_map_visit()
	var player_row := _entry_by_id(GameState.get_ranking_board("explore").get("entries", []), "player")
	if int(player_row.get("primary", 0)) < 1:
		_fail("ERR_RANK_BOARD_MISSING", "explore score %s" % str(player_row))
	var before := int(GameState.expansion_state.get("adventurers", {}).get(LIANG, {}).get("arena_score", 0))
	var applied: Dictionary = GameState.expansion_state_service.day_cycle_service._apply_action(
		GameState.expansion_state, LIANG, "arena_prep", 1, "test_arena_prep")
	GameState.expansion_state = applied
	var after := int(GameState.expansion_state.get("adventurers", {}).get(LIANG, {}).get("arena_score", 0))
	if after != before + 1:
		_fail("ERR_RANK_BOARD_MISSING", "arena_prep score %d->%d" % [before, after])


func _set_gear(adv_id: String, bonus: int) -> void:
	var state: Dictionary = GameState.expansion_state.duplicate(true)
	var adventurers: Dictionary = (state.get("adventurers", {}) as Dictionary).duplicate(true)
	var runtime: Dictionary = (adventurers.get(adv_id, {}) as Dictionary).duplicate(true)
	runtime["gear_bonus"] = bonus
	adventurers[adv_id] = runtime
	state["adventurers"] = adventurers
	GameState.expansion_state = state


func _rank_snap(entries: Array) -> String:
	var parts: Array[String] = []
	for raw_entry: Variant in entries:
		if raw_entry is Dictionary:
			parts.append("%s:%d:%d" % [
				str(raw_entry.get("id", "")),
				int(raw_entry.get("rank", 0)),
				int(raw_entry.get("primary", 0)),
			])
	return ",".join(parts)


func _npc_ids(entries: Array) -> Array:
	var out: Array = []
	for raw_entry: Variant in entries:
		if raw_entry is Dictionary and str(raw_entry.get("id", "")) != "player":
			out.append(str(raw_entry.get("id", "")))
	return out


func _tied_ids(board_id: String, primary: int, secondary: int) -> Array:
	var out: Array = []
	for raw_entry: Variant in GameState.get_ranking_board(board_id).get("entries", []):
		if not raw_entry is Dictionary:
			continue
		if int(raw_entry.get("primary", -1)) == primary and int(raw_entry.get("secondary", -1)) == secondary:
			out.append(str(raw_entry.get("id", "")))
	return out


func _entry_by_id(entries: Array, entry_id: String) -> Dictionary:
	for raw_entry: Variant in entries:
		if raw_entry is Dictionary and str(raw_entry.get("id", "")) == entry_id:
			return raw_entry
	return {}


func _fail(code: String, detail: String) -> void:
	_errors.append("%s %s" % [code, detail])


func _fail_raw(text: String) -> void:
	_errors.append(text)


func _finish() -> void:
	if _errors.size() > 0:
		print("REGISTRY_FAIL: " + "; ".join(_errors))
		get_tree().quit(1)
		return
	print("PASS ranking: six boards from data, stable ties, gear changes order, preview boards, save/load")
	get_tree().quit(0)
