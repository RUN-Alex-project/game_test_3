extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	var expected := {
		"grocery":[Vector2(166.8,120.3), "image_1156.png"],
		"stone_shop":[Vector2(290,123.3), "image_1134.png"],
		"collector":[Vector2(446.15,124.3), "image_1138.png"],
		"warehouse":[Vector2(533.6,120.85), "image_1130.png"],
		"daily_officer":[Vector2(620.45,119.3), "image_1076.png"],
		"stone_synthesizer":[Vector2(130.5,373.55), "image_1151.png"],
		"forger":[Vector2(207.5,377.95), "image_1142.png"],
		"pet_master":[Vector2(410.45,385.95), "image_1147.png"],
		"experience_mentor":[Vector2(517.65,377.9), "image_1126.png"],
		"research":[Vector2(470,203), "image_1171.png"],
		"territory:cassano_city":[Vector2(33.95,365.55), "image_1076.png"],
	}
	for action_id: String in expected:
		assert(main.interactive_actors.has(action_id), "Cassano NPC missing: " + action_id)
		var actor = main.interactive_actors[action_id]
		assert(actor.position == expected[action_id][0], "Cassano NPC native position is wrong: " + action_id)
		assert(actor.texture.resource_path.ends_with(expected[action_id][1]), "Cassano NPC native image is wrong: " + action_id)
	assert(not main.interactive_actors.has("princess"), "palace princess incorrectly remained in Cassano")
	assert(not main.interactive_actors.has("battle:territory_cassano_guard"), "duplicate visible territory challenger remained in Cassano")

	main._open_actor_dialogue("experience_mentor")
	assert(main.dialogue_panel.visible and main.dialogue_panel.body_label.text.contains("二洞另加5个"), "experience mentor dialogue is incomplete")
	main._open_actor_dialogue("stone_synthesizer")
	assert(main.dialogue_panel.visible and main.dialogue_panel.body_label.text.contains("20个"), "stone synthesizer dialogue is incomplete")

	GameState.inventory.fill({})
	var equipment := GameState.create_item_entry("lottery_weapon")
	equipment.enhancement.quality_level = 4
	equipment.enhancement.socket_count = 2
	equipment.enhancement.magic_soul_level = 12
	GameState.inventory[0] = equipment
	var extraction := GameState.exchange_first_inventory_equipment_for_exp_balls()
	assert(extraction.success and extraction.exp_balls == 11 and GameState.count_item("exp_ball") == 11, "native experience-mentor formula is wrong")

	GameState.inventory.fill({})
	assert(GameState.add_item("soul_crystal", 20), "synthesis fixture failed")
	var synthesis := GameState.synthesize_stone("soul_king")
	assert(synthesis.success and GameState.count_item("soul_crystal") == 0 and GameState.count_item("soul_king") == 1, "native 20-to-1 synthesis failed")

	print("PASS Cassano native NPC identities, frames, positions, dialogue, mentor extraction, and synthesis")
	get_tree().quit(0)
