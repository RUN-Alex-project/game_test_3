extends RefCounted

const RULES_PATH := "res://data/auction_rules.json"
const GuildMarketServiceScript = preload("res://scripts/guild_market_service.gd")
const MailServiceScript = preload("res://scripts/mail_service.gd")
const MarketServiceScript = preload("res://scripts/market_service.gd")
const LedgerServiceScript = preload("res://scripts/economy_ledger_service.gd")

const BLOCK_DUP_SETTLE := true
const REQUIRE_ESCROW_MATCH := true
const REFUND_ONCE := true
const REQUIRE_FUNDS := true
const REQUIRE_UNIQUE_LISTING_ID := true
const WRITE_LEDGER := true

var rules: Dictionary = {}
var guild = GuildMarketServiceScript.new()
var mail_service = MailServiceScript.new()
var npc_market = MarketServiceScript.new()
var ledger_service = LedgerServiceScript.new()


func _init() -> void:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	rules = parsed if parsed is Dictionary else {}


func validate_rules() -> Array[String]:
	var errors: Array[String] = []
	if int(rules.get("listing_days", 0)) <= 0:
		errors.append("AUCTION_DUP_SETTLE days")
	if int(rules.get("min_raise", 0)) <= 0:
		errors.append("AUCTION_FUNDS min_raise")
	return errors


func create_listing(expansion: Dictionary, seller_id: String, item_id: String, quantity: int, start_price: int, day: int, operation_id: String, escrow_source: String) -> Dictionary:
	var state: Dictionary = guild.sync_auction(expansion)
	var market: Dictionary = guild.normalize(state.get("market", {}))
	if guild.BLOCK_DUP_OPERATION and _op_seen(market, operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true, "listing_id": "", "fee": 0}
	var row: Dictionary = guild.catalog_row(item_id)
	if row.is_empty() or not bool(row.get("allow_auction", false)):
		return {"success": false, "code": "MARKET_NOT_WHITELIST", "expansion": expansion}
	if quantity <= 0 or start_price <= 0:
		return {"success": false, "code": "MARKET_BAD_QUOTE", "expansion": expansion}
	if not guild._quote_ok(item_id, start_price):
		return {"success": false, "code": "MARKET_BAD_QUOTE", "expansion": expansion}
	var listing_id := "list:%d" % int(market.get("next_listing_id", 1))
	if REQUIRE_UNIQUE_LISTING_ID:
		for raw_row: Variant in market.get("auction_listings", []):
			if raw_row is Dictionary and str(raw_row.get("listing_id", "")) == listing_id:
				return {"success": false, "code": "SAVE_DUP_LISTING", "expansion": expansion}
	var fee := int(rules.get("listing_fee", int(guild.rules.get("listing_fee", 5))))
	var listing := {
		"listing_id": listing_id,
		"operation_id": operation_id,
		"seller_id": seller_id,
		"item_id": item_id,
		"quantity": quantity,
		"start_price": start_price,
		"high_bid": 0,
		"high_bidder": "",
		"high_bid_op": "",
		"escrow_item": item_id,
		"escrow_qty": quantity if REQUIRE_ESCROW_MATCH else 0,
		"escrow_source": escrow_source,
		"catalog_version": int(guild.rules.get("catalog_version", 1)),
		"created_day": day,
		"days_left": int(rules.get("listing_days", 2)),
		"status": "open",
		"settle_operation_id": "",
		"refunded_ops": [],
	}
	var listings: Array = market.get("auction_listings", [])
	listings.append(listing)
	market["auction_listings"] = listings
	if REQUIRE_UNIQUE_LISTING_ID:
		market["next_listing_id"] = int(market.get("next_listing_id", 1)) + 1
	if WRITE_LEDGER:
		market = ledger_service.append(market, {
			"operation_id": operation_id,
			"day": day,
			"reason": "auction_list",
			"gold_delta": -fee,
			"gold_before": 0,
			"gold_after": -fee,
			"item_id": item_id,
			"item_qty": quantity,
			"related_id": listing_id,
		})
	_remember_op(market, operation_id)
	state["market"] = market
	return {"success": true, "code": "OK", "expansion": guild.sync_auction(state), "listing_id": listing_id, "fee": fee}


func place_bid(expansion: Dictionary, listing_id: String, bidder_id: String, amount: int, day: int, operation_id: String) -> Dictionary:
	var state: Dictionary = guild.sync_auction(expansion)
	var market: Dictionary = guild.normalize(state.get("market", {}))
	if guild.BLOCK_DUP_OPERATION and _op_seen(market, operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true, "refund_gold": 0, "refund_npc": "", "refund_npc_gold": 0}
	var found := _find_listing(market, listing_id)
	if found < 0:
		return {"success": false, "code": "AUCTION_DUP_SETTLE", "expansion": expansion}
	var listing: Dictionary = ((market["auction_listings"] as Array)[found] as Dictionary).duplicate(true)
	if str(listing.get("status", "")) != "open":
		return {"success": false, "code": "AUCTION_DUP_SETTLE", "expansion": expansion}
	if bidder_id == str(listing.get("seller_id", "")):
		return {"success": false, "code": "MARKET_UNKNOWN_NPC", "expansion": expansion}
	var min_raise := int(rules.get("min_raise", 10))
	var need := int(listing.get("start_price", 0))
	if int(listing.get("high_bid", 0)) > 0:
		need = int(listing.get("high_bid", 0)) + min_raise
	if amount < need:
		return {"success": false, "code": "MARKET_BAD_QUOTE", "expansion": expansion}
	var old_bidder := str(listing.get("high_bidder", ""))
	var old_bid := int(listing.get("high_bid", 0))
	var old_op := str(listing.get("high_bid_op", ""))
	var refund_gold := 0
	var refund_npc := ""
	var refund_npc_gold := 0
	if old_bid > 0 and not old_bidder.is_empty():
		var already := false
		for raw_op: Variant in listing.get("refunded_ops", []):
			if str(raw_op) == old_op:
				already = true
		if already and REFUND_ONCE:
			pass
		elif old_bidder == "player":
			var refunded: Array = listing.get("refunded_ops", [])
			refunded.append(old_op)
			listing["refunded_ops"] = refunded
			if bidder_id == "player":
				refund_gold = old_bid
			else:
				market["pending_player_gold"] = int(market.get("pending_player_gold", 0)) + old_bid
		else:
			refund_npc = old_bidder
			refund_npc_gold = old_bid
			state = npc_market.add_settlement_loot(state, old_bidder, "", 0, old_bid, day, "auction_refund:%s" % old_op, "auction_refund")
			if not REFUND_ONCE:
				state = npc_market.add_settlement_loot(state, old_bidder, "", 0, old_bid, day, "auction_refund2:%s" % old_op, "auction_refund")
			var refunded2: Array = listing.get("refunded_ops", [])
			refunded2.append(old_op)
			listing["refunded_ops"] = refunded2
	if bidder_id != "player":
		var ledger: Dictionary = npc_market.normalize_ledger(bidder_id, state.get("economy", {}).get("adventurer_ledgers", {}).get(bidder_id, {}))
		if REQUIRE_FUNDS:
			if int(ledger.get("gold", 0)) < amount:
				return {"success": false, "code": "AUCTION_FUNDS", "expansion": expansion}
			state = npc_market.add_settlement_loot(state, bidder_id, "", 0, -amount, day, "auction_bid:%s" % operation_id, "auction_bid")
	listing["high_bid"] = amount
	listing["high_bidder"] = bidder_id
	listing["high_bid_op"] = operation_id
	var listings: Array = (market.get("auction_listings", []) as Array).duplicate()
	listings[found] = listing
	market["auction_listings"] = listings
	var bids: Array = market.get("auction_bids", [])
	bids.append({
		"listing_id": listing_id,
		"bidder_id": bidder_id,
		"amount": amount,
		"day": day,
		"operation_id": operation_id,
	})
	market["auction_bids"] = bids
	if WRITE_LEDGER:
		market = ledger_service.append(market, {
			"operation_id": operation_id,
			"day": day,
			"reason": "auction_bid",
			"gold_delta": -amount,
			"gold_before": 0,
			"gold_after": -amount,
			"item_id": str(listing.get("item_id", "")),
			"item_qty": 0,
			"related_id": listing_id,
		})
	_remember_op(market, operation_id)
	state["market"] = market
	return {
		"success": true,
		"code": "OK",
		"expansion": guild.sync_auction(state),
		"refund_gold": refund_gold,
		"refund_npc": refund_npc,
		"refund_npc_gold": refund_npc_gold,
	}


func cancel_listing(expansion: Dictionary, listing_id: String, operation_id: String) -> Dictionary:
	var state: Dictionary = guild.sync_auction(expansion)
	var market: Dictionary = guild.normalize(state.get("market", {}))
	if guild.BLOCK_DUP_OPERATION and _op_seen(market, operation_id):
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var found := _find_listing(market, listing_id)
	if found < 0:
		return {"success": false, "code": "AUCTION_DUP_SETTLE", "expansion": expansion}
	var listing: Dictionary = ((market["auction_listings"] as Array)[found] as Dictionary).duplicate(true)
	if str(listing.get("status", "")) != "open":
		return {"success": false, "code": "AUCTION_DUP_SETTLE", "expansion": expansion}
	if int(listing.get("high_bid", 0)) > 0:
		return {"success": false, "code": "AUCTION_FUNDS", "expansion": expansion}
	listing["status"] = "cancelled"
	var listings: Array = (market.get("auction_listings", []) as Array).duplicate()
	listings[found] = listing
	market["auction_listings"] = listings
	_remember_op(market, operation_id)
	state["market"] = market
	return {"success": true, "code": "OK", "expansion": guild.sync_auction(state), "item_id": str(listing.get("item_id", "")), "item_qty": int(listing.get("quantity", 0))}


func process_ended_day(expansion: Dictionary, ended_day: int) -> Dictionary:
	var state: Dictionary = guild.sync_auction(expansion)
	var market: Dictionary = guild.normalize(state.get("market", {}))
	if int(market.get("last_auction_settle_day", 0)) == ended_day:
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": state, "replayed": true, "player_gold_delta": 0}
	var listings: Array = (market.get("auction_listings", []) as Array).duplicate()
	for index in listings.size():
		var raw_row: Variant = listings[index]
		if not raw_row is Dictionary:
			continue
		var listing: Dictionary = (raw_row as Dictionary).duplicate(true)
		if str(listing.get("status", "")) != "open":
			listings[index] = listing
			continue
		state["market"] = market
		state = _npc_bids_for(state, listing, ended_day)
		market = guild.normalize(state.get("market", {}))
		listings = (market.get("auction_listings", []) as Array).duplicate()
		listing = (listings[index] as Dictionary).duplicate(true)
		listing["days_left"] = int(listing.get("days_left", 1)) - 1
		listings[index] = listing
		market["auction_listings"] = listings
		state["market"] = market
		if int(listing.get("days_left", 0)) <= 0:
			var settled: Dictionary = settle_listing(state, str(listing.get("listing_id", "")), "settle:%s:d%d" % [str(listing.get("listing_id", "")), ended_day], ended_day)
			if bool(settled.get("success", false)):
				state = settled.expansion
				market = guild.normalize(state.get("market", {}))
	market["last_auction_settle_day"] = ended_day
	state["market"] = market
	return {"success": true, "code": "OK", "expansion": guild.sync_auction(state), "player_gold_delta": int(market.get("pending_player_gold", 0))}


func settle_listing(expansion: Dictionary, listing_id: String, operation_id: String, day: int) -> Dictionary:
	var state: Dictionary = guild.sync_auction(expansion)
	var market: Dictionary = guild.normalize(state.get("market", {}))
	var found := _find_listing(market, listing_id)
	if found < 0:
		return {"success": false, "code": "AUCTION_DUP_SETTLE", "expansion": expansion}
	var listing: Dictionary = ((market["auction_listings"] as Array)[found] as Dictionary).duplicate(true)
	if BLOCK_DUP_SETTLE and str(listing.get("status", "")) != "open":
		return {"success": false, "code": "AUCTION_DUP_SETTLE", "expansion": expansion}
	if REQUIRE_ESCROW_MATCH:
		if str(listing.get("escrow_item", "")) != str(listing.get("item_id", "")):
			return {"success": false, "code": "AUCTION_ESCROW_MISMATCH", "expansion": expansion}
		if int(listing.get("escrow_qty", 0)) != int(listing.get("quantity", 0)):
			return {"success": false, "code": "AUCTION_ESCROW_MISMATCH", "expansion": expansion}
	var high_bid := int(listing.get("high_bid", 0))
	var high_bidder := str(listing.get("high_bidder", ""))
	var seller_id := str(listing.get("seller_id", ""))
	var item_id := str(listing.get("item_id", ""))
	var qty := int(listing.get("quantity", 0))
	var tax_bps := int(rules.get("sale_tax_bps", int(guild.rules.get("sale_tax_bps", 500))))
	if high_bid > 0 and not high_bidder.is_empty():
		var tax := int(high_bid * tax_bps / 10000)
		var payout := high_bid - tax
		if payout < 0:
			return {"success": false, "code": "LEDGER_AMOUNT", "expansion": expansion}
		listing["status"] = "sold"
		if seller_id == "player":
			market["pending_player_gold"] = int(market.get("pending_player_gold", 0)) + payout
		else:
			state = npc_market.add_settlement_loot(state, seller_id, "", 0, payout, day, "auction_payout:%s" % listing_id, "auction_payout")
		if high_bidder == "player":
			state = _mail_item(state, listing_id, "win", item_id, qty, day, "You won an auction listing.")
		else:
			state = npc_market.add_settlement_loot(state, high_bidder, item_id, qty, 0, day, "auction_win:%s" % listing_id, "auction_win")
		_bump_rep(state, market, seller_id, high_bidder)
	else:
		listing["status"] = "flowed"
		if seller_id == "player":
			state = _mail_item(state, listing_id, "flow", item_id, qty, day, "Auction listing expired and the item was returned.")
		else:
			state = npc_market.add_settlement_loot(state, seller_id, item_id, qty, 0, day, "auction_flow:%s" % listing_id, "auction_flow")
	listing["settle_operation_id"] = operation_id
	var listings: Array = (market.get("auction_listings", []) as Array).duplicate()
	listings[found] = listing
	market["auction_listings"] = listings
	if WRITE_LEDGER:
		market = ledger_service.append(market, {
			"operation_id": operation_id,
			"day": day,
			"reason": "auction_settle",
			"gold_delta": high_bid,
			"gold_before": 0,
			"gold_after": high_bid,
			"item_id": item_id,
			"item_qty": qty,
			"related_id": listing_id,
		})
	_remember_op(market, operation_id)
	state["market"] = market
	return {"success": true, "code": "OK", "expansion": guild.sync_auction(state)}


func _npc_bids_for(expansion: Dictionary, listing: Dictionary, ended_day: int) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var listing_id := str(listing.get("listing_id", ""))
	var item_id := str(listing.get("item_id", ""))
	var seller_id := str(listing.get("seller_id", ""))
	for adv_id in guild.adventurer_service.all_ids():
		if adv_id == seller_id:
			continue
		var profile: Dictionary = guild.profile_of(adv_id)
		var preferred: Array = profile.get("preferred_items", [])
		var likes := false
		for raw_id: Variant in preferred:
			if str(raw_id) == item_id:
				likes = true
		if not likes:
			continue
		if int(profile.get("bid_aggression", 0)) < int(rules.get("npc_min_aggression", 40)):
			continue
		var seed_val := guild.mix(int(state.get("world_seed", 0)), ended_day, "auction_bid", listing_id, guild.adventurer_service.all_ids().find(adv_id))
		var current: Dictionary = _current_listing(state, listing_id)
		var high := int(current.get("high_bid", 0))
		var need := int(current.get("start_price", 0)) if high <= 0 else high + int(rules.get("min_raise", 10))
		var bump := (seed_val % 21)
		var amount := need + bump
		var bid: Dictionary = place_bid(state, listing_id, adv_id, amount, ended_day, "npcbid:%s:%s:d%d" % [listing_id, adv_id, ended_day])
		if bool(bid.get("success", false)):
			state = bid.expansion
	return state


func _current_listing(state: Dictionary, listing_id: String) -> Dictionary:
	var market: Dictionary = guild.normalize(state.get("market", {}))
	var found := _find_listing(market, listing_id)
	if found < 0:
		return {}
	return ((market["auction_listings"] as Array)[found] as Dictionary).duplicate(true)


func _mail_item(expansion: Dictionary, listing_id: String, kind: String, item_id: String, qty: int, day: int, body: String) -> Dictionary:
	var mail := {
		"mail_id": "mail:auction:%s:%s" % [listing_id, kind],
		"operation_id": "auction_mail:%s:%s" % [listing_id, kind],
		"sender_id": str(rules.get("system_sender", "guild_market")),
		"recipient": "player",
		"subject": kind,
		"body": body,
		"attachments": [{
			"item_id": item_id,
			"quantity": qty,
			"source": "auction_escrow",
		}],
		"created_day": day,
		"expires_day": day + int(rules.get("mail_expire_days", 7)),
		"claimed": false,
		"expired": false,
		"source_type": "auction",
	}
	var mailed: Dictionary = mail_service._append_mail(expansion, mail)
	if bool(mailed.get("success", false)):
		return mailed.expansion
	return expansion


func _bump_rep(state: Dictionary, market: Dictionary, seller_id: String, buyer_id: String) -> void:
	var cap := int(guild.rules.get("reputation_cap", 99))
	var delta := int(guild.rules.get("reputation_per_auction", 2))
	if seller_id == "player" or buyer_id == "player":
		market["reputation"] = mini(cap, int(market.get("reputation", 0)) + delta)
		market["reputation_level"] = guild.reputation_level(int(market.get("reputation", 0)))
	var adventurers: Dictionary = {}
	if state.get("adventurers") is Dictionary:
		adventurers = (state["adventurers"] as Dictionary).duplicate(true)
	for adv_id in [seller_id, buyer_id]:
		if adv_id == "player" or not adventurers.has(adv_id):
			continue
		var runtime: Dictionary = (adventurers[adv_id] as Dictionary).duplicate(true)
		runtime["merchant_reputation"] = mini(cap, int(runtime.get("merchant_reputation", 0)) + delta)
		adventurers[adv_id] = runtime
	state["adventurers"] = adventurers


func _find_listing(market: Dictionary, listing_id: String) -> int:
	var listings: Array = market.get("auction_listings", [])
	for index in listings.size():
		var raw_row: Variant = listings[index]
		if raw_row is Dictionary and str(raw_row.get("listing_id", "")) == listing_id:
			return index
	return -1


func _op_seen(market: Dictionary, operation_id: String) -> bool:
	for raw_id: Variant in market.get("settled_operation_ids", []):
		if str(raw_id) == operation_id:
			return true
	return false


func _remember_op(market: Dictionary, operation_id: String) -> void:
	var ids: Array = market.get("settled_operation_ids", [])
	ids.append(operation_id)
	market["settled_operation_ids"] = ids
