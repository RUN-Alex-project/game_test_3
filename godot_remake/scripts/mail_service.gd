extends RefCounted

const RULES_PATH := "res://data/mail_rules.json"
const MESSAGES_PATH := "res://data/adventurer_messages.json"
const ITEMS_PATH := "res://data/items.json"
const AdventurerServiceScript = preload("res://scripts/adventurer_service.gd")
const ItemProvenanceServiceScript = preload("res://scripts/item_provenance_service.gd")

## Mutation hooks for v1.44 negatives (N9 / N10). Production stays true.
const MARK_CLAIMED := true
const MARK_EXPIRED := true

var rules: Dictionary = {}
var messages: Dictionary = {}
var item_ids: Dictionary = {}
var adventurer_service = AdventurerServiceScript.new()
var provenance = ItemProvenanceServiceScript.new()


func _init() -> void:
	rules = _read_dict(RULES_PATH)
	messages = _read_dict(MESSAGES_PATH)
	item_ids = _load_item_ids()


func default_expire_days() -> int:
	return int(rules.get("default_expire_days", 7))


func expire_policy() -> String:
	return str(rules.get("expire_policy", "return_to_sender"))


func message_for(action_id: String) -> Dictionary:
	var raw: Variant = messages.get(action_id, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func validate_rules() -> Array[String]:
	var errors: Array[String] = []
	if int(rules.get("default_expire_days", 0)) <= 0:
		errors.append("ERR_MAIL_EXPIRE expire_days %s" % str(rules.get("default_expire_days")))
	var policy := expire_policy()
	if policy != "return_to_sender" and policy != "destroy":
		errors.append("ERR_MAIL_EXPIRE policy %s" % policy)
	return errors


func validate_mailbox(container: Variant) -> Array[String]:
	var errors: Array[String] = []
	var mails: Array = []
	if container is Dictionary:
		var boxed: Variant = container.get("mailbox", [])
		if boxed is Array:
			mails = boxed
		else:
			errors.append("ERR_MAIL_TYPE mailbox not array")
			return errors
	elif container is Array:
		mails = container
	else:
		errors.append("ERR_MAIL_TYPE mailbox container")
		return errors
	var seen_id: Dictionary = {}
	var seen_op: Dictionary = {}
	var allowed: Dictionary = {"player": true, "guild_market": true}
	for adv_id in adventurer_service.all_ids():
		allowed[adv_id] = true
	for raw_mail: Variant in mails:
		if not raw_mail is Dictionary:
			errors.append("ERR_MAIL_TYPE entry")
			continue
		var mail: Dictionary = raw_mail
		var mail_id := str(mail.get("mail_id", ""))
		var op := str(mail.get("operation_id", ""))
		if mail_id.is_empty():
			errors.append("ERR_MAIL_ID empty")
		elif seen_id.has(mail_id):
			errors.append("ERR_MAIL_DUP_ID %s" % mail_id)
		else:
			seen_id[mail_id] = true
		if op.is_empty():
			errors.append("ERR_MAIL_DUP_OP empty operation_id")
		elif seen_op.has(op):
			errors.append("ERR_MAIL_DUP_OP %s" % op)
		else:
			seen_op[op] = true
		var sender := str(mail.get("sender_id", ""))
		var recipient := str(mail.get("recipient", ""))
		if not allowed.has(sender) and sender != "player":
			errors.append("ERR_MAIL_SENDER %s" % sender)
		if not allowed.has(recipient):
			errors.append("ERR_MAIL_RECIPIENT %s" % recipient)
		var attachments: Variant = mail.get("attachments", [])
		if not attachments is Array:
			errors.append("ERR_MAIL_TYPE attachments")
			continue
		for raw_att: Variant in attachments:
			if not raw_att is Dictionary:
				errors.append("ERR_MAIL_TYPE attachment")
				continue
			var item_id := str(raw_att.get("item_id", ""))
			if item_id.is_empty() or not item_ids.has(item_id):
				errors.append("ERR_MAIL_FAKE_ATTACH %s" % item_id)
			if int(raw_att.get("quantity", 0)) <= 0:
				errors.append("ERR_MAIL_FAKE_ATTACH qty %s" % item_id)
	return errors


func enqueue_settlement_mail(expansion: Dictionary, adv_id: String, action_id: String, ended_day: int, attachments: Array) -> Dictionary:
	var template: Dictionary = message_for(action_id)
	var mail := {
		"mail_id": "mail:%s:d%d:%s" % [adv_id, ended_day, action_id],
		"operation_id": "settle_mail:%s:d%d" % [adv_id, ended_day],
		"sender_id": adv_id,
		"recipient": "player",
		"subject": str(template.get("subject", action_id)),
		"body": str(template.get("body", "")),
		"attachments": attachments.duplicate(true),
		"created_day": ended_day,
		"expires_day": ended_day + default_expire_days(),
		"claimed": false,
		"expired": false,
		"source_type": "settlement",
	}
	return _append_mail(expansion, mail)


func enqueue_player_send(expansion: Dictionary, adv_id: String, item_id: String, quantity: int, day: int, operation_id: String) -> Dictionary:
	if not adventurer_service.roster.has(adv_id):
		return {"success": false, "code": "ERR_UNKNOWN_ADV", "expansion": expansion}
	if not item_ids.has(item_id):
		return {"success": false, "code": "ERR_MAIL_FAKE_ATTACH", "expansion": expansion}
	if quantity <= 0:
		return {"success": false, "code": "ERR_MAIL_FAKE_ATTACH", "expansion": expansion}
	var state: Dictionary = expansion.duplicate(true)
	var mailbox: Array = _mailbox_of(state)
	for raw_mail: Variant in mailbox:
		if raw_mail is Dictionary and str(raw_mail.get("operation_id", "")) == operation_id:
			return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	var mail := {
		"mail_id": "mail:player:%s:%s" % [adv_id, operation_id],
		"operation_id": operation_id,
		"sender_id": "player",
		"recipient": adv_id,
		"subject": str(message_for("gift_reply").get("subject", "gift")),
		"body": str(message_for("gift_reply").get("body", "")),
		"attachments": [{
			"item_id": item_id,
			"quantity": quantity,
			"source": provenance.player_bag_source(),
		}],
		"created_day": day,
		"expires_day": day + default_expire_days(),
		"claimed": false,
		"expired": false,
		"source_type": "player_send",
	}
	return _append_mail(state, mail)


func claim(expansion: Dictionary, mail_id: String, operation_id: String) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var mailbox: Array = _mailbox_of(state)
	var found := -1
	for index in mailbox.size():
		var raw_mail: Variant = mailbox[index]
		if raw_mail is Dictionary and str(raw_mail.get("mail_id", "")) == mail_id:
			found = index
			break
	if found < 0:
		return {"success": false, "code": "ERR_MAIL_MISSING", "expansion": expansion}
	var mail: Dictionary = (mailbox[found] as Dictionary).duplicate(true)
	if str(mail.get("recipient", "")) != "player":
		return {"success": false, "code": "ERR_MAIL_NOT_PLAYER", "expansion": expansion}
	if bool(mail.get("expired", false)):
		return {"success": false, "code": "ERR_MAIL_EXPIRED", "expansion": expansion}
	if str(mail.get("claim_operation_id", "")) == operation_id and not operation_id.is_empty():
		return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true, "attachments": []}
	if bool(mail.get("claimed", false)):
		return {"success": false, "code": "ERR_MAIL_ALREADY_CLAIMED", "expansion": expansion}
	var fake := validate_mailbox({"mailbox": [mail]})
	if not fake.is_empty():
		return {"success": false, "code": str(fake[0]).get_slice(" ", 0), "expansion": expansion}
	var attachments: Array = (mail.get("attachments", []) as Array).duplicate(true)
	if MARK_CLAIMED:
		mail["claimed"] = true
		mail["claim_operation_id"] = operation_id
	mailbox[found] = mail
	state["mailbox"] = mailbox
	return {"success": true, "code": "OK", "expansion": state, "attachments": attachments}


func expire_due(expansion: Dictionary, ended_day: int) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var mailbox: Array = _mailbox_of(state)
	var changed := false
	for index in mailbox.size():
		var raw_mail: Variant = mailbox[index]
		if not raw_mail is Dictionary:
			continue
		var mail: Dictionary = (raw_mail as Dictionary).duplicate(true)
		if bool(mail.get("claimed", false)):
			continue
		if bool(mail.get("expired", false)):
			continue
		if ended_day < int(mail.get("expires_day", ended_day + 1)):
			continue
		if expire_policy() == "return_to_sender":
			state = _return_attachments(state, mail)
		if MARK_EXPIRED:
			mail["expired"] = true
		mailbox[index] = mail
		changed = true
	state["mailbox"] = mailbox
	return {"success": true, "code": "OK", "expansion": state, "changed": changed}


func deliver_npc_inbound(expansion: Dictionary, ended_day: int) -> Dictionary:
	var state: Dictionary = expansion.duplicate(true)
	var mailbox: Array = _mailbox_of(state)
	for index in mailbox.size():
		var raw_mail: Variant = mailbox[index]
		if not raw_mail is Dictionary:
			continue
		var mail: Dictionary = (raw_mail as Dictionary).duplicate(true)
		var recipient := str(mail.get("recipient", ""))
		if recipient == "player" or recipient.is_empty():
			continue
		if bool(mail.get("claimed", false)) or bool(mail.get("expired", false)):
			continue
		if not adventurer_service.roster.has(recipient):
			continue
		state = _credit_attachments_to_npc(state, recipient, mail.get("attachments", []), ended_day, str(mail.get("operation_id", "")))
		if MARK_CLAIMED:
			mail["claimed"] = true
			mail["claim_operation_id"] = "auto_deliver:%s" % str(mail.get("mail_id", ""))
		mailbox[index] = mail
	state["mailbox"] = mailbox
	return {"success": true, "expansion": state}


func _append_mail(expansion: Dictionary, mail: Dictionary) -> Dictionary:
	var errors := validate_mailbox({"mailbox": [mail]})
	if not errors.is_empty():
		return {"success": false, "code": str(errors[0]).get_slice(" ", 0), "expansion": expansion}
	var state: Dictionary = expansion.duplicate(true)
	var mailbox: Array = _mailbox_of(state)
	for raw_mail: Variant in mailbox:
		if raw_mail is Dictionary and str(raw_mail.get("operation_id", "")) == str(mail.get("operation_id", "")):
			return {"success": true, "code": "ALREADY_APPLIED", "expansion": expansion, "replayed": true}
	mailbox.append(mail)
	state["mailbox"] = mailbox
	return {"success": true, "code": "OK", "expansion": state}


func _return_attachments(state: Dictionary, mail: Dictionary) -> Dictionary:
	var sender := str(mail.get("sender_id", ""))
	var recipient := str(mail.get("recipient", ""))
	if sender == "player":
		return state
	if recipient != "player":
		return state
	if not adventurer_service.roster.has(sender):
		return state
	return _credit_attachments_to_npc(state, sender, mail.get("attachments", []), int(mail.get("created_day", 0)), "expire:%s" % str(mail.get("operation_id", "")))


func _credit_attachments_to_npc(state: Dictionary, adv_id: String, attachments: Variant, day: int, operation_id: String) -> Dictionary:
	var out: Dictionary = state.duplicate(true)
	var economy: Dictionary = _economy_of(out)
	var ledgers: Dictionary = economy.get("adventurer_ledgers", {})
	if not ledgers is Dictionary:
		ledgers = {}
	else:
		ledgers = ledgers.duplicate(true)
	var ledger: Dictionary = (ledgers.get(adv_id, {}) as Dictionary).duplicate(true)
	var items: Dictionary = _items_of(ledger)
	if not attachments is Array:
		attachments = []
	for raw_att: Variant in attachments:
		if not raw_att is Dictionary:
			continue
		var item_id := str(raw_att.get("item_id", ""))
		var qty := int(raw_att.get("quantity", 0))
		var source := str(raw_att.get("source", provenance.player_bag_source()))
		if item_id.is_empty() or qty <= 0:
			continue
		items = _add_stack(items, item_id, qty, source)
		var entries: Array = (ledger.get("ledger_entries", []) as Array).duplicate()
		entries.append({
			"operation_id": operation_id,
			"day": day,
			"kind": "mail_in",
			"item_id": item_id,
			"quantity": qty,
			"gold_delta": 0,
		})
		ledger["ledger_entries"] = entries
	ledger["items"] = items
	ledgers[adv_id] = ledger
	economy["adventurer_ledgers"] = ledgers
	out["economy"] = economy
	return out


func _add_stack(items: Dictionary, item_id: String, qty: int, source: String) -> Dictionary:
	var out: Dictionary = items.duplicate(true)
	var stack: Dictionary = (out.get(item_id, {}) as Dictionary).duplicate()
	var have := int(stack.get("quantity", 0))
	stack["quantity"] = have + qty
	if str(stack.get("source", "")).is_empty():
		stack["source"] = source
	out[item_id] = stack
	return out


func _mailbox_of(state: Dictionary) -> Array:
	var boxed: Variant = state.get("mailbox", [])
	if boxed is Array:
		return boxed.duplicate(true)
	return []


func _economy_of(state: Dictionary) -> Dictionary:
	var raw: Variant = state.get("economy", {})
	return raw.duplicate(true) if raw is Dictionary else {}


func _items_of(ledger: Dictionary) -> Dictionary:
	var raw: Variant = ledger.get("items", {})
	return raw.duplicate(true) if raw is Dictionary else {}


func _read_dict(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _load_item_ids() -> Dictionary:
	var ids := {}
	var file := FileAccess.open(ITEMS_PATH, FileAccess.READ)
	if file == null:
		return ids
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Array:
		for raw_entry: Variant in parsed:
			if raw_entry is Dictionary:
				var entry_id := str(raw_entry.get("id", ""))
				if not entry_id.is_empty():
					ids[entry_id] = true
	return ids
