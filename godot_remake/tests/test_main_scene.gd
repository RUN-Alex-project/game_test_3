extends Node


func _no_legacy_panel(root: Node) -> bool:
	for n in root.find_children("*", "", true, false):
		var s = n.get_script()
		if s != null and s is GDScript and (s.resource_path.ends_with("map_panel.gd") or s.resource_path.ends_with("battle_panel.gd")):
			return false
	return true


func _ready() -> void:
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	assert(not main.inventory_panel.visible, "inventory should be hidden at startup")
	assert(not main.warehouse_panel.visible, "warehouse should start hidden")
	assert(main.player.texture.resource_path.ends_with("image_0455.png"), "player did not start on the native standing clip")
	main._update_player_animation(Vector2.DOWN, 0.34)
	assert(main.player.texture.resource_path.ends_with("image_0467.png"), "player down-walk timeline did not advance")
	main._update_player_animation(Vector2.ZERO, 0.0)
	assert(main.player.texture.resource_path.ends_with("image_0455.png"), "player idle animation did not reset")

	main._toggle_warehouse()
	assert(main.inventory_panel.visible and main.warehouse_panel.visible, "warehouse mode must show both containers")
	assert(main.warehouse_panel.position == Vector2(208, 220) and main.inventory_panel.position == Vector2(453, 300), "warehouse/backpack do not use the native paired positions")

	main._toggle_inventory()
	assert(main.inventory_panel.position == Vector2(453, 300), "inventory did not return to its native position")
	assert(main.inventory_panel.visible and not main.warehouse_panel.visible, "normal inventory mode is incorrect")

	main._toggle_gold_shop()
	assert(main.gold_shop.visible, "gold shop did not open")
	assert(not main.inventory_panel.visible and not main.warehouse_panel.visible and not main.stone_shop.visible, "shop mode leaked another panel")
	main._toggle_enhancement()
	assert(main.enhancement_panel.visible, "enhancement panel did not open")
	assert(not main.gold_shop.visible and not main.equipment_panel.visible, "enhancement panel was not exclusive")
	main._toggle_pets()
	assert(main.pet_panel.visible and not main.enhancement_panel.visible, "pet panel did not open exclusively")
	main._toggle_research()
	assert(main.research_panel.visible and not main.pet_panel.visible, "research panel did not open exclusively")
	main._toggle_progression()
	assert(main.progression_panel.visible and not main.research_panel.visible, "progression panel did not open exclusively")
	assert(main.progression_panel.position.y + main.progression_panel.size.y <= 506.0, "progression panel overlaps the bottom bar")
	main._toggle_quests()
	assert(main.quest_panel.visible and not main.progression_panel.visible, "quest panel did not open exclusively")
	assert(main.quest_panel.position.y + main.quest_panel.size.y <= 506.0, "quest panel overlaps the bottom bar")
	main._toggle_skills()
	assert(main.skill_panel.visible and not main.quest_panel.visible, "skill panel did not open exclusively")
	assert(main.skill_panel.position.y + main.skill_panel.size.y <= 506.0, "skill panel overlaps the bottom bar")

	assert(GameState.start_fuwa_round().success, "Fuwa event could not start")
	main._apply_current_map()
	await get_tree().process_frame
	assert(GameState.current_map_id == "green_field", "Fuwa event did not enter grass")
	assert(main.background.texture.resource_path.ends_with("image_1097.jpg"), "grass background did not change")
	assert(not main.location_label.text.is_empty(), "map HUD did not change")
	assert(main.actor_layer.get_child_count() == 2, "grass actor layer was not rebuilt")
	main._start_battle("fuwa_beast")
	assert(_no_legacy_panel(main), "legacy battle panel reopened through _start_battle")
	assert(main.scene_battle_controller.session != null and main.scene_battle_controller.active_monster_id == "fuwa_beast", "battle entry did not redirect to the world actor")
	assert(main.scene_battle_controller.session.turn == 1, "redirected world battle did not attack immediately")
	# P2 拒签整改：quit 前确定性等待战斗/反馈协程自然完成（流程上限 2.2s，超过任何挂起窗口）再释放 main
	main.scene_battle_controller.cancel_battle()
	await get_tree().create_timer(2.5).timeout
	if main.is_inside_tree():
		remove_child(main)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("PASS main scene panel modes, storage interaction, and legacy battle redirect")
	get_tree().quit(0)

