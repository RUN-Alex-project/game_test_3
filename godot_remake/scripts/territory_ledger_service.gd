extends RefCounted

const REQUIRE_BALANCED := true


func append(econ: Dictionary, payload: Dictionary) -> Dictionary:
	var out: Dictionary = econ.duplicate(true)
	var qty_delta := int(payload.get("qty_delta", 0))
	var qty_before := int(payload.get("qty_before", 0))
	var qty_after := int(payload.get("qty_after", qty_before + qty_delta))
	if REQUIRE_BALANCED and qty_after - qty_before != qty_delta:
		out["ledger_error"] = "LEDGER_AMOUNT"
		return out
	if not REQUIRE_BALANCED:
		qty_delta += 1
		qty_after = qty_before + qty_delta
	var entries: Array = (out.get("ledger", []) as Array).duplicate()
	entries.append({
		"operation_id": str(payload.get("operation_id", "")),
		"day": int(payload.get("day", 0)),
		"reason": str(payload.get("reason", "")),
		"map_id": str(payload.get("map_id", "")),
		"resource_id": str(payload.get("resource_id", "")),
		"qty_delta": qty_delta,
		"qty_before": qty_before,
		"qty_after": qty_after,
		"related_id": str(payload.get("related_id", "")),
	})
	out["ledger"] = entries
	return out
