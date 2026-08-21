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
		"adventurer_roster": main.adventurer_roster_panel,
		"adventurer_mail": main.adventurer_mail_panel,
		"adventurer_trade": main.adventurer_trade_panel,
		"ranking": main.ranking_panel,
		"arena": main.arena_panel,
		"guild_market": main.guild_market_panel,
		"property_territory": main.property_territory_panel,
		"border_command": main.border_command_panel,
		"ice_codex": main.ice_codex_panel,
		"abyss_board": main.abyss_board_panel,
		"challenge_board": main.challenge_board_panel,
		"pet_endgame": main.pet_endgame_panel,
		"season_board": main.season_board_panel,
	}
	for name in panels:
		assert(not panels[name].visible, "%s panel visible at startup (must be hidden)" % name)
		print("STARTUP_HIDDEN %s visible=%s" % [name, str(panels[name].visible)])
	print("PASS all 25 non-default panels hidden at startup")
	get_tree().quit(0)
