extends RefCounted

const REQUIRE_BALANCED := true


func append(market: Dictionary, payload: Dictionary) -> Dictionary:
	var out: Dictionary = market.duplicate(true)
	var gold_delta := int(payload.get("gold_delta", 0))
	var gold_before := int(payload.get("gold_before", 0))
	var gold_after := int(payload.get("gold_after", gold_before + gold_delta))
	if REQUIRE_BALANCED and gold_after - gold_before != gold_delta:
		out["ledger_error"] = "LEDGER_AMOUNT"
		return out
	if not REQUIRE_BALANCED:
		gold_delta += 1
		gold_after = gold_before + gold_delta
	var entries: Array = (out.get("ledger", []) as Array).duplicate()
	entries.append({
		"operation_id": str(payload.get("operation_id", "")),
		"day": int(payload.get("day", 0)),
		"reason": str(payload.get("reason", "")),
		"gold_delta": gold_delta,
		"gold_before": gold_before,
		"gold_after": gold_after,
		"item_id": str(payload.get("item_id", "")),
		"item_qty": int(payload.get("item_qty", 0)),
		"related_id": str(payload.get("related_id", "")),
	})
	out["ledger"] = entries
	return out
