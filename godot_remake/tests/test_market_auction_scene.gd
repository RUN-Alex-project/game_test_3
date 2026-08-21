extends Node

const LIN := "npc_adv_lin_xia"
const YE := "npc_adv_ye_fei"

var _errors: Array = []


func _ready() -> void:
	if GameState == null:
		print("REGISTRY_FAIL: MARKET_UNKNOWN_NPC GameState missing")
		get_tree().quit(1)
		return
	_assert_registry()
	_assert_catalog()
	_assert_trades()
	_assert_rejects()
	_assert_auction_flow_and_sale()
	_assert_save_load()
	_finish()


func _reset() -> void:
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	GameState.current_day = 1
	GameState.gold = 10000
	GameState._initialize_inventory()
	GameState.ensure_guild_catalog()
	GameState.refresh_rankings()


func _assert_registry() -> void:
	var report: Dictionary = GameState.expansion_state_service.validate_data_files()
	for err in report.get("errors", []):
		_fail_raw(str(err))
	if GameState.has_method("transfer_item_to_npc"):
		_fail("MARKET_UNKNOWN_NPC", "transfer_item_to_npc exists")
	if GameState.has_method("set_combat_power"):
		_fail("MARKET_UNKNOWN_NPC", "set_combat_power exists")
	var src := FileAccess.get_file_as_string("res://scripts/guild_market_service.gd")
	if src.contains("class_name MarketService"):
		_fail("MARKET_UNKNOWN_NPC", "guild overwrites MarketService")


func _assert_catalog() -> void:
	_reset()
	var market: Dictionary = GameState.expansion_state.get("market", {})
	var catalog: Array = market.get("daily_catalog", [])
	if catalog.size() != 8:
		_fail("MARKET_CATALOG_STALE", "catalog size %d" % catalog.size())
	var daily := 0
	var theme := 0
	var seen: Dictionary = {}
	for raw_row: Variant in catalog:
		if not raw_row is Dictionary:
			continue
		var item_id := str(raw_row.get("item_id", ""))
		if GameState.expansion_state_service.guild_market_service.catalog_row(item_id).is_empty():
			_fail("MARKET_NOT_WHITELIST", item_id)
		if str(raw_row.get("slot_type", "")) == "daily":
			daily += 1
		elif str(raw_row.get("slot_type", "")) == "theme":
			theme += 1
		seen[item_id] = true
	if daily != 6 or theme != 2:
		_fail("MARKET_CATALOG_STALE", "daily %d theme %d" % [daily, theme])
	var first_ids := _catalog_ids()
	GameState.ensure_guild_catalog()
	if _catalog_ids() != first_ids:
		_fail("MARKET_STALE_REFRESH", "same-day catalog drifted")
	GameState.advance_day()
	var second_ids := _catalog_ids()
	if int(GameState.expansion_state.get("market", {}).get("last_refresh_day", 0)) != GameState.current_day:
		_fail("MARKET_STALE_REFRESH", "refresh day %s" % str(GameState.expansion_state.get("market", {}).get("last_refresh_day")))
	if second_ids == first_ids:
		_fail("MARKET_STALE_REFRESH", "cross-day catalog stuck")
	if int(GameState.expansion_state_service.guild_market_service.rules.get("catalog_version", 0)) != 1:
		_fail("MARKET_CATALOG_STALE", "rules version")
	var stale: Dictionary = GameState.expansion_state_service.guild_market_service.ensure_catalog(GameState.expansion_state, 1)
	if str(stale.get("code", "")) != "MARKET_STALE_REFRESH":
		_fail("MARKET_STALE_REFRESH", "old day refresh %s" % str(stale.get("code")))


func _assert_trades() -> void:
	_reset()
	var gold0 := GameState.gold
	var fruit0 := GameState.count_item("fruit")
	var rose0 := GameState.count_item("rose")
	var lin_offer := "offer:1:%s" % LIN
	var ye_offer := "offer:1:%s" % YE
	var lin: Dictionary = GameState.accept_guild_offer(lin_offer, "trade_lin")
	if not bool(lin.get("success", false)):
		_fail("MARKET_UNKNOWN_NPC", "lin trade %s" % str(lin.get("code")))
		return
	if GameState.gold >= gold0:
		_fail("LEDGER_AMOUNT", "lin gold not charged %d" % GameState.gold)
	if GameState.count_item("fruit") != fruit0 + 1:
		_fail("LEDGER_AMOUNT", "lin fruit %d" % GameState.count_item("fruit"))
	var ye: Dictionary = GameState.accept_guild_offer(ye_offer, "trade_ye")
	if not bool(ye.get("success", false)):
		_fail("MARKET_UNKNOWN_NPC", "ye trade %s" % str(ye.get("code")))
		return
	if GameState.count_item("rose") != rose0 + 1:
		_fail("LEDGER_AMOUNT", "ye rose %d" % GameState.count_item("rose"))
	if int(GameState.expansion_state.get("market", {}).get("reputation", 0)) < 2:
		_fail("LEDGER_AMOUNT", "reputation %s" % str(GameState.expansion_state.get("market", {}).get("reputation")))
	var rel_lin := int(GameState.expansion_state.get("relationships", {}).get(LIN, {}).get("value", 0))
	var rel_ye := int(GameState.expansion_state.get("relationships", {}).get(YE, {}).get("value", 0))
	if rel_lin < 1 or rel_ye < 1:
		_fail("LEDGER_AMOUNT", "relationship lin=%d ye=%d" % [rel_lin, rel_ye])
	var replay: Dictionary = GameState.accept_guild_offer(lin_offer, "trade_lin")
	if not bool(replay.get("replayed", false)):
		_fail("MARKET_DUP_OPERATION", "missing replay %s" % str(replay))
	var expected_delta := int(lin.get("gold_delta", 0))
	var found_ledger := false
	for raw_row: Variant in GameState.expansion_state.get("market", {}).get("ledger", []):
		if raw_row is Dictionary and str(raw_row.get("operation_id", "")) == "trade_lin":
			found_ledger = true
			if int(raw_row.get("gold_delta", 0)) != expected_delta:
				_fail("LEDGER_AMOUNT", "ledger %s vs %d" % [str(raw_row.get("gold_delta")), expected_delta])
	if not found_ledger:
		_fail("LEDGER_AMOUNT", "missing trade_lin ledger")
	GameState.refresh_rankings()
	if bool(GameState.get_ranking_board("merchant_reputation").get("preview", false)):
		_fail("MARKET_CATALOG_STALE", "merchant board still preview")


func _assert_rejects() -> void:
	_reset()
	var gold0 := GameState.gold
	var fruit0 := GameState.count_item("fruit")
	var bad_npc: Dictionary = GameState.accept_guild_offer("offer:1:npc_missing", "bad_npc")
	if str(bad_npc.get("code", "")) != "MARKET_UNKNOWN_NPC":
		_fail("MARKET_UNKNOWN_NPC", str(bad_npc))
	var unknown: Dictionary = GameState.create_guild_trade("npc_missing", "fruit", 1, 25, "bad_adv")
	if str(unknown.get("code", "")) != "MARKET_UNKNOWN_NPC":
		_fail("MARKET_UNKNOWN_NPC", str(unknown))
	var white: Dictionary = GameState.create_guild_trade(LIN, "novice_sword", 1, 25, "bad_item")
	if str(white.get("code", "")) != "MARKET_NOT_WHITELIST":
		_fail("MARKET_NOT_WHITELIST", str(white))
	var quote: Dictionary = GameState.create_guild_trade(LIN, "fruit", 1, 1, "bad_quote")
	if str(quote.get("code", "")) != "MARKET_BAD_QUOTE":
		_fail("MARKET_BAD_QUOTE", str(quote))
	if GameState.gold != gold0 or GameState.count_item("fruit") != fruit0:
		_fail("LEDGER_AMOUNT", "reject mutated resources")
	var rel0 := int(GameState.expansion_state.get("relationships", {}).get(LIN, {}).get("value", 0))
	if rel0 != 0:
		_fail("LEDGER_AMOUNT", "reject mutated relationship")


func _assert_auction_flow_and_sale() -> void:
	_reset()
	var potions := GameState.count_item("exp_potion")
	var listed: Dictionary = GameState.list_auction_item("exp_potion", 1, 20, "list_potion")
	if not bool(listed.get("success", false)):
		_fail("MARKET_NOT_WHITELIST", "list potion %s" % str(listed))
		return
	if GameState.count_item("exp_potion") != potions - 1:
		_fail("AUCTION_ESCROW_MISMATCH", "potion not escrowed")
	var listed_row := _listing(str(listed.get("listing_id", "")))
	if int(listed_row.get("escrow_qty", 0)) != 1:
		_fail("AUCTION_ESCROW_MISMATCH", "escrow_qty %s" % str(listed_row.get("escrow_qty")))
	var flow_id := str(listed.get("listing_id", ""))
	GameState.advance_day()
	GameState.advance_day()
	var flowed := _listing(flow_id)
	if str(flowed.get("status", "")) != "flowed":
		_fail("AUCTION_DUP_SETTLE", "potion status %s" % str(flowed.get("status")))
	var again: Dictionary = GameState.expansion_state_service.auction_service.settle_listing(
		GameState.expansion_state, flow_id, "settle_again", GameState.current_day)
	if str(again.get("code", "")) != "AUCTION_DUP_SETTLE":
		_fail("AUCTION_DUP_SETTLE", str(again))
	var mail_id := "mail:auction:%s:flow" % flow_id
	var roses_mail := GameState.count_item("exp_potion")
	var claimed: Dictionary = GameState.claim_mail(mail_id, "claim_flow")
	if not bool(claimed.get("success", false)):
		_fail("AUCTION_ESCROW_MISMATCH", "flow mail %s" % str(claimed))
	if GameState.count_item("exp_potion") != roses_mail + 1:
		_fail("AUCTION_ESCROW_MISMATCH", "flow claim qty")
	var claim2: Dictionary = GameState.claim_mail(mail_id, "claim_flow")
	if not bool(claim2.get("replayed", false)) and bool(claim2.get("success", false)):
		_fail("MARKET_DUP_OPERATION", "mail double claim %s" % str(claim2))

	_reset()
	var gold0 := GameState.gold
	var roses := GameState.count_item("rose")
	var sale: Dictionary = GameState.list_auction_item("rose", 1, 20, "list_rose")
	if not bool(sale.get("success", false)):
		_fail("MARKET_NOT_WHITELIST", "list rose %s" % str(sale))
		return
	if GameState.count_item("rose") != roses - 1:
		_fail("AUCTION_ESCROW_MISMATCH", "rose not escrowed")
	var sale_id := str(sale.get("listing_id", ""))
	var ye_gold0 := _npc_gold(YE)
	var su_gold0 := _npc_gold("npc_adv_su_yan")
	GameState.advance_day()
	var after_bid := _listing(sale_id)
	if int(after_bid.get("high_bid", 0)) <= 0:
		_fail("AUCTION_FUNDS", "npc did not bid %s" % str(after_bid))
	var ye_gold1 := _npc_gold(YE)
	if ye_gold1 >= ye_gold0:
		_fail("AUCTION_FUNDS", "ye gold not frozen")
	var su_gold1 := _npc_gold("npc_adv_su_yan")
	if su_gold1 > su_gold0:
		_fail("AUCTION_FUNDS", "su refunded extra %d>%d" % [su_gold1, su_gold0])
	GameState.advance_day()
	var sold := _listing(sale_id)
	if str(sold.get("status", "")) != "sold":
		_fail("AUCTION_DUP_SETTLE", "rose status %s bid=%s" % [str(sold.get("status")), str(sold)])
	if GameState.gold <= gold0 - int(sale.get("fee", 5)):
		_fail("LEDGER_AMOUNT", "seller payout missing gold %d" % GameState.gold)
	var second_list: Dictionary = GameState.list_auction_item("rose", 1, 20, "list_rose_2")
	if not bool(second_list.get("success", false)):
		_fail("SAVE_DUP_LISTING", str(second_list))
	if str(second_list.get("listing_id", "")) == sale_id:
		_fail("SAVE_DUP_LISTING", "duplicate listing id")


func _assert_save_load() -> void:
	_reset()
	GameState.accept_guild_offer("offer:1:%s" % LIN, "save_trade")
	var before := _market_snap()
	GameState.save_path = "user://test_v146_market.json"
	if not GameState.save_game():
		_fail("SAVE_DUP_LISTING", "save failed")
		return
	GameState.gold = 1
	if not GameState.load_game():
		_fail("SAVE_DUP_LISTING", "load failed")
		return
	if _market_snap() != before:
		_fail("MARKET_CATALOG_STALE", "save/load market drifted")


func _catalog_ids() -> String:
	var parts: Array[String] = []
	for raw_row: Variant in GameState.expansion_state.get("market", {}).get("daily_catalog", []):
		if raw_row is Dictionary:
			parts.append("%s:%s" % [str(raw_row.get("slot_type")), str(raw_row.get("item_id"))])
	return ",".join(parts)


func _listing(listing_id: String) -> Dictionary:
	for raw_row: Variant in GameState.expansion_state.get("market", {}).get("auction_listings", []):
		if raw_row is Dictionary and str(raw_row.get("listing_id", "")) == listing_id:
			return raw_row
	return {}


func _npc_gold(adv_id: String) -> int:
	return int(GameState.expansion_state.get("economy", {}).get("adventurer_ledgers", {}).get(adv_id, {}).get("gold", 0))


func _market_snap() -> String:
	var market: Dictionary = GameState.expansion_state.get("market", {})
	return "%s|%s|%s|%s" % [
		str(int(market.get("reputation", 0))),
		_catalog_ids(),
		str((market.get("trade_orders", []) as Array).size()),
		str((market.get("ledger", []) as Array).size()),
	]


func _fail(code: String, detail: String) -> void:
	_errors.append("%s %s" % [code, detail])


func _fail_raw(text: String) -> void:
	_errors.append(text)


func _finish() -> void:
	if not _errors.is_empty():
		for err in _errors:
			print("REGISTRY_FAIL: %s" % err)
		get_tree().quit(1)
		return
	print("PASS market_auction: catalog, trades, rejects, auction flow/sale, save/load")
	get_tree().quit(0)
