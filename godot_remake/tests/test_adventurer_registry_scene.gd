extends Node

const FIRST_IDS := [
	"npc_adv_lin_xia", "npc_adv_su_yan", "npc_adv_liang_chen", "npc_adv_jiang_yue",
	"npc_adv_qin_he", "npc_adv_gu_ning", "npc_adv_ye_fei", "npc_adv_bai_luo",
	"npc_adv_xiao_ran", "npc_adv_tang_xue", "npc_adv_he_ming", "npc_adv_shen_yao",
]
const HISTORY_PROBE := "res://work/v143/history_probe.json"
const SCHEMA_PATH := "res://docs/save_schema_registry.json"
const CONTRACT_PATH := "res://docs/expansion_data_contract_v22.json"
const MOYU_PATH := "res://docs/moyu_23_24_content_registry.json"

var _errors: Array = []


func _ready() -> void:
	var report: Dictionary = GameState.expansion_state_service.validate_data_files()
	for err in report.get("errors", []):
		_fail_raw(str(err))

	var ids: Array[String] = GameState.expansion_state_service.adventurer_service.all_ids()
	if ids.size() != 12:
		_fail("ERR_ADV_COUNT", "roster size %d" % ids.size())
	for adv_id in FIRST_IDS:
		if adv_id not in ids:
			_fail("ERR_ADV_COUNT", "missing %s" % adv_id)
	for adv_id in ids:
		if adv_id not in FIRST_IDS:
			_fail("ERR_BACKUP_IN_PROD", "unexpected %s" % adv_id)
		if str(adv_id).begins_with("npc_adv_b") and str(adv_id).substr(9).is_valid_int():
			_fail("ERR_BACKUP_IN_PROD", adv_id)

	var state: Dictionary = GameState.expansion_state_service.default_enabled_state()
	var adv_keys: Array = state.get("adventurers", {}).keys()
	var rel_keys: Array = state.get("relationships", {}).keys()
	adv_keys.sort()
	rel_keys.sort()
	var id_copy: Array = ids.duplicate()
	id_copy.sort()
	if adv_keys != id_copy or rel_keys != id_copy:
		_fail("ERR_ADV_COUNT", "runtime keys mismatch roster")
	if int(state.get("world_seed", 0)) != 1297043285:
		_fail("ERR_EXPANSION_MISSING", "default seed %s" % str(state.get("world_seed")))

	_check_schema()
	_check_contract()
	_check_moyu_first()
	_check_history_probe()
	if GameState.has_method("set_relationship_value"):
		_fail("ERR_DIRECT_REL_SETTER", "GameState.set_relationship_value exists")
	_finish()


func _check_schema() -> void:
	var schema: Dictionary = _read_json(SCHEMA_PATH)
	var decision: Dictionary = schema.get("schema_decision", {})
	if int(decision.get("version", 0)) != 22:
		_fail("ERR_EXPANSION_MISSING", "schema version %s" % str(decision.get("version")))
	if not bool(decision.get("upgrade", false)):
		_fail("ERR_EXPANSION_MISSING", "schema upgrade false")
	var found := false
	for field in schema.get("fields", []):
		if field is Dictionary and str(field.get("path", "")) == "expansion_state":
			found = true
	if not found:
		_fail("ERR_EXPANSION_MISSING", "save_schema_registry missing expansion_state")
	if "expansion_state" not in GameState.SAVE_SCHEMA_KEYS:
		_fail("ERR_EXPANSION_MISSING", "SAVE_SCHEMA_KEYS missing expansion_state")
	if GameState.SAVE_SCHEMA_KEYS.size() != 39:
		_fail("ERR_EXPANSION_MISSING", "SAVE_SCHEMA_KEYS size %d" % GameState.SAVE_SCHEMA_KEYS.size())
	var strict_payload: Dictionary = GameState._build_save_payload()
	strict_payload.erase("expansion_state")
	if GameState._validate_save_schema(strict_payload):
		_fail("ERR_EXPANSION_MISSING", "strict v22 accepted missing expansion_state")


func _check_contract() -> void:
	var contract: Dictionary = _read_json(CONTRACT_PATH)
	if str(contract.get("status", "")) != "ENABLED":
		_fail("ERR_CONTRACT_ENABLED", "status=%s" % str(contract.get("status")))


func _check_moyu_first() -> void:
	var registry: Dictionary = _read_json(MOYU_PATH)
	var first: Array = []
	for entry in registry.get("entries", []):
		if not entry is Dictionary:
			continue
		if str(entry.get("kind", "")) == "npc" and str(entry.get("cohort", "")) == "first":
			first.append(str(entry.get("id", "")))
	first.sort()
	var expect: Array = FIRST_IDS.duplicate()
	expect.sort()
	if first != expect:
		_fail("ERR_ADV_COUNT", "moyu first cohort mismatch")


func _check_history_probe() -> void:
	var probe: Dictionary = _read_json(HISTORY_PROBE)
	if probe.is_empty():
		_fail("ERR_DUP_HISTORY_OP", "history probe missing")
		return
	if not GameState.expansion_state_service.relationship_service.history_operation_ids_unique(probe):
		_fail("ERR_DUP_HISTORY_OP", "history probe duplicate operation_id")


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("ERR_JSON_PARSE", path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("ERR_JSON_PARSE", path)
		return {}
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
	print("PASS adventurer_registry: 12 ids, no backup, schema v22 expansion_state, contract ENABLED, unique history ops, no set_relationship_value")
	get_tree().quit(0)
