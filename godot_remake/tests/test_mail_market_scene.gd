extends Node

const LIN := "npc_adv_lin_xia"

var _errors: Array = []


func _ready() -> void:
	_reset()
	_assert_send_no_copy()
	_reset()
	_assert_claim_and_replay()
	_reset()
	_assert_bag_full()
	_reset()
	_assert_expire_idempotent()
	_reset()
	_assert_trade()
	_finish()


func _reset() -> void:
	GameState.expansion_state = GameState.expansion_state_service.default_enabled_state()
	GameState.current_day = 1
	GameState._initialize_inventory()
	GameState.gold = 99_999_999_999


func _assert_send_no_copy() -> void:
	if GameState.count_item("fruit") < 1:
		GameState.add_item("fruit", 1)
	var player_before := GameState.count_item("fruit")
	var npc_before := _item_qty(LIN, "fruit")
	var sent: Dictionary = GameState.send_player_mail(LIN, "fruit", "send_fruit_1")
	if not bool(sent.get("success", false)):
		_fail("ERR_SEND_DUP", str(sent))
		return
	if GameState.count_item("fruit") != player_before - 1:
		_fail("ERR_SEND_DUP", "player fruit not consumed")
	if _item_qty(LIN, "fruit") != npc_before:
		_fail("ERR_SEND_DUP", "npc gained fruit before deliver")
	if _mail_attach_qty("fruit") != 1:
		_fail("ERR_SEND_DUP", "escrow missing")
	var replay: Dictionary = GameState.send_player_mail(LIN, "fruit", "send_fruit_1")
	if not bool(replay.get("replayed", false)):
		_fail("ERR_SEND_DUP", "send replay missing")
	if GameState.count_item("fruit") != player_before - 1:
		_fail("ERR_SEND_DUP", "replay consumed extra")
	var bound: Dictionary = GameState.send_player_mail(LIN, "novice_sword", "send_sword")
	if bool(bound.get("success", true)):
		_fail("ERR_SEND_DUP", "bound send succeeded")


func _assert_claim_and_replay() -> void:
	var setup: Dictionary = _escrow_rose_mail("claim_mail_1")
	GameState.expansion_state = setup.expansion
	var mail_id := str(setup.get("mail_id", ""))
	var roses := GameState.count_item("rose")
	var claimed: Dictionary = GameState.claim_mail(mail_id, "c1")
	if not bool(claimed.get("success", false)):
		_fail("ERR_MAIL_DOUBLE_CLAIM", str(claimed))
		return
	if GameState.count_item("rose") != roses + 1:
		_fail("ERR_MAIL_DOUBLE_CLAIM", "claim did not add rose")
	var replay: Dictionary = GameState.claim_mail(mail_id, "c1")
	if not bool(replay.get("replayed", false)):
		_fail("ERR_MAIL_DOUBLE_CLAIM", "claim replay missing")
	if GameState.count_item("rose") != roses + 1:
		_fail("ERR_MAIL_DOUBLE_CLAIM", "replay added extra")
	var second: Dictionary = GameState.claim_mail(mail_id, "c2")
	if bool(second.get("success", false)) and not bool(second.get("replayed", false)):
		_fail("ERR_MAIL_DOUBLE_CLAIM", "second op added extra")
	if GameState.count_item("rose") != roses + 1:
		_fail("ERR_MAIL_DOUBLE_CLAIM", "second op count %d" % GameState.count_item("rose"))


func _assert_bag_full() -> void:
	var setup: Dictionary = _escrow_rose_mail("full_mail_1")
	GameState.expansion_state = setup.expansion
	GameState.inventory.clear()
	for _i in GameState.INVENTORY_SIZE:
		GameState.inventory.append(GameState.create_item_entry("novice_sword"))
	var mail_id := str(setup.get("mail_id", ""))
	var before_mail := _find_mail(mail_id)
	var result: Dictionary = GameState.claim_mail(mail_id, "full_c1")
	if str(result.get("code", "")) != "ERR_MAIL_BAG_FULL":
		_fail("ERR_MAIL_BAG_FULL", str(result))
	var after_mail := _find_mail(mail_id)
	if bool(after_mail.get("claimed", false)):
		_fail("ERR_MAIL_BAG_FULL", "claimed on full bag")
	if (after_mail.get("attachments", []) as Array).size() != (before_mail.get("attachments", []) as Array).size():
		_fail("ERR_MAIL_BAG_FULL", "attachments lost")
	GameState._initialize_inventory()


func _assert_expire_idempotent() -> void:
	var setup: Dictionary = _escrow_rose_mail("expire_mail_1")
	var state: Dictionary = setup.expansion
	var mails: Array = state.get("mailbox", [])
	if not mails.is_empty() and mails[mails.size() - 1] is Dictionary:
		var mail: Dictionary = mails[mails.size() - 1]
		mail["expires_day"] = 1
		mails[mails.size() - 1] = mail
		state["mailbox"] = mails
	var roses_mail := _item_qty_in_state(state, LIN, "rose")
	var cycle = GameState.expansion_state_service.day_cycle_service
	var once: Dictionary = cycle.settle_ended_day(state, 1)
	var roses_once := _item_qty_in_state(once.expansion, LIN, "rose")
	var twice: Dictionary = cycle.settle_ended_day(once.expansion, 1)
	var roses_twice := _item_qty_in_state(twice.expansion, LIN, "rose")
	if roses_twice != roses_once:
		_fail("ERR_EXPIRE_DOUBLE_REFUND", "once=%d twice=%d start_after_escrow=%d" % [roses_once, roses_twice, roses_mail])


func _assert_trade() -> void:
	var player_roses := GameState.count_item("rose")
	var npc_roses := _item_qty(LIN, "rose")
	var player_gold := GameState.gold
	var npc_gold := _npc_gold(LIN)
	var buy1: Dictionary = GameState.buy_from_adventurer(LIN, "rose", 1, "buy_rose_1")
	if not bool(buy1.get("success", false)):
		_fail("ERR_MARKET_FAKE_STOCK", str(buy1))
		return
	if GameState.count_item("rose") != player_roses + 1:
		_fail("ERR_MARKET_FAKE_STOCK", "buy did not add")
	if _item_qty(LIN, "rose") != npc_roses - 1:
		_fail("ERR_MARKET_FAKE_STOCK", "npc stock not reduced")
	if GameState.gold != player_gold - 15:
		_fail("ERR_MARKET_FAKE_STOCK", "player gold")
	if _npc_gold(LIN) != npc_gold + 15:
		_fail("ERR_MARKET_FAKE_STOCK", "npc gold")
	if not _has_entry(LIN, "buy_rose_1"):
		_fail("ERR_LEDGER_MISMATCH", "missing buy entry")
	var replay: Dictionary = GameState.buy_from_adventurer(LIN, "rose", 1, "buy_rose_1")
	if not bool(replay.get("replayed", false)):
		_fail("ERR_MARKET_FAKE_STOCK", "buy replay missing")
	if GameState.count_item("rose") != player_roses + 1:
		_fail("ERR_MARKET_FAKE_STOCK", "buy replay extra")
	GameState.buy_from_adventurer(LIN, "rose", 1, "buy_rose_2")
	var empty: Dictionary = GameState.buy_from_adventurer(LIN, "rose", 1, "buy_rose_3")
	if bool(empty.get("success", false)):
		_fail("ERR_MARKET_FAKE_STOCK", "bought empty stock")
	if _item_qty(LIN, "rose") < 0:
		_fail("ERR_MARKET_FAKE_STOCK", "negative npc stock")
	var sell: Dictionary = GameState.sell_to_adventurer(LIN, "rose", 1, "sell_rose_1")
	if not bool(sell.get("success", false)):
		_fail("ERR_MARKET_FAKE_STOCK", str(sell))
	if not _has_entry(LIN, "sell_rose_1"):
		_fail("ERR_LEDGER_MISMATCH", "missing sell entry")
	var bound: Dictionary = GameState.sell_to_adventurer(LIN, "novice_sword", 1, "sell_sword")
	if bool(bound.get("success", true)):
		_fail("ERR_MARKET_UNTRADABLE", "sold equipment")
	var story_snap: Dictionary = GameState.story_flags.duplicate(true)
	if GameState.story_flags != story_snap:
		_fail("ERR_LEDGER_MISMATCH", "story flags mutated")


func _escrow_rose_mail(operation_suffix: String) -> Dictionary:
	var state: Dictionary = GameState.expansion_state_service.default_enabled_state()
	var consumed: Dictionary = GameState.expansion_state_service.market_service.consume_ledger_item(state, LIN, "rose", 1)
	state = consumed.expansion
	var mailed: Dictionary = GameState.expansion_state_service.mail_service.enqueue_settlement_mail(
		state, LIN, "rest", 1, [{"item_id": "rose", "quantity": 1, "source": "npc_stock"}])
	var mail_id := ""
	for raw_mail: Variant in mailed.expansion.get("mailbox", []):
		if raw_mail is Dictionary:
			mail_id = str(raw_mail.get("mail_id", ""))
	return {"expansion": mailed.expansion, "mail_id": mail_id, "op": operation_suffix}


func _item_qty(adv_id: String, item_id: String) -> int:
	return _item_qty_in_state(GameState.expansion_state, adv_id, item_id)


func _item_qty_in_state(state: Dictionary, adv_id: String, item_id: String) -> int:
	var stack: Dictionary = state.get("economy", {}).get("adventurer_ledgers", {}).get(adv_id, {}).get("items", {}).get(item_id, {})
	return int(stack.get("quantity", 0))


func _npc_gold(adv_id: String) -> int:
	return int(GameState.expansion_state.get("economy", {}).get("adventurer_ledgers", {}).get(adv_id, {}).get("gold", 0))


func _mail_attach_qty(item_id: String) -> int:
	var total := 0
	for raw_mail: Variant in GameState.expansion_state.get("mailbox", []):
		if not raw_mail is Dictionary:
			continue
		for raw_att: Variant in raw_mail.get("attachments", []):
			if raw_att is Dictionary and str(raw_att.get("item_id", "")) == item_id:
				total += int(raw_att.get("quantity", 0))
	return total


func _find_mail(mail_id: String) -> Dictionary:
	for raw_mail: Variant in GameState.expansion_state.get("mailbox", []):
		if raw_mail is Dictionary and str(raw_mail.get("mail_id", "")) == mail_id:
			return raw_mail
	return {}


func _has_entry(adv_id: String, operation_id: String) -> bool:
	var entries: Array = GameState.expansion_state.get("economy", {}).get("adventurer_ledgers", {}).get(adv_id, {}).get("ledger_entries", [])
	for raw_entry: Variant in entries:
		if raw_entry is Dictionary and str(raw_entry.get("operation_id", "")) == operation_id:
			return true
	return false


func _fail(code: String, detail: String) -> void:
	_errors.append("%s %s" % [code, detail])


func _finish() -> void:
	if _errors.size() > 0:
		print("REGISTRY_FAIL: " + "; ".join(_errors))
		get_tree().quit(1)
		return
	print("PASS mail_market: send escrow, claim replay, bag full keeps attach, expire idempotent, buy/sell conservation")
	get_tree().quit(0)
