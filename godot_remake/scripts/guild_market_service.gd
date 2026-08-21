extends RefCounted

const RULES_PATH := "res://data/market_rules.json"
const CATALOG_PATH := "res://data/market_catalog.json"
const PROFILES_PATH := "res://data/adventurer_trade_profiles.json"
const AdventurerServiceScript = preload("res://scripts/adventurer_service.gd")
const MarketServiceScript = preload("res://scripts/market_service.gd")
const LedgerServiceScript = preload("res://scripts/economy_ledger_service.gd")
const SnapshotServiceScript = preload("res://scripts/market_snapshot_service.gd")

## v1.46 negative hooks. Production stays true.
const REQUIRE_WHITELIST := true
const REQUIRE_QUOTE_RANGE := true
const REQUIRE_KNOWN_NPC := true
const BLOCK_DUP_OPERATION := true
const REQUIRE_CATALOG_VERSION := true
const WRITE_LEDGER := true
const BLOCK_OLD_DAY_REFRESH := true

var rules: Dictionary = {}
var catalog_by_id: Dictionary = {}
var catalog_order: Array[String] = []
var profiles: Dictionary = {}
var adventurer_service = AdventurerServiceScript.new()
var npc_market = MarketServiceScript.new()
var ledger_service = LedgerServiceScript.new()
var snapshot_service = SnapshotServiceScript.new()


func _init() -> void:
	rules = _read_dict(RULES_PATH)
	var catalog_root: Dictionary = _read_dict(CATALOG_PATH)
	for raw_item: Variant in catalog_root.get("items", []):
		if not raw_item is Dictionary:
			continue
		var item_id := str(raw_item.get("item_id", ""))
		if item_id.is_empty():
			continue
		catalog_by_id[item_id] = raw_item
		catalog_order.append(item_id)
	var file := FileAccess.open(PROFILES_PATH, FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Array:
			for raw_row: Variant in parsed:
				if raw_row is Dictionary:
					var adv_id := str(raw_row.get("adventurer_id", ""))
					if not adv_id.is_empty():
						profiles[adv_id] = raw_row


func default_market() -> Dictionary:
	return {
		"reputation": 0,
		"reputation_level": 1,
		"last_refresh_day": 0,
		"last_auction_settle_day": 0,
		"daily_catalog": [],
		"weekly_theme": "",
		"daily_seed": 0,
		"catalog_version": int(rules.get("catalog_version", 1)),
		"trade_orders": [],
		"npc_offers": [],
		"auction_listings": [],
		"auction_bids": [],
		"ledger": [],
		"next_operation_seq": 1,
		"next_listing_id": 1,
		"settled_operation_ids": [],
		"claimed_mail_ids": [],
		"daily_trade_counts": {},
		"pending_player_gold": 0,
	}


func normalize(raw: Variant) -> Dictionary:
	var base: Dictionary = default_market()
	if not raw is Dictionary:
		return base
	var incoming: Dictionary = raw
	for key in ["reputation", "reputation_level", "last_refresh_day", "last_auction_settle_day", "daily_seed", "catalog_version", "next_operation_seq", "next_listing_id", "pending_player_gold"]:
		if incoming.has(key):
			base[key] = int(incoming.get(key, 0))
	base["weekly_theme"] = str(incoming.get("weekly_theme", ""))
	for key in ["daily_catalog", "trade_orders", "npc_offers", "auction_listings", "auction_bids", "ledger", "settled_operation_ids", "claimed_mail_ids"]:
		if incoming.get(key) is Array:
			base[key] = (incoming[key] as Array).duplicate(true)
	if incoming.get("daily_trade_counts") is Dictionary:
		base["daily_trade_counts"] = (incoming["daily_trade_counts"] as Dictionary).duplicate(true)
	base["reputation_level"] = reputation_level(int(base.get("reputation", 0)))
	return base


func sync_auction(state: Dictionary) -> Dictionary:
	var out: Dictionary = state.duplicate(true)
	var market: Dictionary = normalize(out.get("market", {}))
	out["market"] = market
	out["auction"] = {
		"listings": (market.get("auction_listings", []) as Array).duplicate(true),
		"bids": (market.get("auction_bids", []) as Array).duplicate(true),
		"enabled": true,
	}
	return out


func validate_data() -> Array[String]:
	var errors: Array[String] = []
	if int(rules.get("catalog_version", 0)) <= 0:
		errors.append("MARKET_CATALOG_STALE version")
	if int(rules.get("daily_slot_count", 0)) != 6:
		errors.append("MARKET_CATALOG_STALE daily_slot")
	if int(rules.get("theme_slot_count", 0)) != 2:
		errors.append("MARKET_CATALOG_STALE theme_slot")
	var seen: Dictionary = {}
	for item_id in catalog_order:
		if seen.has(item_id):
			errors.append("MARKET_NOT_WHITELIST dup %s" % item_id)
		seen[item_id] = true
		var row: Dictionary = catalog_by_id[item_id]
		if int(row.get("min_quote", 0)) < 0 or int(row.get("max_quote", 0)) < int(row.get("min_quote", 0)):
			errors.append("MARKET_BAD_QUOTE %s" % item_id)
	for adv_id in adventurer_service.all_ids():
		if not profiles.has(adv_id):
			errors.append("MARKET_UNKNOWN_NPC missing profile %s" % adv_id)
	return errors


func validate_save(market_raw: Variant) -> Array[String]:
	var errors: Array[String] = []
	var market: Dictionary = normalize(market_raw)
	var listing_seen: Dictionary = {}
	for raw_row: Variant in market.get("auction_listings", []):
		if not raw_row is Dictionary:
			errors.append("SAVE_DUP_LISTING type")
			continue
		var listing_id := str(raw_row.get("listing_id", ""))
		if listing_id.is_empty() or listing_seen.has(listing_id):
			errors.append("SAVE_DUP_LISTING %s" % listing_id)
		listing_seen[listing_id] = true
	var claimed_seen: Dictionary = {}
	for raw_id: Variant in market.get("claimed_mail_ids", []):
		var mail_id := str(raw_id)
		if mail_id.is_empty() or claimed_seen.has(mail_id):
			errors.append("SAVE_DUP_CLAIM %s" % mail_id)
		claimed_seen[mail_id] = true
	return errors


func catalog_row(item_id: String) -> Dictionary:
	var raw: Variant = catalog_by_id.get(item_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func profile_of(adv_id: String) -> Dictionary:
	var raw: Variant = profiles.get(adv_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func reputation_level(value: int) -> int:
	var level := 1
	for raw_row: Variant in rules.get("reputation_levels", []):
		if raw_row is Dictionary and value >= int(raw_row.get("min", 0)):
			level = int(raw_row.get("level", 1))
	return level


func mix(world_seed: int, day: int, system_id: String, entity_id: String, seq: int) -> int:
	return fnv1a32("%d|%d|%s|%s|%d" % [world_seed, day, system_id, entity_id, seq])


func fnv1a32(text: String) -> int:
	var h: int = 2166136261
	for byte_value in text.to_utf8_buffer():
		h = (h ^ int(byte_value)) & 0xFFFFFFFF
		h = (h * 16777619) & 0xFFFFFFFF
	return h


func ensure_catalog(expansion: Dictionary, day: int) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var market: Dictionary = normalize(state.get("market", {}))
	if day < 1:
		return {"success": false, "code": "MARKET_STALE_REFRESH", "expansion": expansion}
	if BLOCK_OLD_DAY_REFRESH and day < int(market.get("last_refresh_day", 0)):
		return {"success": false, "code": "MARKET_STALE_REFRESH", "expansion": expansion}
	if int(market.get("last_refresh_day", 0)) == day and not (market.get("daily_catalog", []) as Array).is_empty():
		state["market"] = market
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": sync_auction(state), "replayed": true}
	var world_seed := int(state.get("world_seed", 0))
	var seed_val := mix(world_seed, day, "guild_market", "catalog", 0)
	var daily: Array = _pick_unique(catalog_order, int(rules.get("daily_slot_count", 6)), seed_val, true)
	var weekday := posmod(day, 7)
	var theme: Dictionary = {}
	for raw_theme: Variant in rules.get("weekly_themes", []):
		if raw_theme is Dictionary and int(raw_theme.get("weekday", -1)) == weekday:
			theme = raw_theme
			break
	var theme_ids: Array[String] = []
	for raw_id: Variant in theme.get("item_ids", []):
		theme_ids.append(str(raw_id))
	var theme_picks: Array = _pick_unique(theme_ids, int(rules.get("theme_slot_count", 2)), mix(world_seed, day, "guild_market", "theme", 1), false)
	var slots: Array = []
	for item_id in daily:
		slots.append(_slot(str(item_id), "daily", day))
	for item_id in theme_picks:
		slots.append(_slot(str(item_id), "theme", day))
	market["daily_catalog"] = slots
	market["weekly_theme"] = str(theme.get("theme_id", ""))
	market["daily_seed"] = seed_val
	market["last_refresh_day"] = day
	market["catalog_version"] = int(rules.get("catalog_version", 1))
	market["daily_trade_counts"] = {}
	market["npc_offers"] = _build_offers(state, market, day)
	state["market"] = market
	return {"success": true, "code": "OK", "expansion": sync_auction(state)}


func accept_offer(expansion: Dictionary, offer_id: String, day: int, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var market: Dictionary = normalize(state.get("market", {}))
	if BLOCK_DUP_OPERATION and _op_seen(market, operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true, "gold_delta": 0, "item_id": "", "item_qty": 0, "item_dir": ""}
	var offer: Dictionary = {}
	for raw_offer: Variant in market.get("npc_offers", []):
		if raw_offer is Dictionary and str(raw_offer.get("offer_id", "")) == offer_id:
			offer = raw_offer.duplicate(true)
			break
	if offer.is_empty():
		return {"success": false, "code": "MARKET_UNKNOWN_NPC", "expansion": expansion}
	if bool(offer.get("accepted", false)):
		return {"success": false, "code": "MARKET_DUP_OPERATION", "expansion": expansion}
	var adv_id := str(offer.get("adventurer_id", ""))
	if REQUIRE_KNOWN_NPC and not adventurer_service.roster.has(adv_id):
		return {"success": false, "code": "MARKET_UNKNOWN_NPC", "expansion": expansion}
	var item_id := str(offer.get("item_id", ""))
	var qty := int(offer.get("quantity", 0))
	var price := int(offer.get("price", 0))
	var direction := str(offer.get("direction", ""))
	if REQUIRE_WHITELIST and catalog_row(item_id).is_empty():
		return {"success": false, "code": "MARKET_NOT_WHITELIST", "expansion": expansion}
	if REQUIRE_CATALOG_VERSION and int(offer.get("catalog_version", 0)) != int(rules.get("catalog_version", 1)):
		return {"success": false, "code": "MARKET_CATALOG_STALE", "expansion": expansion}
	if REQUIRE_QUOTE_RANGE and not _quote_ok(item_id, price):
		return {"success": false, "code": "MARKET_BAD_QUOTE", "expansion": expansion}
	if not _quota_ok(market, adv_id, day):
		return {"success": false, "code": "MARKET_UNKNOWN_NPC", "expansion": expansion}
	var gold_before := 0
	var item_dir := ""
	if direction == "npc_sell":
		var consumed: Dictionary = npc_market.consume_ledger_item(state, adv_id, item_id, qty)
		if not bool(consumed.get("success", false)):
			return {"success": false, "code": "AUCTION_FUNDS", "expansion": expansion}
		state = consumed.expansion
		state = npc_market.add_settlement_loot(state, adv_id, "", 0, price, day, "guild_npc:%s" % operation_id, "guild_sell")
		gold_before = 0
		item_dir = "player_gain"
	elif direction == "npc_buy":
		var ledger: Dictionary = npc_market.normalize_ledger(adv_id, state.get("economy", {}).get("adventurer_ledgers", {}).get(adv_id, {}))
		if int(ledger.get("gold", 0)) < price:
			return {"success": false, "code": "AUCTION_FUNDS", "expansion": expansion}
		state = npc_market.add_settlement_loot(state, adv_id, item_id, qty, -price, day, "guild_npc:%s" % operation_id, "guild_buy")
		item_dir = "player_give"
	else:
		return {"success": false, "code": "MARKET_UNKNOWN_NPC", "expansion": expansion}
	market = normalize(state.get("market", {}))
	var orders: Array = market.get("trade_orders", [])
	var snap: Dictionary = snapshot_service.freeze_trade(state, adv_id, item_id, int(rules.get("catalog_version", 1)), int(market.get("reputation", 0)))
	orders.append({
		"order_id": "ord:%s" % operation_id,
		"operation_id": operation_id,
		"offer_id": offer_id,
		"adventurer_id": adv_id,
		"item_id": item_id,
		"quantity": qty,
		"price": price,
		"direction": direction,
		"day": day,
		"snapshot": snap,
	})
	market["trade_orders"] = orders
	_mark_offer_accepted(market, offer_id)
	_bump_quota(market, adv_id, day)
	_bump_reputation(state, market, adv_id)
	if WRITE_LEDGER:
		var gold_delta := -price if direction == "npc_sell" else price
		market = ledger_service.append(market, {
			"operation_id": operation_id,
			"day": day,
			"reason": "direct_trade",
			"gold_delta": gold_delta,
			"gold_before": gold_before,
			"gold_after": gold_before + gold_delta,
			"item_id": item_id,
			"item_qty": qty,
			"related_id": offer_id,
		})
	_remember_op(market, operation_id)
	state["market"] = market
	return {
		"success": true,
		"code": "OK",
		"expansion": sync_auction(state),
		"gold_delta": -price if direction == "npc_sell" else price,
		"item_id": item_id,
		"item_qty": qty,
		"item_dir": item_dir,
		"adventurer_id": adv_id,
	}


func create_player_trade(expansion: Dictionary, adv_id: String, item_id: String, quantity: int, quote: int, day: int, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var market: Dictionary = normalize(state.get("market", {}))
	if BLOCK_DUP_OPERATION and _op_seen(market, operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true, "gold_delta": 0, "item_id": "", "item_qty": 0, "item_dir": ""}
	if REQUIRE_KNOWN_NPC and not adventurer_service.roster.has(adv_id):
		return {"success": false, "code": "MARKET_UNKNOWN_NPC", "expansion": expansion}
	if REQUIRE_WHITELIST and (catalog_row(item_id).is_empty() or not bool(catalog_row(item_id).get("allow_direct", false))):
		return {"success": false, "code": "MARKET_NOT_WHITELIST", "expansion": expansion}
	if quantity <= 0:
		return {"success": false, "code": "MARKET_BAD_QUOTE", "expansion": expansion}
	if REQUIRE_QUOTE_RANGE and not _quote_ok(item_id, quote):
		return {"success": false, "code": "MARKET_BAD_QUOTE", "expansion": expansion}
	if not _quota_ok(market, adv_id, day):
		return {"success": false, "code": "MARKET_UNKNOWN_NPC", "expansion": expansion}
	var profile: Dictionary = profile_of(adv_id)
	if int(market.get("reputation", 0)) < int(profile.get("min_reputation", 0)):
		return {"success": false, "code": "MARKET_UNKNOWN_NPC", "expansion": expansion}
	var snap: Dictionary = snapshot_service.freeze_trade(state, adv_id, item_id, int(rules.get("catalog_version", 1)), int(market.get("reputation", 0)))
	if REQUIRE_CATALOG_VERSION and int(snap.get("catalog_version", 0)) != int(rules.get("catalog_version", 1)):
		return {"success": false, "code": "MARKET_CATALOG_STALE", "expansion": expansion}
	var price := int(snap.get("price", quote))
	if quote != 0:
		price = quote
	if REQUIRE_QUOTE_RANGE and not _quote_ok(item_id, price):
		return {"success": false, "code": "MARKET_BAD_QUOTE", "expansion": expansion}
	var ledger: Dictionary = npc_market.normalize_ledger(adv_id, state.get("economy", {}).get("adventurer_ledgers", {}).get(adv_id, {}))
	if int(ledger.get("gold", 0)) < price * quantity:
		return {"success": false, "code": "AUCTION_FUNDS", "expansion": expansion}
	state = npc_market.add_settlement_loot(state, adv_id, item_id, quantity, -price * quantity, day, "guild_npc:%s" % operation_id, "guild_buy")
	market = normalize(state.get("market", {}))
	var orders: Array = market.get("trade_orders", [])
	orders.append({
		"order_id": "ord:%s" % operation_id,
		"operation_id": operation_id,
		"adventurer_id": adv_id,
		"item_id": item_id,
		"quantity": quantity,
		"price": price * quantity,
		"direction": "player_sell",
		"day": day,
		"snapshot": snap,
	})
	market["trade_orders"] = orders
	_bump_quota(market, adv_id, day)
	_bump_reputation(state, market, adv_id)
	if WRITE_LEDGER:
		market = ledger_service.append(market, {
			"operation_id": operation_id,
			"day": day,
			"reason": "direct_trade",
			"gold_delta": price * quantity,
			"gold_before": 0,
			"gold_after": price * quantity,
			"item_id": item_id,
			"item_qty": quantity,
			"related_id": adv_id,
		})
	_remember_op(market, operation_id)
	state["market"] = market
	return {
		"success": true,
		"code": "OK",
		"expansion": sync_auction(state),
		"gold_delta": price * quantity,
		"item_id": item_id,
		"item_qty": quantity,
		"item_dir": "player_give",
		"adventurer_id": adv_id,
	}


func _slot(item_id: String, slot_type: String, day: int) -> Dictionary:
	var row: Dictionary = catalog_row(item_id)
	return {
		"item_id": item_id,
		"slot_type": slot_type,
		"day": day,
		"price": int(row.get("value", 0)),
		"remaining": 1,
	}


func _pick_unique(pool: Array, count: int, seed_val: int, require_direct: bool) -> Array:
	var chosen: Array = []
	var seen: Dictionary = {}
	if pool.is_empty() or count <= 0:
		return chosen
	var guard := 0
	var cursor := absi(seed_val)
	while chosen.size() < count and guard < 256:
		guard += 1
		cursor = (cursor * 16777619 + 97) & 0x7FFFFFFF
		var item_id := str(pool[cursor % pool.size()])
		if seen.has(item_id):
			continue
		if require_direct and not bool(catalog_row(item_id).get("allow_direct", false)):
			continue
		if item_id.is_empty() or (require_direct and catalog_row(item_id).is_empty()):
			continue
		seen[item_id] = true
		chosen.append(item_id)
	for raw_id: Variant in pool:
		if chosen.size() >= count:
			break
		var item_id := str(raw_id)
		if seen.has(item_id) or item_id.is_empty():
			continue
		if require_direct and (catalog_row(item_id).is_empty() or not bool(catalog_row(item_id).get("allow_direct", false))):
			continue
		seen[item_id] = true
		chosen.append(item_id)
	return chosen


func _build_offers(state: Dictionary, market: Dictionary, day: int) -> Array:
	var offers: Array = []
	var version := int(rules.get("catalog_version", 1))
	for adv_id in adventurer_service.all_ids():
		var profile: Dictionary = profile_of(adv_id)
		var preferred: Array = profile.get("preferred_items", [])
		if preferred.is_empty():
			continue
		var item_id := str(preferred[0])
		var row: Dictionary = catalog_row(item_id)
		if row.is_empty():
			continue
		var snap: Dictionary = snapshot_service.freeze_trade(state, adv_id, item_id, version, int(market.get("reputation", 0)))
		var direction := "npc_sell"
		var ledger: Dictionary = npc_market.normalize_ledger(adv_id, state.get("economy", {}).get("adventurer_ledgers", {}).get(adv_id, {}))
		var have := int((ledger.get("items", {}) as Dictionary).get(item_id, {}).get("quantity", 0)) if ledger.get("items") is Dictionary else 0
		if have <= 0:
			direction = "npc_buy"
		offers.append({
			"offer_id": "offer:%d:%s" % [day, adv_id],
			"adventurer_id": adv_id,
			"item_id": item_id,
			"quantity": 1,
			"price": int(snap.get("price", int(row.get("value", 0)))),
			"direction": direction,
			"catalog_version": version,
			"accepted": false,
			"snapshot": snap,
		})
	return offers


func _quote_ok(item_id: String, quote: int) -> bool:
	var row: Dictionary = catalog_row(item_id)
	if row.is_empty():
		return false
	return quote >= int(row.get("min_quote", 0)) and quote <= int(row.get("max_quote", 0))


func _quota_ok(market: Dictionary, adv_id: String, day: int) -> bool:
	var counts: Dictionary = market.get("daily_trade_counts", {})
	var used := int(counts.get("%s:%d" % [adv_id, day], 0))
	var cap := int(profile_of(adv_id).get("daily_trades", 1))
	return used < cap


func _bump_quota(market: Dictionary, adv_id: String, day: int) -> void:
	var counts: Dictionary = market.get("daily_trade_counts", {})
	var key := "%s:%d" % [adv_id, day]
	counts[key] = int(counts.get(key, 0)) + 1
	market["daily_trade_counts"] = counts


func _mark_offer_accepted(market: Dictionary, offer_id: String) -> void:
	var offers: Array = []
	for raw_offer: Variant in market.get("npc_offers", []):
		if raw_offer is Dictionary:
			var row: Dictionary = (raw_offer as Dictionary).duplicate(true)
			if str(row.get("offer_id", "")) == offer_id:
				row["accepted"] = true
			offers.append(row)
	market["npc_offers"] = offers


func _bump_reputation(state: Dictionary, market: Dictionary, adv_id: String) -> void:
	var cap := int(rules.get("reputation_cap", 99))
	var delta := int(rules.get("reputation_per_trade", 1))
	market["reputation"] = mini(cap, int(market.get("reputation", 0)) + delta)
	market["reputation_level"] = reputation_level(int(market.get("reputation", 0)))
	var adventurers: Dictionary = {}
	if state.get("adventurers") is Dictionary:
		adventurers = (state["adventurers"] as Dictionary).duplicate(true)
	var runtime: Dictionary = {}
	if adventurers.get(adv_id) is Dictionary:
		runtime = (adventurers[adv_id] as Dictionary).duplicate(true)
	runtime["merchant_reputation"] = mini(cap, int(runtime.get("merchant_reputation", 0)) + delta)
	adventurers[adv_id] = runtime
	state["adventurers"] = adventurers


func _op_seen(market: Dictionary, operation_id: String) -> bool:
	for raw_id: Variant in market.get("settled_operation_ids", []):
		if str(raw_id) == operation_id:
			return true
	return false


func _remember_op(market: Dictionary, operation_id: String) -> void:
	var ids: Array = market.get("settled_operation_ids", [])
	ids.append(operation_id)
	market["settled_operation_ids"] = ids


func _read_dict(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}
