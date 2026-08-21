extends Node

const LIN := "npc_adv_lin_xia"
const SEED := 1297043285
const PROBE_PATH := "res://work/v144/mailbox_probe.json"

var _errors: Array = []


func _ready() -> void:
	_assert_registry()
	_assert_seed_mix()
	_assert_thirty_days()
	_assert_same_day()
	_assert_advance_day_hook()
	_assert_save_no_repeat()
	_finish()


func _assert_registry() -> void:
	var report: Dictionary = GameState.expansion_state_service.validate_data_files()
	for err in report.get("errors", []):
		_fail_raw(str(err))
	if GameState.has_method("transfer_item_to_npc"):
		_fail("ERR_DIRECT_TRANSFER", "GameState.transfer_item_to_npc exists")
	var probe: Dictionary = _read_json(PROBE_PATH)
	for err in GameState.expansion_state_service.mail_service.validate_mailbox(probe):
		_fail_raw(str(err))
	var src := FileAccess.get_file_as_string("res://scripts/day_cycle_service.gd")
	if not src.contains("fnv1a32") or not src.contains("USE_WORLD_SEED"):
		_fail("ERR_NONDETERMINISTIC_RNG", "day_cycle_service")
	var state: Dictionary = GameState.expansion_state_service.default_enabled_state()
	var ledgers: Dictionary = state.get("economy", {}).get("adventurer_ledgers", {})
	if ledgers.size() != 12:
		_fail("ERR_LEDGER_MISMATCH", "ledger count %d" % ledgers.size())
	for adv_id in GameState.expansion_state_service.adventurer_service.all_ids():
		var ledger: Dictionary = ledgers.get(adv_id, {})
		if int(ledger.get("daily_budget", -1)) < 0 or int(ledger.get("gold", -1)) < 0:
			_fail("ERR_NEG_BUDGET", adv_id)


func _assert_seed_mix() -> void:
	var cycle = GameState.expansion_state_service.day_cycle_service
	var a := cycle.mix(1, 1, "day_cycle", LIN, 0)
	var b := cycle.mix(2, 1, "day_cycle", LIN, 0)
	if a == b:
		_fail("ERR_SEED_IGNORED", "mix(1)==mix(2)==%d" % a)


func _assert_thirty_days() -> void:
	var cycle = GameState.expansion_state_service.day_cycle_service
	var first: Dictionary = _run_days(GameState.expansion_state_service.default_enabled_state(), 30)
	var second: Dictionary = _run_days(GameState.expansion_state_service.default_enabled_state(), 30)
	if _snap(first) != _snap(second):
		_fail("ERR_DOUBLE_SETTLE", "30-day snapshots differ")
	if int(first.get("day_sequence", 0)) != 30:
		_fail("ERR_DOUBLE_SETTLE", "day_sequence %s" % str(first.get("day_sequence")))
	for day in range(1, 31):
		if _log_count(first, day) != 12:
			_fail("ERR_DOUBLE_SETTLE", "day %d log %d" % [day, _log_count(first, day)])
	for adv_id in GameState.expansion_state_service.adventurer_service.all_ids():
		var ledger: Dictionary = first.get("economy", {}).get("adventurer_ledgers", {}).get(adv_id, {})
		if (ledger.get("ledger_entries", []) as Array).is_empty():
			_fail("ERR_LEDGER_MISMATCH", "no entries %s" % adv_id)
		if int(ledger.get("last_settlement_day", 0)) != 30:
			_fail("ERR_DOUBLE_SETTLE", "last day %s %s" % [adv_id, str(ledger.get("last_settlement_day"))])


func _assert_same_day() -> void:
	var cycle = GameState.expansion_state_service.day_cycle_service
	var start: Dictionary = GameState.expansion_state_service.default_enabled_state()
	var once: Dictionary = cycle.settle_ended_day(start, 1)
	var twice: Dictionary = cycle.settle_ended_day(once.expansion, 1)
	var log_size := _log_count(twice.expansion, 1)
	if log_size != 12:
		_fail("ERR_DOUBLE_SETTLE", "same-day log %d" % log_size)
	if int(twice.expansion.get("day_sequence", 0)) != 1:
		_fail("ERR_DOUBLE_SETTLE", "same-day sequence %s" % str(twice.expansion.get("day_sequence")))
	if int(twice.get("settled_count", -1)) != 0:
		_fail("ERR_DOUBLE_SETTLE", "second settle count %s" % str(twice.get("settled_count")))
	for adv_id in GameState.expansion_state_service.adventurer_service.all_ids():
		var ledger: Dictionary = once.expansion.get("economy", {}).get("adventurer_ledgers", {}).get(adv_id, {})
		if (ledger.get("ledger_entries", []) as Array).is_empty():
			_fail("ERR_LEDGER_MISMATCH", "day1 no entry %s" % adv_id)


func _assert_advance_day_hook() -> void:
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	GameState.current_day = 1
	var gold_before := GameState.gold
	var stones_before := GameState.magic_stones
	GameState.advance_day()
	if GameState.current_day != 2:
		_fail("ERR_DOUBLE_SETTLE", "current_day %d" % GameState.current_day)
	if GameState.gold != gold_before or GameState.magic_stones != stones_before:
		_fail("ERR_LEDGER_MISMATCH", "settle mutated player currency")
	if _log_count(GameState.expansion_state, 1) != 12:
		_fail("ERR_DOUBLE_SETTLE", "advance_day log %d" % _log_count(GameState.expansion_state, 1))
	if int(GameState.expansion_state.get("day_sequence", 0)) != 1:
		_fail("ERR_DOUBLE_SETTLE", "advance sequence")


func _assert_save_no_repeat() -> void:
	GameState.save_path = "user://test_v144_daycycle.json"
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	GameState.current_day = 1
	GameState.advance_day()
	if not GameState.save_game():
		_fail("ERR_DOUBLE_SETTLE", "save failed")
		return
	if not GameState.load_game():
		_fail("ERR_DOUBLE_SETTLE", "load failed")
		return
	var again: Dictionary = GameState.expansion_state_service.day_cycle_service.settle_ended_day(GameState.expansion_state, 1)
	if int(again.get("settled_count", -1)) != 0:
		_fail("ERR_DOUBLE_SETTLE", "loaded settle count %s" % str(again.get("settled_count")))
	if _log_count(again.expansion, 1) != 12:
		_fail("ERR_DOUBLE_SETTLE", "loaded log %d" % _log_count(again.expansion, 1))


func _run_days(start: Dictionary, days: int) -> Dictionary:
	var cycle = GameState.expansion_state_service.day_cycle_service
	var state: Dictionary = start
	for day in range(1, days + 1):
		var result: Dictionary = cycle.settle_ended_day(state, day)
		state = result.expansion
	return state


func _snap(state: Dictionary) -> String:
	return JSON.stringify({
		"day_sequence": int(state.get("day_sequence", 0)),
		"mailbox": state.get("mailbox", []),
		"economy": state.get("economy", {}),
	})


func _log_count(state: Dictionary, day: int) -> int:
	var total := 0
	for raw_row: Variant in state.get("economy", {}).get("daily_settlement_log", []):
		if raw_row is Dictionary and int(raw_row.get("day", 0)) == day:
			total += 1
	return total


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("ERR_MAIL_FAKE_ATTACH", "missing %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _fail(code: String, detail: String) -> void:
	_errors.append("%s %s" % [code, detail])


func _fail_raw(text: String) -> void:
	_errors.append(text)


func _finish() -> void:
	if _errors.size() > 0:
		print("REGISTRY_FAIL: " + "; ".join(_errors))
		get_tree().quit(1)
		return
	print("PASS day_cycle: seed mix, 30-day replay, same-day skip, advance_day hook, save no repeat, 12 actions/day")
	get_tree().quit(0)
