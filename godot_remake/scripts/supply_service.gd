extends RefCounted

const RULES_PATH := "res://data/south_border_story.json"
const REQUIRE_ITEM := true
const REQUIRE_QTY := true

var rules: Dictionary = {}


func _init() -> void:
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	rules = parsed if parsed is Dictionary else {}


func spec() -> Dictionary:
	return (rules.get("supply", {}) as Dictionary).duplicate(true)


func required_qty(expansion: Dictionary) -> int:
	var spec_row := spec()
	var rel_id := str(spec_row.get("relationship_id", ""))
	var need := int(spec_row.get("qty", 2))
	var rel_val := int(expansion.get("relationships", {}).get(rel_id, {}).get("value", 0))
	if rel_val >= int(spec_row.get("relationship_min", 99)):
		need = int(spec_row.get("discount_qty", 1))
	return need


func preview_submit(expansion: Dictionary, item_id: String, have_qty: int, stage: String) -> Dictionary:
	var spec_row := spec()
	if stage != "supply":
		return {"success": false, "code": "BORDER_PRECONDITION", "expansion": expansion}
	if bool(expansion.get("chapters", {}).get("south_border", {}).get("supply_submitted", false)):
		return {"success": false, "code": "BORDER_SUPPLY_ITEM", "expansion": expansion}
	if REQUIRE_ITEM and item_id != str(spec_row.get("item_id", "fruit")):
		return {"success": false, "code": "BORDER_SUPPLY_ITEM", "expansion": expansion}
	var need := required_qty(expansion)
	if REQUIRE_QTY and have_qty < need:
		return {"success": false, "code": "BORDER_SUPPLY_QTY", "expansion": expansion}
	var chapters: Dictionary = (expansion.get("chapters", {}) as Dictionary).duplicate(true)
	var row: Dictionary = (chapters.get("south_border", {}) as Dictionary).duplicate(true)
	row["supply_submitted"] = true
	row["stage"] = "defense"
	chapters["south_border"] = row
	var state: Dictionary = expansion.duplicate(true)
	state["chapters"] = chapters
	return {"success": true, "code": "OK", "expansion": state, "qty": need, "item_id": item_id}
