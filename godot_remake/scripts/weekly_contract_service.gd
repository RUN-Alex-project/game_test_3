extends RefCounted

const REWARD_PATH := "res://data/treeheart_harbor_rewards.json"
const SKIP_SAME_WEEK := true
const USE_WORLD_SEED := true

var rewards: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(REWARD_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	rewards = parsed if parsed is Dictionary else {}


func week_index(day: int) -> int:
	return int(floor(float(maxi(1, day) - 1) / 7.0))


func mix(world_seed: int, week: int) -> int:
	var h := 2166136261
	h = (h * 16777619) ^ world_seed
	h = (h * 16777619) ^ week
	return abs(h)


func ensure_week(expansion: Dictionary, day: int) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var chapters: Dictionary = (state.get("chapters", {}) as Dictionary).duplicate(true)
	var row: Dictionary = (chapters.get("treeheart_harbor", {}) as Dictionary).duplicate(true)
	if str(row.get("stage", "locked")) != "treeheart_weekly_contract":
		state["chapters"] = chapters
		chapters["treeheart_harbor"] = row
		state["chapters"] = chapters
		return state
	var week := week_index(day)
	var contract: Dictionary = (row.get("weekly_contract", {}) as Dictionary).duplicate(true)
	var world_seed := 0
	if USE_WORLD_SEED:
		world_seed = int(state.get("world_seed", 0))
	if int(contract.get("week", -1)) != week:
		var seed_value := mix(world_seed, week)
		var spec: Dictionary = (rewards.get("weekly_reward", {}) as Dictionary).duplicate(true)
		contract = {
			"week": week,
			"seed": seed_value,
			"settled": false,
			"gold": int(spec.get("gold", 0)),
			"item_id": str(spec.get("item_id", "fruit")),
			"qty": int(spec.get("qty", 1)),
		}
		row["weekly_contract"] = contract
	chapters["treeheart_harbor"] = row
	state["chapters"] = chapters
	return state


func claim(expansion: Dictionary, day: int, operation_id: String) -> Dictionary:
	var state := ensure_week(expansion, day)
	var chapters: Dictionary = (state.get("chapters", {}) as Dictionary).duplicate(true)
	var row: Dictionary = (chapters.get("treeheart_harbor", {}) as Dictionary).duplicate(true)
	if str(row.get("stage", "")) != "treeheart_weekly_contract":
		return {"success": false, "code": "WEEKLY_DUP", "expansion": expansion}
	var ops: Array = (row.get("completed_operation_ids", []) as Array).duplicate()
	if operation_id in ops:
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": state, "replayed": true}
	var contract: Dictionary = (row.get("weekly_contract", {}) as Dictionary).duplicate(true)
	if SKIP_SAME_WEEK and bool(contract.get("settled", false)):
		return {"success": false, "code": "WEEKLY_DUP", "expansion": state}
	contract["settled"] = true
	ops.append(operation_id)
	row["completed_operation_ids"] = ops
	row["last_weekly_claim_day"] = day
	row["weekly_contract"] = contract
	var claims: Dictionary = (row.get("reward_claims", {}) as Dictionary).duplicate(true)
	claims["weekly:%d" % int(contract.get("week", 0))] = operation_id
	row["reward_claims"] = claims
	chapters["treeheart_harbor"] = row
	state["chapters"] = chapters
	return {"success": true, "code": "OK", "expansion": state, "gold": int(contract.get("gold", 0)), "item_id": str(contract.get("item_id", "")), "qty": int(contract.get("qty", 0)), "seed": int(contract.get("seed", 0))}
