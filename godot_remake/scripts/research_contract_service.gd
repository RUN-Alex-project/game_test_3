extends RefCounted

const PATH := "res://data/research_endgame_contracts.json"
const REQUIRE_COST := true
const SKIP_DUP := true
const REQUIRE_WHITELIST := true
const ENFORCE_RATE_CAP := true

var by_id: Dictionary = {}
var rules: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	rules = parsed if parsed is Dictionary else {}
	file.close()
	for raw: Variant in rules.get("contracts", []):
		if raw is Dictionary:
			by_id[str(raw.get("contract_id", ""))] = raw


func normalize(raw: Variant) -> Dictionary:
	return preload("res://scripts/pet_collection_service.gd").new().normalize(raw)


func validate_save(_state: Dictionary) -> Array:
	return []


func _write(expansion: Dictionary, row: Dictionary) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	state["pet_endgame"] = row
	return state


func claim(expansion: Dictionary, contract_id: String, research: Dictionary, soul_king: int, max_bond: int, production_rate: int, operation_id: String) -> Dictionary:
	if not by_id.has(contract_id):
		return {"success": false, "code": "RESEARCH_CONTRACT_COST", "expansion": expansion}
	var spec: Dictionary = by_id[contract_id]
	var row: Dictionary = normalize(expansion.get("pet_endgame", {}))
	var ops: Dictionary = (row.get("operation_ids", {}) as Dictionary).duplicate(true)
	if ops.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var claimed: Dictionary = (row.get("contracts_claimed", {}) as Dictionary).duplicate(true)
	if claimed.has(contract_id) and SKIP_DUP:
		return {"success": false, "code": "RESEARCH_CONTRACT_COST", "expansion": expansion}
	if ENFORCE_RATE_CAP and production_rate > int(rules.get("production_rate_cap", 6)):
		return {"success": false, "code": "RESEARCH_CONTRACT_COST", "expansion": expansion}
	if float(research.get("technology_level", 0.0)) < float(spec.get("min_tech", 0)):
		return {"success": false, "code": "RESEARCH_CONTRACT_COST", "expansion": expansion}
	if max_bond < int(spec.get("min_bond", 0)):
		return {"success": false, "code": "RESEARCH_CONTRACT_COST", "expansion": expansion}
	var need := int(spec.get("soul_king", 0))
	if REQUIRE_COST and soul_king < need:
		return {"success": false, "code": "RESEARCH_CONTRACT_COST", "expansion": expansion}
	var item_id := str(spec.get("reward_item", "fruit"))
	var whitelist: Array = rules.get("whitelist", [])
	if REQUIRE_WHITELIST and not item_id in whitelist:
		return {"success": false, "code": "RESEARCH_CONTRACT_COST", "expansion": expansion}
	claimed[contract_id] = true
	row["contracts_claimed"] = claimed
	ops[operation_id] = true
	row["operation_ids"] = ops
	var ledger: Array = (row.get("pet_ledger", []) as Array).duplicate()
	ledger.append({"op": "contract", "id": contract_id, "operation_id": operation_id})
	row["pet_ledger"] = ledger
	return {
		"success": true,
		"code": "OK",
		"expansion": _write(expansion, row),
		"consume_soul_king": need if REQUIRE_COST else 0,
		"gold": int(spec.get("reward_gold", 0)),
		"item_id": item_id,
		"qty": int(spec.get("reward_qty", 1)),
		"rate_unchanged": true,
	}
