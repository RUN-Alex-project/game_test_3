extends RefCounted

const MATRIX_PATH := "res://docs/long_flow_matrix_v155.json"
const AUDIT_PATH := "res://docs/balance_audit_v155.json"
const REGISTRY_PATH := "res://docs/value_audit_registry.json"
const BASELINE_PATH := "res://docs/current_test_baseline.json"
const MANIFEST_PATH := "res://tests/test_manifest.json"
const V21_PATH := "res://tests/fixtures/save_v21.json"
const FUTURE_PATH := "res://tests/fixtures/save_future.json"
const CORRUPT_PATH := "res://tests/fixtures/save_corrupt.json"
const CombatServiceScript = preload("res://scripts/combat_service.gd")

const REQUIRE_MATRIX := true
const REQUIRE_ALL_FLOWS := true
const BLOCK_FAKE_TERMINAL := true
const REQUIRE_SAVE_POINTS := true
const REQUIRE_FROZEN := true
const REQUIRE_AUDIT := true
const BLOCK_DOUBLE := true
const BLOCK_OP_DUP := true
const REQUIRE_LEDGER := true
const REQUIRE_V21 := true
const REQUIRE_V22_TYPE := true
const REJECT_FUTURE := true
const REQUIRE_ATOMIC := true
const BLOCK_SEASON_DUP := true
const BLOCK_ARBITRAGE := true
const REQUIRE_NO_LEAK := true
const BLOCK_SKIP := true
const REQUIRE_RC := true
const REQUIRE_APP_READY := true
const REQUIRE_BASELINE := true

var matrix: Dictionary = {}
var audit: Dictionary = {}
var registry: Dictionary = {}
var ledger: Array = []
var ops: Dictionary = {}
var combat = CombatServiceScript.new()


func _init() -> void:
	matrix = _load_json(MATRIX_PATH)
	audit = _load_json(AUDIT_PATH)
	registry = _load_json(REGISTRY_PATH)


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func flow_ids() -> Array:
	var ids: Array = []
	for raw: Variant in matrix.get("flows", []):
		if raw is Dictionary:
			ids.append(str(raw.get("flow_id", "")))
	return ids


func record(op: String) -> Dictionary:
	if ops.has(op) and BLOCK_OP_DUP:
		return {"success": false, "code": "LEDGER_OP_DUP"}
	ops[op] = int(ops.get(op, 0)) + 1
	ledger.append(op)
	return {"success": true, "code": "OK"}


func validate_matrix() -> String:
	if REQUIRE_MATRIX:
		var ids: Array = flow_ids()
		if ids.size() != 10:
			return "FLOW_SET"
		var seen: Dictionary = {}
		for fid in ids:
			if seen.has(fid):
				return "FLOW_SET"
			seen[fid] = true
	else:
		return "FLOW_SET"
	return ""


func frozen_error() -> String:
	if not REQUIRE_AUDIT:
		return "BALANCE_AUDIT"
	var items: Array = audit.get("items", [])
	if items.is_empty():
		return "BALANCE_AUDIT"
	if not REQUIRE_FROZEN:
		return "VALUE_OVERRIDE"
	var by_id: Dictionary = {}
	for raw: Variant in registry.get("values", []):
		if raw is Dictionary:
			by_id[str(raw.get("value_id", ""))] = raw.get("effective_value")
	for raw: Variant in items:
		if not raw is Dictionary:
			continue
		var vid := str(raw.get("value_id", ""))
		if vid in ["grocery_option_count", "save_schema_keys"]:
			continue
		if not by_id.has(vid):
			return "VALUE_OVERRIDE"
		if not _same(by_id[vid], raw.get("candidate")):
			return "VALUE_OVERRIDE"
	return ""


func _same(a: Variant, b: Variant) -> bool:
	if a is float or b is float:
		return is_equal_approx(float(a), float(b))
	return str(a) == str(b)
