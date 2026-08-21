extends RefCounted

const CAT_PATH := "res://data/pet_collection_catalog.json"
const VALIDATE_CATALOG := true
const REQUIRE_REAL_OWNED := true
const SKIP_REWARD_DUP := true
const REQUIRE_WHITELIST := true

var catalog: Dictionary = {}
var by_id: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(CAT_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	catalog = parsed if parsed is Dictionary else {}
	file.close()
	for raw: Variant in catalog.get("entries", []):
		if raw is Dictionary:
			by_id[str(raw.get("collection_id", ""))] = raw


func empty_runtime() -> Dictionary:
	return {
		"owned": {},
		"rewards_claimed": {},
		"support_instance_id": 0,
		"support_ids": [],
		"support_effect": "trial_resist",
		"support_snapshot": {},
		"trial_records": {},
		"first_claimed": {},
		"weekly_claimed": {},
		"active_trial_id": "",
		"active_session_id": "",
		"contracts_claimed": {},
		"operation_ids": {},
		"pet_ledger": [],
	}


func normalize(raw: Variant) -> Dictionary:
	var base := empty_runtime()
	var row: Dictionary = {}
	if raw is Dictionary:
		row = (raw as Dictionary).duplicate(true)
	for key in base.keys():
		if not row.has(key):
			row[key] = base[key]
	if not row.get("owned") is Dictionary:
		row["owned"] = {}
	if not row.get("rewards_claimed") is Dictionary:
		row["rewards_claimed"] = {}
	if not row.get("support_ids") is Array:
		row["support_ids"] = []
	if not row.get("support_snapshot") is Dictionary:
		row["support_snapshot"] = {}
	if not row.get("trial_records") is Dictionary:
		row["trial_records"] = {}
	if not row.get("first_claimed") is Dictionary:
		row["first_claimed"] = {}
	if not row.get("weekly_claimed") is Dictionary:
		row["weekly_claimed"] = {}
	if not row.get("contracts_claimed") is Dictionary:
		row["contracts_claimed"] = {}
	if not row.get("operation_ids") is Dictionary:
		row["operation_ids"] = {}
	if not row.get("pet_ledger") is Array:
		row["pet_ledger"] = []
	row["support_instance_id"] = int(row.get("support_instance_id", 0))
	return row


func validate_catalog() -> Array:
	var rows: Array = catalog.get("entries", [])
	var ids: Dictionary = {}
	if VALIDATE_CATALOG and rows.size() != int(catalog.get("expected_count", 6)):
		return ["PET_COLLECTION_DUP"]
	for raw: Variant in rows:
		if not raw is Dictionary:
			return ["PET_COLLECTION_DUP"]
		var cid := str((raw as Dictionary).get("collection_id", ""))
		if cid.is_empty() or (VALIDATE_CATALOG and ids.has(cid)):
			return ["PET_COLLECTION_DUP"]
		ids[cid] = true
	if VALIDATE_CATALOG and ids.size() != 6:
		return ["PET_COLLECTION_DUP"]
	return []


func validate_save(state: Dictionary) -> Array:
	return []


func owned_from_pets(pets: Array) -> Dictionary:
	var owned: Dictionary = {}
	if not REQUIRE_REAL_OWNED:
		for cid in by_id.keys():
			owned[str(cid)] = true
		return owned
	var templates: Dictionary = {}
	for raw: Variant in pets:
		if raw is Dictionary:
			templates[str((raw as Dictionary).get("template_id", ""))] = true
	for cid in by_id.keys():
		var spec: Dictionary = by_id[cid]
		if templates.has(str(spec.get("template_id", ""))):
			owned[str(cid)] = true
	return owned


func _write(expansion: Dictionary, row: Dictionary) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	state["pet_endgame"] = row
	return state


func claim(expansion: Dictionary, collection_id: String, pets: Array, operation_id: String) -> Dictionary:
	if not by_id.has(collection_id):
		return {"success": false, "code": "PET_COLLECTION_UNKNOWN", "expansion": expansion}
	var row: Dictionary = normalize(expansion.get("pet_endgame", {}))
	var ops: Dictionary = (row.get("operation_ids", {}) as Dictionary).duplicate(true)
	if ops.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var owned: Dictionary = owned_from_pets(pets)
	row["owned"] = owned
	if not owned.has(collection_id):
		return {"success": false, "code": "PET_COLLECTION_FAKE", "expansion": expansion}
	var spec: Dictionary = by_id[collection_id]
	var rid := str(spec.get("reward_id", ""))
	var claimed: Dictionary = (row.get("rewards_claimed", {}) as Dictionary).duplicate(true)
	if claimed.has(rid) and SKIP_REWARD_DUP:
		return {"success": false, "code": "PET_COLLECTION_REWARD_DUP", "expansion": expansion}
	var item_id := str(spec.get("reward_item", "fruit"))
	var whitelist: Array = catalog.get("whitelist", [])
	if REQUIRE_WHITELIST and not item_id in whitelist:
		return {"success": false, "code": "PET_COLLECTION_UNKNOWN", "expansion": expansion}
	claimed[rid] = true
	row["rewards_claimed"] = claimed
	ops[operation_id] = true
	row["operation_ids"] = ops
	var ledger: Array = (row.get("pet_ledger", []) as Array).duplicate()
	ledger.append({"op": "claim", "id": collection_id, "operation_id": operation_id})
	row["pet_ledger"] = ledger
	return {
		"success": true,
		"code": "OK",
		"expansion": _write(expansion, row),
		"gold": int(spec.get("reward_gold", 0)),
		"item_id": item_id,
		"qty": int(spec.get("reward_qty", 1)),
	}
