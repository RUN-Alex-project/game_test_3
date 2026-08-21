extends RefCounted

const SOURCE_NPC_STOCK := "npc_stock"
const SOURCE_SETTLEMENT := "settlement"
const SOURCE_PLAYER_BAG := "player_bag"
const SOURCE_FORGED := "forged"
const SOURCE_UNTRADABLE := "untradable"


func is_bound_category(category: String) -> bool:
	return category == "equipment"


func is_tradable(category: String, source: String) -> bool:
	if is_bound_category(category):
		return false
	var tag := source.strip_edges()
	if tag.is_empty() or tag == SOURCE_FORGED or tag == SOURCE_UNTRADABLE:
		return false
	return true


func npc_stock_source() -> String:
	return SOURCE_NPC_STOCK


func settlement_source() -> String:
	return SOURCE_SETTLEMENT


func player_bag_source() -> String:
	return SOURCE_PLAYER_BAG
