extends Node

func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	# P1: every non-default window must be hidden at startup.
	var panels: Dictionary = {
		"inventory": main.inventory_panel,
		"warehouse": main.warehouse_panel,
		"gold_shop": main.gold_shop,
		"stone_shop": main.stone_shop,
		"equipment": main.equipment_panel,
		"enhancement": main.enhancement_panel,
		"pet": main.pet_panel,
		"research": main.research_panel,
		"progression": main.progression_panel,
		"quest": main.quest_panel,
		"skill": main.skill_panel,
		"dialogue": main.dialogue_panel,
	}
	for name in panels:
		assert(not panels[name].visible, "%s panel visible at startup (must be hidden)" % name)
		print("STARTUP_HIDDEN %s visible=%s" % [name, str(panels[name].visible)])
	print("PASS all 12 non-default panels hidden at startup")
	get_tree().quit(0)
