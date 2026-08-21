extends RefCounted

const SCHEDULES_PATH := "res://data/adventurer_schedules.json"
const AdventurerServiceScript = preload("res://scripts/adventurer_service.gd")
const MailServiceScript = preload("res://scripts/mail_service.gd")
const MarketServiceScript = preload("res://scripts/market_service.gd")
const AuctionServiceScript = preload("res://scripts/auction_service.gd")

## Mutation hooks for v1.44 negatives (N1 / N2). Production stays true.
const USE_WORLD_SEED := true
const SKIP_SAME_DAY := true

const ALLOWED_ACTIONS := {
	"hunt": true, "gather": true, "train": true, "trade": true,
	"rest": true, "commission": true, "arena_prep": true,
}

var schedules: Dictionary = {}
var adventurer_service = AdventurerServiceScript.new()
var mail_service = MailServiceScript.new()
var market_service = MarketServiceScript.new()
var auction_service = AuctionServiceScript.new()


func _init() -> void:
	var file := FileAccess.open(SCHEDULES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Array:
		for raw_entry: Variant in parsed:
			if raw_entry is Dictionary:
				var adv_id := str(raw_entry.get("adventurer_id", ""))
				if not adv_id.is_empty():
					schedules[adv_id] = raw_entry


func mix(world_seed: int, day: int, system_id: String, entity_id: String, seq: int) -> int:
	var seed_term := world_seed if USE_WORLD_SEED else 0
	var text := "%d|%d|%s|%s|%d" % [seed_term, day, system_id, entity_id, seq]
	return fnv1a32(text)


func fnv1a32(text: String) -> int:
	var h: int = 2166136261
	for byte_value in text.to_utf8_buffer():
		h = (h ^ int(byte_value)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return h


func pick_action(world_seed: int, day: int, adv_id: String, seq: int) -> String:
	var row: Dictionary = schedules.get(adv_id, {})
	var actions: Array = row.get("actions", [])
	var total := 0
	for raw_action: Variant in actions:
		if raw_action is Dictionary:
			total += maxi(0, int(raw_action.get("weight", 0)))
	if total <= 0:
		return "rest"
	var roll := mix(world_seed, day, "day_cycle", adv_id, seq) % total
	var acc := 0
	for raw_action: Variant in actions:
		if not raw_action is Dictionary:
			continue
		acc += maxi(0, int(raw_action.get("weight", 0)))
		if roll < acc:
			var action_id := str(raw_action.get("id", "rest"))
			return action_id if ALLOWED_ACTIONS.has(action_id) else "rest"
	return "rest"


func validate_schedules() -> Array[String]:
	var errors: Array[String] = []
	for adv_id in adventurer_service.all_ids():
		if not schedules.has(adv_id):
			errors.append("ERR_SCHED_MISSING %s" % adv_id)
			continue
		var actions: Array = schedules[adv_id].get("actions", [])
		if actions.is_empty():
			errors.append("ERR_SCHED_MISSING empty %s" % adv_id)
		var weight_sum := 0
		for raw_action: Variant in actions:
			if not raw_action is Dictionary:
				errors.append("ERR_SCHED_MISSING bad action %s" % adv_id)
				continue
			var action_id := str(raw_action.get("id", ""))
			if not ALLOWED_ACTIONS.has(action_id):
				errors.append("ERR_SCHED_MISSING unknown %s %s" % [adv_id, action_id])
			var weight := int(raw_action.get("weight", 0))
			if weight <= 0:
				errors.append("ERR_SCHED_MISSING weight %s" % adv_id)
			weight_sum += weight
		if weight_sum <= 0:
			errors.append("ERR_SCHED_MISSING weight_sum %s" % adv_id)
	return errors


func settle_ended_day(expansion: Dictionary, ended_day: int) -> Dictionary:
	if ended_day < 1:
		return {"success": false, "code": "ERR_BAD_DAY", "expansion": expansion, "settled_count": 0}
	var state: Dictionary = _ensure(expansion)
	var expired: Dictionary = mail_service.expire_due(state, ended_day)
	state = expired.expansion
	var delivered: Dictionary = mail_service.deliver_npc_inbound(state, ended_day)
	state = delivered.expansion
	var world_seed := int(state.get("world_seed", 0))
	var log: Array = _log_of(state)
	var settled_count := 0
	for adv_id in adventurer_service.all_ids():
		var ledger: Dictionary = market_service.normalize_ledger(adv_id, _ledgers(state).get(adv_id, {}))
		if SKIP_SAME_DAY and int(ledger.get("last_settlement_day", 0)) == ended_day:
			continue
		var action_id := pick_action(world_seed, ended_day, adv_id, 0)
		var operation_id := "settle:%s:d%d" % [adv_id, ended_day]
		state = _apply_action(state, adv_id, action_id, ended_day, operation_id)
		log.append({
			"day": ended_day,
			"adventurer_id": adv_id,
			"action": action_id,
			"operation_id": operation_id,
		})
		settled_count += 1
	var economy: Dictionary = (state.get("economy", {}) as Dictionary).duplicate(true)
	economy["daily_settlement_log"] = log
	state["economy"] = economy
	var auctioned: Dictionary = auction_service.process_ended_day(state, ended_day)
	if bool(auctioned.get("success", false)):
		state = auctioned.expansion
	if settled_count > 0:
		state["day_sequence"] = int(state.get("day_sequence", 0)) + 1
	return {
		"success": true,
		"code": "OK",
		"expansion": state,
		"settled_count": settled_count,
		"replayed": settled_count == 0,
	}


func _apply_action(expansion: Dictionary, adv_id: String, action_id: String, ended_day: int, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	match action_id:
		"gather":
			state = market_service.add_settlement_loot(state, adv_id, "silver_ore", 1, 0, ended_day, operation_id, action_id)
		"hunt":
			state = market_service.add_settlement_loot(state, adv_id, "fruit", 1, 0, ended_day, operation_id, action_id)
		"trade":
			var consumed: Dictionary = market_service.consume_ledger_item(state, adv_id, "fruit", 1)
			if bool(consumed.get("success", false)):
				state = consumed.expansion
				var fruit_price := int(market_service.get_profile(adv_id).get("sell_prices", {}).get("fruit", 25))
				state = market_service.add_settlement_loot(state, adv_id, "", 0, fruit_price, ended_day, operation_id, action_id)
			else:
				state = market_service.add_settlement_loot(state, adv_id, "", 0, 10, ended_day, operation_id, action_id)
		"arena_prep":
			state = market_service.add_settlement_loot(state, adv_id, "", 0, 0, ended_day, operation_id, action_id)
			state = _bump_npc_arena_score(state, adv_id)
		_:
			state = market_service.add_settlement_loot(state, adv_id, "", 0, 0, ended_day, operation_id, action_id)
	if action_id == "rest":
		state = _send_rest_mail(state, adv_id, ended_day)
	return state


func _bump_npc_arena_score(expansion: Dictionary, adv_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var adventurers: Dictionary = {}
	if state.get("adventurers") is Dictionary:
		adventurers = (state["adventurers"] as Dictionary).duplicate(true)
	var runtime: Dictionary = {}
	if adventurers.get(adv_id) is Dictionary:
		runtime = (adventurers[adv_id] as Dictionary).duplicate(true)
	runtime["arena_score"] = int(runtime.get("arena_score", 0)) + 1
	adventurers[adv_id] = runtime
	state["adventurers"] = adventurers
	return state


func _send_rest_mail(expansion: Dictionary, adv_id: String, ended_day: int) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var attachments: Array = []
	var consumed: Dictionary = market_service.consume_ledger_item(state, adv_id, "rose", 1)
	if bool(consumed.get("success", false)):
		state = consumed.expansion
		attachments.append({
			"item_id": "rose",
			"quantity": 1,
			"source": str(consumed.get("source", "npc_stock")),
		})
	var mailed: Dictionary = mail_service.enqueue_settlement_mail(state, adv_id, "rest", ended_day, attachments)
	if bool(mailed.get("success", false)) and not bool(mailed.get("replayed", false)):
		state = mailed.expansion
	return state


func _ensure(expansion: Dictionary) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	if int(state.get("world_seed", 0)) == 0:
		state["world_seed"] = 1297043285
	if not state.get("mailbox") is Array:
		state["mailbox"] = []
	else:
		state["mailbox"] = (state["mailbox"] as Array).duplicate(true)
	var economy: Dictionary = {}
	if state.get("economy") is Dictionary:
		economy = (state["economy"] as Dictionary).duplicate(true)
	var ledgers: Dictionary = {}
	if economy.get("adventurer_ledgers") is Dictionary:
		ledgers = (economy["adventurer_ledgers"] as Dictionary).duplicate(true)
	for adv_id in adventurer_service.all_ids():
		ledgers[adv_id] = market_service.normalize_ledger(adv_id, ledgers.get(adv_id, {}))
	economy["adventurer_ledgers"] = ledgers
	if not economy.get("daily_settlement_log") is Array:
		economy["daily_settlement_log"] = []
	else:
		economy["daily_settlement_log"] = (economy["daily_settlement_log"] as Array).duplicate(true)
	state["economy"] = economy
	return state


func _ledgers(state: Dictionary) -> Dictionary:
	var economy: Variant = state.get("economy", {})
	if economy is Dictionary and economy.get("adventurer_ledgers") is Dictionary:
		return economy["adventurer_ledgers"]
	return {}


func _log_of(state: Dictionary) -> Array:
	var economy: Variant = state.get("economy", {})
	if economy is Dictionary and economy.get("daily_settlement_log") is Array:
		return (economy["daily_settlement_log"] as Array).duplicate(true)
	return []
