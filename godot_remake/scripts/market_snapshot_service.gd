extends RefCounted

const AdventurerServiceScript = preload("res://scripts/adventurer_service.gd")

var adventurer_service = AdventurerServiceScript.new()


func freeze_trade(expansion: Dictionary, adv_id: String, item_id: String, catalog_version: int, reputation: int) -> Dictionary:
	var rel_value := 0
	var relationships: Variant = expansion.get("relationships", {})
	if relationships is Dictionary and relationships.get(adv_id) is Dictionary:
		rel_value = int(relationships[adv_id].get("value", 0))
	var catalog: Dictionary = {}
	var file := FileAccess.open("res://data/market_catalog.json", FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed is Dictionary:
			for raw_item: Variant in parsed.get("items", []):
				if raw_item is Dictionary and str(raw_item.get("item_id", "")) == item_id:
					catalog = raw_item
					break
	var rules: Dictionary = {}
	var rules_file := FileAccess.open("res://data/market_rules.json", FileAccess.READ)
	if rules_file != null:
		var parsed_rules: Variant = JSON.parse_string(rules_file.get_as_text())
		rules_file.close()
		if parsed_rules is Dictionary:
			rules = parsed_rules
	var profile: Dictionary = {}
	var profiles_file := FileAccess.open("res://data/adventurer_trade_profiles.json", FileAccess.READ)
	if profiles_file != null:
		var parsed_profiles: Variant = JSON.parse_string(profiles_file.get_as_text())
		profiles_file.close()
		if parsed_profiles is Array:
			for raw_row: Variant in parsed_profiles:
				if raw_row is Dictionary and str(raw_row.get("adventurer_id", "")) == adv_id:
					profile = raw_row
					break
	var base := int(catalog.get("value", 0))
	var bias := int(profile.get("quote_bias", 0))
	var level := 1
	for raw_level: Variant in rules.get("reputation_levels", []):
		if raw_level is Dictionary and reputation >= int(raw_level.get("min", 0)):
			level = int(raw_level.get("level", 1))
	var price := base + bias + int(rel_value / 10.0) + level * 2
	var min_q := int(catalog.get("min_quote", price))
	var max_q := int(catalog.get("max_quote", price))
	price = clampi(price, min_q, max_q)
	return {
		"catalog_version": catalog_version,
		"relationship_value": rel_value,
		"reputation": reputation,
		"reputation_level": level,
		"item_id": item_id,
		"base_value": base,
		"quote_bias": bias,
		"price": price,
	}
