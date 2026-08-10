extends Node


func _ready() -> void:
	GameState.current_map_id = "cassano_city"
	GameState.current_day = 7
	GameState.military_merit = 1000
	GameState.last_military_salary_day = 0
	GameState.story_flags = {"king_rescued":false, "princess_friend_gift_available":false, "maid_year_pig_available":true}
	var main := preload("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame

	main._travel_to("palace")
	await get_tree().process_frame
	assert(GameState.current_map_id == "palace", "Cassano upper exit did not enter the palace")
	assert(main.background.texture.resource_path.ends_with("image_1175.jpg"), "palace does not use the original background")
	for actor_id in ["marshal", "prime_minister", "princess", "maid", "pk_officer"]:
		assert(main.interactive_actors.has(actor_id), "palace actor is missing: " + actor_id)
	assert(not main.interactive_actors.has("king"), "captured king appeared in the palace before rescue")
	assert(main.interactive_actors["marshal"].texture.resource_path.ends_with("image_1177.png"), "marshal artwork is not original")
	assert(main.interactive_actors["prime_minister"].texture.resource_path.ends_with("image_1142.png"), "prime minister artwork is not from the original sprite")
	assert(main.interactive_actors["maid"].texture.resource_path.ends_with("image_1134.png"), "maid artwork is not from the original sprite")
	main._open_actor_dialogue("prime_minister")
	assert(main.dialogue_panel.speaker_label.text == "首相", "prime minister dialogue did not open")
	main._open_prime_minister_king_news()
	assert(main.dialogue_panel.body_label.text.contains("俘虏"), "pre-rescue king news is missing")
	GameState.story_flags.king_rescued = true
	main._apply_current_map()
	assert(main.interactive_actors.has("king"), "rescued king did not return to the palace")
	assert(main.interactive_actors["king"].texture.resource_path.ends_with("image_1191.png"), "king artwork is not original")
	main._open_actor_dialogue("king")
	assert(main.dialogue_panel.body_label.text.contains("魔族大军"), "king final-war briefing is missing")

	main._open_actor_dialogue("marshal")
	assert(main.dialogue_panel.speaker_label.text == "元帅", "marshal dialogue did not open")
	main._open_marshal_info_dialogue()
	assert(main.dialogue_panel.body_label.text.contains("救出国王"), "original king-rescue briefing is missing")

	var before_stones := GameState.magic_stones
	var salary := GameState.claim_military_salary()
	assert(salary.success and salary.magic_stones == 999999999, "modified SWF military salary was not restored")
	assert(GameState.magic_stones == before_stones + 999999999, "military salary did not reach the wallet")
	assert(GameState.claim_military_salary().reason == "already_claimed", "military salary can be claimed twice on the same Sunday")

	GameState.current_day = 6
	GameState.last_pk_race_day = 0
	main._open_actor_dialogue("pk_officer")
	assert(main.dialogue_panel.body_label.text.contains("60级组") and main.dialogue_panel.body_label.text.contains("100级以上组"), "PK group briefing is incomplete")
	main._handle_dialogue_action("pk_register")
	await get_tree().process_frame
	assert(GameState.current_map_id == "pk_arena", "palace PK officer did not enter the arena")

	print("PASS palace map, original royal NPCs, marshal salary, and PK registration")
	get_tree().quit(0)
