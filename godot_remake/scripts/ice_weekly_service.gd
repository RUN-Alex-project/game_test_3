extends RefCounted

const REWARD_PATH := "res://data/ice_element_rewards.json"
const SKIP_SAME_WEEK := true

var rewards: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(REWARD_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	rewards = parsed if parsed is Dictionary else {}


func week_index(day: int) -> int:
	return int(floor(float(maxi(1, day) - 1) / 7.0))


func ensure_week(expansion: Dictionary, day: int) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var chapters: Dictionary = (state.get("chapters", {}) as Dictionary).duplicate(true)
	var row: Dictionary = (chapters.get("ice_element", {}) as Dictionary).duplicate(true)
	var wk: Dictionary = (row.get("weekly_contract", {}) as Dictionary).duplicate(true)
	var week := week_index(day)
	if int(wk.get("week", -1)) != week:
		wk = {"week": week, "settled": false, "claimed": false}
		row["weekly_contract"] = wk
		chapters["ice_element"] = row
		state["chapters"] = chapters
	return state


func claim(expansion: Dictionary, day: int, operation_id: String) -> Dictionary:
	var state: Dictionary = ensure_week(expansion, day)
	var chapters: Dictionary = (state.get("chapters", {}) as Dictionary).duplicate(true)
	var row: Dictionary = (chapters.get("ice_element", {}) as Dictionary).duplicate(true)
	var claims: Dictionary = (row.get("reward_claims", {}) as Dictionary).duplicate(true)
	if claims.has(operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var wk: Dictionary = (row.get("weekly_contract", {}) as Dictionary).duplicate(true)
	if str(row.get("stage", "")) != "weekly_element_trial":
		return {"success": false, "code": "ICE_PRECONDITION", "expansion": expansion}
	if SKIP_SAME_WEEK and bool(wk.get("claimed", false)):
		return {"success": false, "code": "ICE_WEEKLY_DUP", "expansion": expansion}
	wk["claimed"] = true
	wk["settled"] = true
	claims[operation_id] = true
	row["weekly_contract"] = wk
	row["reward_claims"] = claims
	row["last_weekly_claim_day"] = day
	var ledger: Array = (row.get("ice_ledger", []) as Array).duplicate()
	ledger.append({"op": "weekly", "day": day})
	row["ice_ledger"] = ledger
	chapters["ice_element"] = row
	state["chapters"] = chapters
	var spec: Dictionary = rewards.get("weekly", {})
	return {
		"success": true,
		"code": "OK",
		"expansion": state,
		"gold": int(spec.get("gold", 0)),
		"item_id": str(spec.get("item_id", "")),
		"qty": int(spec.get("qty", 1)),
	}
