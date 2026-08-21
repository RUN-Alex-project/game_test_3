extends RefCounted

const PROFILES_PATH := "res://data/npc_market_profiles.json"
const ITEMS_PATH := "res://data/items.json"
const AdventurerServiceScript = preload("res://scripts/adventurer_service.gd")
const ItemProvenanceServiceScript = preload("res://scripts/item_provenance_service.gd")

## Mutation hooks for v1.44 negatives (N5 / N6). Production stays true.
const REQUIRE_STOCK := true
const WRITE_LEDGER_ENTRIES := true

var profiles: Dictionary = {}
var item_defs: Dictionary = {}
var adventurer_service = AdventurerServiceScript.new()
var provenance = ItemProvenanceServiceScript.new()


func _init() -> void:
	item_defs = _load_items()
	var file := FileAccess.open(PROFILES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Array:
		for raw_entry: Variant in parsed:
			if raw_entry is Dictionary:
				var adv_id := str(raw_entry.get("adventurer_id", ""))
				if not adv_id.is_empty():
					profiles[adv_id] = raw_entry


func get_profile(adv_id: String) -> Dictionary:
	var raw: Variant = profiles.get(adv_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func default_ledger(adv_id: String) -> Dictionary:
	var spec: Dictionary = adventurer_service.get_adventurer(adv_id).get("initial_ledger", {})
	var items_raw: Variant = spec.get("items", {})
	var items: Dictionary = {}
	if items_raw is Dictionary:
		items = items_raw.duplicate(true)
	var profile: Dictionary = get_profile(adv_id)
	return {
		"gold": int(spec.get("gold", 0)),
		"magic_stones": int(spec.get("magic_stones", 0)),
		"items": items,
		"daily_budget": int(spec.get("daily_budget", int(profile.get("daily_budget", 0)))),
		"budget_spent": 0,
		"budget_spent_day": 0,
		"last_settlement_day": 0,
		"ledger_entries": [],
	}


func normalize_ledger(adv_id: String, raw: Variant) -> Dictionary:
	var base: Dictionary = default_ledger(adv_id)
	if not raw is Dictionary:
		return base
	var incoming: Dictionary = raw
	for key in ["gold", "magic_stones", "daily_budget", "budget_spent", "budget_spent_day", "last_settlement_day"]:
		if incoming.has(key):
			base[key] = int(incoming.get(key, 0))
	if incoming.get("items") is Dictionary:
		base["items"] = (incoming["items"] as Dictionary).duplicate(true)
	if incoming.get("ledger_entries") is Array:
		base["ledger_entries"] = (incoming["ledger_entries"] as Array).duplicate(true)
	return base


func validate_profiles() -> Array[String]:
	var errors: Array[String] = []
	for adv_id in adventurer_service.all_ids():
		if not profiles.has(adv_id):
			errors.append("ERR_MARKET_PROFILE_MISSING %s" % adv_id)
			continue
		var profile: Dictionary = profiles[adv_id]
		if int(profile.get("daily_budget", 0)) < 0:
			errors.append("ERR_NEG_BUDGET %s" % adv_id)
		for price_map_name in ["buy_prices", "sell_prices"]:
			var prices: Variant = profile.get(price_map_name, {})
			if not prices is Dictionary:
				errors.append("ERR_MARKET_NEGATIVE_PRICE %s %s" % [adv_id, price_map_name])
				continue
			for item_id in prices.keys():
				if not item_defs.has(str(item_id)):
					errors.append("ERR_LEDGER_UNKNOWN_ITEM %s" % str(item_id))
				if int(prices[item_id]) < 0:
					errors.append("ERR_MARKET_NEGATIVE_PRICE %s %s %s" % [adv_id, price_map_name, str(item_id)])
		for want in profile.get("wants", []):
			if not item_defs.has(str(want)):
				errors.append("ERR_LEDGER_UNKNOWN_ITEM want %s" % str(want))
	return errors


func validate_ledgers(expansion: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var economy: Variant = expansion.get("economy", {})
	if not economy is Dictionary:
		return errors
	var ledgers: Variant = economy.get("adventurer_ledgers", {})
	if not ledgers is Dictionary:
		return errors
	for adv_id in ledgers.keys():
		var ledger: Variant = ledgers[adv_id]
		if not ledger is Dictionary:
			errors.append("ERR_LEDGER_TYPE %s" % str(adv_id))
			continue
		if int(ledger.get("gold", 0)) < 0 or int(ledger.get("daily_budget", 0)) < 0:
			errors.append("ERR_NEG_BUDGET %s" % str(adv_id))
		var items: Variant = ledger.get("items", {})
		if items is Dictionary:
			for item_id in items.keys():
				if not item_defs.has(str(item_id)):
					errors.append("ERR_LEDGER_UNKNOWN_ITEM %s" % str(item_id))
	return errors


func credit_item(expansion: Dictionary, adv_id: String, item_id: String, quantity: int, source: String, day: int, operation_id: String) -> Dictionary:
	if not adventurer_service.roster.has(adv_id):
		return {"success": false, "code": "ERR_UNKNOWN_ADV", "expansion": expansion}
	if not item_defs.has(item_id) or quantity <= 0:
		return {"success": false, "code": "ERR_LEDGER_UNKNOWN_ITEM", "expansion": expansion}
	var state: Dictionary = expansion.duplicate(true)
	var ledger: Dictionary = _ledger(state, adv_id)
	for raw_entry: Variant in ledger.get("ledger_entries", []):
		if raw_entry is Dictionary and str(raw_entry.get("operation_id", "")) == operation_id:
			return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var items: Dictionary = _items(ledger)
	items = _add_stack(items, item_id, quantity, source)
	ledger["items"] = items
	ledger = _append_entry(ledger, {
		"operation_id": operation_id,
		"day": day,
		"kind": "credit",
		"item_id": item_id,
		"quantity": quantity,
		"gold_delta": 0,
	})
	_write_ledger(state, adv_id, ledger)
	return {"success": true, "code": "OK", "expansion": state}


func buy_from_adventurer(expansion: Dictionary, adv_id: String, item_id: String, quantity: int, day: int, operation_id: String) -> Dictionary:
	if quantity <= 0:
		return {"success": false, "code": "ERR_MARKET_QTY", "expansion": expansion}
	if not adventurer_service.roster.has(adv_id):
		return {"success": false, "code": "ERR_UNKNOWN_ADV", "expansion": expansion}
	var def: Dictionary = item_defs.get(item_id, {})
	if def.is_empty():
		return {"success": false, "code": "ERR_UNKNOWN_ITEM", "expansion": expansion}
	var state: Dictionary = expansion.duplicate(true)
	var ledger: Dictionary = _ledger(state, adv_id)
	for raw_entry: Variant in ledger.get("ledger_entries", []):
		if raw_entry is Dictionary and str(raw_entry.get("operation_id", "")) == operation_id:
			return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true, "gold_cost": 0, "quantity": 0}
	var items: Dictionary = _items(ledger)
	var stack: Dictionary = (items.get(item_id, {}) as Dictionary).duplicate()
	var have := int(stack.get("quantity", 0))
	var source := str(stack.get("source", provenance.npc_stock_source()))
	if REQUIRE_STOCK and have < quantity:
		return {"success": false, "code": "ERR_MARKET_NO_STOCK", "expansion": expansion}
	if not provenance.is_tradable(str(def.get("category", "")), source if have > 0 else provenance.npc_stock_source()):
		return {"success": false, "code": "ERR_MARKET_UNTRADABLE", "expansion": expansion}
	var price := _sell_price(adv_id, item_id) * quantity
	if price < 0:
		return {"success": false, "code": "ERR_MARKET_NEGATIVE_PRICE", "expansion": expansion}
	stack["quantity"] = have - quantity
	if int(stack.get("quantity", 0)) <= 0:
		items.erase(item_id)
	else:
		items[item_id] = stack
	ledger["items"] = items
	ledger["gold"] = int(ledger.get("gold", 0)) + price
	ledger = _append_entry(ledger, {
		"operation_id": operation_id,
		"day": day,
		"kind": "sell_to_player",
		"item_id": item_id,
		"quantity": quantity,
		"gold_delta": price,
	})
	_write_ledger(state, adv_id, ledger)
	return {"success": true, "code": "OK", "expansion": state, "gold_cost": price, "quantity": quantity}


func sell_to_adventurer(expansion: Dictionary, adv_id: String, item_id: String, quantity: int, day: int, operation_id: String) -> Dictionary:
	if quantity <= 0:
		return {"success": false, "code": "ERR_MARKET_QTY", "expansion": expansion}
	if not adventurer_service.roster.has(adv_id):
		return {"success": false, "code": "ERR_UNKNOWN_ADV", "expansion": expansion}
	var def: Dictionary = item_defs.get(item_id, {})
	if def.is_empty():
		return {"success": false, "code": "ERR_UNKNOWN_ITEM", "expansion": expansion}
	if provenance.is_bound_category(str(def.get("category", ""))):
		return {"success": false, "code": "ERR_MARKET_UNTRADABLE", "expansion": expansion}
	var state: Dictionary = expansion.duplicate(true)
	var ledger: Dictionary = _ledger(state, adv_id)
	for raw_entry: Variant in ledger.get("ledger_entries", []):
		if raw_entry is Dictionary and str(raw_entry.get("operation_id", "")) == operation_id:
			return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true, "gold_gain": 0, "quantity": 0}
	var price := _buy_price(adv_id, item_id) * quantity
	if price < 0:
		return {"success": false, "code": "ERR_MARKET_NEGATIVE_PRICE", "expansion": expansion}
	if int(ledger.get("budget_spent_day", 0)) != day:
		ledger["budget_spent"] = 0
		ledger["budget_spent_day"] = day
	var budget := int(ledger.get("daily_budget", 0))
	var spent := int(ledger.get("budget_spent", 0))
	if spent + price > budget:
		return {"success": false, "code": "ERR_MARKET_BUDGET", "expansion": expansion}
	if int(ledger.get("gold", 0)) < price:
		return {"success": false, "code": "ERR_MARKET_NPC_GOLD", "expansion": expansion}
	var items: Dictionary = _items(ledger)
	items = _add_stack(items, item_id, quantity, provenance.player_bag_source())
	ledger["items"] = items
	ledger["gold"] = int(ledger.get("gold", 0)) - price
	ledger["budget_spent"] = spent + price
	ledger = _append_entry(ledger, {
		"operation_id": operation_id,
		"day": day,
		"kind": "buy_from_player",
		"item_id": item_id,
		"quantity": quantity,
		"gold_delta": -price,
	})
	_write_ledger(state, adv_id, ledger)
	return {"success": true, "code": "OK", "expansion": state, "gold_gain": price, "quantity": quantity}


func add_settlement_loot(expansion: Dictionary, adv_id: String, item_id: String, quantity: int, gold_delta: int, day: int, operation_id: String, kind: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var ledger: Dictionary = _ledger(state, adv_id)
	var items: Dictionary = _items(ledger)
	if quantity > 0 and not item_id.is_empty():
		items = _add_stack(items, item_id, quantity, provenance.settlement_source())
	ledger["items"] = items
	ledger["gold"] = int(ledger.get("gold", 0)) + gold_delta
	ledger["last_settlement_day"] = day
	ledger = _append_entry(ledger, {
		"operation_id": operation_id,
		"day": day,
		"kind": kind,
		"item_id": item_id,
		"quantity": quantity,
		"gold_delta": gold_delta,
	})
	_write_ledger(state, adv_id, ledger)
	return state


func consume_ledger_item(expansion: Dictionary, adv_id: String, item_id: String, quantity: int) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var ledger: Dictionary = _ledger(state, adv_id)
	var items: Dictionary = _items(ledger)
	var stack: Dictionary = (items.get(item_id, {}) as Dictionary).duplicate()
	var have := int(stack.get("quantity", 0))
	if have < quantity:
		return {"success": false, "expansion": expansion, "source": ""}
	var source := str(stack.get("source", provenance.npc_stock_source()))
	stack["quantity"] = have - quantity
	if int(stack.get("quantity", 0)) <= 0:
		items.erase(item_id)
	else:
		items[item_id] = stack
	ledger["items"] = items
	_write_ledger(state, adv_id, ledger)
	return {"success": true, "expansion": state, "source": source}


func _sell_price(adv_id: String, item_id: String) -> int:
	var prices: Dictionary = get_profile(adv_id).get("sell_prices", {})
	return int(prices.get(item_id, -1))


func _buy_price(adv_id: String, item_id: String) -> int:
	var prices: Dictionary = get_profile(adv_id).get("buy_prices", {})
	return int(prices.get(item_id, -1))


func _ledger(state: Dictionary, adv_id: String) -> Dictionary:
	var economy: Dictionary = (state.get("economy", {}) as Dictionary).duplicate(true)
	var ledgers: Dictionary = (economy.get("adventurer_ledgers", {}) as Dictionary).duplicate(true)
	return normalize_ledger(adv_id, ledgers.get(adv_id, {}))


func _write_ledger(state: Dictionary, adv_id: String, ledger: Dictionary) -> void:
	var economy: Dictionary = (state.get("economy", {}) as Dictionary).duplicate(true)
	var ledgers: Dictionary = (economy.get("adventurer_ledgers", {}) as Dictionary).duplicate(true)
	ledgers[adv_id] = ledger
	economy["adventurer_ledgers"] = ledgers
	state["economy"] = economy


func _items(ledger: Dictionary) -> Dictionary:
	var raw: Variant = ledger.get("items", {})
	return raw.duplicate(true) if raw is Dictionary else {}


func _add_stack(items: Dictionary, item_id: String, qty: int, source: String) -> Dictionary:
	var out: Dictionary = items.duplicate(true)
	var stack: Dictionary = (out.get(item_id, {}) as Dictionary).duplicate()
	stack["quantity"] = int(stack.get("quantity", 0)) + qty
	if str(stack.get("source", "")).is_empty():
		stack["source"] = source
	out[item_id] = stack
	return out


func _append_entry(ledger: Dictionary, entry: Dictionary) -> Dictionary:
	var out: Dictionary = ledger.duplicate(true)
	if not WRITE_LEDGER_ENTRIES:
		return out
	var entries: Array = (out.get("ledger_entries", []) as Array).duplicate()
	entries.append(entry)
	out["ledger_entries"] = entries
	return out


func _load_items() -> Dictionary:
	var ids := {}
	var file := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if file == null:
		return ids
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Array:
		for raw_entry: Variant in parsed:
			if raw_entry is Dictionary:
				ids[str(raw_entry.get("id", ""))] = raw_entry
	return ids
